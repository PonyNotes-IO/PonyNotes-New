//! store 层的集成测试：跑真实 SQLite（含全部迁移），不 mock。
//!
//! 这里要验证的是「表结构 + 事务 + SQL 语句」三者能对上。单测里 mock 掉数据库
//! 只能证明逻辑分支，证明不了 DDL 和查询语句真的能跑。

use std::collections::HashMap;
use std::sync::Arc;

use collab_document::blocks::{Block, DocumentData, DocumentMeta};
use flowy_link::entities::{ExtractedLinks, LinkEdge, LinkKind, UnresolvedLink};
use flowy_link::extractor::extract_links;
use flowy_link::store::LinkIndexStore;
use serde_json::json;
use uuid::Uuid;

/// 建一个跑完全部迁移的临时库。
///
/// 库文件放在系统临时目录：它只有几十 KB，与构建产物不同量级，
/// 不会触发 `/tmp` 的容量问题。
fn test_store() -> LinkIndexStore {
  let dir = tempfile::tempdir().expect("create temp dir");
  let db = flowy_sqlite::init(dir.path()).expect("init sqlite database");
  // tempdir 在函数返回时就被删了，但 sqlite 已经打开文件句柄，Linux 下可以继续读写。
  // 为了让行为确定，这里泄漏路径，由进程退出时清理。
  std::mem::forget(dir);
  LinkIndexStore::new(db.get_pool())
}

fn edge(src_block: &str, dst_page: &str, kind: LinkKind, offset: u32) -> LinkEdge {
  LinkEdge {
    src_page_id: "p_src".to_string(),
    src_block_id: src_block.to_string(),
    dst_page_id: dst_page.to_string(),
    dst_block_id: None,
    kind,
    label: String::new(),
    char_offset: offset,
    occurrence: 1,
  }
}

#[test]
fn workspace_snapshot_and_coverage_include_empty_notes_and_isolate_workspaces() {
  let store = test_store();
  let ws = Uuid::new_v4();
  let other = Uuid::new_v4();
  store
    .replace_page(&ws, "empty", "empty", &ExtractedLinks::default(), false)
    .unwrap();
  let links = ExtractedLinks {
    edges: vec![edge("b1", "target", LinkKind::Reference, 0)],
    unresolved: vec![],
  };
  store
    .replace_page(&ws, "source", "one", &links, false)
    .unwrap();
  store
    .replace_page(&other, "other-source", "one", &links, false)
    .unwrap();
  assert_eq!(store.indexed_page_count(&ws).unwrap(), 2);
  assert_eq!(store.indexed_page_count(&other).unwrap(), 1);
  assert_eq!(store.workspace_edges(&ws, 100).unwrap().len(), 1);
  assert_eq!(
    store.workspace_edges(&ws, 100).unwrap()[0].src_page_id,
    "source"
  );
  store.delete_page(&ws, "empty").unwrap();
  assert_eq!(store.indexed_page_count(&ws).unwrap(), 1);
}

#[test]
fn service_uses_view_identity_without_changing_the_crdt_root() {
  let dir = tempfile::tempdir().unwrap();
  let db = flowy_sqlite::init(dir.path()).unwrap();
  let service = flowy_link::LinkIndexService::new(db.get_pool());
  let workspace = Uuid::new_v4();
  let data = DocumentData {
    page_id: "root-block".into(),
    blocks: HashMap::from([
      (
        "root-block".into(),
        Block {
          id: "root-block".into(),
          ty: "page".into(),
          parent: String::new(),
          children: "root-children".into(),
          external_id: None,
          external_type: None,
          data: HashMap::new(),
        },
      ),
      (
        "paragraph".into(),
        Block {
          id: "paragraph".into(),
          ty: "paragraph".into(),
          parent: "root-block".into(),
          children: "paragraph-children".into(),
          external_id: None,
          external_type: None,
          data: HashMap::from([(
            "delta".into(),
            json!([{"insert":"$", "attributes":{"mention":{"type":"page", "page_id":"target"}}}]),
          )]),
        },
      ),
    ]),
    meta: DocumentMeta {
      children_map: HashMap::from([("root-children".into(), vec!["paragraph".into()])]),
      text_map: None,
    },
  };
  service
    .index_document_for(&workspace, "view-uuid", &data, false)
    .unwrap();
  let incoming = service.get_backlinks(&workspace, "target", 10).unwrap();
  assert_eq!(incoming.len(), 1);
  assert_eq!(incoming[0].src_page_id, "view-uuid");
  assert_eq!(incoming[0].src_block_id, "paragraph");
  assert_eq!(
    service
      .get_outgoing(&workspace, "root-block")
      .unwrap()
      .len(),
    0
  );
}

#[test]
fn migration_creates_tables_and_accepts_writes() {
  let store = test_store();
  let ws = Uuid::new_v4();

  let extracted = ExtractedLinks {
    edges: vec![edge("b1", "p_target", LinkKind::Reference, 5)],
    unresolved: vec![],
  };

  let written = store
    .replace_page(&ws, "p_src", "hash-1", &extracted, false)
    .expect("replace_page should succeed");
  assert!(written, "首次写入应当真的落库");

  let backlinks = store
    .backlinks(&ws, "p_target", 50)
    .expect("query backlinks");
  assert_eq!(backlinks.len(), 1);
  assert_eq!(backlinks[0].src_page_id, "p_src");
  assert_eq!(backlinks[0].src_block_id, "b1");
  assert_eq!(backlinks[0].char_offset, 5);
}

#[test]
fn same_content_hash_skips_reindex() {
  let store = test_store();
  let ws = Uuid::new_v4();
  let extracted = ExtractedLinks {
    edges: vec![edge("b1", "p_target", LinkKind::Reference, 0)],
    unresolved: vec![],
  };

  assert!(store
    .replace_page(&ws, "p_src", "same-hash", &extracted, false)
    .unwrap());
  // 内容未变：第二遍应当被短路，避免「编辑一个字重算全页」
  assert!(
    !store
      .replace_page(&ws, "p_src", "same-hash", &extracted, false)
      .unwrap(),
    "相同 hash 不应重复写入"
  );
  // force 时无视 hash
  assert!(store
    .replace_page(&ws, "p_src", "same-hash", &extracted, true)
    .unwrap());
}

#[test]
fn reindex_replaces_old_edges_instead_of_appending() {
  let store = test_store();
  let ws = Uuid::new_v4();

  // 第一版：引用了 target 和 other
  let v1 = ExtractedLinks {
    edges: vec![
      edge("b1", "p_target", LinkKind::Reference, 0),
      edge("b1", "p_other", LinkKind::Reference, 10),
    ],
    unresolved: vec![],
  };
  store.replace_page(&ws, "p_src", "h1", &v1, false).unwrap();

  // 第二版：去掉了 other，这是典型的「删掉一个链接」
  let v2 = ExtractedLinks {
    edges: vec![edge("b1", "p_target", LinkKind::Reference, 0)],
    unresolved: vec![],
  };
  store.replace_page(&ws, "p_src", "h2", &v2, false).unwrap();

  assert_eq!(store.backlinks(&ws, "p_target", 50).unwrap().len(), 1);
  assert_eq!(
    store.backlinks(&ws, "p_other", 50).unwrap().len(),
    0,
    "被删掉的链接必须从索引里消失，否则反链会永远指向已经不存在的引用"
  );
}

#[test]
fn self_reference_is_excluded_from_backlinks() {
  let store = test_store();
  let ws = Uuid::new_v4();

  // 一页引用自己：面板要能提示，但反链列表里不该出现自己
  let extracted = ExtractedLinks {
    edges: vec![edge("b1", "p_src", LinkKind::Reference, 0)],
    unresolved: vec![],
  };
  store
    .replace_page(&ws, "p_src", "h", &extracted, false)
    .unwrap();

  assert!(
    store.backlinks(&ws, "p_src", 50).unwrap().is_empty(),
    "自引用不应计入入链"
  );
  // 但出链里要保留，用户需要看到「本文引用了自己」
  assert_eq!(store.outgoing(&ws, "p_src").unwrap().len(), 1);
}

#[test]
fn outgoing_is_ordered_by_position() {
  let store = test_store();
  let ws = Uuid::new_v4();

  let extracted = ExtractedLinks {
    edges: vec![
      edge("b3", "p_late", LinkKind::Reference, 90),
      edge("b1", "p_early", LinkKind::Reference, 10),
      edge("b2", "p_middle", LinkKind::Reference, 50),
    ],
    unresolved: vec![],
  };
  store
    .replace_page(&ws, "p_src", "h", &extracted, false)
    .unwrap();

  let out = store.outgoing(&ws, "p_src").unwrap();
  let order: Vec<&str> = out.iter().map(|r| r.dst_page_id.as_str()).collect();
  assert_eq!(
    order,
    vec!["p_early", "p_middle", "p_late"],
    "出链应按正文顺序"
  );
}

#[test]
fn delete_page_drops_source_edges_but_keeps_incoming() {
  let store = test_store();
  let ws = Uuid::new_v4();

  // A 引用 B
  let a = ExtractedLinks {
    edges: vec![LinkEdge {
      src_page_id: "p_a".to_string(),
      ..edge("b1", "p_b", LinkKind::Reference, 0)
    }],
    unresolved: vec![],
  };
  store.replace_page(&ws, "p_a", "h1", &a, false).unwrap();

  // 删掉 A：A → B 的边要清掉（A 已不存在），但 B 作为目标的记录语义上已随 A 消失
  store.delete_page(&ws, "p_a").unwrap();
  assert!(store.outgoing(&ws, "p_a").unwrap().is_empty());

  // 反过来：B 被其他页引用时，删 B 不应删掉「别人引用 B」的记录
  let c = ExtractedLinks {
    edges: vec![LinkEdge {
      src_page_id: "p_c".to_string(),
      ..edge("b1", "p_b", LinkKind::Reference, 0)
    }],
    unresolved: vec![],
  };
  store.replace_page(&ws, "p_c", "h2", &c, false).unwrap();
  store.delete_page(&ws, "p_b").unwrap();

  assert_eq!(
    store.backlinks(&ws, "p_b", 50).unwrap().len(),
    1,
    "删掉被引用的页，引用记录要保留，UI 才能提示「引用了已删除的笔记」"
  );
}

#[test]
fn unresolved_links_round_trip() {
  let store = test_store();
  let ws = Uuid::new_v4();

  let extracted = ExtractedLinks {
    edges: vec![],
    unresolved: vec![UnresolvedLink {
      src_page_id: "p_src".to_string(),
      src_block_id: "b7".to_string(),
      normalized_title: "future page".to_string(),
      raw_title: "Future Page".to_string(),
      char_offset: 12,
    }],
  };
  store
    .replace_page(&ws, "p_src", "h", &extracted, false)
    .unwrap();

  let rows = store.unresolved_of(&ws, "p_src").unwrap();
  assert_eq!(rows.len(), 1);
  assert_eq!(
    rows[0].raw_title, "Future Page",
    "原文要保留，建页时直接回填"
  );
  assert_eq!(rows[0].normalized_title, "future page");
}

#[test]
fn backlink_page_count_deduplicates_by_source() {
  let store = test_store();
  let ws = Uuid::new_v4();

  // 同一页的两个块都引用了 target：来源页计数应为 1，边数为 2
  let extracted = ExtractedLinks {
    edges: vec![
      edge("b1", "p_target", LinkKind::Reference, 0),
      edge("b2", "p_target", LinkKind::Reference, 30),
    ],
    unresolved: vec![],
  };
  store
    .replace_page(&ws, "p_src", "h", &extracted, false)
    .unwrap();

  assert_eq!(store.backlinks(&ws, "p_target", 50).unwrap().len(), 2);
  assert_eq!(store.backlink_page_count(&ws, "p_target").unwrap(), 1);
}

#[test]
fn workspace_isolation() {
  let store = test_store();
  let ws1 = Uuid::new_v4();
  let ws2 = Uuid::new_v4();

  let extracted = ExtractedLinks {
    edges: vec![edge("b1", "p_target", LinkKind::Reference, 0)],
    unresolved: vec![],
  };
  store
    .replace_page(&ws1, "p_src", "h", &extracted, false)
    .unwrap();

  assert_eq!(store.backlinks(&ws1, "p_target", 50).unwrap().len(), 1);
  assert!(
    store.backlinks(&ws2, "p_target", 50).unwrap().is_empty(),
    "不同工作区的索引不能互相串"
  );
}

#[test]
fn end_to_end_from_document_data() {
  // 端到端：构造 CRDT 文档快照 → 提取 → 落库 → 反查
  let store = test_store();
  let ws = Uuid::new_v4();

  let mut blocks = HashMap::new();
  blocks.insert(
    "b1".to_string(),
    Block {
      id: "b1".to_string(),
      ty: "paragraph".to_string(),
      parent: "p_src".to_string(),
      children: "b1-children".to_string(),
      external_id: None,
      external_type: None,
      data: HashMap::new(),
    },
  );

  let mut text_map = HashMap::new();
  text_map.insert(
    "b1".to_string(),
    json!([
      {"insert": "跳转到 "},
      {"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p_target"}}},
      {"insert": " 看看"}
    ])
    .to_string(),
  );

  let mut children_map = HashMap::new();
  children_map.insert("p_src".to_string(), vec!["b1".to_string()]);

  let doc = DocumentData {
    page_id: "p_src".to_string(),
    blocks,
    meta: DocumentMeta {
      children_map,
      text_map: Some(text_map),
    },
  };

  let extracted = extract_links(&doc);
  assert_eq!(extracted.edges.len(), 1);

  store
    .replace_page(&ws, "p_src", "hash-e2e", &extracted, false)
    .unwrap();

  let backlinks = store.backlinks(&ws, "p_target", 50).unwrap();
  assert_eq!(backlinks.len(), 1);
  assert_eq!(backlinks[0].char_offset, 4, "「跳转到 」是四个字符");

  // 状态表也要同步，否则重启后会误判为「没建过索引」而全量重扫
  let state = store
    .page_state("p_src")
    .unwrap()
    .expect("state should exist");
  assert_eq!(state.content_hash, "hash-e2e");
  assert_eq!(state.link_count, 1);
}
