# 小马笔记本地 MCP 接入与兼容性清单

- 日期：2026-10-21
- 适用版本：客户端 MCP 服务 `0.4.0`（阶段五）
- 端点：`http://127.0.0.1:27861/mcp`（固定端口，仅回环地址）

## 1. 鉴权

1. 客户端登录后打开 设置 →「AI 接入 (MCP)」。
2. 开启服务并生成 Token（明文只展示一次）。
3. Agent 每个请求携带 `Authorization: Bearer <MCP Token>`。
4. Token 绑定生成时的账号和后端环境；退出登录、切换账号、切换后端或撤销授权后立即失效。
5. Token 不放在 URL 查询参数中，也不会写入客户端日志。

## 2. 直接使用 Streamable HTTP 的 Agent

```json
{
  "mcpServers": {
    "ponynotes": {
      "type": "streamable-http",
      "url": "http://127.0.0.1:27861/mcp",
      "headers": { "Authorization": "Bearer <MCP Token>" }
    }
  }
}
```

设置页的 Token 弹窗可直接复制这段配置（含 Token）。

## 3. 只支持 stdio 的 Agent

桥接程序位于 `PonyNotes-New/frontend/tools/mcp_stdio_bridge/`，把 stdio 会话转发到本地 HTTP 端点，不重复实现工具。

```bash
cd PonyNotes-New/frontend/tools/mcp_stdio_bridge
dart pub get
PONYNOTES_MCP_TOKEN=<MCP Token> dart run bin/mcp_stdio_bridge.dart
```

Agent 配置：

```json
{
  "mcpServers": {
    "ponynotes": {
      "command": "dart",
      "args": [
        "run",
        "<PonyNotes-New>/frontend/tools/mcp_stdio_bridge/bin/mcp_stdio_bridge.dart"
      ],
      "env": {
        "PONYNOTES_MCP_URL": "http://127.0.0.1:27861/mcp",
        "PONYNOTES_MCP_TOKEN": "<MCP Token>"
      }
    }
  }
}
```

说明：

- 协议输出只写 stdout，诊断信息只写 stderr。
- 缺少 `PONYNOTES_MCP_TOKEN` 时以退出码 64 退出；连接失败以退出码 1 退出。
- 客户端未运行或服务未开启时，桥接程序会启动失败并输出原因。

已通过的自动化验证（`dart test`，4 项）：

- 代理暴露上游工具及 schema。
- 代理转发工具调用并返回结果。
- 错误 Token 被拒绝（HTTP 403）。
- 真实启动 `bin/mcp_stdio_bridge.dart` 子进程，通过 stdio 完成 initialize、tools/list、tools/call。

真实客户端验证（2026-10-21，Linux 客户端 + Claude Code）：

- HTTP 接入：工具发现 17 个，读取、创建、追加、块修改、重命名、删除/恢复页面均通过。
- stdio 桥接：对运行中的客户端启动桥接进程，完成 initialize、tools/list（17 个工具）和 `get_context` 调用。

## 4. 命令行冒烟检查

先开启服务并准备好 Token：

```bash
curl -s http://127.0.0.1:27861/mcp \
  -H 'Authorization: Bearer <MCP Token>' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

不带 Token 时应返回 403；带正确 Token 时应返回 17 个工具。也可以在设置页点击「服务自检」，它会验证端点可达且鉴权生效。

## 5. 目标 Agent 实测清单

以下各项需要在装有对应客户端的机器上逐项执行并记录结果。当前均为**待实测**，不要据此承诺兼容。

| 目标 | 接入方式 | 检查项 | 结果 |
| --- | --- | --- | --- |
| Claude Code | Streamable HTTP + Bearer；stdio 桥接 | 工具发现 17 个、上下文读取、页面读写全流程 | 通过（2026-10-21，Linux 客户端） |
| Codex | Streamable HTTP + Bearer | 工具发现、`get_context`、`create_page`、页面写入可见 | 待实测 |
| OpenClaw | 优先 HTTP，必要时 stdio 桥接 | 自定义 header、协议版本协商、工具调用 | 待实测 |
| WorkBuddy | 优先 HTTP，必要时 stdio 桥接 | 本机地址访问、Token 配置方式 | 待实测 |
| 豆包办公 | 以客户端实际支持为准 | 是否支持本机 HTTP/stdio、鉴权字段 | 待实测 |
| 千问办公 | 以客户端实际支持为准 | 是否支持本机 HTTP/stdio、鉴权字段 | 待实测 |

每项至少记录：

1. 客户端版本与操作系统。
2. 使用的接入方式（HTTP 或 stdio）和配置片段。
3. `tools/list` 是否成功、工具数量。
4. 一次只读调用（`get_context` 或 `list_pages`）结果。
5. 一次写入调用（`create_page` 或 `append_content`）及客户端界面是否同步显示。
6. 失败时的错误码与客户端日志（隐去 Token）。

## 6. 已知限制

- 云端运行的 Agent 无法直接访问用户电脑的 `127.0.0.1`，需要另行解决连接方式。
- 需要完整 OAuth 授权流程的 Agent 不能直接使用当前的手工 Bearer Token 模式。
- 同一时刻只支持客户端当前工作区；跨工作区操作需先 `open_workspace`。
- 写入与界面编辑的并发只做了写后重读确认，尚未做并发实测。
- `search_notes` 的本地搜索来自 tantivy，只返回页面 ID 和标题，没有命中摘要；中文查询可能返回较宽的结果集。
