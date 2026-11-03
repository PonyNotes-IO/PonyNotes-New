//! `note_link` 系列表的读写。
//!
//! # 事务与幂等
//!
//! 写入单位是**一页**：删掉该页所有边，再整体插入新边，最后更新 state。
//! 放在一个事务里，保证查询方永远看不到「删了一半」的中间态。
//!
//! 之所以用「整页重算」而不是「逐边 diff」，是因为链接解析的产出是顺序敏感的
//! （偏移、出现次数都跟块顺序有关），diff 出的增量一旦算错，错误会一直累积下去；
//! 而整页重算的成本只是一次 delete + 一次批量 insert，在一页几十条边的量级下可以忽略。
//!
//! # 为什么不做外键
//!
//! 目标页可能尚未同步到本机。加外键会让「引用了一个还没下载的页面」写入失败，
//! 而那恰恰是最需要记下来的情形。完整性由查询期的 join 保证，不靠约束。
//!
//! # 删页的语义
//!
//! 删页时只清理**以它为源**的边。以它为目标的边要保留 —— 那表示「别处引用了
//! 一个已被删除的页面」，这条信息对用户有用（提示修复或恢复），删掉就永久丢失了。

use std::sync::Arc;

use diesel::connection::Connection;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Integer, Nullable, Text};
use flowy_sqlite::prelude::*;
use flowy_sqlite::{ConnectionPool, DBConnection, QueryableByName, RunQueryDsl};
use uuid::Uuid;

use crate::entities::{ExtractedLinks, LinkEdge, LinkKind};
use crate::error::{LinkError, LinkResult};

// ---------------------------------------------------------------------------
// 表定义。字段必须与 migrations/2026-11-03-000001_note_link_index/up.sql 一致。
// ---------------------------------------------------------------------------

diesel::table! {
  note_link (id) {
    id -> Integer,
    workspace_id -> Text,
    src_page_id -> Text,
    src_block_id -> Text,
    dst_page_id -> Text,
    dst_block_id -> Nullable<Text>,
    kind -> Text,
    label -> Text,
    char_offset -> Integer,
    occurrence -> Integer,
    updated_at -> BigInt,
  }
}

diesel::table! {
  note_link_state (page_id) {
    page_id -> Text,
    workspace_id -> Text,
    content_hash -> Text,
    link_count -> Integer,
    indexed_at -> BigInt,
  }
}

diesel::table! {
  note_link_unresolved (workspace_id, src_page_id, src_block_id, normalized_title) {
    workspace_id -> Text,
    src_page_id -> Text,
    src_block_id -> Text,
    normalized_title -> Text,
    raw_title -> Text,
    char_offset -> Integer,
  }
}

/// 写入用的行结构。`updated_at` 由调用方统一填，保证同一次写入内的时间戳相同。
#[derive(Debug, Insertable)]
#[diesel(table_name = note_link)]
struct NoteLinkRow {
  workspace_id: String,
  src_page_id: String,
  src_block_id: String,
  dst_page_id: String,
  dst_block_id: Option<String>,
  kind: String,
  label: String,
  char_offset: i32,
  occurrence: i32,
  updated_at: i64,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = note_link_state)]
struct NoteLinkStateRow {
  page_id: String,
  workspace_id: String,
  content_hash: String,
  link_count: i32,
  indexed_at: i64,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = note_link_unresolved)]
struct UnresolvedRow {
  workspace_id: String,
  src_page_id: String,
  src_block_id: String,
  normalized_title: String,
  raw_title: String,
  char_offset: i32,
}

// ---------------------------------------------------------------------------
// 查询结果
// ---------------------------------------------------------------------------

/// 一页的索引状态，用于判断是否需要重算。
#[derive(Debug, Clone, PartialEq, Eq, QueryableByName)]
pub struct PageIndexState {
  #[diesel(sql_type = Text)]
  pub workspace_id: String,
  #[diesel(sql_type = Text)]
  pub page_id: String,
  #[diesel(sql_type = Text)]
  pub content_hash: String,
  #[diesel(sql_type = Integer)]
  pub link_count: i32,
  #[diesel(sql_type = BigInt)]
  pub indexed_at: i64,
}

/// 反向链接的一条记录（面板直接消费）。
#[derive(Debug, Clone, PartialEq, Eq, QueryableByName)]
pub struct BacklinkRecord {
  #[diesel(sql_type = Text)]
  pub src_page_id: String,
  #[diesel(sql_type = Text)]
  pub src_block_id: String,
  #[diesel(sql_type = Text)]
  pub dst_page_id: String,
  #[diesel(sql_type = Nullable<Text>)]
  pub dst_block_id: Option<String>,
  #[diesel(sql_type = Text)]
  pub kind: String,
  #[diesel(sql_type = Text)]
  pub label: String,
  #[diesel(sql_type = Integer)]
  pub char_offset: i32,
  #[diesel(sql_type = Integer)]
  pub occurrence: i32,
}

impl BacklinkRecord {
  /// 数据库里的字符串还原成类型化的边。
  ///
  /// `kind` 未知时返回 `None` 而不是猜成 `Reference`：
  /// 单条脏数据不该污染统计，也不该让整个查询失败。
  pub fn to_edge(&self) -> Option<LinkEdge> {
    Some(LinkEdge {
      src_page_id: self.src_page_id.clone(),
      src_block_id: self.src_block_id.clone(),
      dst_page_id: self.dst_page_id.clone(),
      dst_block_id: self.dst_block_id.clone(),
      kind: LinkKind::from_str(&self.kind)?,
      label: self.label.clone(),
      char_offset: self.char_offset.max(0) as u32,
      occurrence: self.occurrence.max(1) as u32,
    })
  }
}

/// 悬空引用的读模型。
#[derive(Debug, Clone, PartialEq, Eq, QueryableByName)]
pub struct UnresolvedRecord {
  #[diesel(sql_type = Text)]
  pub src_page_id: String,
  #[diesel(sql_type = Text)]
  pub src_block_id: String,
  #[diesel(sql_type = Text)]
  pub normalized_title: String,
  #[diesel(sql_type = Text)]
  pub raw_title: String,
  #[diesel(sql_type = Integer)]
  pub char_offset: i32,
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

pub struct LinkIndexStore {
  /// 直接持有连接池，而不是 `Database`。
  ///
  /// 上层（`UserDB::open_sqlite_db`）本来就只暴露 `Arc<ConnectionPool>`，
  /// 这里贴合它，避免为了拿 `Database` 而去改动用户会话层的结构。
  /// 连接池本身是 `Arc` 内部共享，克隆成本可以忽略。
  pool: Arc<ConnectionPool>,
}

impl LinkIndexStore {
  /// Bounded workspace snapshot for structural graphs. Empty documents count toward coverage.
  pub fn workspace_edges(
    &self,
    workspace_id: &Uuid,
    limit: i64,
  ) -> LinkResult<Vec<BacklinkRecord>> {
    let mut conn = self.connection()?;
    Ok(sql_query(
      "SELECT src_page_id, src_block_id, dst_page_id, dst_block_id, kind, label, char_offset, occurrence \
       FROM note_link WHERE workspace_id = ? ORDER BY src_page_id, src_block_id, dst_page_id LIMIT ?",
    ).bind::<Text, _>(workspace_id.to_string()).bind::<BigInt, _>(limit).load(&mut conn)?)
  }

  pub fn indexed_page_count(&self, workspace_id: &Uuid) -> LinkResult<i64> {
    let mut conn = self.connection()?;
    #[derive(QueryableByName)]
    struct Count {
      #[diesel(sql_type = BigInt)]
      count: i64,
    }
    let rows: Vec<Count> =
      sql_query("SELECT COUNT(*) AS count FROM note_link_state WHERE workspace_id = ?")
        .bind::<Text, _>(workspace_id.to_string())
        .load(&mut conn)?;
    Ok(rows.first().map(|row| row.count).unwrap_or(0))
  }

  pub fn new(pool: Arc<ConnectionPool>) -> Self {
    Self { pool }
  }

  fn connection(&self) -> LinkResult<DBConnection> {
    self.pool.get().map_err(|err| {
      // 取不到连接是基础设施故障，记 error 级日志；上层可以重试或跳过这一页。
      tracing::error!("[Link] failed to acquire sqlite connection: {:?}", err);
      LinkError::ConnectionUnavailable
    })
  }

  /// 读一页的索引状态。返回 `None` 表示这页还没建过索引。
  pub fn page_state(&self, page_id: &str) -> LinkResult<Option<PageIndexState>> {
    let mut conn = self.connection()?;
    let rows: Vec<PageIndexState> = sql_query(
      "SELECT page_id, workspace_id, content_hash, link_count, indexed_at \
       FROM note_link_state WHERE page_id = ?",
    )
    .bind::<Text, _>(page_id)
    .load(&mut conn)?;
    Ok(rows.into_iter().next())
  }

  /// 整页重建索引（幂等）。
  ///
  /// - `content_hash` 与已有记录相同且 `force = false` 时直接返回 `false`（跳过），
  ///   这是避免「编辑一个字就重算全页」的第一道闸。
  /// - 返回值表示**是否真的写了**。
  pub fn replace_page(
    &self,
    workspace_id: &Uuid,
    src_page_id: &str,
    content_hash: &str,
    extracted: &ExtractedLinks,
    force: bool,
  ) -> LinkResult<bool> {
    if !force {
      if let Some(state) = self.page_state(src_page_id)? {
        if state.content_hash == content_hash && state.workspace_id == workspace_id.to_string() {
          return Ok(false);
        }
      }
    }

    let ws = workspace_id.to_string();
    let now = now_millis();

    let link_rows: Vec<NoteLinkRow> = extracted
      .edges
      .iter()
      .map(|edge| NoteLinkRow {
        workspace_id: ws.clone(),
        src_page_id: src_page_id.to_string(),
        src_block_id: edge.src_block_id.clone(),
        dst_page_id: edge.dst_page_id.clone(),
        dst_block_id: edge.dst_block_id.clone(),
        kind: edge.kind.as_str().to_string(),
        label: edge.label.clone(),
        // char_offset 是 u32，SQLite 用有符号整型存，超出 i32 的文档几乎不可能出现，
        // 但仍做饱和转换，避免溢出成负数
        char_offset: i32::try_from(edge.char_offset).unwrap_or(i32::MAX),
        occurrence: i32::try_from(edge.occurrence).unwrap_or(i32::MAX),
        updated_at: now,
      })
      .collect();

    let unresolved_rows: Vec<UnresolvedRow> = extracted
      .unresolved
      .iter()
      .map(|link| UnresolvedRow {
        workspace_id: ws.clone(),
        src_page_id: src_page_id.to_string(),
        src_block_id: link.src_block_id.clone(),
        normalized_title: link.normalized_title.clone(),
        raw_title: link.raw_title.clone(),
        char_offset: i32::try_from(link.char_offset).unwrap_or(i32::MAX),
      })
      .collect();

    let state_row = NoteLinkStateRow {
      workspace_id: ws,
      page_id: src_page_id.to_string(),
      content_hash: content_hash.to_string(),
      link_count: link_rows.len() as i32,
      indexed_at: now,
    };

    let mut conn = self.connection()?;
    conn.transaction::<(), LinkError, _>(|conn| {
      use diesel::prelude::*;

      // 1. 清掉这一页的旧边与旧悬空引用
      diesel::delete(note_link::table.filter(note_link::src_page_id.eq(src_page_id)))
        .execute(conn)?;
      diesel::delete(
        note_link_unresolved::table.filter(note_link_unresolved::src_page_id.eq(src_page_id)),
      )
      .execute(conn)?;

      // 2. 批量写入新边
      if !link_rows.is_empty() {
        diesel::insert_into(note_link::table)
          .values(&link_rows)
          .execute(conn)?;
      }
      if !unresolved_rows.is_empty() {
        diesel::insert_into(note_link_unresolved::table)
          .values(&unresolved_rows)
          .execute(conn)?;
      }

      // 3. 更新页状态（upsert）
      diesel::replace_into(note_link_state::table)
        .values(&state_row)
        .execute(conn)?;

      Ok(())
    })?;

    Ok(true)
  }

  /// 谁引用了这页（排除自引用）。
  ///
  /// 按 `updated_at` 倒序：最近编辑过的引用更可能是用户当下要找的。
  pub fn backlinks(
    &self,
    workspace_id: &Uuid,
    dst_page_id: &str,
    limit: i64,
  ) -> LinkResult<Vec<BacklinkRecord>> {
    let mut conn = self.connection()?;
    let rows = sql_query(
      "SELECT src_page_id, src_block_id, dst_page_id, dst_block_id, kind, label, \
              char_offset, occurrence \
       FROM note_link \
       WHERE workspace_id = ? AND dst_page_id = ? AND src_page_id <> dst_page_id \
       ORDER BY updated_at DESC, char_offset ASC \
       LIMIT ?",
    )
    .bind::<Text, _>(workspace_id.to_string())
    .bind::<Text, _>(dst_page_id)
    .bind::<BigInt, _>(limit.clamp(1, 1000))
    .load(&mut conn)?;
    Ok(rows)
  }

  /// 这页引用了谁。按正文顺序（偏移升序），与阅读顺序一致。
  pub fn outgoing(
    &self,
    workspace_id: &Uuid,
    src_page_id: &str,
  ) -> LinkResult<Vec<BacklinkRecord>> {
    let mut conn = self.connection()?;
    let rows = sql_query(
      "SELECT src_page_id, src_block_id, dst_page_id, dst_block_id, kind, label, \
              char_offset, occurrence \
       FROM note_link \
       WHERE workspace_id = ? AND src_page_id = ? \
       ORDER BY char_offset ASC",
    )
    .bind::<Text, _>(workspace_id.to_string())
    .bind::<Text, _>(src_page_id)
    .load(&mut conn)?;
    Ok(rows)
  }

  /// 这页产生的悬空引用候选。
  pub fn unresolved_of(
    &self,
    workspace_id: &Uuid,
    src_page_id: &str,
  ) -> LinkResult<Vec<UnresolvedRecord>> {
    let mut conn = self.connection()?;
    let rows = sql_query(
      "SELECT src_page_id, src_block_id, normalized_title, raw_title, char_offset \
       FROM note_link_unresolved \
       WHERE workspace_id = ? AND src_page_id = ? \
       ORDER BY char_offset ASC",
    )
    .bind::<Text, _>(workspace_id.to_string())
    .bind::<Text, _>(src_page_id)
    .load(&mut conn)?;
    Ok(rows)
  }

  /// 删除以该页为源的索引（页面被删除时调用）。
  ///
  /// 注意：**不删除以它为目标的边**。那些边表示「别处引用了已删除的页面」，
  /// 保留下来 UI 才能提示「引用了已删除的笔记」，删掉就等于静默吞掉信息。
  pub fn delete_page(&self, workspace_id: &Uuid, page_id: &str) -> LinkResult<()> {
    let ws = workspace_id.to_string();
    let mut conn = self.connection()?;
    conn.transaction::<(), LinkError, _>(|conn| {
      use diesel::prelude::*;
      diesel::delete(
        note_link::table
          .filter(note_link::workspace_id.eq(&ws))
          .filter(note_link::src_page_id.eq(page_id)),
      )
      .execute(conn)?;
      diesel::delete(
        note_link_unresolved::table
          .filter(note_link_unresolved::workspace_id.eq(&ws))
          .filter(note_link_unresolved::src_page_id.eq(page_id)),
      )
      .execute(conn)?;
      diesel::delete(note_link_state::table.filter(note_link_state::page_id.eq(page_id)))
        .execute(conn)?;
      Ok(())
    })?;
    Ok(())
  }

  /// 统计：入链来源页数量（去重）。图谱与侧边栏徽标用它，比逐条边遍历便宜。
  pub fn backlink_page_count(&self, workspace_id: &Uuid, dst_page_id: &str) -> LinkResult<i64> {
    #[derive(QueryableByName)]
    struct CountRow {
      #[diesel(sql_type = BigInt)]
      n: i64,
    }

    let mut conn = self.connection()?;
    let rows: Vec<CountRow> = sql_query(
      "SELECT COUNT(DISTINCT src_page_id) AS n \
       FROM note_link \
       WHERE workspace_id = ? AND dst_page_id = ? AND src_page_id <> dst_page_id",
    )
    .bind::<Text, _>(workspace_id.to_string())
    .bind::<Text, _>(dst_page_id)
    .load(&mut conn)?;
    Ok(rows.first().map(|r| r.n).unwrap_or(0))
  }
}

/// 毫秒时间戳。用 i64 存，避免 2038 问题。
fn now_millis() -> i64 {
  std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}
