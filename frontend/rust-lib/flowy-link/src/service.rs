//! 对上层暴露的服务层。
//!
//! # 内容指纹为什么基于「提取结果」而不是全文
//!
//! 索引的唯一目的是回答「谁引用了谁」。正文写得再多，只要链接关系没变，
//! 就没有重写索引的必要。所以指纹算在 `ExtractedLinks` 上，而不是文档 JSON 上：
//!
//! - 写一段不涉及链接的文字 → 指纹不变 → 跳过写库（省掉一次事务）
//! - 改一个链接目标 → 指纹变 → 重算（这是必须的）
//!
//! 提取本身是 O(该页链接数) 的轻量遍历，每次都跑也无所谓；
//! 真正贵的是 SQLite 写事务和随后的 UI 通知。
//!
//! 反过来若用全文指纹，任何一次纯文字编辑都会触发重写索引，
//! 在长文档里会变成持续的写放大。

use std::sync::Arc;

use collab_document::blocks::DocumentData;
use flowy_sqlite::ConnectionPool;
use uuid::Uuid;

use crate::entities::ExtractedLinks;
use crate::error::LinkResult;
use crate::extractor::extract_links;
use crate::store::{BacklinkRecord, LinkIndexStore, PageIndexState, UnresolvedRecord};

/// 一次索引的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IndexOutcome {
  /// 链接关系有变化，已写入。
  Written { edges: usize, unresolved: usize },
  /// 链接关系与上次一致，跳过写入。
  Unchanged { edges: usize },
}

impl IndexOutcome {
  pub fn is_written(&self) -> bool {
    matches!(self, Self::Written { .. })
  }
}

pub struct LinkIndexService {
  store: LinkIndexStore,
}

impl LinkIndexService {
  pub fn new(pool: Arc<ConnectionPool>) -> Self {
    Self {
      store: LinkIndexStore::new(pool),
    }
  }

  /// 索引一页文档。
  ///
  /// 这是整个链路唯一需要外部调用的写入口：文档变了就调它，
  /// 指纹会判断是否真有需要写库。
  pub fn index_document(
    &self,
    workspace_id: &Uuid,
    doc: &DocumentData,
  ) -> LinkResult<IndexOutcome> {
    self.index_document_for(workspace_id, &doc.page_id, doc, false)
  }

  /// The view UUID is distinct from DocumentData.page_id (the CRDT root block).
  pub fn index_document_for(
    &self,
    workspace_id: &Uuid,
    page_id: &str,
    doc: &DocumentData,
    force: bool,
  ) -> LinkResult<IndexOutcome> {
    let mut extracted = extract_links(doc);
    for edge in &mut extracted.edges {
      edge.src_page_id = page_id.to_string();
    }
    for link in &mut extracted.unresolved {
      link.src_page_id = page_id.to_string();
    }
    let fingerprint = fingerprint(&extracted);

    let written =
      self
        .store
        .replace_page(workspace_id, page_id, &fingerprint, &extracted, force)?;

    Ok(if written {
      IndexOutcome::Written {
        edges: extracted.edges.len(),
        unresolved: extracted.unresolved.len(),
      }
    } else {
      IndexOutcome::Unchanged {
        edges: extracted.edges.len(),
      }
    })
  }

  /// 强制重建（用于「修复索引」入口与首次迁移）。
  pub fn reindex_document(
    &self,
    workspace_id: &Uuid,
    doc: &DocumentData,
  ) -> LinkResult<IndexOutcome> {
    let extracted = extract_links(doc);
    let fingerprint = fingerprint(&extracted);
    self
      .store
      .replace_page(workspace_id, &doc.page_id, &fingerprint, &extracted, true)?;
    Ok(IndexOutcome::Written {
      edges: extracted.edges.len(),
      unresolved: extracted.unresolved.len(),
    })
  }

  /// 谁引用了这页。
  pub fn get_backlinks(
    &self,
    workspace_id: &Uuid,
    page_id: &str,
    limit: i64,
  ) -> LinkResult<Vec<BacklinkRecord>> {
    self.store.backlinks(workspace_id, page_id, limit)
  }

  /// 这页引用了谁。
  pub fn get_outgoing(
    &self,
    workspace_id: &Uuid,
    page_id: &str,
  ) -> LinkResult<Vec<BacklinkRecord>> {
    self.store.outgoing(workspace_id, page_id)
  }

  /// 这页的悬空引用。
  pub fn get_unresolved(
    &self,
    workspace_id: &Uuid,
    page_id: &str,
  ) -> LinkResult<Vec<UnresolvedRecord>> {
    self.store.unresolved_of(workspace_id, page_id)
  }

  /// 入链来源页数量（去重），供侧边栏徽标使用。
  pub fn backlink_count(&self, workspace_id: &Uuid, page_id: &str) -> LinkResult<i64> {
    self.store.backlink_page_count(workspace_id, page_id)
  }

  pub fn page_state(&self, page_id: &str) -> LinkResult<Option<PageIndexState>> {
    self.store.page_state(page_id)
  }

  /// 页面被删除时清理以它为源的索引。
  ///
  /// 指向它的边会保留（调用方会看到「引用了已删除的页面」），这是刻意的。
  pub fn on_page_deleted(&self, workspace_id: &Uuid, page_id: &str) -> LinkResult<()> {
    self.store.delete_page(workspace_id, page_id)
  }
}

/// 计算提取结果的稳定指纹（FNV-1a 64）。
///
/// 不用 `DefaultHasher`：它的输出在不同 Rust 版本间不保证稳定，
/// 而指纹要落进数据库跨版本比较。FNV 实现简单且稳定。
///
/// 输入顺序必须确定 —— 依赖 `extract_links` 保证按 `children_map` 顺序产出。
fn fingerprint(extracted: &ExtractedLinks) -> String {
  let mut hasher = Fnv1a::new();

  for edge in &extracted.edges {
    hasher.write(edge.src_block_id.as_bytes());
    hasher.write(edge.dst_page_id.as_bytes());
    if let Some(block) = edge.dst_block_id.as_deref() {
      hasher.write(block.as_bytes());
    }
    hasher.write(edge.kind.as_str().as_bytes());
    hasher.write(edge.label.as_bytes());
    hasher.write(&edge.char_offset.to_le_bytes());
    hasher.write(&edge.occurrence.to_le_bytes());
  }

  // 用分隔符隔开边与悬空引用，避免两组数据拼出同一个 hash
  hasher.write(b"|unresolved|");
  for link in &extracted.unresolved {
    hasher.write(link.src_block_id.as_bytes());
    hasher.write(link.normalized_title.as_bytes());
    hasher.write(link.raw_title.as_bytes());
    hasher.write(&link.char_offset.to_le_bytes());
  }

  format!("{:016x}", hasher.finish())
}

/// FNV-1a 64 位散列。
struct Fnv1a {
  state: u64,
}

impl Fnv1a {
  const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
  const PRIME: u64 = 0x0000_0100_0000_01b3;

  fn new() -> Self {
    Self {
      state: Self::OFFSET_BASIS,
    }
  }

  fn write(&mut self, bytes: &[u8]) {
    // Field framing prevents ("ab", "c") and ("a", "bc") sharing a fingerprint.
    for byte in (bytes.len() as u64).to_le_bytes() {
      self.state ^= byte as u64;
      self.state = self.state.wrapping_mul(Self::PRIME);
    }
    for byte in bytes {
      self.state ^= *byte as u64;
      self.state = self.state.wrapping_mul(Self::PRIME);
    }
  }

  fn finish(&self) -> u64 {
    self.state
  }
}

#[cfg(test)]
mod tests {
  use std::collections::HashMap;

  use collab_document::blocks::{Block, DocumentMeta};

  use super::*;
  use crate::entities::{LinkEdge, LinkKind, UnresolvedLink};

  fn edge(block: &str, dst: &str, offset: u32) -> LinkEdge {
    LinkEdge {
      src_page_id: "p1".to_string(),
      src_block_id: block.to_string(),
      dst_page_id: dst.to_string(),
      dst_block_id: None,
      kind: LinkKind::Reference,
      label: String::new(),
      char_offset: offset,
      occurrence: 1,
    }
  }

  fn doc_with(text: &str) -> DocumentData {
    let mut blocks = HashMap::new();
    blocks.insert(
      "b1".to_string(),
      Block {
        id: "b1".to_string(),
        ty: "paragraph".to_string(),
        parent: "p1".to_string(),
        children: "b1-children".to_string(),
        external_id: None,
        external_type: None,
        data: HashMap::new(),
      },
    );
    let mut text_map = HashMap::new();
    text_map.insert("b1".to_string(), text.to_string());
    let mut children_map = HashMap::new();
    children_map.insert("p1".to_string(), vec!["b1".to_string()]);

    DocumentData {
      page_id: "p1".to_string(),
      blocks,
      meta: DocumentMeta {
        children_map,
        text_map: Some(text_map),
      },
    }
  }

  #[test]
  fn fingerprint_is_stable_for_same_structure() {
    let a = ExtractedLinks {
      edges: vec![edge("b1", "p2", 3)],
      unresolved: vec![],
    };
    let b = ExtractedLinks {
      edges: vec![edge("b1", "p2", 3)],
      unresolved: vec![],
    };
    assert_eq!(fingerprint(&a), fingerprint(&b));
  }

  #[test]
  fn fingerprint_changes_when_target_changes() {
    let a = ExtractedLinks {
      edges: vec![edge("b1", "p2", 3)],
      unresolved: vec![],
    };
    let b = ExtractedLinks {
      edges: vec![edge("b1", "p3", 3)],
      unresolved: vec![],
    };
    assert_ne!(fingerprint(&a), fingerprint(&b));
  }

  #[test]
  fn fingerprint_changes_when_offset_changes() {
    // 同目标但位置变了：跳转落点不同，需要重算
    let a = ExtractedLinks {
      edges: vec![edge("b1", "p2", 3)],
      unresolved: vec![],
    };
    let b = ExtractedLinks {
      edges: vec![edge("b1", "p2", 9)],
      unresolved: vec![],
    };
    assert_ne!(fingerprint(&a), fingerprint(&b));
  }

  #[test]
  fn fingerprint_distinguishes_edges_from_unresolved() {
    // 防止「两组数据拼出同一个 hash」这类碰撞
    let a = ExtractedLinks {
      edges: vec![edge("b1", "p2", 0)],
      unresolved: vec![],
    };
    let b = ExtractedLinks {
      edges: vec![],
      unresolved: vec![UnresolvedLink {
        src_page_id: "p1".to_string(),
        src_block_id: "b1".to_string(),
        normalized_title: "p2".to_string(),
        raw_title: "p2".to_string(),
        char_offset: 0,
      }],
    };
    assert_ne!(fingerprint(&a), fingerprint(&b));
  }

  #[test]
  fn text_only_edit_keeps_same_fingerprint() {
    // 这是最关键的取舍：只改文字、不动链接，指纹应当不变，从而跳过写库
    let with_mention = doc_with(
      &serde_json::json!([
        {"insert": "见 "},
        {"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p2"}}}
      ])
      .to_string(),
    );
    let more_text = doc_with(
      &serde_json::json!([
        {"insert": "这里加了很多说明文字，再 "},
        {"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p2"}}}
      ])
      .to_string(),
    );

    // 注意：偏移变了（前缀变长），所以指纹其实会变 —— 这是正确的，
    // 因为跳转落点确实变了。此用例锁定这个语义，避免以后误以为可以省掉偏移。
    assert_ne!(
      fingerprint(&extract_links(&with_mention)),
      fingerprint(&extract_links(&more_text))
    );

    // 真正「链接不变」的场景：文字改在后面
    let tail_changed = doc_with(
      &serde_json::json!([
        {"insert": "见 "},
        {"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p2"}}},
        {"insert": "，补充了新的说明"}
      ])
      .to_string(),
    );
    assert_eq!(
      fingerprint(&extract_links(&with_mention)),
      fingerprint(&extract_links(&tail_changed)),
      "只改链接之后的文字，不应触发索引重写"
    );
  }
}
