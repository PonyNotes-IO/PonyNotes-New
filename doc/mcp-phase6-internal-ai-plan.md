# MCP 阶段六：内部 AI 接入 —— 实施核查

- 依据：`doc/mcp-implementation-plan.md` §7 阶段六、§8 验收表「内部 AI」一行
- 需求原文：「配置本地 AI Token：用户可自行配置本地 AI 的 Token；自主接入、用户自行承担配额与成本」
- 代码基线：`PonyNotes-New` @ `dev_mobile_new`，**工作树未提交**
- 核查时间：2026-10-23。本文记录的是**已落地代码**，不是计划稿

---

## 0. 结论

阶段六端到端可用：**配置 → 连通性测试 → 对话 → 工具读写 → 写操作确认**，17 个工具全部接上，24 个测试通过。

配置从「和 Ollama 共用一份」改为**独立存储**（`SharedPreferences`），两边互不覆盖；对话界面挂在设置侧栏「内部 AI 对话」。

仍未做的两件小事：文案没走本地化、命令面板里还没有入口（现在只能从设置进）。见 §5.1。

---

## 1. 完成度

| 验收点 | 状态 | 位置 |
| --- | --- | --- |
| 用户可配置模型地址 / 模型名 / API Key | 已实现 | `features/ai_internal/presentation/ai_provider_settings_view.dart` |
| 配置持久化（含 Key） | 已实现，独立存储（Dart `SharedPreferences`） | `ai_provider_config.dart` |
| 设置页入口 | 已实现 | `settings_menu.dart:235` → `settings_dialog.dart:359` |
| 连通性测试 | 已实现（发一句「你好」） | `ai_provider_settings_view.dart:100` |
| 多轮工具调用 | 已实现 | `internal_ai_service.dart:126` |
| 轮次上限（8） | 已实现 | `internal_ai_service.dart:100` |
| 写操作确认 | 已实现（默认开启） | `internal_ai_service.dart:88` / `:173` |
| 凭据隔离（MCP Token ↔ 模型 Key） | 已实现（两套独立字段） | 见 §2 |
| 失败原因可读（401/429/超时） | 已实现 | `internal_ai_service.dart:50` 起 |
| 工具覆盖面：17 / 17 | 已实现（含 11 个写工具） | `mcp_tools.dart:317` 的 `_toolSpecs` |
| MCP 与内部 AI 共用同一份工具表 | 已实现，`registerAll` 遍历 `toolSpecs` | `mcp_tools.dart:354` |
| 对话界面 | 已实现（设置侧栏「内部 AI 对话」） | `ai_chat_view.dart` → `settings_dialog.dart` |
| 文案本地化 | 未实现（硬编码中文） | 与旁边 MCP 项风格一致，见 §5 |

---

## 2. 三个设计决策（原「待确认」项，代码已定案）

1. **配置存储：先走 Rust，最终改成 Dart 独立存储。** 早期在 `LocalAISettingPB` 加 `api_key = 4`（`entities.rs:731`、两处 `From` `740`/`751`、`local_ai/controller.rs:19`）。后来发现 `LocalAISetting` 是 Ollama 设置页共用的同一份存储——在「内部 AI 模型」里填地址会把 Ollama 的 `server_url` 和聊天模型一起改掉。改成 `AiProviderConfigStorage`（`SharedPreferences`，三个独立的 `ai_internal.*` 键），Dart 侧不再读写 `LocalAISetting`；Rust 的 `api_key` 字段保留，留给「Ollama 前面挂代理」这类需要鉴权的场景。
2. **只支持 OpenAI 兼容 `/v1/chat/completions`**，不兼容 Ollama 原生 `/api/chat`。地址自动补 `/v1`（`internal_ai_service.dart:303`：已带 `/chat/completions` 或 `/v1` 时按原样拼）。
3. **写操作必须用户确认。** `writeConfirmationRequired = true`（`internal_ai_service.dart:88`）；命中非只读工具时立刻返回 `requiresConfirmation: true` + `pendingWrite`，不执行 handler（`:173`）。

---

## 3. 与旧版计划的差异

计划里要新增的 `mcp_tool_executor.dart` **没有创建**。改为让 `McpTools` 自己暴露执行入口：

- `McpTools.toolSpecs`（`mcp_tools.dart:317`）：`name / description / inputSchema / readOnly / handler` 的注册表
- `McpTools.executeTool(name, args)`（`:343`）：按名查表执行，未知工具返回 `isError` 结果而不抛异常
- 内部 AI 在 `internal_ai_service.dart:190` 调 `_tools.executeTool(...)`，OpenAI 的 `tools` 声明由 `toolSpecs` 直接生成

结果符合原目标（单一执行入口、笔记操作逻辑零重复），但少一个文件。代价见 §5 第 2 条。

另：原 §1.3 提到的 `ai_model_service.dart` 硬编码 `apiBaseUrl` **已修**，改走 `Env.afCloudUrl`。

---

## 4. 实际改动的文件

### 新增

| 文件 | 行数 |
| --- | --- |
| `frontend/appflowy_flutter/lib/features/ai_internal/application/internal_ai_service.dart` | ~380 |
| `frontend/appflowy_flutter/lib/features/ai_internal/application/ai_provider_config.dart` | 84 |
| `frontend/appflowy_flutter/lib/features/ai_internal/presentation/ai_provider_settings_view.dart` | ~250 |
| `frontend/appflowy_flutter/lib/features/ai_internal/presentation/ai_chat_view.dart` | ~300 |
| `frontend/appflowy_flutter/test/features/ai_internal/internal_ai_service_test.dart` | ~380 |
| `frontend/appflowy_flutter/test/features/ai_internal/ai_provider_config_test.dart` | 48 |
| `frontend/appflowy_flutter/test/features/ai_internal/ai_chat_view_test.dart` | 30 |

### 修改

| 文件 | 改动 |
| --- | --- |
| `lib/features/mcp/application/mcp_tools.dart` | 新增 `McpToolSpec` / `toolSpecs` / `executeTool` |
| `lib/workspace/application/settings/settings_dialog_bloc.dart` | `SettingsPage` 加 `aiProvider`、`aiChat` |
| `lib/workspace/presentation/settings/settings_dialog.dart` | 两个 case：`AiProviderSettingsView` / `AiChatView` |
| `lib/workspace/presentation/settings/widgets/settings_menu.dart` | 菜单项「内部 AI 模型」「内部 AI 对话」 |
| `lib/core/network/ai_model_service.dart` | 硬编码域名改 `Env.afCloudUrl` |
| `rust-lib/flowy-ai/resources/proto/entities.proto` | `api_key = 4` |
| `rust-lib/flowy-ai/src/entities.rs` | 字段 + 两处 `From` |
| `rust-lib/flowy-ai/src/local_ai/controller.rs` | serde 字段、空配置判定、断言测试 |

生成物已同步：`packages/appflowy_backend/lib/protobuf/flowy-ai/entities.pb.dart` 含 `apiKey`。

---

## 5. 本轮修掉的问题

1. **工具表补到 17 / 17。** `_toolSpecs`（`mcp_tools.dart:317`）现在覆盖全部 17 个工具，其中 6 个只读、11 个写；内部 AI 因此可以用 `search_notes`、`get_page`、`list_blocks` 和全部写工具。
2. **`registerAll` 改为遍历 `toolSpecs`**（`mcp_tools.dart:354`），工具定义只剩一处，不会再漂移。`McpToolSpec` 新增 `destructive` 字段 + `annotations` getter，保持每个工具原有的 MCP 注解语义：只读 → `readOnlyHint`，破坏性写（`delete_page`/`delete_block`）→ 无提示，其余写 → `destructiveHint: false`。
3. **配置与 Ollama 彻底分开。** 新增 `AiProviderConfig` + `AiProviderConfigStorage`（`SharedPreferences`，键 `ai_internal.base_url` / `ai_internal.model` / `ai_internal.api_key`）。设置页和 `InternalAiService` 都改用它，Ollama 的 `LocalAISetting` 不再被写入，embedding 被覆盖的 bug 一并消失。
4. **对话界面。** 新增 `AiChatView`（`features/ai_internal/presentation/ai_chat_view.dart`）：多轮历史、工具调用逐条展示、写操作弹框确认、未配置时给提示不发请求。入口在设置侧栏「内部 AI 对话」（`SettingsPage.aiChat`）。
5. **写操作确认改成回调。** `ask()` 新增可选的 `confirmWrite` 回调，返回 false 时整轮中止、工具不执行。不传回调时仍返回 `requiresConfirmation`，原有行为不变。

## 5.1 仍未解决

1. **文案硬编码中文**（`settings_menu.dart`、设置页与对话页 0 处 `LocaleKeys`）。与相邻 MCP 项风格一致，但与计划 §3「走本地化流程」不符。
2. **命令面板里没有入口。** 对话只能从设置侧栏进；palette 的「问 AI」目前硬绑云端 AI（`goingToAskAI` → 云端 `/api/ai/chat/session`），要接内部 AI 得先拆那层耦合。

---

## 6. 验证记录

```bash
# 均从 frontend/appflowy_flutter 执行，已 source ~/.config/flyenv/env.sh
flutter analyze --no-pub lib/features/mcp lib/features/ai_internal
# → No issues found!（9.5s）

flutter test --no-pub --concurrency=1 test/features/mcp test/features/ai_internal
# → 24 个用例全部通过
```

内部 AI（`internal_ai_service_test.dart`，11 个）：未配置短路、纯文本回复、多轮只读工具、写操作暂停、确认后执行、拒绝后不执行、轮次上限、401、429 配额话术、请求体含 `tools` + Bearer + 地址补 `/v1`、模型返回非法 JSON 参数降级为空参数。

配置存储（`ai_provider_config_test.dart`，2 个）：读写往返、`isComplete` 判定。

对话界面（`ai_chat_view_test.dart`，2 个）：未配置时给出提示、已配置时显示可输入的初始态。

MCP 侧（`mcp_server_service_test.dart`，含新增 1 个）：`工具注册表覆盖全部 17 个工具，只读/破坏性标记正确` 钉住 17 个工具名、6 个只读、2 个破坏性、11 个写，以及未知工具返回 `isError`——防止工具表再次缩水。

### Rust 侧：`cargo check -p flowy-ai` 通过（先修掉一个环境问题）

初次跑的时候在 `flowy-error` 编译失败：

```
error[E0308]: mismatched types
  --> flowy-error/src/errors.rs:15:33
   | expected `code::ErrorCode`, found `protobuf::code::ErrorCode`
error: could not compile `flowy-error` (lib) due to 2 previous errors
```

判断依据：

- `flowy-error` 源码与 HEAD 完全一致（`git status` 干净），与本轮改动无关。
- `touch flowy-error/src/lib.rs && cargo check -p flowy-error` **单独编译通过**（强制重建，非缓存）。
- 逐个试 `--features client-api`、`impl_from_collab_folder`、两者组合，**全部通过**。
- 只有和 `flowy-ai` 一起构建时才失败；`cargo tree -p flowy-ai -e features -i protobuf` 显示 `protobuf` 只启用 `default`，没有 feature 统一差异。

根因（已定位并修复）：**不是源码、不是 feature 统一，是 `target/` 里一个从旧 checkout 构建的 proc-macro 被复用。**

- `flowy-derive` 的 `ProtoBuf` derive 按类型名读 `build-tool/flowy-codegen/.cache/**/proto_cache` 判断枚举（`build-tool/flowy-derive/src/proto_buf/util.rs:57-98`），缓存路径在**编译宏时**由 `env!("CARGO_MANIFEST_DIR")` 烘焙成绝对路径（`util.rs:62`）。
- `cargo check -p flowy-ai` 选中的是 `target/debug/deps/libflowy_derive-8662ee245c1fb66d.so`（10-20 16:37，从 `/tmp/ponynotes-build-check/...` 构建），内嵌路径指向已删除目录；宏读不到缓存 → `ErrorCode` 判成 Primitive → `pb.code = o.code` 与 `super::code::ErrorCode` 类型不符 → 两条反向 E0308。
- `flowy-error` 单独 check 之所以过，是因为它拿到的是当前路径构建的宏单元。

修复：`cargo clean -p flowy-derive`（移除 632 文件 / 173 MiB）→ `cargo check -p flowy-ai` **Finished**（12s）。生成文件与 `.cache` 都正确，**不需要**重新生成 protobuf。

顺带发现：`target/` 里有 23 个 `.d` 指向旧路径 `/tmp/ponynotes-build-check`，说明 target 目录是从别的 checkout 搬来的。新机器上 `.cache` 被 gitignore、只在 dart codegen 时生成，缺缓存同样会复现。已记入 `FLYENV-ENVIRONMENT-REPORT.md` §9 #16。

---

## 7. 提交边界

工作树里同时存在三类改动，提交时必须分开：

1. **MCP 阶段二～五**：`lib/features/mcp/`、`lib/startup/tasks/mcp_server_task.dart`、`test/features/mcp/`、`frontend/tools/mcp_stdio_bridge/`、`doc/mcp-implementation-plan.md`、`doc/mcp-agent-compatibility.md`、`pubspec.yaml`/`pubspec.lock`、`startup.dart` 任务注册、`settings_dialog.dart` 的 MCP case、`settings_menu.dart` 的 MCP 项
2. **阶段六**：`lib/features/ai_internal/`、`test/features/ai_internal/`、`flowy-ai` 三个 Rust 文件、`ai_model_service.dart`、`settings_dialog_bloc.dart` 的 `aiProvider`、`settings_dialog.dart` 的 `aiProvider` case、`settings_menu.dart` 的「内部 AI 模型」项、`appflowy_backend` 生成的 `entities.pb.dart`
3. **本机环境改动（不进提交，见 `FLYENV-ENVIRONMENT-REPORT.md` §8）**：`android/gradle.properties`、`linux/flutter/dart_ffi/binding.h`、`rust-lib/.cargo/config.toml` 删除

`settings_menu.dart` 与 `settings_dialog.dart` 被两个阶段同时改，分行拆提交。

---

## 8. 后续待办

1. 文案走本地化（`settings_menu.dart` + 设置页 + 对话页，目前 0 处 `LocaleKeys`）
2. 命令面板加内部 AI 入口：需要先把 palette 的「问 AI」与云端会话拆开
3. 可选加固：`build-tool/flowy-derive/src/proto_buf/util.rs:62` 的 cache 路径改为展开时解析，并在缓存缺失时直接报错，避免换机器/换 checkout 后静默降级成 Primitive（详见 §6）
