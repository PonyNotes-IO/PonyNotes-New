# 快速启动指南 - AppFlowy 主页功能

## 🚀 快速开始（5分钟）

### 步骤 1: 配置 AI 服务（可选）

在 `AppFlowy/frontend/appflowy_flutter/` 目录下创建 `.env.ai` 文件：

```bash
cd AppFlowy/frontend/appflowy_flutter/
cat > .env.ai << EOF
# 选择一个 AI 提供商（OpenAI 或 Anthropic）

# 如果使用 Anthropic Claude
AI_PROVIDER=anthropic
ANTHROPIC_API_KEY=your_api_key_here
ANTHROPIC_MODEL=claude-3-5-sonnet-20241022

# 或者使用 OpenAI
# AI_PROVIDER=openai
# OPENAI_API_KEY=your_api_key_here
# OPENAI_MODEL=gpt-4

# 通用配置
AI_TEMPERATURE=0.7
AI_MAX_TOKENS=4096
EOF
```

### 步骤 2: 安装依赖

```bash
cd AppFlowy/frontend/appflowy_flutter/
flutter pub get
```

### 步骤 3: 运行应用

```bash
flutter run
```

### 步骤 4: 开始使用

应用启动后，主页会自动显示，包含：

- ✅ **待办事项列表** - 管理你的任务
- 🤖 **AI 助手** - 智能问答和建议
- 📄 **最近访问** - 快速访问常用文档

## 📝 快速操作

### 创建待办事项
1. 点击 "+ 新建待办" 按钮
2. 输入标题和描述
3. 选择优先级（高/中/低）
4. 设置截止日期（可选）
5. 添加标签（可选）
6. 点击"创建"

### 使用 AI 助手
1. 在底部输入框输入你的问题
2. 按 Enter 或点击发送按钮
3. 等待 AI 回复
4. 如果需要创建待办，AI 会提供建议

### 查看最近访问
- 滚动到"最近访问"区域
- 点击任意文档快速打开

## 🔧 常见配置

### 只使用待办功能（不需要 AI）
- 不创建 `.env.ai` 文件即可
- 待办功能完全独立运行
- AI 输入区域会显示配置提示

### 切换 AI 提供商
编辑 `.env.ai` 文件：
```env
# 从 Anthropic 切换到 OpenAI
AI_PROVIDER=openai
OPENAI_API_KEY=your_openai_key
OPENAI_MODEL=gpt-4
```

### 自定义 AI 参数
```env
# 调整创造性（0.0-1.0）
AI_TEMPERATURE=0.9

# 增加响应长度
AI_MAX_TOKENS=8192

# 使用自定义 API 端点
OPENAI_BASE_URL=https://your-custom-endpoint.com/v1
```

## 📊 功能速览

### 待办优先级
- 🔴 **高优先级**: 紧急重要任务
- 🟡 **中优先级**: 常规任务（默认）
- 🟢 **低优先级**: 可以稍后处理

### 待办来源
- 📝 **手动创建**: 你自己添加的待办
- 📅 **日历同步**: 从 AppFlowy 日历导入
- 🤖 **AI 建议**: AI 助手生成的任务

### AI 模型选择

**Anthropic Claude:**
- `claude-3-5-sonnet-20241022` (推荐) - 平衡性能和速度
- `claude-3-opus` - 最强性能
- `claude-3-haiku` - 最快响应

**OpenAI:**
- `gpt-4` (推荐) - 最佳质量
- `gpt-4-turbo` - 更快的 GPT-4
- `gpt-3.5-turbo` - 经济实惠

## 🐛 快速故障排除

### 问题: 主页不显示
```bash
# 清理并重新构建
flutter clean
flutter pub get
flutter run
```

### 问题: AI 不响应
1. 检查 API 密钥是否正确
2. 验证网络连接
3. 查看控制台错误信息
4. 确认 `.env.ai` 文件在正确位置

### 问题: 待办不保存
1. 检查应用存储权限
2. 重启应用
3. 清除应用数据重试

### 查看日志
```bash
flutter run -v
```

## 📖 更多信息

- 详细文档: 参见 `HOMEPAGE_INTEGRATION.md`
- 代码位置: `lib/plugins/homepage/`
- 配置文件: `.env.ai`

## 🎯 下一步

- 探索 AI 助手的更多功能
- 创建你的第一个待办事项
- 尝试不同的 AI 模型
- 集成日历功能

---

**提示**: 如果不需要 AI 功能，完全可以只使用待办和最近访问功能！

