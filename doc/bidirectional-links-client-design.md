# 客户端双链笔记设计方案

> 适用范围：PonyNotes 客户端（Flutter + Rust FFI + collab/yrs CRDT + 本地 SQLite/Tantivy）
> 目标：把「笔记之间的显式引用」做成一等公民 —— 可创建、可解析、可反查、可视化，并且增量、可修复。
> 状态：客户端双链主流程已实现（本地索引、实时刷新、FFI、入链/出链面板、未解析链接建页、未链接提及、结构图谱与可选语义图层）；性能预算待实测。

## 目录

- [0. 结论摘要](#0-结论摘要)
- [1. 现状评估](#1-现状评估为什么要改)
- [2. 概念边界](#2-概念边界)
- [3. 整体架构](#3-整体架构)
- [4. 核心模块](#4-核心模块) — 数据模型 / 链接建立 / 解析 / 反向索引 / 面板契约 / 图谱
- [5. 数据存储方式](#5-数据存储方式) — 三层划分、**本地表 vs 服务端表**、对服务端的影响
- [6. 链接解析与更新机制](#6-链接解析与更新机制) — 事件源 / 三级增量 / 防抖 / 幂等修复 / CRDT 影响
- [7. 性能与一致性取舍](#7-性能与一致性取舍)
- [8. 可落地方案](#8-可落地方案) — **编译环境** / 模块文件 / 接口契约 / 分阶段 / 埋点
- [9. 风险清单](#9-风险清单)
- [10. 附：核心代码骨架](#10-附核心代码骨架)
- [11. 一页速览](#11-一页速览)

---

## 0. 结论摘要

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| 链接的真相源 | **内嵌在文档正文里**（mention 节点的 `page_id` 属性） | 文档本身就是 CRDT 同步单元，链接跟随文档走，不需要额外事务协调 |
| 反向链接 | **派生索引表**（SQLite `note_link`），永远可重建 | 反查不能靠遍历全库；但索引绝不能成为真相源 |
| 索引粒度 | **按文档重算，按块增量** | 一页通常 < 100 条链接，重算成本极低；块级增量用来对付大文档和打字期 |
| 更新触发 | ~~复用现有 `InstantIndexedDataConsumer` 管线~~ **改为挂 `DocumentManager` 的索引刷新汇聚点** | 实测发现 `InstantIndexedDataConsumer` 管线只传纯文本段落，block id 与 mention 属性全部丢失，无法提取结构化链接；改为在 `index_encoded_collab` 处从 `EncodedCollab` 重建 `DocumentData`（见 §8.3 实施记录） |
| 一致性 | **最终一致 + 读己之写** | 出链读编辑器内存（永远准确），入链读索引（允许 ~500ms 延迟） |
| 图谱数据源 | 结构边（`note_link`）与语义边（AI 抽取）**分层，默认只显示结构边** | 结构边精确、免费、可解释；语义边推断、昂贵、不确定 |
| 是否上云 | **不上云**，纯本地派生数据 | 笔记端到端加密，服务端读不到明文；索引是设备私有的 |
| 最大风险 | 多设备下「本地索引只覆盖已同步的笔记」 | 必须显式向用户暴露索引完整度，不能假装全知 |

一句话：**链接内嵌、索引派生、事件驱动、按页幂等重算、出链实时入链异步。**

---

## 1. 现状评估（为什么要改）

当前实现位于 `frontend/appflowy_flutter/lib/plugins/knowledge_graph/`，是 WeKnora 图谱契约的移植。它的工作方式是：

1. `KnowledgeGraphCubit.refresh()` 拉取工作区**全部 view**，逐页 `getDocument`（每批 4 个，单页 8s 超时）；
2. `KnowledgeGraphBuilder.addDocument()` 把每个 block 的 `data` 和 `meta.textMap` 都 `jsonDecode`，然后 `_references()` **递归遍历整棵 JSON**，凡是键名等于 `page_id` / `view_id` 就记一条边，`href`/`url` 则解析 URL scheme 反推 viewId；
3. 全量结果在内存里建图，`RustStreamReceiver` 收到任何文档更新事件 → 800ms 防抖 → **整图重建**；
4. AI 实体抽取另存 JSON 缓存文件，按 `sha256(blocks+text)` 指纹复用。

这个实现能用，但作为双链功能的地基有四个硬伤：

| 问题 | 后果 |
| --- | --- |
| 递归找键名，而非按编辑器语义解析 | 会把非链接属性误判成链接；拿不到偏移和上下文；`href` 里带 `page_id` 的普通外链会误命中 |
| 无持久化索引，每次全量扫 | 打开图谱 = O(全部文档)；5000 篇笔记时秒级到十秒级卡顿 |
| 全图重建无增量 | 打字 → 800ms → 重建全图，CPU 抖动、节点位置乱跳 |
| 语义边与结构边混在一张图、用同一套过滤 | 无法单独回答"谁引用了我"；AI 抽取失败会连带结构关系一起丢 |

结论：**结构边（双链）要从图谱功能里拆出来，做成独立的数据层 + 索引 + 服务接口**，图谱视图退化为它的一个消费者。

---

## 2. 概念边界

三个容易混淆的东西，必须在数据模型上就分开：

| 概念 | 语义 | 来源 | 是否可推断 | 是否进双链索引 |
| --- | --- | --- | --- | --- |
| **层级（hierarchy）** | 父页面 / 子页面 | `view.parent_view_id` | 完全可推断 | ❌ 不存表，查询时 join view 表 |
| **引用（reference / 双链）** | 正文里明确指向另一篇笔记 | 编辑器 mention 节点、块引用、嵌入 | 精确解析 | ✅ 主表 |
| **语义关系（relation）** | "A 是 B 的创始人" | AI 抽取 / 数据库 relation 字段 | 推断或用户显式配置 | ⚠️ 单独图层；数据库 relation 字段属于显式，可进主表并标 `kind=relation` |

层级边不落表是刻意的：它已经从 `view` 表完全可推导，存一份就是给自己制造不一致的机会，而且会让边数翻倍（每篇笔记至少一条父边）。

---

## 3. 整体架构

```
┌──────────────────────────────────────────────────────────────────┐
│  Flutter (Dart)                                                  │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────┐ │
│  │ 编辑器       │  │ 反向链接面板  │  │ 图谱视图      │  │ 搜索    │ │
│  │ [[ 自动补全   │  │ 入链/出链/上下文│ │ 结构层/语义层 │  │ 未链接   │ │
│  └─────┬──────┘  └──────┬───────┘  └──────┬───────┘  └────┬────┘ │
│        │ 写 mention      │ get_backlinks   │ get_graph      │      │
└────────┼─────────────────┼─────────────────┼────────────────┼──────┘
         │                 │   FFI (protobuf event)            │
┌────────┼─────────────────┼─────────────────┼────────────────┼──────┐
│  Rust  ▼                 ▼                 ▼                ▼      │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ flowy-link（新）                                              │ │
│  │  extractor  ── 结构解析（block/childrenMap/textMap）           │ │
│  │  store      ── note_link / note_link_state / unresolved       │ │
│  │  service    ── get_backlinks / get_outgoing / get_graph        │ │
│  │  consumer   ── 实现 InstantIndexedDataConsumer                 │ │
│  └───────┬───────────────────────────────┬──────────────────────┘ │
│          │ 读 collab                      │ 写 SQLite              │
│  ┌───────▼────────┐              ┌───────▼────────┐                │
│  │ collab-document│              │ flowy-sqlite   │                │
│  │ (yrs / CRDT)   │              │ (WAL)          │                │
│  └───────┬────────┘              └────────────────┘                │
│          │ 变更事件                                                │
│  ┌───────▼──────────────────────────────────────────────────────┐ │
│  │ InstantIndexedDataWriter（复用）                              │ │
│  │   consumers: Tantivy 全文 | Embedding | **Link（新增）**       │ │
│  └──────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

要点：

- **只有一条写入链路**：所有派生数据（全文索引、向量、链接索引）都挂在 `InstantIndexedDataWriter` 的 consumer 上，不另起一套订阅。这样"文档变了但索引没变"的漏更新只可能出现在一个地方，也只需要在一个地方修。
- **解析在 Rust，不在 Dart**：解析要遍历全部 block，放在 UI isolate 会掉帧；Rust 侧还能直接拿到 `DocumentData` 而不用过 protobuf。
- **Dart 只做展示与交互**，不持有索引状态。

---

## 4. 核心模块

### 4.1 笔记数据模型

一篇文档在 CRDT 里的实际形态：

```
DocumentData {
  page_id: String,
  blocks:  HashMap<block_id, Block>,
  meta: {
    children_map: HashMap<children_id, Vec<block_id>>,   // 树形结构
    text_map:     HashMap<external_id, String>            // 富文本 delta（JSON 字符串）
  }
}

Block {
  id, ty, parent, children_id, external_id, external_type,
  data: String   // JSON：{ "delta": [...] } 或 {"url": ...} 等
}
```

关键点：**正文可能有两个位置**。

- `block.external_type == "text"` 时，delta 在 `meta.text_map[block.external_id]`；
- 否则 delta 在 `block.data` 里的 `"delta"` 字段。

现有 Dart 代码已经区分了这两种情况，Rust 侧也要照做，否则会漏掉大部分正文。

**链接节点的形态**（inline mention）：

```json
{ "insert": "$", "attributes": { "mention": { "type": "page", "page_id": "<uuid>" } } }
```

`type` 取值见 `MentionType`：`page` / `childPage` / `date` / `user` / `link`。我们只关心 `page`、`childPage`、以及 `link` 中指向内部页面的那些。

**链接的三种承载方式**（都要支持，但优先级不同）：

| 形式 | 载体 | 优先级 |
| --- | --- | --- |
| 行内提及 `[[页面]]` | delta op 的 `mention.page_id` | P0 |
| 子页面 / 嵌入 | `childPage` mention 或子 view 的 `parent_view_id` | P0（子页算层级，嵌入算引用） |
| 指向某一块 `((block_id))` | `mention.page_id + mention.block_id` | P2 |

数据模型上不需要为链接单独开一张"链接表存在文档里"——**链接是正文的一部分**。这条决定了后面所有的取舍：复制页面自然带走链接，删除页面自然消除出链，协作冲突由 CRDT 天然解决。

### 4.2 链接的建立

创建入口（P0 只需前两个）：

1. **`[[` 触发补全**：输入两个方括号 → 弹出页面选择器（复用 `mobile_page_selector_sheet` / 桌面端 mention 面板）→ 插入带 `page_id` 的 mention 节点。**绝不插入纯文本标题**。
2. **拖拽 / 粘贴**：侧边栏把页面拖进正文 → 默认插入 mention（按住 Alt 转为子页面）。
3. **粘贴站内分享链接**：`ponynotes://...?viewId=xxx` 或 `/share` 链接 → 解析出 viewId → 转成 mention。这段逻辑目前散落在图谱的 `_references()` 里，应下沉到 `extractor` 的"URL → viewId 解析"，只在一个地方维护。
4. **自动转链接**：输入文字恰好等于某笔记标题时提示"建立链接？"（P3，依赖标题索引）。

**创建即索引**：编辑器插入 mention 的那一刻，Dart 侧就可以把新边推给"出链内存缓存"，UI 立刻正确；持久化交给事件管线（见 §6）。

### 4.3 链接解析

解析器的输入是 `&DocumentData`，输出是扁平的边列表。

```rust
pub struct LinkEdge {
  pub src_page_id: String,
  pub src_block_id: String,
  pub dst_page_id: String,
  pub dst_block_id: Option<String>,
  pub kind: LinkKind,        // Reference | Embed | BlockRef | Relation
  pub label: String,         // 展示文本快照（当时输入的标题）
  pub offset: u32,           // 在该块正文中的字符偏移，用于滚动定位
}

pub fn extract(page_id: &str, doc: &DocumentData) -> Vec<LinkEdge>;
```

算法：

```
walk(root_block_id):                      # 用 children_map 走真实顺序
  for block in children(root):
    delta = resolve_delta(block)          # text_map 优先，其次 data.delta
    pos = 0
    for op in delta:
      if op.insert is str:  pos += len; continue
      if op.insert == "$" and op.attributes.mention.type in {page, childPage}:
        push(LinkEdge { dst: page_id, block: block.id, offset: pos, label: 原文本 })
      pos += 1
    walk(block.children_id)
```

必须遵守的五条规则：

1. **走 `children_map`，不按 blocks 的哈希顺序**：`blocks` 是 `HashMap`，顺序不稳定，按它解析会得到非确定的 offset。
2. **只认结构化属性，不递归找键名**：这是与现状最大的差别。`page_id` 只有出现在 `mention` 命名空间下才算链接；数据库 relation 字段走独立分支。
3. **同块内去重合并**：同一块里重复引用同一页面，存一行 + `occurrence` 计数，保留首个 offset。否则一个索引列表块能把边数炸到几百倍。
4. **自引用**：允许（日记里链接自己），但 `dst == src` 的边在图谱和计数里排除，只保留在面板里提示"本文引用了自己"。
5. **悬空引用不丢弃**：目标页面被删/不在本地时，边仍然保留（`dst_page_id` 指向一个不存在的 view），查询时 join view 表判定为"已删除"或"未同步"。删边等于让信息永久丢失。

**未解析链接（unresolved）**：当正文里出现纯文本 `[[某标题]]`（导入的 Markdown、用户手打）而当前没有同名页面时，解析器额外产出：

```rust
struct UnresolvedLink { src_page_id, src_block_id, normalized_title, raw_title }
```

`normalized_title` 做 NFKC + 去首尾空白 + 连续空白折叠 + 大小写折叠（中文场景下不需要大小写，但英文标题需要）。这些进 `note_link_unresolved` 表，UI 上以灰色虚线展示，点击可"创建该笔记并自动回填"。**解析器永远不自动创建页面**——AI 生成的内容里满是 `[[概念]]`，自动建页会污染工作区。

### 4.4 反向链接索引

表结构（新增 migration）：

```sql
-- 结构边主表：一行 = 一次（源块 → 目标页）的引用
CREATE TABLE IF NOT EXISTS note_link (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  workspace_id TEXT    NOT NULL,
  src_page_id  TEXT    NOT NULL,
  src_block_id TEXT    NOT NULL,
  dst_page_id  TEXT    NOT NULL,
  dst_block_id TEXT,                        -- 块引用时非空
  kind         TEXT    NOT NULL,            -- reference|embed|block_ref|relation
  label        TEXT    NOT NULL DEFAULT '', -- 展示文本快照
  offset       INTEGER NOT NULL DEFAULT 0,
  occurrence   INTEGER NOT NULL DEFAULT 1,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_note_link_dst ON note_link(workspace_id, dst_page_id);
CREATE INDEX IF NOT EXISTS idx_note_link_src ON note_link(workspace_id, src_page_id);

-- 每页索引状态：用于判定是否需要重算（复用 collab 的 content_hash）
CREATE TABLE IF NOT EXISTS note_link_state (
  page_id      TEXT PRIMARY KEY,
  content_hash TEXT NOT NULL,
  link_count   INTEGER NOT NULL,
  indexed_at   INTEGER NOT NULL
);

-- 悬空/未解析引用
CREATE TABLE IF NOT EXISTS note_link_unresolved (
  workspace_id     TEXT NOT NULL,
  src_page_id      TEXT NOT NULL,
  src_block_id     TEXT NOT NULL,
  normalized_title TEXT NOT NULL,
  raw_title        TEXT NOT NULL,
  PRIMARY KEY (workspace_id, src_page_id, src_block_id, normalized_title)
);
```

设计说明：

- **不存层级边**：`SELECT parent_view_id FROM view` 就够了，省一半行数、少一处不一致。
- **不存上下文全文**：面板要展示"引用处的上下文"，用 `(src_page_id, src_block_id)` 回查文档拿最新文本。存快照会和正文漂移，而块已经被删时上下文本来就该消失。
- **`label` 是快照，不是真相**：展示标题时优先用 view 表的**当前**标题，`label` 只在目标页已删除/未同步时兜底显示（"引用了已删除的《旧标题》"）。
- **不建外键**：目标页可能尚未同步到本地，外键会让插入失败。完整性由查询期 join 保证。

查询（入链）：

```sql
SELECT src_page_id, src_block_id, kind, label, offset, Count(*) AS n
FROM note_link
WHERE workspace_id = ?1 AND dst_page_id = ?2 AND src_page_id <> ?2
GROUP BY src_block_id
ORDER BY updated_at DESC
LIMIT 200;
```

在 Rust 层再做一次权限过滤（目标 view 是否可读、是否同 space、是否在回收站），**不要**把权限状态复制进索引表——权限会变，复制就是埋雷。

### 4.5 反向链接面板（数据契约）

面板分三块，数据来源刻意不同：

| 区块 | 数据源 | 一致性 |
| --- | --- | --- |
| **出链**（本文引用了谁） | 编辑器 `EditorState` 内存直接算 | 强一致，零延迟 |
| **入链**（谁引用了本文） | `note_link` 索引 | 最终一致（≤ 1s） |
| **未链接提及**（正文提到标题但没建链） | Tantivy `NAME` 字段检索 | 最终一致，可关闭 |

为什么出链不用索引？因为用户刚插入一个链接时，如果面板显示的还是旧的，会显得"坏了"。出链是 O(当前文档)，内存里算一遍毫无成本；入链是 O(全库)，必须走索引。**这个不对称是整个设计里最划算的一笔**。

面板订阅 `link_changed(view_id)` 事件流，索引写入后主动推送刷新，避免轮询。

### 4.6 图谱视图

**双层图**，UI 上有开关：

```
StructuralLayer:  nodes = views(documents)
                  edges = note_link (kind != hierarchy)
                  + hierarchy edges（查询时由 parent_view_id 生成）

SemanticLayer:    nodes = entity:<normalized_name>
                  edges = AI 抽取的 relation / doc→entity 的 mention
                  独立缓存文件，独立开关，永不默认开启
```

两者可以叠加显示，但**过滤、计数、布局权重必须分开**——语义边是"可能相关"，结构边是"确实引用"，混在一起用户无法判断可信度。

**局部图优先**：

- 默认打开某篇笔记的图谱 = **自我网络（ego graph）**，深度 1（可切 2），节点上限 500、边上限 2000；
- 每次增量展开时按度数排序取前 N，超出部分显示"+ 还有 137 个节点"而不是静默截断；
- 全局图是显式操作，且走后台任务 + 进度提示。

**布局**：

- 力导向用 Barnes-Hut 四叉树近似（朴素 O(n²) 在 2000 节点时每帧 4M 次距离计算，必然掉帧）；
- 布局在**独立 isolate** 里跑，只回传坐标；
- **坐标持久化**：`graph_layout(page_id, x, y, updated_at)`。重开图谱时用旧坐标播种，只跑少量迭代；新增节点落在邻居质心附近。没有这一步，每次编辑后图都会"炸开重排"，用户会失去空间记忆。
- 支持固定节点（pin）、按 space/tag 分组着色。

**渲染**：

- `CustomPainter` + `RepaintBoundary`，所有边合成一条 `Path` 批量绘制；
- 标签按缩放级别分级显示（zoom < 0.5 只显示度数 top 20 的节点标签）；
- 命中测试用空间哈希网格，不要线性遍历。

节点规模到 5000+ 且需要平滑缩放时，再考虑 WebView + sigma.js 的方案；在此之前自绘的性能和交互一致性更好。

---

## 5. 数据存储方式

三层，职责严格分离：

| 层 | 内容 | 位置 | 可重建 | 是否同步 |
| --- | --- | --- | --- | --- |
| 真相层 | 文档 + 内嵌 mention | collab/yrs（本地 + 云端 E2EE） | 否 | 是 |
| 派生层 | `note_link` / `state` / `unresolved` | 本地 SQLite（WAL） | 是，任何时刻 | 否 |
| 缓存层 | 图谱布局坐标、AI 语义图 | 本地 SQLite / JSON 文件 | 是 | 否 |

**为什么索引不上云**：

1. 笔记端到端加密，服务端只有密文，本来就建不了索引；
2. 即使客户端上传明文索引，也等于把"笔记之间的关联结构"泄露给服务端——这恰好是知识图谱里最敏感的部分；
3. 上传索引就要处理多端合并、版本、权限，复杂度远超收益。

代价是每台设备各自建索引（见 §10 风险 R1）。

**增量写入的事务边界**：一页一个事务。

```sql
BEGIN;
DELETE FROM note_link WHERE src_page_id = ?1;
INSERT INTO note_link (...) VALUES (...), (...);   -- 批量
INSERT OR REPLACE INTO note_link_state(page_id, content_hash, link_count, indexed_at)
  VALUES (?1, ?2, ?3, ?4);
COMMIT;
```

SQLite 开 WAL + `synchronous=NORMAL`：崩溃最多丢最后一次防抖窗口的索引，不丢文档，且下次启动会被 hash 校验拉回。

### 5.1 对服务端的影响：零改动，但有读放大

**结论：本方案不需要改动后端**（`PonyNotes-Cloud-New/` 一行不动）。

#### 先排除一个歧义：「建表」建在谁的机器上

项目里有两个名字都叫 `migrations` 的目录，形态与执行主体完全不同，很容易混：

| | 客户端（本方案要动的） | 服务端（**不动**） |
| --- | --- | --- |
| 路径 | `PonyNotes-New/frontend/rust-lib/flowy-sqlite/migrations/` | `PonyNotes-Cloud-New/migrations/` |
| 形态 | **目录**，每个含 `up.sql` / `down.sql`（当前 37 个） | **单文件** `.sql`（当前 98 个） |
| 执行者 | 客户端进程自己 | 部署时对 PostgreSQL |
| 执行时机 | App 启动时 `run_pending_migrations` | 发布流程 |
| 数据落地 | 用户设备上的 `flowy-database.db` | 服务器数据库 |

客户端的机制是编译期内嵌，`flowy-sqlite/src/lib.rs`：

```rust
pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("../flowy-sqlite/migrations/");
// 启动时在本地库上执行
(*conn).run_pending_migrations(MIGRATIONS)
```

迁移脚本随安装包分发，运行时在本地 SQLite 上建表，**没有任何网络请求**。所以下文所说的"新增 `note_link` 表"，指的是在 `flowy-sqlite/migrations/` 下增加第 38 个目录，字段定义落在用户本机的 SQLite 文件里。

具体地：

| 事项 | 是否涉及服务端 |
| --- | --- |
| 新增 `note_link` 等表 | ❌ 本地 SQLite，客户端迁移目录（见上表），与服务端 `PonyNotes-Cloud-New/migrations` 无关 |
| 新接口（`get_backlinks` / `get_graph`） | ❌ 纯本地 FFI 事件，走 `flowy-document` 的 event_map |
| protobuf 变更 | ❌ 客户端本地生成，服务端不校验这些消息 |
| 同步协议 | ❌ 链接已在 collab 文档里随 CRDT 同步，无需新通道 |
| 索引数据 | ❌ 不上传、不落云端 |

**但"不改代码"不等于"没有影响"。** 唯一的真实影响在读取路径：

```
get_document_data(doc_id)
  → get_document(doc_id)
    → create_document_instance(doc_id, enable_sync = false)
        └─ if !is_doc_exist(doc_id) { cloud_service.get_document_doc_state(...) }   // 走网络
```

也就是说，**本地磁盘没有的文档会触发一次云端拉取**。这带来两个必须处理的点：

1. **首次全量索引 = N 次云端请求**。1 万篇笔记就是 1 万次拉取，且这些实例 `enable_sync=false`，不会被 `self.documents` 缓存，重复扫描可能重复拉。当前图谱实现"任何编辑 → 800ms 防抖 → 全量重建"如果命中未本地化的文档，等于在按编辑频率反复打服务端。
   - 对策：**索引只处理本地已存在的文档**（`is_doc_exist` 为真），未本地化的页标记 `pending` 跳过；后台补齐任务限速（如 5 页/秒）+ 指数退避 + 失败不计入修复队列。绝不为了"反链完整"一次性拉全库。
2. **容量与带宽成本**：若产品坚持"换设备立刻看到完整反链"，就必须主动拉全库，服务端对象存储与带宽成本会上升。这是运营成本，不是代码改动，但要在立项时说清楚。

**这也是 E2EE 的不可逆性**：一旦把索引搬到服务端，服务端就要能读明文，等于放弃端到端加密，且回不了头。保持纯客户端派生，是在保后路。

**什么情况下才真的必须改后端**：需要服务端主动推送"你的笔记被谁引用了"、或需要跨设备秒级全量反链。这两个需求都与 E2EE 冲突，建议明确不做。

---

## 6. 链接解析与更新机制

### 6.1 事件源

| 事件 | 来源 | 处理 |
| --- | --- | --- |
| 本地编辑 | 编辑器 transaction → collab 本地写 | 走统一管线 |
| 远端协作更新 | `DocumentNotification::DidReceiveUpdate`（含 `DocEventPB`） | 走统一管线 |
| 导入 / 恢复 | folder 事件 + 文档加载 | 全量重算该页 |
| 删除 / 移入回收站 | `DidMoveViewToTrash` / `DidDeleteView` | 不删边，只置状态；永久删除时清理 |
| 重命名 | `DidUpdateView` | 只更新 `label` 快照，不重算边 |
| 移动 / 换 space | `DidMoveView` | 层级边自动跟随（不落表的好处） |

### 6.2 增量策略（三级）

```
L0  编辑器内（Dart）：mention 插入/删除 → 立刻更新出链内存缓存，不动 DB
L1  块级增量（Rust）：事件带 changed_block_ids → 只重解析这些块，按 src_block_id 局部替换
L2  文档级重算（Rust）：事件无块信息 / hash 不匹配 / 首次索引 → 整页 delete+insert
L3  全库修复（后台）：启动时比对 note_link_state.content_hash 与 collab content_hash，差异入修复队列
```

**为什么不直接做 L2**：一篇 300 块的文档，块级增量 ~50µs，整页重算 ~1ms。单次差异不大，但打字时每秒触发 10 次，L2 会产生 10 倍的写入放大和无谓的 WAL 增长。L1 的价值在于"高频路径便宜"，L2 的价值在于"简单且永远正确"。两者都要，L1 是优化，L2 是兜底。

**L1 的前置条件**：`DocEventPB` 目前只带 `(events, is_remote)`，需要扩展出 `changed_block_ids`。这是 `flowy-document` 里的一处小改动（`subscribe_block_changed` 的回调本来就拿到了块级事件），但它是整个增量方案的支点，必须做。

### 6.3 防抖与合并

```
编辑事件 → 每页一个 dirty 标记 + 500ms 防抖
        → 单个后台任务串行消费（mpsc，一工作区一个消费者）
        → 同一页在窗口内多次变更合并为一次
        → 每次消费前重新计算 hash，hash 未变则跳过
```

**串行 + 单写者**是刻意的：并发写同一页会互相覆盖 `DELETE/INSERT`，加锁又容易死锁。一工作区一个 consumer 任务，吞吐也足够（每页 1ms，1000 页全量也就 1s）。

### 6.4 幂等与修复

不变式：**静止状态下，`rows(src_page = p)` 必须等于 `extract(doc(p))`。**

保证方式：

- 每次写入都是"全删该页 + 全插"，天然幂等，重放安全；
- `content_hash` 用 `sha256(规范化后的边集合)`，与 `index_collab_record_table.content_hash`（已有表，记录 collab 内容哈希）对照；
- 启动时跑一次轻量对账：只比 hash，不解析文档；不一致的页进后台修复队列，限速（如 20 页/秒）避免开机卡顿；
- 提供开发者命令 `ForceReindex(workspace_id)`，用于 schema 升级或用户反馈"链接不对"。

### 6.5 CRDT 合并的影响

两台设备并发编辑同一页，CRDT 合并后文档是确定的，索引按整页重算也是确定的 → 两端最终一致，不需要合并索引本身。这是"派生 + 幂等重算"相对"增量维护索引"的核心优势：**把分布式一致性问题下推给了 CRDT**。

---

## 7. 性能与一致性取舍

### 7.1 关键取舍表

| 取舍 | 选择 | 代价 | 何时该反过来 |
| --- | --- | --- | --- |
| 索引 vs 实时遍历 | 索引 | 多一层存储、可能不一致 | 文档 < 100 篇的轻量场景，实时遍历更省事 |
| 整页重算 vs 块级 diff | 两者都要 | 块级 diff 需要块级事件 | 事件管线改不动时，整页重算 + 更长的防抖也能上线 |
| 出链实时 vs 出链走索引 | 实时 | 面板逻辑分两套 | 出链数量极大（>500）时实时遍历会卡编辑器 |
| 索引是否同步 | 不同步 | 跨设备不全 | 用户强需求"换设备立刻看到全部反链"时，再考虑加密索引同步 |
| 语义边是否默认显示 | 不默认 | 用户可能以为功能缺失 | 语义抽取质量稳定后可默认开启 |
| 图谱整图 vs 局部图 | 局部优先 | 全局探索感变弱 | 节点 < 300 时整图无损 |

### 7.2 预算（估算，需实测校准）

| 操作 | 目标 | 备注 |
| --- | --- | --- |
| 单块解析 | < 5 µs | 纯内存遍历，无 IO |
| 单页整页重算 | < 2 ms | 300 块 + 20 条链接 |
| 打开反链面板 | < 30 ms | 索引查询 + 上下文回填 |
| 10k 页全量建索引 | < 30 s（后台，可分片） | 必须可中断、可续跑 |
| 索引体积 | 10 万行 ≈ 15 MB | 不存层级边、不存上下文全文 |
| 打字期每千次编辑写放大 | < 20 次事务 | 500ms 防抖 + hash 跳过 |

### 7.3 一致性模型（写清楚，UI 才有依据）

- **读己之写**：本设备刚做的编辑，出链立刻正确（内存算）。
- **单调读**：索引只前进不后退；同一页的重算用 `updated_at` + 事务保证不出现"旧结果覆盖新结果"（重算前比对 hash）。
- **最终一致**：入链延迟 ≤ 防抖窗口 + 写事务，通常 < 1s。
- **局部完整**：索引只覆盖**本地已同步**的文档。远端有新文档但本机没拉下来时，入链会少。这一点必须通过 UI 表达（见 R1），不能靠猜。

---

## 8. 可落地方案

### 8.0 编译与验证环境

**开工前必须先设置 `TMPDIR`**，否则编译直接失败：

```bash
export TMPDIR=/home/michi/.cache/build-tmp   # 或任意根分区下的目录
mkdir -p "$TMPDIR"
cd frontend/rust-lib && cargo check -p flowy-sqlite
```

原因：`/tmp` 在这台机器上是 **tmpfs，只有 10MB**，而 `libsqlite3-sys` 的 `bundled` 特性要编译 `sqlite3.c`（单文件 20 万行），cc 的中间产物有数百 MB，写不下会报：

```
error: sqlite3/sqlite3.c: fatal error: error writing to /tmp/ccXXXX.s: No space left on device
```

根分区实际有 200G+ 空闲，只是默认临时目录选错了。首次带 `TMPDIR` 编译约 18 秒（有 `target` 缓存时）。

工具链：`rust-toolchain.toml` 固定 `1.91`；工作区已有 21G `target` 缓存，增量编译可用。

### 8.1 模块与文件

```
frontend/rust-lib/flowy-link/                 # 新 crate（P0 已落地）
  src/extractor.rs     # DocumentData -> Vec<LinkEdge> / Vec<UnresolvedLink（wikilink + 行内 mention + 块级 mention）
  src/store.rs         # LinkIndexStore：note_link 读写，事务，hash 比对（持有 Arc<ConnectionPool>）
  src/service.rs       # LinkIndexService：index_document / on_page_deleted / get_backlinks / get_outgoing
  src/entities.rs      # LinkEdge / LinkKind / UnresolvedLink / IndexOutcome
  src/error.rs         # LinkError / LinkResult
  tests/store_test.rs  # 真实 SQLite 集成测试
flowy-sqlite/migrations/2026-11-03-000001_note_link_index/  # up.sql / down.sql（P0 已落地）
flowy-document/src/manager.rs                  # index_links 挂 index_encoded_collab 汇聚点；remove_link_index 挂 delete_document
flowy-user/src/services/{db,authenticate_user}.rs  # get_pool 开放 + get_sqlite_pool 透传
flowy-core/src/deps_resolve/document_deps.rs   # DocumentUserImpl::sqlite_pool 实现

（待实现）
flowy-document/src/event_map.rs                # 新增 Backlink/Graph 事件（编号从 21 起）
flowy-ai 之外的事件暴露走 event_map.proto + FFI

frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/backlinks/
  backlink_panel.dart          # 三区块面板
  backlink_cubit.dart          # 订阅 link_changed 流
  mention_autocomplete.dart    # [[ 触发补全
frontend/appflowy_flutter/lib/plugins/knowledge_graph/
  application/link_graph_service.dart   # 新：走 FFI 取图
  application/knowledge_graph_data.dart # 改：删除 _references() 递归找键名
```

### 8.2 接口契约（protobuf 草案）

```protobuf
message BacklinkPB {
  string src_page_id = 1;
  string src_page_name = 2;   // 查询时 join view 表填充当前标题
  string src_block_id = 3;
  LinkKind kind = 4;
  string context = 5;         // 引用处前后各 60 字，服务端剪裁
  uint32 occurrence = 6;
  bool target_missing = 7;    // 目标页已删除/未同步
}

message GraphRequest {
  string workspace_id = 1;
  string focus_page_id = 2;   // 空 = 全图
  uint32 depth = 3;           // 默认 1，上限 2
  uint32 max_nodes = 4;       // 默认 500
  bool include_semantic = 5;  // 默认 false
}
```

### 8.3 分阶段

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| **P0** | 表 + extractor + consumer + `get_backlinks`；反链面板（入链/出链）；`[[` 补全 | 1000 篇笔记新建链 → 1s 内反链出现；重启后不丢 |
| **P1** | 图谱改走索引 + 局部图 + 坐标持久化；L1 块级增量 | 打开图谱 < 300ms；编辑时图不重排 |
| **P2** | 未解析链接 + 一键建页；块引用；嵌入（transclusion）；未链接提及 | 导入 Markdown 的双链能自动识别 |
| **P3** | 语义层与结构层叠加（保留现有 AI 能力，改为可选图层） | 语义抽取失败时结构关系不受影响 |

**迁移注意**：P0 上线时旧图谱数据的 `_references` 逻辑要删干净，但 AI 抽取缓存文件保留（key 不变即可复用）。两套边同时存在会让图谱出现重复边和幽灵节点。

### 8.4 埋点

- `links_indexed_total` / `links_reindex_repaired`（修复量长期非 0 说明有漏事件）
- `backlink_query_ms` P50/P95
- `graph_open_ms` + 节点/边数
- `unresolved_link_created`（有多少悬空链接最终被建页，判断功能价值）

### 8.3 实施记录（P0，2026-11-03）

**已落地并通过验证**：`flowy-link` crate（extractor / store / service，26 个测试全绿，含真实 SQLite 集成测试）、`note_link` 迁移、`DocumentManager` 接入（索引刷新 + 删除清理）、按用户连接池装配。

**实施中发现的设计修正**（均已回写上文）：

1. **接入点变更**：原方案挂 `InstantIndexedDataConsumer`，但该管线传给消费方的 `UnindexedData` 只有纯文本段落（`Text` / `Paragraphs`），block id 与 mention 属性全部丢失，结构化链接根本无法提取。实际实现：在 `DocumentManager` 的 `index_encoded_collab` 汇聚点（与 Tantivy 索引同一触发时机），用 `decode_document_data` 从 `EncodedCollab` 新建临时 Collab 实例还原 `DocumentData`。
2. **连接池获取方式**：连接池按用户、按会话隔离，而 `DocumentManager` 构造早于登录，无法构造时注入。实际实现：`DocumentUserService::sqlite_pool()` 按需获取（带默认实现返回错误 → 索引自动跳过），`flowy-core` 的 `DocumentUserImpl` 基于新增的 `AuthenticateUser::get_sqlite_pool` 实现。
3. **删除路径**：`delete_document` 调 `remove_link_index` 清出链；指向已删页的入链刻意保留。

**本机构建约束**（所有 cargo 命令必须遵守）：

- `/tmp` 是 10MB 的 tmpfs，编译大 C 文件必炸：必须带 `TMPDIR=/home/michi/.cache/build-tmp`。
- GCC 15.2 与 `librocksdb-sys`（rocksdb 9.0）不兼容（`uint64_t has not been declared`）：必须带 `CXXFLAGS="-include cstdint"`。rocksdb 首次编译约 6 分钟，之后有缓存。
- 重新生成 Rust protobuf（如 proto 变更）：`cargo check -p <crate> --features dart` 触发 build.rs；本机 `protoc-gen-dart` 插件输出带 `MSG :` 前缀会解析失败并 panic，用不含 `~/.pub-cache/bin` 的 PATH 跑即可跳过 dart 生成、只生成 Rust prost 文件。
- 多个 cargo 进程并发会抢锁，串行执行。

**业务接入完成（2026-11-03）**：

- `DocumentEvent::GetDocumentLinks = 22`：传页面 UUID 返回入链、出链、未解析候选；留空页面 UUID 返回当前工作区结构边快照。`ReindexDocumentLinks = 23`：只修复本地已存在的单页，不触发全库远端下载。请求中的工作区必须与当前会话一致。
- `DocumentNotification::DidUpdateLinks = 5`：按工作区通知索引变化。打开的文档通过 CRDT block observer 接入 500ms 防抖，覆盖本地修改、撤销/重做和远端合并；关闭保存、导入和永久删除沿用原索引汇聚点并通知消费者。
- `DocumentData.page_id` 实际是文档根块，不等于笔记 view UUID。解析从根块的 `children` 对应 children_map 遍历，`index_document_for` 用 view UUID 写入源页面，避免反查命中内部根块 ID。
- 后续迁移给 `note_link_state` 增加工作区归属，覆盖统计包含零链接页面。`flowy-sqlite/build.rs` 跟踪 migrations 目录，避免新增迁移被编译缓存漏掉。
- 编辑器页尾的 `BacklinkPanel` 提供实时出链、入链、引用上下文和块跳转；来源只使用当前可读、非回收站 view 列表中的标题。目标不可用时显示缺失状态。旧笔记首次使用时后台补建本地索引，并提供手动重建、进度、失败数量和重试。
- 未解析 `[[标题]]` 支持从同名候选中明确选页，或经创建权限检查创建子笔记后回填正文 mention；对话框期间发生的正文变化不会被覆盖。现有 `[[` 自动补全继续写结构化 mention。现有 mention 的 `block_id`、页面拖拽和站内链接粘贴与双链索引兼容。
- 未链接提及按需调用独立的 `SearchEvent::LocalSearch = 1`，只查询当前工作区本地 Tantivy，不启动云端搜索、不取消命令面板正在进行的搜索。最多验证 50 篇候选，排除本文及已有入链来源，实际回读正文确认标题出现后再展示来源块。索引不可用或搜索失败时显示重试，不将失败伪装成空结果。
- 生产图谱通过一次索引查询读取结构边，不再为结构关系读取全库正文；局部图支持 1/2 跳，每次最多渲染 500 个节点，超限显示遗漏数量。后端结构边快照最多 20000 条，并显式报告截断。
- 图谱坐标按用户、工作区、全局/局部图与结构/语义视图分别持久化。已有节点保留坐标，新节点优先落在已知邻居附近；搜索/筛选保留已知位置。语义图层由用户主动开启，AI 抽取继续是显式操作。
- 解析器补齐同块重复引用合并、重复 unresolved 去重、NFKC 标题规范化、块引用目标、站内 URL 白名单；未知 mention 类型和任意 JSON 的 page_id/view_id 不再被当成链接。指纹包含展示快照与字段边界，避免别名更新遗漏或字段拼接歧义。

**验证（2026-11-03）**：`cargo check -p flowy-core` 通过；`cargo test -p flowy-link -p flowy-search` 共 34 项通过（解析、真实 SQLite、真实 Tantivy、本地搜索不调用云端且不取消现有搜索）；Flutter 3.35.0 下双链与图谱的单元/组件测试共 34 项通过。Flutter 验证使用 `--no-pub` 复用项目现有依赖与已同步的翻译资源，不能混用系统另一个 Flutter SDK。

**验收边界**：本轮覆盖双链业务主流程。§7.2 的毫秒级性能预算和千篇/万篇容量目标尚未做实机压测；L1 按块增量仍属后续优化，当前采用防抖整页解析与链接指纹跳写。嵌入沿用既有页面/块引用展示，不新增独立的全文 transclusion 编辑器。索引始终只覆盖本机已有文档，未同步的远端内容需同步后重建或打开该页。

---

## 9. 风险清单

| # | 风险 | 影响 | 缓解 |
| --- | --- | --- | --- |
| R1 | **索引只覆盖本地已同步文档**，多设备下入链不全 | 用户以为链接丢了 | 面板显示"索引基于本机 N 篇笔记"，对未同步页给占位提示；可选"拉取全部后重建" |
| R2 | 索引与文档漂移（漏事件、崩溃、schema 变更导致解析规则变化） | 反链不准，且难被用户察觉 | hash 对账 + 启动修复队列 + `ForceReindex`；解析规则变更时 bump 一个 `extractor_version` 写进 state 表，版本不符全量重建 |
| R3 | 结构化解析漏掉未覆盖的链接形态（新块类型、新 mention 类型） | 静默少链接 | 解析器对未知 `mention.type` 打日志计数；单测覆盖每种块类型；golden file 测试 |
| R4 | 同名笔记导致标题解析歧义 | 链错页面 | 一律以 id 为准；标题只用于悬空链接的**提示**，由用户点选确认 |
| R5 | 权限/空间隔离：反链把 A 空间的笔记标题泄露到 B 空间 | 隐私事故 | 查询期按可读 view 过滤；索引不复制权限；跨 space 的边默认不显示 |
| R6 | 大文档（万字 + 上百链接）整页重算抖动 | 编辑卡顿 | L1 块级增量兜住高频；单页链接数超阈值时降级为"仅后台索引" |
| R7 | 打字期写放大导致 WAL 膨胀 / IO 抖动 | 移动端耗电、卡顿 | 500ms 防抖 + hash 跳过 + 移动端仅在面板打开时索引 |
| R8 | AI 语义边质量波动污染图谱 | 用户不信任图谱 | 分层 + 默认关闭 + 边显示"依据原文"引用块；抽取失败不影响结构层 |
| R9 | 循环引用 / 自引用导致图谱布局发散 | 图挤成一团 | 布局加最小斥力；自引用不入图；环高亮而非展开 |
| R10 | 嵌入（transclusion）语义未定：嵌入了内容算不算链接？ | 边定义混乱 | 明确定义：嵌入 = 引用边 + 渲染时展开；不参与反向链接的"引用计数"，单独计数 |
| R11 | 回收站里的页面仍持有出链，反链面板出现"幽灵来源" | 用户困惑 | 目标在回收站/来源在回收站分别用不同状态展示，不静默过滤 |
| R12 | Flutter 侧两套图数据源并存期（旧 JSON 遍历 + 新索引） | 重复边、幽灵节点 | 一次性切换，用 feature flag 控制；旧路径标记 deprecated 并在下个版本删除 |

---

## 10. 附：核心代码骨架

### 10.1 extractor（Rust）

```rust
pub fn extract(page_id: &str, doc: &DocumentData) -> (Vec<LinkEdge>, Vec<UnresolvedLink>) {
  let mut edges = Vec::new();
  let mut unresolved = Vec::new();
  let mut visited = HashSet::new();
  walk(page_id, doc, doc.page_id.as_str(), &mut visited, &mut edges, &mut unresolved);
  dedup_merge(&mut edges);          // 同 (block, dst) 合并，累加 occurrence
  edges.retain(|e| e.dst_page_id != page_id); // 自引用不入索引
  (edges, unresolved)
}

fn resolve_delta<'a>(doc: &'a DocumentData, block: &'a Block) -> Option<Cow<'a, str>> {
  match (&block.external_type, block.external_id.as_str()) {
    (&Some(ref ty), id) if ty == "text" => doc.meta.text_map.as_ref()?.get(id).map(|s| Cow::Borrowed(s.as_str())),
    _ => None,
  }
  // 否则读 block.data 里的 "delta"；两者都没有则跳过
}

fn walk(...) {
  // 严格按 doc.meta.children_map 顺序遍历，保证 offset 确定
}
```

### 10.2 consumer（Rust）

```rust
#[async_trait]
impl InstantIndexedDataConsumer for LinkInstantIndexConsumer {
  fn consumer_id(&self) -> String { "note_link_instant_index".into() }

  async fn consume_collab(&self, ws: &Uuid, data: Option<UnindexedData>,
                          object_id: &Uuid, _t: CollabType) -> Result<bool, FlowyError> {
    let Some(data) = data.filter(|d| !d.is_empty()) else { return Ok(false) };
    // 1. 从 UnindexedData 还原 DocumentData
    // 2. 与 note_link_state.content_hash 比对，未变直接返回
    // 3. extract → 单事务 delete+insert（见 §5）
    Ok(true)
  }

  async fn did_delete_collab(&self, object_id: &Uuid) -> Result<(), FlowyError> {
    // 永久删除：清掉该页出链；入链不删，改由查询期判定 target_missing
    Ok(())
  }
}
```

### 10.3 反链面板（Dart）

```dart
// 出链：直接读编辑器，永远准确
List<LinkTarget> outgoing = collectMentions(editorState.document);

// 入链：订阅后端流，允许延迟
Stream<BacklinkPB> incoming =
    LinkService.instance.subscribeBacklinks(viewId);

// 未链接提及：仅当用户展开时查询，避免每次开面板都打全文索引
Future<List<UnlinkedMention>> unlinked() =>
    LinkService.instance.findTitleOccurrences(viewId, excludeLinked: true);
```

---

## 11. 一页速览

1. 链接是正文的一部分，不是独立的表；索引是它的物化视图。
2. 解析用结构化遍历（`children_map` + delta op 属性），永远不递归找键名。
3. 索引按页幂等重算，hash 对账做兜底；块级增量只用来优化高频路径。
4. 出链实时算、入链查索引——用不对称换体验和性能。
5. 图谱分两层：结构可解释、语义可关闭；默认只给自我网络，坐标要持久化。
6. 索引不出设备，代价是"本地完整而非全局完整"，必须在 UI 里诚实表达。
