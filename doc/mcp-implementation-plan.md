# 小马笔记二期第一章：客户端本地 MCP 实现计划

- 日期：2026-10-21
- 状态：阶段二～阶段六全部实现（27 个工具，服务版本 0.6.9）。2026-10-23 已在运行中的客户端对 27 个工具做过全量实测；真实目标 Agent（OpenClaw、WorkBuddy、豆包办公、千问办公）联调、并发编辑实测仍待完成。
- 需求来源：工作区根目录《小马笔记二期功能.docx》第一章，以及用户对客户端本地 MCP、独立功能工具和 Token 接入方式的说明。
- 主要实施仓库：`PonyNotes-New`。

## 1. 目标与需求理解

小马笔记客户端提供本地 MCP Server，供外部 Agent 在用户授权后，以当前用户的身份读取、检索、创建和修改笔记内容。

每项独立功能对应一个 MCP tool，具备独立的名称、参数 schema、返回结果和处理函数。工具内部复用客户端业务服务，不向 Agent 暴露任意 Rust 事件分发、SQL 或脚本执行入口。

典型使用场景：

> 用户让外部 Agent 新建项目工作区，创建需求文档和会议记录，并整理资料。Agent 依次调用工作区、页面和内容工具，小马客户端执行操作并展示结果。

第一章三个需求的关系如下：

| 需求 | 实现职责 |
| --- | --- |
| 多模块调用与上下文理解 | 模型负责理解意图和规划调用；客户端提供明确、可靠的工具及当前上下文 |
| 外部 Agent 接入 | 客户端作为 MCP Server，开放经授权的笔记操作能力 |
| 用户配置 AI Token | 小马内部 AI 使用用户配置的模型服务，复用同一组业务操作能力 |

MCP Token 用于 Agent 访问小马；模型 API Key 用于小马访问模型服务。二者独立管理。

## 2. 范围

首批完成桌面客户端的工作区、页面、正文、内容块和搜索操作，以及授权设置、真实 Agent 联调和必要的 stdio 兼容入口。

以下能力不属于首批工具：

- 数据库行列和视图的专用操作。
- 附件上传、下载及批量文件处理。
- Notion、Obsidian 笔记迁移及保真导入。
- 手机端常驻 MCP 服务、局域网开放和公网访问。
- 工作区永久删除、成员邀请和权限管理。

工作区删除、成员管理等功能若后续需要开放，应各自新增独立工具和权限校验。

“本地 MCP”指服务在客户端运行，并不意味着所有业务都可以离线执行。云工作区创建、远端检索等能力是否需要网络，沿用现有产品能力，并返回明确的不可用原因。

## 3. 传输架构

### 3.1 主入口采用本地 Streamable HTTP

客户端启动并开启 MCP 后，在本机回环地址提供 MCP 端点。Agent 通过地址和 Bearer Token 连接。

| 比较点 | 内置 Streamable HTTP | 独立 stdio 服务 |
| --- | --- | --- |
| 服务启动者 | 小马客户端 | Agent 启动子进程 |
| 当前登录状态 | 直接使用客户端会话 | 需要连接客户端或另外维护会话 |
| 多 Agent 接入 | 连接同一个本地服务 | 通常分别启动桥接进程 |
| 配置方式 | 地址和 Token | 可执行文件、参数和环境变量 |
| 本项目用途 | 主要接入方式 | 兼容入口 |

产品形态参考 FlyEnv：客户端内开启服务、生成 Token、复制配置。具体接入能力以所选 MCP SDK 和目标 Agent 的实测为准。

```mermaid
flowchart LR
    A[支持 HTTP 的 Agent] --> M[小马客户端 MCP Server]
    B[使用 stdio 的 Agent] --> P[stdio 桥接程序]
    P --> M
    M --> T[独立工具与权限校验]
    T --> S[现有客户端业务服务]
    S --> R[Rust 核心 / 本地数据 / 云同步]
```

### 3.2 服务生命周期与边界

- 首次使用由用户主动开启，并说明 Agent 可按当前账号权限读取和修改内容。
- 仅绑定本机回环地址；第一版采用固定端口，端口冲突时明确提示。
- 开启后展示实际连接地址；关闭时停止接受请求并终止授权连接。
- 客户端退出后，MCP 服务停止。
- 校验 Bearer Token、Host 和 Origin，拒绝非法来源；限制请求体大小、执行时间及结果数量。
- Token 不放在 URL 查询参数中，也不写入日志。
- 云端运行的 Agent 无法直接连接用户电脑的回环地址，需要另行解决连接方式。

### 3.3 stdio 兼容

对确实只支持 stdio 的目标 Agent，提供桥接入口，将 stdio 通信转发至客户端 HTTP MCP 服务。

桥接层只处理传输、连接和凭据传递，不重复实现工具与笔记业务。优先验证可复用的桥接方案，再决定是否打包专用程序；日志不能混入 stdio 协议输出。

## 4. Token 与用户身份

### 4.1 独立生成 MCP Token

用户要求的“以用户身份操作”通过复用客户端当前会话实现，不向 Agent 提供原始登录 access token 或 refresh token。

执行流程：

1. 用户登录客户端，开启 MCP，生成随机的 MCP Token。
2. 客户端将 Token 的校验摘要关联到当前账号、认证类型和后端环境。
3. Agent 使用 `Authorization: Bearer <MCP Token>` 发起请求。
4. 客户端校验 Token，并确认对应账号仍是当前账号、授权仍然有效。
5. 根据目标资源检查用户权限，再调用现有业务服务。
6. 若操作涉及云端，由客户端现有网络层使用当前有效的登录凭据。

不得通过简单编码、截取或包装登录 Token，把它当作独立的 MCP 凭据。

### 4.2 生命周期

- 登录 access token 正常刷新，不要求用户重配 MCP Token。
- 重置 MCP Token 后，旧 Token 和已有授权连接失效；不能只在建立连接时验证一次。
- 退出账号、切换账号或切换后端环境，撤销原有 MCP 授权。
- 本地保存校验摘要；明文仅在生成时展示供复制，遗失后重置。
- 工具参数不允许指定另一个用户身份。
- 账号、授权和工作区上下文发生变化时，等待中的操作必须重新检查上下文，避免旧请求继续写入。

第一版采用用户手工配置 Bearer Token 的接入模式。要求完整 OAuth 授权流程的 Agent 需另行适配，不能直接承诺兼容。

## 5. 首批工具契约

以下每一行对应一个独立 MCP tool。准确字段类型、必填项和返回结构在实施第一阶段完成定义。

| 工具 | 功能及关键参数 |
| --- | --- |
| `get_context` | 返回当前账号标识、工作区和客户端状态，不返回登录凭据 |
| `list_workspaces` | 列出当前账号可访问的工作区 |
| `create_workspace` | 按名称和现有工作区类型创建工作区，返回新工作区 ID |
| `open_workspace` | 显式切换客户端当前工作区，成功后返回实际上下文 |
| `list_pages` | 按工作区和父页面列出页面，支持分页 |
| `get_page` | 读取页面元信息和正文，提供可定位的块 ID |
| `search_notes` | 检索笔记，返回页面 ID、标题、命中摘要和工作区 |
| `create_page` | 在指定父级下创建页面，可携带初始内容 |
| `rename_page` | 修改页面标题 |
| `move_page` | 将页面移动到指定父级，检查目标层级是否合法 |
| `delete_page` | 将页面移入回收站 |
| `restore_page` | 从回收站恢复页面 |
| `append_content` | 将 Markdown 内容追加到指定页面 |
| `list_blocks` | 读取页面或父块下的结构化内容块 |
| `insert_block` | 在指定父块和位置插入内容块 |
| `update_block` | 根据块 ID 更新内容或支持的属性 |
| `delete_block` | 删除指定块，明确对子块的影响 |
| `move_block` | 移动块（含子块）到其他父块下或调整同级顺序 |
| `list_trash` | 列出回收站页面，拿到可恢复的页面 ID |
| `duplicate_page` | 复制页面（可含子页面），副本标题追加「副本」 |
| `query_database` | 读取 grid/board/calendar 视图的行数据，按字段名返回单元格文本（后续追加，见 §10） |
| `create_database_row` | 在视图中新增一行并写入若干单元格 |
| `update_database_cell` | 按字段名或字段 ID 更新某个单元格 |
| `delete_database_row` | 删除视图中的一行 |
| `create_database_field` | 新增字段（文本、数字、日期、单选、多选、勾选、URL、检查清单、时间） |
| `update_database_field` | 重命名字段 |
| `delete_database_field` | 删除字段及其数据，主字段不可删 |

通用约定：

- 工具名称、schema 和处理函数分别注册，共用业务服务。
- 页面和块操作明确携带并校验 `workspace_id`。
- 返回稳定资源 ID，供后续调用引用；列表和搜索控制返回数量。
- `create_workspace` 返回新工作区 ID，不隐式承诺已切换；切换使用 `open_workspace`。
- 页面删除采用回收站语义，不提供永久删除入口。
- 参数和协议错误与业务失败分开表达；权限不足、资源不存在、工作区不匹配、离线不可用和执行超时应可区分。
- 写入成功以业务层确认保存为准，不能以“已发出事件”作为成功结果。
- 超时后不能假定写入失败并自动重复创建；返回已知状态，指导 Agent 查询确认。

### 5.1 内容格式

Markdown 用于阅读、生成初始内容和追加正文；结构化块用于精确定位和修改。

读取结果应保留块 ID、类型及父子关系。修改单段内容时沿用块操作或文本增量，不通过整页 Markdown 覆盖重建。

首批明确支持的块类型和字段。遇到暂不支持的复杂块，返回限制并保留数据，不能静默转换或丢弃。

### 5.2 工作区上下文与并发

现有部分业务依赖客户端当前工作区。第一版采用显式切换方式，不假设已有后台多工作区并行操作能力。

- 请求中的工作区必须与执行时的实际上下文一致。
- `open_workspace` 会改变客户端界面上下文，工具说明必须写明该副作用。
- 工作区切换与数据操作需要协调；切换过程中不得执行到另一个工作区。
- 用户在界面切换工作区或账号，也必须触发请求上下文重新校验。
- 同一页面的 MCP 写入沿用现有事务、增量和通知机制，并测试与界面编辑并发的情况。

## 6. 代码落点与复用

优先在 Flutter/Dart 层增加 MCP 功能模块，再调用现有 Rust 业务接口。

理由是客户端已经具备 Markdown 转换、AI 内容写入页面、页面服务、文档服务及部分权限入口，可以减少内容转换和跨语言桥接的重复实现。

| 现有入口 | 相对客户端仓库路径 | 复用方向 |
| --- | --- | --- |
| 页面服务 | `frontend/appflowy_flutter/lib/workspace/application/view/view_service.dart` | 创建、读取、移动、删除页面 |
| 文档服务 | `frontend/appflowy_flutter/lib/plugins/document/application/document_service.dart` | 文档读取、块操作和文本增量 |
| Markdown 转换 | `frontend/appflowy_flutter/lib/shared/markdown_to_document.dart` | Markdown 与编辑器文档之间转换 |
| AI 内容写入 | `frontend/appflowy_flutter/lib/plugins/ai_chat/application/chat_edit_document_service.dart` | 参考现有创建页面、追加内容流程 |
| 搜索入口 | `frontend/appflowy_flutter/lib/workspace/application/command_palette/search_service.dart` | 聚合内部搜索结果 |
| 工作区权限 | `frontend/appflowy_flutter/lib/workspace/application/permission/workspace_permission_service.dart` | 追踪权限查询和最终执行校验 |
| Rust 核心 | `frontend/rust-lib/flowy-core/src/lib.rs` | 用户、工作区、文档、搜索管理和事件分发 |
| Rust 工作区管理 | `frontend/rust-lib/flowy-user/src/user_manager/manager_user_workspace.rs` | 工作区创建、读取、打开等业务 |

拟新增模块以 `frontend/appflowy_flutter/lib/features/mcp/` 为起点，涵盖服务生命周期、鉴权、工具注册、工具处理和设置入口。具体文件结构遵循附近功能模块的组织方式，不预先增加通用框架。

协议层优先验证现成 Dart MCP SDK，`mcp_dart` 可作为候选。采用前检查当前 Flutter/Dart 版本、依赖冲突、Streamable HTTP、协议协商和目标 Agent 兼容性，不在计划阶段承诺版本。

Rust 仅补齐现有业务接口确实缺失的能力。第一版没有已确认的 Cloud MCP 服务改造需求；如共享 DTO 或构建打包确需变化，再分别检查 Cloud 与 Builder 的影响。

### 6.1 权限校验不能只依赖界面

检查时发现现有工作区权限服务存在“查询不到角色时默认允许、交给后端检查”的兜底。MCP 不能直接照搬该兜底并视为已完成授权检查。

实施时应追踪每种写入的最终权限校验，覆盖工作区角色、页面访问权限和只读状态。权限无法确认时拒绝写入；本地工作区使用已验证的本地身份和权限规则，不能因此强制依赖云端。

## 7. 实施阶段

### 阶段一：工具契约与业务映射

- 定义各工具 schema、返回结构、错误行为和调用链。
- 核实工作区、空间、页面和块的实际层级关系。
- 确认本地与云工作区支持的操作、离线限制及权限来源。
- 验证 SDK 与当前工具链兼容性，明确首批块类型。

交付：可评审的工具契约和代码映射，收敛实施范围及排期。

### 阶段二：最小接入闭环

- 实现开关、HTTP 服务生命周期、Token 生成和重置。
- 先提供 `get_context`、`list_workspaces` 两个只读工具。
- 以 Codex 作为首个候选联调客户端，验证工具发现、Token 和上下文读取。
- 核验目标客户端支持的协议版本，由 SDK 处理协商。

交付：真实 Agent 能连接客户端并读取授权上下文。

### 阶段三：读取与检索

- 完成页面列表、页面读取、块读取和搜索工具。
- 将现有流式搜索整理成有结果上限、超时和明确完成状态的工具结果。
- 确认所有读取均校验资源归属和用户权限。

交付：Agent 能找到指定笔记并读取指定段落和块 ID。

### 阶段四：创建与修改

- 完成工作区创建和切换、页面创建与整理、回收站操作。
- 完成 Markdown 追加及精确块修改。
- 接入现有通知链路，让界面反映 MCP 修改。
- 处理切换工作区、并发写入、失败和超时后的状态确认。

交付：Agent 完成“新建工作区 → 创建页面 → 写入正文 → 修改指定块”，客户端可见并持久化结果。

### 阶段五：授权、设置与接入兼容

- 覆盖只读成员、Token 撤销、切换账号、切换后端和工作区切换。
- 设置页展示服务状态、实际地址、授权范围说明和 Token 生成/重置入口。
- 提供可复制的目标 Agent 配置，敏感值不写入仓库或普通日志。
- 按 OpenClaw、WorkBuddy、豆包办公、千问办公等目标逐一确认本机连接和鉴权能力，记录实测结果。
- 对需要 stdio 的目标交付经测试的桥接入口。
- 日志记录工具名、目标 ID、时间和结果，避免记录 Token 和完整笔记正文。

交付：接入说明、兼容性清单及完整外部 Agent 操作闭环。

### 阶段六：第一章内部 AI 接入

- 核实现行内部 AI 配置链路；现有部分配置代码带弃用标记，不能直接认定可复用。
- 接入用户配置的模型地址、模型名称和 API Key。
- 内部 AI 复用同一套工具处理能力，不重复编写笔记操作逻辑。
- 验证多步工具调用、后续对话继续操作及模型调用失败行为。

交付：完成第一章内部 AI 配置和多步操作需求。

## 8. 验收与检查

| 验收场景 | 通过标准 |
| --- | --- |
| 真实 Agent 接入 | 能发现工具、验证 Token，并完成读写流程 |
| 独立工具 | 各功能具备独立工具名、schema 和结果，无任意业务执行入口 |
| 页面与块操作 | ID、层级和内容正确，客户端展示与持久化结果一致 |
| 工作区切换 | 不静默跨工作区操作；旧上下文请求被拒绝或安全终止 |
| 账号与 Token | 退出、切换、重置后旧授权不能继续操作 |
| 只读与无权限用户 | 写入被拒绝，读取不越权 |
| 并发编辑 | Agent 与用户同时编辑不会因整页替换丢失内容 |
| 不支持的块 | 明确报告限制，不静默删除或降级数据 |
| 离线与云同步 | 区分本地保存、同步状态和依赖网络而无法执行的操作 |
| 服务生命周期 | 关闭服务和退出应用后停止接入，端口冲突明确报错 |
| stdio 兼容 | 指定目标 Agent 经桥接调用同一套工具成功 |
| 内部 AI | 使用用户配置的模型完成多步操作，凭据不与 MCP Token 混用 |

检查从最小相关范围开始：

- Flutter/Dart：格式、受影响路径分析、鉴权与工具处理的必要测试。
- 文档写入：使用匹配的 FFI 库验证实际持久化、通知和并发编辑行为。
- Rust：仅对发生修改的 crate 运行检查及相关测试。
- 桥接程序：验证协议输出、启动失败、凭据传递和客户端未运行时的行为。
- 跨平台：桌面目标分别验证端口监听、生命周期、路径和打包配置。
- 最后检查各受影响仓库的 diff 与 `git diff --check`，保留原有未提交改动。

## 9. 估算与待验证事项

单人开发初步估算：外部 MCP 桌面版闭环约 3～4 周；第一章内部 AI 配置及多步调用另预留 1～2 周。该估算尚未经过实现验证，应在阶段一完成后根据实际缺口调整。

实施前需要收敛的事项：

1. 目标 Agent 的本机 HTTP、Bearer Token、stdio 和 OAuth 接入能力。
2. 所选 Dart SDK 与当前工具链和依赖的兼容性。
3. 跨工作区操作的实际生命周期、通知和并发边界。
4. 每条读写路径最终执行的权限检查。
5. 首批支持的内容块类型及 Markdown 往返保真度。
6. 当前内部 AI 配置入口及可复用范围。

本文件是实现计划，实际落地范围见文末「实施进度」。MCP 接入、权限与并发编辑测试尚未运行。

## 10. 实施进度

### 2026-10-21：阶段二最小接入闭环

已实现：

- 依赖 `mcp_dart ^2.4.3`（Dart 3.9 / Flutter 3.35 兼容，依赖无冲突）。
- `frontend/appflowy_flutter/lib/features/mcp/application/mcp_server_service.dart`
  - `StreamableMcpServer` 绑定 `127.0.0.1:27861/mcp`，固定端口，占用时返回明确错误。
  - Bearer Token：32 字节随机值，仅保存 SHA-256 摘要；摘要与生成时的用户 ID 绑定，切换账号后旧 Token 自动失效。摘要用常量时间比较。
  - 开关状态持久化（`shared_preferences`），应用启动时由 `McpServerTask` 恢复；退出/重启只停服务，不清开关。
  - 重置 Token 会关闭现有连接并重启服务，旧 Token 立即失效。
  - 首批工具：`get_context`、`list_workspaces`（均为只读，不返回登录凭据）。
- 设置入口：设置 → 「AI 接入 (MCP)」，包含开关、连接地址、Token 生成/重置（明文仅展示一次）、复制 Agent 配置。
- 测试：`test/features/mcp/mcp_server_service_test.dart` 覆盖 Token 摘要、常量时间比较，以及通过 MCP 客户端发现 `get_context` / `list_workspaces` 两个工具（协议协商到 MCP 2026-07-28）。

### 2026-10-21：阶段三读取与检索

已实现（`lib/features/mcp/application/mcp_tools.dart`，服务版本 `0.2.0`）：

- `list_pages`：按 `workspace_id` 与可选 `parent_id` 列出直接子视图，支持 `limit`/`offset` 分页；返回 `page_id`、标题、布局、是否文档、是否空间、最后编辑时间。省略 `parent_id` 时从工作区根级开始。
- `get_page`：返回文档页面元信息、正文纯文本（上限 20000 字符，超出标记 `text_truncated`）和前 100 个块（含块 ID）。空间和数据库等非文档页面返回 `content_supported=false` 及原因，不尝试读取正文。
- `list_blocks`：按深度优先顺序返回页面或指定父块下的块，包含 `block_id`、`parent_id`、`type`、`text`（单块上限 2000 字符）、`depth`，支持 `limit`/`offset`。
- `search_notes`：复用现有流式搜索，带结果上限（最大 50）、8 秒超时和 `complete` 状态；返回页面 ID、标题、摘要（本地结果可能没有摘要）和工作区。
- 工作区校验：所有需要 `workspace_id` 的工具要求它等于客户端当前工作区，否则返回 `workspace_mismatch`；页面/父级的 `workspaceId` 与请求不一致时同样拒绝。
- 正文读取先走本地文档数据，失败后回退云端文档；长文本块从 `meta.textMap` 提取文本。
- 搜索服务 `performSearch` 增加可选 `limit` 参数，现有调用不受影响。
- 测试新增工具发现（共 6 个）与块文本提取（delta、外部长文本、非法 JSON）。

### 2026-10-21：阶段四创建与修改

已实现（`lib/features/mcp/application/mcp_tools.dart`，服务版本 `0.3.0`）：

- `create_workspace`：按当前工作区类型创建同名工作区，返回新工作区 ID，不自动切换。
- `open_workspace`：显式切换客户端当前工作区；工具说明写明会改变界面上下文，成功后重新读取并返回实际上下文。
- `create_page`：在空间或文档页面下创建文档页面，可携带初始 Markdown；`openAfterCreate=false`，不会抢占界面焦点。
- `rename_page` / `move_page` / `delete_page` / `restore_page`：重命名、移动（拒绝移动到自身或子页面下）、移入回收站、从回收站恢复。删除与恢复通过重新读取回收站确认结果。
- `append_content`：将 Markdown 转换为编辑器节点追加到页面末尾，返回实际写入的块 ID。
- `insert_block`：支持 paragraph、heading1-3、bulleted_list、numbered_list、todo_list、quote、divider；可指定父块与插入位置。
- `update_block`：按块 ID 替换文本块文本，不支持修改块类型。
- `delete_block`：删除块及其所有子块；删除最后一个块时自动补一个空段落。
- 写入路径：先用现有 `TransactionAdapter` 提交到 Rust 业务层，再更新本地编辑器状态，最后重新读取文档确认块 ID/文本，未确认时返回 `write_unconfirmed`，超时返回 `write_timeout` 并提示先查询再决定是否重试。
- 权限：写入前检查当前工作区、页面是否锁定；本地工作区视为本机所有者，服务端工作区查询成员角色，查不到角色或角色为 Guest 时一律拒绝，不沿用界面层“查不到就放行”的兜底。
- 测试新增块类型映射与 17 个工具的发现检查。

尚未完成（按计划后续阶段）：

- 真实 Agent（Codex 等）联调、stdio 桥接。
- 请求体大小、执行时间的显式配置。
- 权限最终校验的完整覆盖（阶段五），内部 AI 接入（阶段六）。
- 并发写入只做了“写入后重新读取确认”，尚未与界面编辑并发实测。

### 2026-10-21：阶段五授权、设置与接入兼容

已实现（服务版本 `0.4.0`）：

- Token 生命周期：生成时同时绑定账号 ID 和后端地址；鉴权时校验摘要、账号和后端，切换账号或后端环境后旧 Token 失效。
- 退出登录撤销授权：`AuthService.signOut()`（云端与 mock 实现）会停止服务并删除 Token 摘要，覆盖设置页、侧栏和移动端的退出路径。
- 设置页新增「授权范围」说明、「服务自检」（无 Token 探测端点，确认可达且鉴权生效）和「撤销授权」。
- Token 弹窗提供两套可复制配置：Streamable HTTP 和 stdio 桥接；敏感值只在生成时展示。
- 工具调用日志记录工具名、目标 ID、耗时和成功/失败，不记录正文、Markdown 或 Token。
- 请求体超过 1 MiB 在鉴权层拒绝；所有工具统一 60 秒超时，搜索 8 秒、写入提交 10 秒。
- stdio 桥接：新增独立 Dart 包 `frontend/tools/mcp_stdio_bridge`，把 stdio 会话代理到本地 HTTP 端点，工具名、schema 和描述与上游一致。
- 兼容性清单与实测步骤见 `doc/mcp-agent-compatibility.md`，OpenClaw、WorkBuddy、豆包办公、千问办公等目标仍标记为待实测。
- 桥接自动化测试 4 项通过：工具发现、调用转发、错误 Token 拒绝、真实 stdio 子进程完成 initialize/tools/list/tools/call。

尚未完成：

- 真实目标 Agent 的本机连接和鉴权实测（需要对应客户端环境）。
- 内部 AI 接入（阶段六）。
- 写入与界面编辑的并发实测。

实施时发现：`mcp_dart` 的 `StreamableMcpServer.authenticator` 在本工程分析环境中被推断为 `Function(dynamic)`，实现中以 `dynamic` 接收再转为 `HttpRequest`。

### 2026-10-21：真实客户端实测与读取修复（服务版本 0.4.1）

在 Linux 客户端用 Claude Code 通过 MCP 实测，发现读取工具返回空正文、`list_blocks` 报“父块不存在”。定位到三个问题并修复：

1. `GetDocumentData` 对未打开的云端文档只创建一个未同步的空实例。读取改为先直接读，内容为空时走 `OpenDocument` 触发同步，读完按需关闭。
2. 文档根块 ID 不一定等于页面（视图）ID。遍历改为使用 `DocumentDataPB.pageId` 作为根；`create_page` 生成初始文档时把根块 ID 重映射为新页面 ID。
3. `ApplyAction` 要求文档处于打开状态，适配器会吞掉 “Call open document first” 错误。写入路径改为打开文档并保持到写入确认后再关闭；错误现在表现为 `write_unconfirmed`。
4. 正文提取改用编辑器同一套 `DocumentDataPB.toDocument()` + `node.delta`，外部长文本也能读取。

实测通过（Claude Code → MCP）：

- 读取“欢迎来到小马笔记”：19 个块、完整正文。
- 创建带 Markdown 的页面并读回。
- `append_content`、`insert_block`、`update_block`、`delete_block` 写入后读回一致。
- `rename_page`、`delete_page`（回收站）、`restore_page` 结果确认。
- 块输出现在包含 `todo_list` 的 `checked` 勾选状态；已用未勾选/已勾选两个块验证。

### 2026-10-21：块类型覆盖扩展

`insert_block` 的 `block_type` 从 9 种扩展到 18 种，覆盖斜杠菜单可插入的文本类块：

- 新增：`toggle_list`、`toggle_heading1`~`3`（`collapsed` 控制折叠）、`code`（`language`）、`callout`（`icon` emoji）、`math_equation`（`formula`）、`image`/`video`/`file`（必填 `url`，`file` 可选 `file_name`，按网络地址处理）。
- `update_block` 增加可选的 `checked`（todo_list）和 `collapsed`（toggle 类），文本与状态可一起修改，也可只改状态。
- `image`、`video`、`file` 只接受已有地址，不支持从本机上传文件。

已实测：标题、段落、无序/有序列表、引用、待办（含勾选切换）、折叠块（含折叠切换）、分隔线、代码块、提示块、公式、图片、视频、文件块均能插入并正确读回；缺 `url` 时返回明确参数错误。

未覆盖（本节完成时，后续章节已补上表格、分栏、子页面、相册、链接预览、行内数据库和日期）：AI 写作块、提醒、Emoji。

### 2026-10-21：复合块类型（表格、分栏、子页面、相册、链接预览）

`insert_block` 再新增 5 种：`table`（`rows` 二维文本，首行为表头内容，`header_row` 暂不生效）、`columns`（`column_count` 2~4）、`sub_page`（`text` 为子页面标题，工具会先创建子页面再插入 `sub_page` 块，返回 `sub_page_id`）、`gallery`（`image_urls`）、`link_preview`（`url`）。

已在运行中的客户端实测：表格（3×2，单元格文本按行列正确读回）、三栏分栏、子页面（`list_pages` 能看到新建的子页面）、相册、链接预览均插入成功，块树读写一致。测试在临时工作区 `mcp-测试空间-tmp` 中进行。

本节完成时仍未接入的能力（后续 2026-10-22 章节已补上行内数据库和日期）：AI 写作块、日期/提醒、Emoji、表格表头开关。

### 2026-10-22：行内数据库与日期元素

`insert_block` 再新增：

- `grid` / `board` / `calendar`：默认先创建对应的数据库视图再插入块；传 `database_id` 时引用已有数据库（该参数接受数据库 ID 或数据库视图 ID，后者会自动解析）。返回 `database_view_id` 和 `database_id`。
- `date`：在承载文本块里插入日期 mention（`date` 传 ISO 8601，`include_time` 控制是否带时间）。优先写入 `after_block_id` 指向的块，否则写父块最后一个文本块，必要时新建段落。
- `ai_writer`：不提供。编辑器的 AI 写作块以 `inMemoryUpdate` 插入，只在当前编辑器会话内有效，无法通过 MCP 持久化；调用会返回明确错误。

已在运行中的客户端验证：独立 Grid/Board/Calendar 块插入成功；用数据库视图 ID 引用已有数据库成功，并同时返回解析后的 `database_id`；日期 mention 写入后读回块仍是承载文本块。

日期元素在纯文本读取时曾表现为零宽字符（已改为可读日期）；提醒已在下一节接入。

### 2026-10-22：日期提醒（reminder）

`insert_block` 的 `date` 支持直接创建提醒：

- `reminder` 取 `at_time_of_event`、`five_mins_before`、`ten_mins_before`、`fifteen_mins_before`、`thirty_mins_before`、`one_hour_before`、`two_hours_before`、`on_day_of_event`、`one_day_before`、`two_days_before`、`one_week_before`、`custom` 之一；省略表示只插入日期、不创建提醒。
- `custom` 通过 `reminder_minutes` 指定提前分钟数（默认 30）。
- 工具会生成提醒 ID，按编辑器相同的方式调用 `ReminderBloc.addById`（`objectId` 为页面 ID，`meta` 带 `block_id`、`include_time`、`notification_type=reminder`），并把 `reminder_id`/`reminder_option` 写入日期 mention；返回结果包含这两个字段。
- 写入未确认时会撤销刚创建的提醒，避免留下孤立提醒。
- `delete_block` 删除的块（含子块）里如果包含带提醒的日期，写入成功后会同步删除这些提醒；`update_block` 整段替换文本时同样会清理被移除日期的提醒。

已实测（运行中的客户端 + stdio 桥接）：`five_mins_before` 和 `custom(45)` 两种提醒都成功创建，日志出现 `Added reminder: <id>`，文档 delta 中包含正确的 `reminder_id`/`reminder_option`。清理逻辑已实现，但对应日志在终端缓冲中滚动过快，未单独截取。

限制：`custom` 的提醒时间按本次传入的分钟数计算，不会修改界面里保存的自定义分钟数；如果之后在界面重新编辑该日期，界面会按它自己的自定义分钟数重算。`date` 的纯文本读取目前显示为日期，不回显提醒信息。

### 2026-10-23：资源块返回地址（服务版本 0.6.4）

`get_page` / `list_blocks` 的块输出新增资源信息：

- 图片、视频、文件、链接预览块返回顶层 `url`。
- 多图相册返回 `image_urls` 列表。
- 块的其他业务属性放在 `attributes`（已去掉 `delta`，避免与 `text` 重复），如图片的 `image_type`、宽度、高度，代码块的 `language`，公式块的 `formula`，提示块的 `icon` 等。

已用用户实际页面验证：三张 PNG 截图块都返回了完整的云存储 URL，直接下载可以正常打开；此前只能看到“这是一个图片块”。

已知限制：`search_notes` 的本地搜索结果来自 tantivy，只返回页面 ID/标题，没有命中摘要，且中文查询可能返回较宽的结果集；云端搜索未实测。测试过程中在 `ceshi` 工作区留下了“MCP 测试页”和“MCP 验收页（已改名）”两篇测试页面。

### 2026-10-23：表格表头、大纲块与块属性更新（服务版本 0.6.5）

- `insert_block` 的 `table` 支持 `header_row`（默认 `true`）和 `header_column`（默认 `false`）。此前 schema 里写着「首行作为表头」，实际没有写入 `enable_header_row`，这次补上，参数与约定一致。
- 新增 `block_type=outline`，插入目录块（`outlineBlockNode()`），与斜杠菜单的「大纲」一致。
- `createSimpleTableBlockNode` 透传两个表头开关；其它调用方不传时默认 `false`，行为不变。
- `update_block` 从「只能改文本/勾选/折叠」扩展到支持 `language`（code 块）、`icon`（callout 块）、`header_row` / `header_column`（table 块），插入后可以再改这些属性。
- `update_block` 的 `text` 改为可选：不传时保留原文本，避免「只想改表头却把正文清空」。一个字段都不传会返回 `invalid_params`。
- 属性拼装抽成 `McpTools.buildUpdateAttributes(node, args)`，块类型不匹配时返回明确错误（例如 `language 仅适用于 code 块。`）。

未接入的两项及原因：

- **AI 写作块**：编辑器以 `inMemoryUpdate` 插入，依赖当前编辑会话，无法持久化。保持现状——`insert_block` 返回明确的参数错误，而不是静默插入一个坏块。
- **Emoji**：斜杠菜单的 emoji 不是独立块，只是往当前文本块插入字符，`text` 参数已经覆盖，不需要新增类型。

验证：`flutter analyze` 干净；`flutter test test/features/mcp` 10 个用例通过，新增断言覆盖表头默认值、显式关闭表头行、表头列、outline 类型，以及 `buildUpdateAttributes` 的字段过滤和类型校验。

### 2026-10-23：数据库读取工具 query_database（服务版本 0.6.6）

此前 Agent 能看到 grid/board/calendar 块，但读不到里面的行数据——对笔记类应用来说这是个实打实的功能洞。新增只读工具 `query_database`（第 18 个工具）：

- 入参：`workspace_id`、`view_id`（来自块的 `attributes.view_id`），可选 `limit`（默认 20，上限 100）和 `field_ids`（只返回指定字段）。
- 一次 `DatabaseViewBackendService.openDatabase()` 拿到字段 ID 和行 ID，再用 `DatabaseEventGetFields` 取字段名/类型，逐格 `DatabaseEventGetCell` 取单元格。
- 输出：`layout`、`fields`（id/name/type）、`rows`（`row_id` + 按字段名组织的单元格文本）、`row_count`、`returned`、`truncated`。
- 单元格按 `FieldType` 转文本：文本/数字/翻译走 UTF-8；日期按秒级时间戳格式化为 `yyyy-MM-dd[ HH:mm]`，区间用 `~` 连接；创建/编辑时间优先用后端给的字符串；单选/多选/检查清单取选项名并用 `, ` 拼接；URL 取内容；时间用 `formatTime`；关联返回行 ID；附件返回文件名；未知类型退回 UTF-8 解码，解析失败返回空串而不是报错。

限制：

- 逐格查询是 N+1 次 FFI 调用（行数 × 字段数），`limit` 默认 20、上限 100 就是为了兜住这个开销；后端目前没有批量取单元格的事件。
- 行顺序沿用视图自身的排序，工具不做二次排序或过滤。
- 只读，不提供新增/修改行的能力。

验证：`flutter analyze` 干净；`flutter test test/features/mcp` 11 个用例通过，新增 `formatCellValue` 的类型映射断言（文本、数字、勾选、单选、时间、关联、空单元格）和工具注册表 18 项检查。

### 2026-10-23：数据库读写、字段管理与块移动（服务版本 0.6.7）

把数据库补成完整闭环：建视图 → 加字段 → 加行 → 改单元格 → 删行/删字段。工具从 18 个增加到 25 个。

**数据库写入**

- `create_database_row`：先解析全部字段名（写错字段名不会留下空行），再 `RowBackendService.createRow`，最后逐格写入；返回 `row_id`、`written` 和逐条 `errors`。
- `update_database_cell`：按字段名或字段 ID 定位，写完后回读一次，把实际落盘的 `saved_value` 一起返回。
- `delete_database_row`：`deleteRows` 后重新打开视图确认行已消失，返回 `deleted`。
- 字段类型写入规则：文本/数字/URL/时间/翻译/摘要走 `CellBackendService.updateCell`；勾选转 `Yes`/`No`；日期走 `DateCellBackendService`（ISO 8601 输入，秒级时间戳写入）；单选/多选优先匹配已有选项名，不存在才新建；检查清单按逗号拆分逐项插入；关联、附件、创建/编辑时间返回明确的“不支持写入”。

**字段管理**

- `create_database_field`：类型名映射到 `FieldType`，可选 `before_field` 定位（用 `moveField` 调整顺序，落在目标字段之前）；`before_field` 不存在时字段仍然创建，返回 `warning`。
- `update_database_field`：重命名，返回 `old_name`。
- `delete_database_field`：主字段直接拒绝；删除后重新读取字段列表确认消失。

**块移动**

- `move_block`：支持换父块或调整同级顺序；拒绝移入自身或自身子孙；同父块内向后移动时自动修正索引；移走唯一子块时给原父块补一个空段落，避免空块校验失败；写入后确认块的父块 ID。

**验证**

- `flutter analyze` 干净；`flutter test test/features/mcp` 12 个用例通过。
- 工具注册表检查更新到 25 项：7 个只读、4 个破坏性（`delete_page`、`delete_block`、`delete_database_row`、`delete_database_field`）、18 个非只读。
- 新增值解析断言：`asBool`（true/YES/1 为真，false/空为假）、`splitValues`（逗号拆分、去空项）。

**已知限制**

- 单元格写入是逐格调用，新增一行带 N 个字段就是 N 次 FFI；没有批量接口。
- 单选/多选写入时，若选项名不存在会**新建选项**而不是报错，这是为了 Agent 能直接写值；需要注意别拼错造成重复选项。
- 关联和附件字段只读不写。
- 以上全部只经过类型检查和单测，**尚未在运行中的客户端上实测**。

### 2026-10-23：回收站列表与页面复制（服务版本 0.6.8）

补上页面生命周期的两个缺口：

- `list_trash`（只读）：列出回收站里的页面 ID、标题和删除时间。此前 `restore_page` 要求调用方自己知道页面 ID，删完再想恢复只能靠记忆。回收站是账号级的，`workspace_id` 只用于校验登录和工作区。
- `duplicate_page`：复制页面，默认连同子页面一起复制（与界面右键复制一致），副本标题追加「 (副本)」。可指定 `parent_page_id` 放到别的页面下；复制完可以再调 `rename_page` 改名。
- 页面 JSON 增加 `icon`（emoji）和 `is_locked`（锁定页写入会被拒绝），`get_page`、`list_pages`、`create_page`、`duplicate_page` 都会带上。

验证：`flutter analyze` 干净；`flutter test test/features/mcp` 12 个用例通过，注册表检查更新到 27 项（8 只读、4 破坏性、19 非只读）。

### 2026-10-23：27 个工具全量实测与三项修复（服务版本 0.6.9）

在运行中的 Linux 客户端、`mcp-测试空间-tmp` 工作区里通过 MCP 协议逐个调用了全部 27 个工具：

- 只读 8 个、页面生命周期 8 个、内容块 7 个、数据库 7 个、工作区 3 个（部分工具跨组统计），基础读写全部通过。
- 负向路径：非当前工作区返回 `workspace_mismatch`；删除主字段返回 `invalid_params`。
- 数据库 0.6.7 新增的写入、字段管理与块移动工具此前只有单测，这次全部在真实客户端验证通过。

本轮发现并修复：

1. **`duplicate_page` 副本沿用源文档的根块与块 ID。** 副本内容独立，但 `get_page` 返回的块 `parent_id` 指向源页面，块 ID 与源文档重复。根因在 `flowy-core/src/deps_resolve/folder_deps/folder_deps_doc_impl.rs`：`duplicate_view` 原样导出 `DocumentDataPB`，创建新视图时没有重映射。新增 `remap_document_ids`，为副本重建全部块 ID（根块使用新页面 ID，其余生成新 ID），同步修正 `parent_id`、`children_id` 与 `children_map`；`text_map` 的键是文本 `external_id`，保持不变。`DuplicateData` 与 `Data` 两条路径都生效，新增 3 个单元测试。

   第一次实现只改了根块 ID，线上回归时副本读出来是空的：根块的 `children_id` 才是正文挂载到 `children_map` 的键，只改块 ID 会让正文留在旧键下。`children_id` 现已一并重映射。
2. **`get_context` / `open_workspace` 的工作区名恒为 “Workspace”。** `WorkspacePB.name` 是账号级默认名，实际展示名在 `UserWorkspacePB` 上。两处改为按 ID 从工作区列表取名字，找不到才回退。`list_workspaces` 行为不变。
3. **刚写入的内容搜不到。** 有两个叠加原因：

   - 本地索引由 30 秒轮询的即时索引器更新，只处理轮询时仍存活的文档；MCP 写入后立即关闭文档，内容常常落在窗口外。现在 `DocumentManager` 记录本次打开期间写过内容的文档（`apply_action`、文本增量、撤销/重做都会标记），关闭时同步编码并交给索引器；新建文档在 `create_document` 里直接索引。30 秒轮询保留，负责长时间打开文档的持续更新。
   - `flowy-search-pub/src/tantivy_state.rs` 的所有写入路径只 `commit` 不 `reader.reload`，已创建的 IndexReader 看不到新 segment，运行期新增的文档要等进程重启才可见。现在 5 处提交后都调用 `reader.reload()`，并新增“写入后不手动 reload 也能立即搜到正文”的单元测试。

验证：

- `cargo check -p flowy-core` 通过；`cargo test -p flowy-core --lib` 6 个用例通过；`cargo test -p flowy-search-pub --lib` 5 个用例通过；`flutter analyze lib/features/mcp` 干净；`flutter test test/features/mcp` 24 个用例通过。
- 在重新构建的 Linux 客户端（0.6.9）上完成线上回归：
  - `get_context` 与 `open_workspace` 返回真实工作区名「MCP 工具测试空间 1023」，不再返回 “Workspace”。
  - 复制源页（标题 + 段落 + 2 个列表项）后，副本 4 个块全部是新生成的 ID，`parent_id` 指向副本页面，正文完整。
  - 新建页面后立即按正文里的中文标记搜索，能命中；追加一段后再立即搜索新标记，同样命中。

测试页面已全部移入回收站。外部 Agent 联调与并发编辑测试仍未进行。
