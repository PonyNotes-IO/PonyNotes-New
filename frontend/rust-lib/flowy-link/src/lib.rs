//! `flowy-link` —— 双向链接的本地派生索引。
//!
//! # 职责边界
//!
//! 这个 crate 只做三件事：
//!
//! 1. **解析**：从 `DocumentData`（CRDT 快照）里抽出结构化的边（[`extractor`]）。
//! 2. **存取**：把边按页幂等地写进本地 SQLite，并按目标反查（[`store`]）。
//! 3. **服务**：对上层提供 `get_backlinks` / `get_outgoing` 这类查询（[`service`]）。
//!
//! 它**不负责**：渲染、跨设备同步、以及任何服务端交互。
//!
//! # 为什么索引不出设备
//!
//! 笔记是端到端加密的，服务端只有密文。即使客户端上传明文索引，也等于把
//! 「笔记之间的关联结构」交出去 —— 那恰恰是知识库最敏感的部分。
//!
//! 代价必须说清楚：**每台设备各自建索引，未同步到本机的笔记，其入链会缺失。**
//! UI 必须诚实表达这一点（"本地可见范围"），不能假装全知。
//!
//! # 一致性模型
//!
//! 索引是派生数据，真相源永远是正文里的 mention 节点。因此：
//!
//! - 索引可以随时丢弃重建，正文不会受影响；
//! - 写索引失败不阻塞文档保存，只影响反查的即时性；
//! - 冲突时以正文为准，索引按页整体重算（幂等），不做增量修补。

pub mod entities;
pub mod error;
pub mod extractor;
pub mod service;
pub mod store;

pub use entities::{ExtractedLinks, LinkEdge, LinkKind, UnresolvedLink};
pub use error::{LinkError, LinkResult};
pub use extractor::{extract_links, normalize_title};
pub use service::{IndexOutcome, LinkIndexService};
