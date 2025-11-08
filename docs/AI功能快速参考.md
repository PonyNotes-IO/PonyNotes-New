# PonyNotes-New AI 功能快速参考

> 快速查阅 AI 功能的关键信息、常用代码和配置

---

## 目录

- [AI 提供商对照表](#ai-提供商对照表)
- [关键文件速查](#关键文件速查)
- [常用代码片段](#常用代码片段)
- [配置模板](#配置模板)
- [API 接口参考](#api-接口参考)
- [故障排查](#故障排查)

---

## AI 提供商对照表

### 支持的 AI 提供商

| 提供商 | 类型 | API Base | 模型示例 | 特点 |
|--------|------|----------|---------|------|
| **AppFlowy Cloud** | 原生云端 | `https://api.appflowy.io` | `gpt-4`, `claude-3` | 企业级、完整功能 |
| **本地 AI (Ollama)** | 原生本地 | `http://localhost:11434` | `llama3.1`, `mistral` | 隐私、离线 |
| **DeepSeek** | 自定义云端 | `https://ark.cn-beijing.volces.com/api/v3` | `deepseek-v3-250324` | 高性价比、推理强 |
| **通义千问** | 自定义云端 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-turbo`, `qwen-max` | 国内、中文优化 |
| **豆包** | 自定义云端 | `https://ark.cn-beijing.volces.com/api/v3` | `doubao-pro-4k` | 字节、多模态 |

### 提供商选择建议

```
┌─────────────────────────────────────────────────────────────┐
│  使用场景                      │  推荐提供商                  │
├─────────────────────────────────────────────────────────────┤
│  企业级应用，完整功能           │  AppFlowy Cloud              │
│  隐私敏感，本地部署             │  本地 AI (Ollama)            │
│  个人使用，性价比高             │  DeepSeek                    │
│  国内用户，中文优化             │  通义千问                    │
│  多模态需求（图片）             │  豆包 / DeepSeek             │
│  代码生成                      │  DeepSeek Coder              │
└─────────────────────────────────────────────────────────────┘
```

---

## 关键文件速查

### Flutter (Dart) 文件

```
frontend/appflowy_flutter/lib/

AI 核心模块:
├── ai/
│   ├── service/
│   │   ├── appflowy_ai_service.dart        # 原生AI服务接口
│   │   ├── ai_entities.dart                # AI数据实体
│   │   └── ai_prompt_input_bloc.dart       # Prompt输入逻辑
│   └── widgets/
│       └── prompt_input/                   # Prompt UI组件

自定义AI模块:
├── core/config/
│   └── ai_config.dart                      # 多提供商配置管理
└── plugins/standalone_ai_chat/
    ├── services/
    │   ├── standalone_ai_service.dart      # 自定义AI服务
    │   ├── image_service.dart              # 图片处理
    │   └── image_storage_service.dart      # 图片存储
    ├── application/
    │   ├── standalone_chat_bloc.dart       # 状态管理
    │   └── standalone_chat_persistence.dart # 本地持久化
    └── presentation/
        └── standalone_chat_page.dart       # UI页面

配置文件:
├── .env.ai                                 # AI配置（需创建）
├── ai_config_example.env                  # 配置模板
└── assets/
    └── built_in_prompts.json               # 内置Prompts
```

### Rust 文件

```
frontend/rust-lib/

AI 核心模块:
├── flowy-ai/src/
│   ├── ai_manager.rs                       # AI管理器（核心）
│   ├── chat.rs                             # Chat实例
│   ├── completion.rs                       # 文本完成
│   ├── model_select.rs                     # 模型选择
│   ├── local_ai/
│   │   ├── controller.rs                   # 本地AI控制器
│   │   ├── chat/                           # LLM聊天
│   │   └── completion/                     # 本地完成
│   ├── embeddings/
│   │   ├── document_indexer.rs             # 文档索引
│   │   ├── embedder.rs                     # 嵌入生成
│   │   └── store.rs                        # 向量存储
│   └── middleware/
│       └── chat_service_mw.rs              # 服务中间件

服务实现:
└── flowy-server/src/local_server/impls/
    └── chat.rs                             # 本地Chat服务实现
```

---

## 常用代码片段

### 1. Flutter: 发送聊天消息

```dart
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/protobuf.dart';

Future<void> sendMessage(String chatId, String message) async {
  final params = StreamMessagePB(
    chatId: chatId,
    message: message,
    messageType: ChatMessageTypePB.User,
    questionStreamPort: Int64(questionPort.sendPort.nativePort),
    answerStreamPort: Int64(answerPort.sendPort.nativePort),
  );
  
  final result = await AIEventStreamChatMessage(params).send();
  result.fold(
    (question) => print('Message sent: ${question.messageId}'),
    (error) => print('Error: ${error.msg}'),
  );
}
```

### 2. Flutter: 使用自定义 AI 提供商

```dart
import 'package:appflowy/core/config/ai_config.dart';
import 'package:appflowy/plugins/standalone_ai_chat/services/standalone_ai_service.dart';

// 初始化配置
await AIConfigService.instance.loadConfig();

// 发送消息
await StandaloneAiService.instance.sendMessage(
  message: "你好，AI",
  provider: AIProvider.deepseek,
  onResponse: (chunk) {
    print('收到: $chunk');
  },
  onError: (error) {
    print('错误: $error');
  },
  onComplete: () {
    print('完成');
  },
);
```

### 3. Flutter: 切换 AI 模型

```dart
Future<void> switchModel(String chatId, String modelName) async {
  final model = AIModelPB(
    name: modelName,
    displayName: 'My Model',
    aiType: ModelTypePB.CloudAI,
  );
  
  final payload = UpdateSelectedModelPB(
    source: chatId,
    model: model,
  );
  
  await AIEventUpdateSelectedModel(payload).send();
}
```

### 4. Rust: 创建 Chat

```rust
use flowy_ai::ai_manager::AIManager;

async fn create_new_chat(
  ai_manager: &AIManager,
  uid: i64,
  parent_view_id: &Uuid,
  chat_id: &Uuid,
) -> Result<()> {
  let chat = ai_manager
    .create_chat(&uid, parent_view_id, chat_id)
    .await?;
  
  println!("Chat created: {}", chat_id);
  Ok(())
}
```

### 5. Rust: 文档索引

```rust
use flowy_ai::local_ai::controller::LocalAIController;

async fn index_document(
  local_ai: &LocalAIController,
  chat_id: &Uuid,
  file_path: PathBuf,
) -> Result<()> {
  // 索引文档
  local_ai.embed_file(chat_id, file_path, None).await?;
  
  println!("Document indexed successfully");
  Ok(())
}
```

### 6. Rust: RAG 检索

```rust
use flowy_ai::embeddings::store::SqliteVectorStore;

async fn search_documents(
  vector_store: &SqliteVectorStore,
  chat_id: &str,
  question: &str,
  top_k: usize,
) -> Result<Vec<String>> {
  // 生成问题嵌入
  let embedding = generate_embedding(question).await?;
  
  // 搜索相关文档
  let results = vector_store.search(chat_id, embedding, top_k).await?;
  
  // 提取内容
  let docs = results.into_iter().map(|r| r.content).collect();
  
  Ok(docs)
}
```

---

## 配置模板

### `.env.ai` 完整配置

```env
# =============================================================================
# 🤖 AI 配置文件
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# DeepSeek (通过火山方舟)
# ─────────────────────────────────────────────────────────────────────────────
AI_DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AI_DEEPSEEK_API_BASE=https://ark.cn-beijing.volces.com/api/v3
AI_DEEPSEEK_MODEL_NAME=deepseek-v3-250324

# ─────────────────────────────────────────────────────────────────────────────
# 通义千问 (阿里云 DashScope)
# ─────────────────────────────────────────────────────────────────────────────
AI_QWEN_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AI_QWEN_API_BASE=https://dashscope.aliyuncs.com/compatible-mode/v1
AI_QWEN_MODEL_NAME=qwen-turbo

# ─────────────────────────────────────────────────────────────────────────────
# 豆包 (字节跳动火山方舟)
# ─────────────────────────────────────────────────────────────────────────────
AI_DOUBAO_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AI_DOUBAO_API_BASE=https://ark.cn-beijing.volces.com/api/v3
AI_DOUBAO_MODEL_NAME=ep-m-20250814175607-b77g6

# ─────────────────────────────────────────────────────────────────────────────
# 通用设置
# ─────────────────────────────────────────────────────────────────────────────
AI_DEFAULT_MODEL=deepseek
AI_CHAT_MAX_TOKENS=4096
AI_CHAT_TEMPERATURE=0.7
AI_CHAT_STREAM_ENABLED=true
```

### Ollama 本地配置

```toml
# LocalAISetting 默认值

ollama_server_url = "http://localhost:11434"
chat_model_name = "llama3.1:latest"
embedding_model_name = "nomic-embed-text:latest"
```

### Rust 环境变量

```env
# 日志级别
RUST_LOG=info,flowy_ai=debug,flowy_server=debug

# Ollama 服务地址
OLLAMA_HOST=http://localhost:11434

# 数据库路径
DATABASE_PATH=~/.appflowy/data.db
```

---

## API 接口参考

### Flutter FFI 接口

#### 1. 流式聊天消息

```dart
// 事件: AIEventStreamChatMessage
// 输入: StreamMessagePB
// 输出: Result<ChatMessagePB, FlowyError>

final params = StreamMessagePB(
  chatId: "uuid",
  message: "Hello AI",
  messageType: ChatMessageTypePB.User,
  questionStreamPort: Int64(port1),
  answerStreamPort: Int64(port2),
);

AIEventStreamChatMessage(params).send();
```

#### 2. 加载聊天历史

```dart
// 事件: AIEventLoadPrevChatMessages
// 输入: LoadPrevChatMessagePB
// 输出: Result<ChatMessageListPB, FlowyError>

final payload = LoadPrevChatMessagePB(
  chatId: "uuid",
  limit: Int64(20),
  beforeMessageId: Int64(1234567890),
);

AIEventLoadPrevChatMessages(payload).send();
```

#### 3. 切换模型

```dart
// 事件: AIEventUpdateSelectedModel
// 输入: UpdateSelectedModelPB
// 输出: Result<(), FlowyError>

final payload = UpdateSelectedModelPB(
  source: "chat_id",
  model: AIModelPB(name: "deepseek-chat"),
);

AIEventUpdateSelectedModel(payload).send();
```

### Rust 内部接口

#### AIManager 主要方法

```rust
// 创建聊天
async fn create_chat(&self, uid: &i64, parent_view_id: &Uuid, chat_id: &Uuid) 
  -> Result<Arc<Chat>, FlowyError>

// 发送消息
async fn stream_chat_message(&self, params: StreamMessageParams) 
  -> Result<ChatMessagePB, FlowyError>

// 更新模型
async fn update_selected_model(&self, source: String, model: AIModel) 
  -> FlowyResult<()>

// 切换本地AI
async fn toggle_local_ai(&self) -> FlowyResult<bool>

// 获取活跃模型
async fn get_active_model(&self, source: &str) -> AIModel
```

#### LocalAIController 主要方法

```rust
// 打开聊天
async fn open_chat(&self, workspace_id: &Uuid, chat_id: &Uuid, 
  model: &str, rag_ids: Vec<String>, summary: String) -> FlowyResult<()>

// 索引文件
async fn embed_file(&self, chat_id: &Uuid, file_path: PathBuf, 
  metadata: Option<HashMap<String, Value>>) -> Result<()>

// 检查模型类型
async fn check_model_type(&self, model_name: &str) -> FlowyResult<ModelType>

// 获取本地AI状态
async fn get_local_ai_state(&self) -> LocalAIPB
```

### 自定义 AI 服务接口

#### StandaloneAiService

```dart
// 发送消息
Future<void> sendMessage({
  required String message,
  required AIProvider provider,
  required Function(String) onResponse,
  required Function(String) onError,
  Function()? onComplete,
  List<ChatImage>? images,
})

// 检查服务可用性
Future<bool> checkServiceAvailability(AIProvider provider)

// 获取支持的模型
List<String> getSupportedModels(AIProvider provider)

// 验证API密钥
bool validateApiKey(AIProvider provider, String apiKey)

// 估算Token数量
int estimateTokenCount(String message)
```

---

## 故障排查

### 问题 1: 本地 AI 无法启动

**症状**: `LocalAI is not ready`

**解决方案**:
```bash
# 1. 检查 Ollama 是否运行
ps aux | grep ollama

# 2. 启动 Ollama 服务
ollama serve

# 3. 验证连接
curl http://localhost:11434/api/tags

# 4. 下载模型
ollama pull llama3.1:latest
ollama pull nomic-embed-text:latest

# 5. 验证模型
ollama list
```

### 问题 2: 自定义 AI 无响应

**症状**: 消息发送后没有响应

**检查清单**:
```dart
// 1. 检查配置是否加载
final status = AIConfigService.instance.getConfigStatus();
print(status);  // 应该显示 isLoaded: true, hasValidConfig: true

// 2. 检查API密钥
final config = AIConfigService.instance.getCurrentConfig();
print('API Key valid: ${config.isValid}');

// 3. 检查网络连接
final available = await StandaloneAiService.instance
  .checkServiceAvailability(AIProvider.deepseek);
print('Service available: $available');

// 4. 查看详细日志
// 在 Flutter 启动时添加: flutter run --verbose
```

### 问题 3: 流式响应中断

**症状**: 响应到一半停止

**可能原因**:
1. **网络超时**: 增加超时时间
2. **API限流**: 检查API调用频率
3. **Token超限**: 减少`max_tokens`参数

**解决方案**:
```dart
// 增加HTTP客户端超时
final client = http.Client();
try {
  final request = http.Request('POST', uri)
    ..headers['Connection'] = 'keep-alive';
  
  final response = await client.send(request)
    .timeout(Duration(minutes: 5));
  
  // 处理响应...
} finally {
  client.close();
}
```

### 问题 4: 向量检索结果不准确

**症状**: RAG 检索的文档不相关

**优化方案**:
```rust
// 1. 调整分块大小
let chunk_size = 512;  // 尝试 256、512、1024
let overlap = 50;      // 尝试 25、50、100

// 2. 调整检索数量
let top_k = 5;  // 尝试 3、5、10

// 3. 调整相似度阈值
let threshold = 0.7;  // 只返回相似度 > 0.7 的结果
let filtered = results.into_iter()
  .filter(|r| r.score > threshold)
  .collect();

// 4. 使用更好的嵌入模型
// llama3.1:latest -> nomic-embed-text:latest
```

### 问题 5: FFI 调用失败

**症状**: `FlowyError::Internal` 或 Panic

**调试步骤**:
```bash
# 1. 启用 Rust 日志
export RUST_LOG=debug
export RUST_BACKTRACE=1

# 2. 运行 Flutter
flutter run

# 3. 查看详细日志
# 日志会显示 Rust panic 的堆栈跟踪

# 4. 常见原因:
#    - 空指针
#    - Arc/Weak 指针失效
#    - SQLite 连接关闭
#    - FFI 参数类型不匹配
```

### 常用调试命令

```bash
# Flutter 调试
flutter run --verbose
flutter logs

# Rust 日志
RUST_LOG=debug cargo build
RUST_BACKTRACE=full cargo test

# Ollama 调试
ollama ps              # 查看运行的模型
ollama show llama3.1   # 查看模型详情
ollama logs            # 查看服务日志

# 数据库调试
sqlite3 ~/.appflowy/data.db
sqlite> .tables
sqlite> SELECT * FROM chat_message LIMIT 5;
```

---

## 性能优化建议

### 1. 降低首字延迟

```dart
// Flutter: 预连接
await StandaloneAiService.instance.sendMessage(
  message: "",  // 空消息，仅预热连接
  provider: AIProvider.deepseek,
  onResponse: (_) {},
  onError: (_) {},
);
```

### 2. 减少 Token 使用

```dart
// 设置合理的 max_tokens
final config = AIConfig(
  maxTokens: 2048,  // 而不是 4096
  temperature: 0.7,
);
```

### 3. 优化向量检索

```rust
// 减少检索数量
let top_k = 3;  // 而不是 10

// 使用更高的相似度阈值
let threshold = 0.8;  // 而不是 0.5
```

### 4. 缓存常用数据

```dart
// 缓存 Prompts
final _promptCache = <String, AiPrompt>{};

Future<AiPrompt> getPrompt(String id) async {
  if (_promptCache.containsKey(id)) {
    return _promptCache[id]!;
  }
  
  final prompt = await fetchPrompt(id);
  _promptCache[id] = prompt;
  return prompt;
}
```

---

## 有用的资源

### 官方文档

- [AppFlowy 文档](https://docs.appflowy.io/)
- [Ollama 文档](https://ollama.com/docs)
- [DeepSeek API](https://platform.deepseek.com/docs)
- [通义千问 API](https://help.aliyun.com/zh/dashscope/)
- [豆包 API](https://www.volcengine.com/docs/82379)

### 社区资源

- [AppFlowy GitHub](https://github.com/AppFlowy-IO/AppFlowy)
- [Flutter 文档](https://flutter.dev/docs)
- [Rust 文档](https://doc.rust-lang.org/)

### 开发工具

- [Postman](https://www.postman.com/) - API 测试
- [DB Browser for SQLite](https://sqlitebrowser.org/) - 数据库查看
- [Flutter DevTools](https://docs.flutter.dev/tools/devtools) - Flutter 调试

---

**快速链接**:
- [完整功能说明](./AI功能实现详细说明.md)
- [架构与数据流](./AI架构与数据流详解.md)
- [项目 README](../README.md)

**更新日期**: 2025-01-08

