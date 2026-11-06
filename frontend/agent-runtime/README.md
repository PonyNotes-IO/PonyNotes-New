# 小马笔记 Agent 运行时

在 AI 对话输入区选择 **Agent**，打开“模型设置”配置 OpenAI 兼容模型，再点击“连接执行器”。桌面端默认在本机运行；手机端在“Agent 设置”中填写远端执行器的 `wss://域名/agent` 地址和连接密钥。

Chat 使用原有对话服务，启动 Chat 不需要 Node 或 pi。Agent 使用锁定的 `@earendil-works/pi-coding-agent@1.5.0`，界面完全由 Flutter 绘制。小型 Node 宿主直接调用 pi SDK，复用其模型工具循环、流式事件、MCP、持久化会话与上下文压缩；JSONL 管道和 WebSocket 共用同一个宿主。

## 使用

- 模式切换保留两边的输入状态；运行期间先停止再切换。
- “引入 Chat 上下文”可预览并将现有问答加入下一条 Agent 任务。
- 支持选择图片和文本附件，最多 4 个、每个 5 MB。原 Chat 的附件能力保留。
- 默认开放当前账号/工作区的笔记工具；写入逐次确认。在 Agent 设置中可单独关闭工具，不影响外部 MCP 客户端。
- 文件工具只有在选择授权目录后才开放。启用命令能力后，每次执行还需确认。Windows 使用 `pwsh.exe -NoProfile -NonInteractive`，不回退旧 PowerShell 或 bash。
- 运行中可选择“补充指令”或“排队发送”；收到执行器结束事件后才恢复空闲。
- 历史任务保留 pi 原生消息及工具结果；恢复会话不重放写入。上下文面板支持手动压缩。
- 工具详情显示结果；笔记写入可显示修改前后内容，确认期间页面有变化时拒绝继续写入。结果笔记可在详情面板中打开。
- 手动停止会拒绝未批准动作并取消执行；已提交给业务服务的写入仍应查询确认结果。

## MCP 和 Skills

Agent 设置中的 MCP 配置是服务名到配置的 JSON 对象：

```json
{
  "docs": { "url": "https://example.com/mcp" },
  "local": {
    "command": "your-mcp-server",
    "args": [],
    "env": { "SERVICE_TOKEN": "your-server-token" }
  }
}
```

配置支持 stdio、Streamable HTTP 和 pi 的 MCP OAuth。外部 MCP 工具逐次审批；`toolExposure` 可隐藏特定工具。旧 SSE transport 不受支持。

需要登录时，在 Agent 输入 `/mcp login 服务名`，点击授权页面入口；远端运行时的 loopback 回调通过客户端中继回原执行器，并验证回调地址和 OAuth state。可用 `/mcp` 检查状态、重连或退出登录。

桌面端可添加用户信任的 Skills 目录。不会自动加载用户全局 pi 扩展或笔记附件中的可执行项目配置。移动端的本地 Skills 目录不会被远端读取；管理员可用 `PONYNOTES_AGENT_SKILLS` JSON 数组指定执行器中信任的 Skills 目录。模型和 MCP 凭据分别存入客户端系统安全存储，传给运行时后只保存在内存；会话文件不存放模型 Key 或 OAuth 凭据。

## 开发与打包

需要 Node.js >= 22.19，CI 固定为 24.9.0。在本目录运行：

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
npm.cmd test
node prepare.mjs
```

`prepare.mjs` 生成忽略入库的 `bundle/`，包含 Node、锁定依赖、运行代码和许可证。Windows/Linux 的 CMake 安装流程会准备并复制运行时；macOS Xcode 的 embed 阶段将其复制到应用 Resources。发布目标必须使用对应平台和架构的 Node 执行打包，并沿用应用的签名流程。

开发运行可从 `frontend/appflowy_flutter` 找到相邻运行时。安装版优先使用随包携带的 Node，不要求用户安装 Node/npm，也不会在线安装运行依赖。

Linux 系统安全存储依赖 `libsecret-1-dev`、`libjsoncpp-dev`；运行时需要可用的系统 Secret Service。相关开发安装脚本和 CI 已补齐构建依赖。

## 手机端远端执行器

每个用户使用独立执行器和数据卷，在受控服务器上设置 `PONYNOTES_AGENT_TOKEN`（至少 32 个字符），再启动：

```powershell
$env:PONYNOTES_AGENT_DATA = 'D:/PonyNotesAgentData'
$env:HOST = '127.0.0.1'
$env:PORT = '4319'
npm.cmd run serve
```

连接密钥应由部署环境注入；不要放入仓库或命令行参数。通过 TLS 反向代理将 `/agent` 转发至此服务。除本机调试外，Flutter 拒绝明文 WebSocket。也可使用本目录 Dockerfile，运行非 root 用户的独立容器并挂载 `/data`。

执行器验证 Bearer 密钥，同一执行器只允许一个活动连接，断线后撤销待批准动作。远端命令能力还需要服务器设置 `PONYNOTES_AGENT_ALLOW_COMMANDS=true`；远端文件只位于自己的任务目录。手机笔记工具经当前登录客户端回传执行，远端不会访问手机的 `127.0.0.1`。客户端离线或被系统挂起时，本机笔记操作无法继续。

pi 和子进程拥有执行器系统用户的权限。授权目录检查与审批不替代系统沙箱；运行命令或不受信任的 stdio MCP 时，应使用专用账号、容器或虚拟机限制访问范围。

## 验证

`npm test` 使用真实 pi 引擎和确定性的本机模型/MCP 服务，覆盖多轮工具调用、完整协议历史恢复、MCP 拒绝执行、路径/符号链接边界、断线撤权、上下文压缩、远端鉴权和单连接限制。

Flutter 的 `test/features/agent/` 覆盖实际 Dart→Node→pi 流式管道与恢复、写入审批/参数校验/撤权、配置隔离、模式切换与草稿，以及桌面亮色和手机暗色的实际组件渲染。

商业模型账号、第三方 MCP OAuth 服务及 Android/iOS/macOS/Linux 实机需要在对应部署环境验证。远端执行器的生产部署、已有云订阅向 pi 提供模型的网关和浏览器 Web 构建不由此运行时自动提供。
