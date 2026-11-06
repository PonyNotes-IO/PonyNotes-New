# 文档索引

本目录存放 PonyNotes 客户端的方案与实施文档。约定：

- 文件名用 kebab-case，主题型文档带 `-plan` / `-design` / `-compatibility` 后缀。
- 文档开头写明**适用范围**与**日期**，涉及改动的注明"是否影响服务端"。
- 方案类文档必须包含：现状评估 → 方案 → 取舍 → 分阶段验收 → 风险清单。
- 已落地的方案在状态列标「已实现」，未动工的标「设计中」。

## 项目自有文档

| 文档 | 主题 | 状态 | 日期 |
| --- | --- | --- | --- |
| [weknora-feishu-mvp-plan.md](./weknora-feishu-mvp-plan.md) | 小马接入 WeKnora 知识库并连接飞书：范围、实施任务、验收与权限边界 | 笔记检索服务已部署，聊天开关及 Windows Debug 构建通过；模型回答待用户验收，飞书待接入 | 2026-11-06 |
| [bidirectional-links-client-design.md](./bidirectional-links-client-design.md) | 客户端双链笔记：数据模型、链接解析、反向索引、图谱、增量更新与一致性取舍 | 主流程已实现，性能预算待实测 | 2026-11-03 |
| [mcp-implementation-plan.md](./mcp-implementation-plan.md) | 客户端本地 MCP 实现计划（二期第一章） | 设计中 | 2026-10-21 |
| [mcp-note-links.md](./mcp-note-links.md) | MCP 双链笔记引用、反链与独立图谱工具（仅客户端） | 已实现，真实客户端验收待完成 | 2026-11-03 |
| [mcp-agent-compatibility.md](./mcp-agent-compatibility.md) | 本地 MCP 接入与兼容性清单 | 设计中 | 2026-10-21 |
| [mcp-phase6-internal-ai-plan.md](./mcp-phase6-internal-ai-plan.md) | MCP 阶段六：内部 AI 接入实施核查 | 设计中 | 2026-10-21 |
| [handwriting-storage-refactor-plan.md](./handwriting-storage-refactor-plan.md) | 手写笔记存储与同步重构（仅客户端改动） | 已实现 | 2026-10-20 |

## 上游遗留

以下文件来自 AppFlowy 上游，与本项目自研内容无关，保留以便对照：

- `CONTRIBUTING.md` — 上游贡献指南
- `roadmap.md` — 上游路线图外链
- `imgs/` — 上游图片资源

## 相关但不在本目录

| 内容 | 位置 |
| --- | --- |
| 双链能力原型（独立可运行，验证机制用） | `/linknotes/` |
| 服务端文档 | `PonyNotes-Cloud-New/` |
