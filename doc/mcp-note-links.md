# MCP 双链笔记与独立图谱工具

适用范围：PonyNotes Flutter 客户端 MCP 与内部 AI；日期：2026-11-03。仅客户端改动，不影响服务端接口。

客户端 MCP 版本：`0.7.0`。本次新增 6 项工具，注册表共 36 项；外部 MCP 和内部 AI 使用相同工具表。工具权限开关与审计列表自动包含新增工具。原知识图谱及其 AI 语义功能保持独立。

## 工具契约

| 工具 | 用途 | 修改内容／界面 |
| --- | --- | --- |
| `insert_note_reference` | 在来源笔记正文插入页级或段落级引用 | 写正文 |
| `remove_note_reference` | 按来源段落、偏移和预期目标移除一次引用 | 写正文，使用破坏性操作注解 |
| `get_reference_context` | 验证引用仍存在，读取两端的当前内容片段 | 只读 |
| `open_note_reference` | 验证引用后定位其来源或目标段落 | 修改界面上下文 |
| `get_note_graph` | 查询独立双链图谱，默认包括孤立笔记 | 只读 |
| `open_note_graph` | 在客户端打开全局或局部独立双链图谱 | 修改界面上下文 |
| `get_backlinks` | 保留旧工具名，增强段落过滤、分页、计数与上下文 | 只读 |
| `get_workspace_links_graph` | 保留旧工具名及原始边字段，新增节点和可访问性过滤 | 只读 |
| `reindex_page_links` | 从本机正文重建指定笔记的派生索引 | 修改派生索引，不改正文 |

所有请求带客户端当前 `workspace_id`。页面和段落 ID 先通过 `list_pages`、`search_notes`、`get_page` 或 `list_blocks` 获取，不根据标题推测 ID。

## 创建和移除引用

引用一段内容，不需要向目标笔记再插一次链接。插入的是与编辑器一致的 `mention.page_id + mention.block_id`，原文仍保存在目标段落；双链关系自动派生。

```json
{
  "tool": "insert_note_reference",
  "arguments": {
    "workspace_id": "workspace-id",
    "page_id": "source-note-id",
    "block_id": "source-paragraph-id",
    "target_page_id": "target-note-id",
    "target_block_id": "target-paragraph-id",
    "offset": 12,
    "replace_length": 0,
    "expected_source_text": "来源段落当前原始文本"
  }
}
```

- 不传 `target_block_id`：引用整篇笔记。
- 不传 `block_id`：在来源笔记末尾新增一个引用段落；此时不传位置和原文校验参数。
- 传 `block_id` 不传 `offset`：追加到段落末尾。
- `offset`、`replace_length` 都按 **Unicode 字符** 计数，emoji 算一个字符，与索引 `char_offset` 一致；工具内部转换成编辑器需要的 UTF-16 偏移。
- 替换范围只允许普通文本，不会静默覆盖已有引用、提醒或公式。
- `expected_source_text` 是可选的乐观校验。原始 mention 占位符是 `$`，展示的目标标题／片段不属于来源原始文本。
- 目标笔记只要求可读；来源笔记必须可写且未锁定。提交前再次校验工作区、目标访问权限和来源段落是否仍与读取时一致。
- 保存结果从后端重新读取验证后才报告成功。内容已保存但索引刷新失败时返回 `inserted=true, index_updated=false`，不要据此重复创建。

成功返回来源 `block_id`、`char_offset`、目标 ID、引用类型和 `index_updated`。

```json
{
  "tool": "remove_note_reference",
  "arguments": {
    "workspace_id": "workspace-id",
    "page_id": "source-note-id",
    "block_id": "source-paragraph-id",
    "offset": 12,
    "target_page_id": "target-note-id",
    "target_block_id": "target-paragraph-id"
  }
}
```

只删除匹配位置的一个引用占位符，不删除来源段落或目标内容。如果当前位置不再指向预期目标，返回 `reference_changed`。目标已删除或失去访问权限时，仍允许清理来源中的悬空引用。

`get_reference_context` 使用与移除相同的位置参数，返回 `source_excerpt`、`target_excerpt`、`target_status` 与可定位的 ID；已失效的位置不会返回伪造的引用关系。

`open_note_reference` 同样使用上述位置参数，并可传 `side="target"`（默认）或 `side="source"`。它先验证当前位置仍是预期引用，再通过编辑器的段落导航服务定位和高亮。整篇笔记引用打开目标笔记；段落已删除时返回错误。返回 `navigation_requested=true` 表示界面导航已提交，不声称动画和滚动已经完成。

## 反向查询

```json
{
  "tool": "get_backlinks",
  "arguments": {
    "workspace_id": "workspace-id",
    "page_id": "target-note-id",
    "block_id": "target-paragraph-id",
    "include_context": true,
    "limit": 20,
    "offset": 0
  }
}
```

- 可选 `block_id`：入链限定目标段落，出链限定来源段落。
- 兼容返回 `backlinks`、`outgoing`、`unresolved`、`indexed_pages`、`truncated`。
- 新增来源／目标笔记数、引用次数、记录数和分页状态；不能用记录条数冒充笔记数。
- `include_context` 默认 false；开启后按需读取来源片段，按页复用同一次正文读取。
- 同笔记内的块引用可反查；独立图谱仍不展示自环。
- 只输出当前可访问的端点，排除父子目录关系，不返回失去访问权限的来源缓存标题和正文。

## 图谱查询和打开

```json
{
  "tool": "get_note_graph",
  "arguments": {
    "workspace_id": "workspace-id",
    "focus_page_id": "note-id",
    "depth": 2,
    "direction": "incoming",
    "query": "",
    "show_isolated": true,
    "blocks_only": false,
    "limit": 400
  }
}
```

- 不传 `focus_page_id`：全局图谱，默认保留无连线的笔记。
- 局部深度为 1～3；方向是 `both`、`incoming` 或 `outgoing`。
- 使用与独立图谱界面相同的数据构建与筛选代码；只包含明确正文引用，不含目录和 AI 关系。
- 返回笔记节点、方向聚合边及引用次数；单条关系的内容和精确位置继续用 `get_backlinks`、`get_reference_context` 获取。
- `get_workspace_links_graph` 保留未聚合原始边，其中含来源块、目标块和 `occurrence`，同时补充孤立笔记节点；大范围分析优先使用有节点上限的 `get_note_graph`。
- `coverage=local_synced_accessible_notes` 表示只覆盖本机已同步且可访问的内容。`incomplete`、`truncated`、`omitted_notes` 分别说明索引范围、底层结果上限、显示筛选上限。

```json
{
  "tool": "open_note_graph",
  "arguments": {
    "workspace_id": "workspace-id",
    "focus_page_id": "note-id"
  }
}
```

打开 `note_graph:<note-id>`；省略中心笔记则打开 `note_graph:global`。该工具不会打开或改写原 `knowledge_graph` 插件。没有客户端标签页界面时返回 `ui_unavailable`；切换尚未确认时返回 `open_unconfirmed`。

## 参数、权限与审计

JSON Schema 对 MCP 和内部 AI 调用同样生效，拒绝错误类型、负偏移、越界限制、未知方向和额外字段。来源页面写权限、工作区归属和锁定规则复用现有 MCP 文档写入检查。

外部 Agent 关闭某个工具后，已连接的会话同样不能执行。审计仅记录工具名、工作区／来源／目标 ID、耗时与结果，不保存正文校验文本或片段。

## 验证

`test/features/mcp/mcp_note_links_test.dart` 覆盖结构化引用读写、Unicode 偏移、页级／块级引用、反向查询与同页引用、计数与分页、权限及锁定、索引失败、真实 MCP IOStream 协议的发现／插入／查询／移除，以及独立图谱打开请求。

测试中的正文和工作区服务为内存适配器；持久化提交继续复用现有 `persistDocument`，其后端读回确认由原 MCP 测试单独验证。尚未在真实运行客户端执行新工具的端到端验收。

本次验证结果：联合执行双链编辑／导航、独立双链图谱、原知识图谱、MCP 工具与设置页回归，共 123 项通过，其中新增双链 MCP 测试 24 项。使用真实 MCP IOStream 协议完成工具发现、创建、反查、移除闭环。受当前环境本机端口限制，原有 HTTP session 跟踪测试未执行；依赖真实后端的 `mcp_write_safety_test.dart` 与运行客户端 HTTP 端到端验收未执行。
