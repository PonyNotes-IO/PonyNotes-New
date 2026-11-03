-- 双向链接索引（本地派生表）
--
-- 三张表都是可重建的物化视图：真相源是 collab 文档正文里的 mention 节点，
-- 索引丢了随时能从正文重建，但正文不能从索引重建。因此这里不做任何级联删除，
-- 也不建外键（目标页可能尚未同步到本机）。

-- 结构边主表：一行 = 一个源块对一个目标页的一次引用（同块多次引用合并为一行 + occurrence）
CREATE TABLE IF NOT EXISTS note_link (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  workspace_id TEXT    NOT NULL,
  src_page_id  TEXT    NOT NULL,
  src_block_id TEXT    NOT NULL,
  dst_page_id  TEXT    NOT NULL,
  -- 块引用时非空；页面引用时为空
  dst_block_id TEXT,
  -- reference | embed | block_ref | relation
  kind         TEXT    NOT NULL,
  -- 展示文本快照。不是真相：目标页存在时优先用 view 表当前标题，这里只在目标缺失时兜底
  label        TEXT    NOT NULL DEFAULT '',
  -- 在该块正文中的字符偏移，用于跳转后滚动定位
  char_offset  INTEGER NOT NULL DEFAULT 0,
  -- 同一块内对同一目标的重复引用次数
  occurrence   INTEGER NOT NULL DEFAULT 1,
  updated_at   INTEGER NOT NULL
);

-- 反向查询（谁引用了本页）走这个索引
CREATE INDEX IF NOT EXISTS idx_note_link_dst ON note_link (workspace_id, dst_page_id);
-- 出链查询、按页清理走这个索引
CREATE INDEX IF NOT EXISTS idx_note_link_src ON note_link (workspace_id, src_page_id);

-- 每页索引状态：用 content_hash 判定是否需要重算，避免无变化的重复建索引
CREATE TABLE IF NOT EXISTS note_link_state (
  page_id      TEXT PRIMARY KEY,
  content_hash TEXT    NOT NULL,
  link_count   INTEGER NOT NULL DEFAULT 0,
  indexed_at   INTEGER NOT NULL
);

-- 悬空引用：正文里出现 [[标题]] 但当前没有同名页面
-- 保留而不丢弃，是因为「指向不存在的页」本身是有用信息（Obsidian 的 placeholders 同样是一等公民）
CREATE TABLE IF NOT EXISTS note_link_unresolved (
  workspace_id     TEXT NOT NULL,
  src_page_id      TEXT NOT NULL,
  src_block_id     TEXT NOT NULL,
  -- NFKC + 去首尾空白 + 空白折叠 + 大小写折叠后的标题，用于匹配
  normalized_title TEXT NOT NULL,
  -- 用户实际输入的原始标题，用于「创建此页」时回填
  raw_title        TEXT NOT NULL,
  char_offset      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (workspace_id, src_page_id, src_block_id, normalized_title)
);
