# 小马笔记 Agent 运行时

新建“问 AI”文档时选择 **Chat** 或 **Agent**。Chat 使用原有问答服务；Agent 文档直接进入工具执行界面，点击输入框旁的模型菜单，在“配置自定义模型”中填写 OpenAI 兼容模型即可使用。桌面端默认在本机运行；手机端在“Agent 设置”中填写远端执行器的 `wss://域名/agent` 地址和连接密钥。

Chat 使用原有对话服务，启动 Chat 不需要 Node 或 pi。Agent 使用锁定的 `@earendil-works/pi-coding-agent@1.5.0`，界面完全由 Flutter 绘制。小型 Node 宿主直接调用 pi SDK，复用其模型工具循环、流式事件、MCP、持久化会话与上下文压缩；JSONL 管道和 WebSocket 共用同一个宿主。

## 使用

- 一个会话就是一个“问 AI”文档。模式保存于文档的 `extra.ai_mode`；没有该字段的旧文档继续使用 Chat。
- Agent 使用文档 ID 关联唯一的 pi 会话，重新打开恢复完整上下文。界面不再显示单独的 Agent 会话列表、“新任务”或手工交接上下文入口。
- 文档内的模式菜单明确提供“新建 Chat 对话”“新建 Agent 对话”；选择后创建新文档，不改变已有文档的历史和执行语义。
- 输入框旁可选择已保存的自定义模型，菜单底部可直接配置地址、模型名和 API Key。支持推理的模型开启“支持推理 / 思考程度”后，可用滑杆选择关闭、极低、低、中、高；设置会传入 pi 和实际模型请求。执行任务时禁止切换，空闲时切换保留当前文档上下文。
- 启动在后台自动连接，不显示连接过程；连接失败仍显示错误和重试入口。
- 支持选择图片和文本附件，最多 4 个、每个 5 MB。原 Chat 的附件能力保留。
- 输入框下方可随时切换工作目录和权限模式，按文档保存（`AgentWorkspaceConfig`），切换目录不丢失当前文档上下文：
  - 未选择工作目录：只开放小马笔记的笔记工具，不加载文件工具、命令、MCP 和 Skills。
  - 选择工作目录后：文件工具限定在该目录内，并开放命令（远端还需 `PONYNOTES_AGENT_ALLOW_COMMANDS=true`）、MCP 和 Skills。
  - 权限模式：逐次确认（所有写入/命令确认）、自动审批（笔记写入与目录内文件修改直接执行，删除、命令、外部 MCP 仍确认）、完全开放（均不确认，开启时二次确认）。
- 在 Agent 设置中可单独关闭笔记工具，不影响外部 MCP 客户端。Windows 命令使用 `pwsh.exe -NoProfile -NonInteractive`，不回退旧 PowerShell 或 bash。
- 运行时用自定义系统提示词替换引擎默认提示词，模型以"小马 Agent"身份回答，不暴露底层实现；工具结果和错误中的引擎名称会被替换。
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

`npm test` 使用真实 pi 引擎和确定性的本机模型/MCP 服务，覆盖同一 Agent 文档中的问答与任务、禁止另建内部会话、初始请求去重、多轮工具调用、完整协议历史恢复、MCP 拒绝执行、路径/符号链接边界、断线撤权、上下文压缩、远端鉴权和单连接限制。

自定义模型会记录真实 token 用量。由于没有供应商费率表，运行时不估算其实际账单费用。

Flutter 的 `test/features/agent/` 覆盖实际 Dart→Node→pi 流式管道与恢复、写入审批/参数校验/撤权、配置隔离、新建时选择两种模式、旧文档模式兼容、文档界面无内部会话列表，以及桌面亮色和手机暗色的实际组件渲染。

商业模型账号、第三方 MCP OAuth 服务及 Android/iOS/macOS/Linux 实机需要在对应部署环境验证。远端执行器的生产部署、已有云订阅向 pi 提供模型的网关和浏览器 Web 构建不由此运行时自动提供。
