# PonyNotes-New AI 功能实现详细说明

## 目录
1. [概述](#概述)
2. [原生 AppFlowy AI 架构](#原生-appflowy-ai-架构)
3. [自定义多模型 AI 扩展](#自定义多模型-ai-扩展)
4. [核心模块详解](#核心模块详解)
5. [数据流与交互](#数据流与交互)
6. [配置与部署](#配置与部署)
7. [关键代码示例](#关键代码示例)

---

## 概述

PonyNotes-New 项目在原生 AppFlowy 的 AI 功能基础上，扩展实现了多 AI 提供商支持，包括：
- **原生支持**: AppFlowy Cloud AI、本地 AI (Ollama)
- **自定义扩展**: DeepSeek、通义千问（阿里云）、豆包（字节跳动）

### 技术栈
- **前端**: Flutter/Dart
- **后端**: Rust (flowy-ai crate)
- **通信**: FFI (Foreign Function Interface)
- **AI 接口**: OpenAI 兼容 API

---

## 原生 AppFlowy AI 架构

### 1. 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter 前端层                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Chat UI     │  │  Prompt UI   │  │  Settings    │  │
│  │  (ai_chat)   │  │  (ai_prompt) │  │  (ai_model)  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                  │           │
│  ┌──────▼─────────────────▼──────────────────▼───────┐  │
│  │       AppFlowyAIService (Dart Service)            │  │
│  │       • streamCompletion()                         │  │
│  │       • getBuiltInPrompts()                        │  │
│  └──────────────────────────┬─────────────────────────┘  │
└─────────────────────────────┼─────────────────────────────┘
                              │ FFI
┌─────────────────────────────▼─────────────────────────────┐
│                      Rust 后端层                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │              AIManager (ai_manager.rs)             │  │
│  │  • 管理 Chat 实例                                   │  │
│  │  • 模型选择控制                                      │  │
│  │  • 本地/云端 AI 切换                                 │  │
│  └────┬──────────────────────┬─────────────────────┬──┘  │
│       │                      │                     │      │
│  ┌────▼────┐  ┌──────────────▼─────────┐  ┌───────▼───┐ │
│  │  Chat   │  │  ChatServiceMiddleware │  │ LocalAI   │ │
│  │  (实例)  │  │  (中间件)               │  │Controller │ │
│  └────┬────┘  └────────┬───────────────┘  └────┬──────┘ │
│       │                │                        │        │
│  ┌────▼────────────────▼───────────────────────▼──────┐ │
│  │              ChatCloudService (Trait)              │ │
│  │  ┌──────────────┐  ┌──────────────────────────┐   │ │
│  │  │ AppFlowyCloud│  │  LocalChatServiceImpl     │   │ │
│  │  │ (云端实现)    │  │  (本地实现 - Ollama)       │   │ │
│  │  └──────────────┘  └──────────────────────────┘   │ │
│  └────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────┘
```

### 2. 核心模块说明

#### 2.1 Flutter 前端模块

**位置**: `frontend/appflowy_flutter/lib/ai/`

**关键文件**:
- `service/appflowy_ai_service.dart` - AI 服务接口实现
- `service/ai_entities.dart` - AI 数据实体
- `service/ai_prompt_input_bloc.dart` - Prompt 输入逻辑
- `service/ai_model_state_notifier.dart` - 模型状态管理
- `widgets/prompt_input/` - Prompt 输入 UI 组件

**主要功能**:
```dart
// 流式完成文本
Future<(String, CompletionStream)?> streamCompletion({
  required String text,
  PredefinedFormat? format,
  required CompletionTypePB completionType,
  required Future<void> Function() onStart,
  required Future<void> Function(String text) processMessage,
  required Future<void> Function() onEnd,
  required void Function(AIError error) onError,
});

// 获取内置 Prompts
Future<List<AiPrompt>> getBuiltInPrompts();
```

**内置 Prompts**:
- 位置: `assets/built_in_prompts.json`
- 包含多种类别: business, coding, academic, writing, other
- 每个 prompt 包含: id, name, category, content, example

#### 2.2 Rust 后端模块

**位置**: `frontend/rust-lib/flowy-ai/src/`

##### AIManager (`ai_manager.rs`)

核心管理器，负责:
- **Chat 实例管理**: 创建、打开、关闭 Chat
- **模型选择**: 管理本地/云端模型切换
- **RAG 文档同步**: 管理检索增强生成的文档
- **本地 AI 集成**: 与 LocalAIController 协作

核心方法:
```rust
// 流式发送聊天消息
pub async fn stream_chat_message(
  &self,
  params: StreamMessageParams,
) -> Result<ChatMessagePB, FlowyError>

// 更新选择的模型
pub async fn update_selected_model(
  &self, 
  source: String, 
  model: AIModel
) -> FlowyResult<()>

// 切换本地 AI
pub async fn toggle_local_ai(&self) -> FlowyResult<()>
```

##### Chat (`chat.rs`)

单个聊天会话实例:
- **消息管理**: 创建问题、流式获取答案
- **历史记录**: 加载本地/远程聊天记录
- **文件索引**: 支持文档嵌入向量化

核心流程:
```rust
pub async fn stream_chat_message(
  &self,
  params: &StreamMessageParams,
  preferred_ai_model: AIModel,
) -> Result<ChatMessagePB, FlowyError> {
  // 1. 创建问题消息
  let question = self.chat_service
    .create_question(workspace_id, chat_id, message, message_type)
    .await?;
  
  // 2. 流式获取答案
  self.stream_response(
    answer_stream_port,
    uid,
    workspace_id,
    question.message_id,
    format,
    preferred_ai_model,
  );
  
  Ok(question_pb)
}
```

##### LocalAIController (`local_ai/controller.rs`)

本地 AI 控制器，集成 Ollama:
- **Ollama 客户端管理**: 连接本地 Ollama 服务
- **模型管理**: 获取本地可用模型列表
- **向量存储**: SQLite 向量数据库集成
- **聊天控制**: LLM 聊天会话管理

配置结构:
```rust
pub struct LocalAISetting {
  pub ollama_server_url: String,        // 默认: http://localhost:11434
  pub chat_model_name: String,          // 默认: llama3.1:latest
  pub embedding_model_name: String,     // 默认: nomic-embed-text:latest
}
```

##### Completion (`completion.rs`)

文本完成功能:
- **多种完成类型**: 改进写作、拼写检查、总结、扩写等
- **自定义 Prompt**: 支持用户自定义提示词
- **流式响应**: 实时返回生成结果

完成类型:
```rust
pub enum CompletionTypePB {
  ImproveWriting,      // 改进写作
  SpellingAndGrammar,  // 拼写和语法检查
  MakeShorter,         // 缩短
  MakeLonger,          // 扩展
  ContinueWriting,     // 继续写作
  ExplainSelected,     // 解释选中内容
  UserQuestion,        // 用户问题
  CustomPrompt,        // 自定义提示词
}
```

##### Embeddings (`embeddings/`)

向量嵌入模块:
- **文档索引**: 将文档转换为向量并存储
- **检索增强**: RAG (Retrieval Augmented Generation)
- **向量存储**: `SqliteVectorStore` 基于 SQLite 的向量数据库
- **调度器**: 后台索引调度

主要组件:
- `document_indexer.rs` - 文档索引器
- `embedder.rs` - 嵌入生成器
- `store.rs` - 向量存储
- `scheduler.rs` - 调度器

#### 2.3 ChatServiceMiddleware

中间件层，位于 `middleware/chat_service_mw.rs`:
- **服务路由**: 根据配置选择云端或本地 AI
- **存储集成**: 集成文件存储服务
- **用户服务**: 集成用户认证信息

功能:
```rust
pub struct ChatServiceMiddleware {
  user_service: Arc<dyn AIUserService>,
  cloud_service: Arc<dyn ChatCloudService>,
  local_ai: Arc<LocalAIController>,
  storage_service: Weak<dyn StorageService>,
}
```

---

## 自定义多模型 AI 扩展

### 1. 设计理念

在原生 AppFlowy AI 之外，PonyNotes-New 新增了独立的 AI 聊天功能，支持多个第三方 AI 提供商。这是一个**独立模块**，不与原生 AI 功能耦合。

### 2. 架构设计

```
┌────────────────────────────────────────────────────────┐
│              Flutter UI Layer                          │
│  ┌──────────────────────────────────────────────────┐ │
│  │  StandaloneAiChatPage (独立AI聊天页面)            │ │
│  │  • 支持多模态输入（文本+图片）                      │ │
│  │  • 实时流式响应显示                                 │ │
│  │  • AI提供商切换                                     │ │
│  └────────────────┬─────────────────────────────────┘ │
│                   │                                     │
│  ┌────────────────▼─────────────────────────────────┐ │
│  │  StandaloneChatBloc (状态管理)                    │ │
│  │  • 聊天历史管理                                     │ │
│  │  • 消息发送/接收                                    │ │
│  │  • 本地持久化                                       │ │
│  └────────────────┬─────────────────────────────────┘ │
└───────────────────┼──────────────────────────────────┘
                    │
┌───────────────────▼──────────────────────────────────┐
│         AI Configuration & Service Layer              │
│  ┌──────────────────────────────────────────────┐   │
│  │  AIConfigService (配置服务)                    │   │
│  │  • 从 .env.ai 加载配置                         │   │
│  │  • 管理多个 AI 提供商配置                       │   │
│  │  • 提供商切换                                   │   │
│  └────────────────┬─────────────────────────────┘   │
│                   │                                   │
│  ┌────────────────▼─────────────────────────────┐   │
│  │  StandaloneAiService (AI调用服务)             │   │
│  │  • HTTP 流式请求                               │   │
│  │  • 多模态消息构建                               │   │
│  │  • SSE (Server-Sent Events) 解析              │   │
│  └────────┬───────────────┬───────────────┬─────┘   │
└───────────┼───────────────┼───────────────┼─────────┘
            │               │               │
┌───────────▼───┐  ┌────────▼────┐  ┌──────▼──────┐
│  DeepSeek API │  │ 通义千问 API  │  │  豆包 API    │
│  (火山方舟)    │  │ (DashScope)  │  │ (火山方舟)   │
└───────────────┘  └─────────────┘  └─────────────┘
```

### 3. AI 提供商配置

#### 配置文件结构

**位置**: `frontend/appflowy_flutter/.env.ai`

**配置示例**:
```env
# DeepSeek - 通过火山方舟访问
AI_DEEPSEEK_API_KEY=your_deepseek_api_key_here
AI_DEEPSEEK_API_BASE=https://ark.cn-beijing.volces.com/api/v3
AI_DEEPSEEK_MODEL_NAME=deepseek-v3-250324

# 通义千问 - 阿里云DashScope
AI_QWEN_API_KEY=your_qwen_api_key_here
AI_QWEN_API_BASE=https://dashscope.aliyuncs.com/compatible-mode/v1
AI_QWEN_MODEL_NAME=qwen-turbo

# 豆包 - 字节跳动火山方舟
AI_DOUBAO_API_KEY=your_doubao_api_key_here
AI_DOUBAO_API_BASE=https://ark.cn-beijing.volces.com/api/v3
AI_DOUBAO_MODEL_NAME=ep-m-20250814175607-b77g6

# 默认AI模型设置
AI_DEFAULT_MODEL=deepseek

# AI聊天设置
AI_CHAT_MAX_TOKENS=4096
AI_CHAT_TEMPERATURE=0.7
AI_CHAT_STREAM_ENABLED=true
```

#### AIConfigService 实现

**位置**: `frontend/appflowy_flutter/lib/core/config/ai_config.dart`

核心功能:
```dart
class AIConfigService {
  // 单例模式
  static AIConfigService get instance;
  
  // 加载配置
  Future<void> loadConfig();
  
  // 获取当前提供商的配置
  AIConfig getCurrentConfig();
  
  // 切换提供商
  void setProvider(AIProvider provider);
  
  // 获取所有可用提供商
  List<AIProvider> getAvailableProviders();
}
```

支持的提供商:
```dart
enum AIProvider {
  deepseek('deepseek', 'DeepSeek'),
  qwen('qwen', '通义千问'),
  doubao('doubao', '豆包');
}
```

### 4. StandaloneAiService 实现

**位置**: `frontend/appflowy_flutter/lib/plugins/standalone_ai_chat/services/standalone_ai_service.dart`

#### 核心方法

```dart
/// 发送消息到AI服务（支持多模态）
Future<void> sendMessage({
  required String message,
  required AIProvider provider,
  required Function(String) onResponse,
  required Function(String) onError,
  Function()? onComplete,
  List<ChatImage>? images,
});
```

#### API 调用实现

**DeepSeek API**:
```dart
Future<void> _callDeepSeekAPI(
  String message,
  AIConfig config,
  Function(String) onResponse,
  Function(String) onError,
  Function()? onComplete,
  List<ChatImage>? images,
) async {
  final apiUrl = '${config.apiBase}/chat/completions';
  final request = http.Request('POST', Uri.parse(apiUrl));
  
  request.headers.addAll({
    'Authorization': 'Bearer ${config.apiKey}',
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  });
  
  final messageContent = await _buildMessageContent(message, images);
  final requestBody = {
    'model': config.model,
    'messages': [
      {'role': 'user', 'content': messageContent}
    ],
    'stream': true,
  };
  
  request.body = jsonEncode(requestBody);
  final streamedResponse = await client.send(request);
  
  if (streamedResponse.statusCode == 200) {
    await _handleStreamedResponse(
      streamedResponse, 
      onResponse, 
      onError, 
      onComplete
    );
  }
}
```

**通义千问 API**:
- 支持两种模式：
  1. **兼容模式**: 使用 OpenAI 格式（`/compatible-mode/v1`）
  2. **原生模式**: 使用 DashScope 格式

```dart
// 兼容模式请求体
{
  'model': config.model,
  'messages': [
    {'role': 'user', 'content': messageContent}
  ],
  'stream': true,
}

// 原生模式请求体
{
  'model': config.model,
  'input': {
    'messages': [
      {'role': 'user', 'content': messageContent}
    ]
  },
  'parameters': {
    'incremental_output': true,
  },
}
```

**豆包 API**:
```dart
// 与 DeepSeek 类似，使用 OpenAI 兼容格式
final apiUrl = '${config.apiBase}/chat/completions';
final requestBody = {
  'model': config.model,
  'messages': [
    {'role': 'user', 'content': messageContent}
  ],
  'stream': true,
};
```

#### 多模态消息构建

```dart
Future<dynamic> _buildMessageContent(
  String message, 
  List<ChatImage>? images
) async {
  // 无图片 - 返回纯文本
  if (images == null || images.isEmpty) {
    return message;
  }

  // 有图片 - 构建多模态内容
  final List<Map<String, dynamic>> content = [];
  
  // 添加文本
  if (message.trim().isNotEmpty) {
    content.add({
      'type': 'text',
      'text': message,
    });
  }
  
  // 添加图片（base64编码）
  for (final image in images) {
    final base64Data = await imageService.getImageBase64(image);
    if (base64Data != null) {
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': base64Data,  // data:image/jpeg;base64,xxxx
        },
      });
    }
  }
  
  return content;
}
```

#### 流式响应处理

```dart
Future<void> _handleStreamedResponse(
  http.StreamedResponse streamedResponse,
  Function(String) onResponse,
  Function(String) onError,
  Function()? onComplete,
) async {
  String buffer = '';
  
  await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
    buffer += chunk;
    final lines = buffer.split('\n');
    buffer = lines.last;
    
    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        
        // 检查结束标志
        if (data == '[DONE]') {
          onComplete?.call();
          return;
        }
        
        try {
          final json = jsonDecode(data);
          final content = json['choices']?[0]?['delta']?['content'];
          
          if (content != null && content.isNotEmpty) {
            onResponse(content);
          }
          
          // 检查 finish_reason
          final finishReason = json['choices']?[0]?['finish_reason'];
          if (finishReason != null && finishReason != 'null') {
            onComplete?.call();
            return;
          }
        } catch (e) {
          continue;
        }
      }
    }
  }
  
  onComplete?.call();
}
```

### 5. 图片处理服务

**位置**: `frontend/appflowy_flutter/lib/plugins/standalone_ai_chat/services/image_service.dart`

功能:
- 图片选择和加载
- Base64 编码转换
- 图片缓存管理
- 文件系统存储

```dart
class ChatImageService {
  // 选择图片
  Future<List<ChatImage>> pickImages();
  
  // 获取图片的 Base64 编码
  Future<String?> getImageBase64(ChatImage image);
  
  // 清理图片缓存
  Future<void> clearCache();
}
```

### 6. 聊天持久化

**位置**: `frontend/appflowy_flutter/lib/plugins/standalone_ai_chat/application/standalone_chat_persistence.dart`

功能:
- 本地聊天历史存储
- 使用 SQLite 数据库
- 支持多会话管理

---

## 核心模块详解

### 1. 模型选择控制 (Model Selection)

**位置**: `frontend/rust-lib/flowy-ai/src/model_select.rs`

#### 设计理念
- 支持多源模型：本地 AI 和服务器 AI
- 每个 Chat 可以有独立的模型选择
- 全局默认模型设置
- 自动回退机制

#### 核心结构

```rust
pub struct ModelSelectionControl {
  sources: Vec<Box<dyn AISource>>,
  local_storage: Option<Box<dyn ModelStorage>>,
  server_storage: Option<Box<dyn ModelStorage>>,
}

pub trait AISource: Send + Sync {
  async fn get_models(&self, workspace_id: &Uuid) -> Vec<AIModel>;
}

pub trait ModelStorage: Send + Sync {
  async fn get_model(&self, workspace_id: &Uuid, key: &SourceKey) -> Option<AIModel>;
  async fn set_model(&self, workspace_id: &Uuid, key: &SourceKey, model: AIModel) -> Result<()>;
}
```

#### 模型来源

**ServerAiSource** - 服务器模型:
```rust
impl AISource for ServerAiSource {
  async fn get_models(&self, workspace_id: &Uuid) -> Vec<AIModel> {
    // 从 ChatServiceMiddleware 获取可用模型
    self.cloud_service.get_available_models(workspace_id).await
  }
}
```

**LocalAiSource** - 本地模型:
```rust
impl AISource for LocalAiSource {
  async fn get_models(&self, workspace_id: &Uuid) -> Vec<AIModel> {
    // 从 LocalAIController 获取 Ollama 模型
    self.local_ai.get_all_chat_local_models().await
  }
}
```

#### 模型选择逻辑

```rust
pub async fn get_active_model(
  &self,
  workspace_id: &Uuid,
  source_key: &SourceKey,
) -> AIModel {
  // 1. 尝试从存储中获取该 source 的模型
  if let Some(model) = self.get_stored_model(workspace_id, source_key).await {
    return model;
  }
  
  // 2. 如果没有，尝试获取全局默认模型
  if let Some(global_model) = self.get_global_model(workspace_id).await {
    return global_model;
  }
  
  // 3. 回退到默认模型
  AIModel::default()
}
```

### 2. 流式消息处理

#### Rust 侧实现

**位置**: `frontend/rust-lib/flowy-ai/src/chat.rs`

```rust
fn stream_response(
  &self,
  answer_stream_port: i64,  // Dart isolate port
  question_id: i64,
  format: ResponseFormat,
  ai_model: AIModel,
) {
  tokio::spawn(async move {
    let mut answer_sink = IsolateSink::new(Isolate::new(answer_stream_port));
    
    match cloud_service.stream_answer(
      &workspace_id, 
      &chat_id, 
      question_id, 
      format, 
      ai_model
    ).await {
      Ok(mut stream) => {
        while let Some(message) = stream.next().await {
          match message {
            Ok(QuestionStreamValue::Answer { value }) => {
              // 发送数据块到 Dart
              answer_sink.send(
                StreamMessage::OnData(value).to_string()
              ).await;
            },
            Ok(QuestionStreamValue::Metadata { value }) => {
              // 发送元数据
              answer_sink.send(
                StreamMessage::Metadata(json_string).to_string()
              ).await;
            },
            Err(err) => {
              // 错误处理
              answer_sink.send(
                StreamMessage::OnError(err.msg).to_string()
              ).await;
              return Err(err);
            },
          }
        }
      },
      Err(err) => {
        // 启动失败
        if err.is_ai_response_limit_exceeded() {
          answer_sink.send(
            StreamMessage::AIResponseLimitExceeded.to_string()
          ).await;
        } else {
          answer_sink.send(
            StreamMessage::OnError(err.msg).to_string()
          ).await;
        }
      },
    }
    
    // 通知完成
    chat_notification_builder(chat_id, ChatNotification::FinishStreaming).send();
  });
}
```

#### Dart 侧接收

**位置**: `frontend/appflowy_flutter/lib/ai/service/appflowy_ai_service.dart`

```dart
class AppFlowyCompletionStream extends CompletionStream {
  final RawReceivePort _port = RawReceivePort();
  final StreamController<String> _controller = StreamController.broadcast();
  
  int get nativePort => _port.sendPort.nativePort;

  void _startListening() {
    _port.handler = _controller.add;
    _subscription = _controller.stream.listen((event) async {
      await _handleEvent(event);
    });
  }

  Future<void> _handleEvent(String event) async {
    if (event.startsWith(AIStreamEventPrefix.start)) {
      await onStart();
    } else if (event.startsWith(AIStreamEventPrefix.data)) {
      await processMessage(
        event.substring(AIStreamEventPrefix.data.length),
      );
    } else if (event.startsWith(AIStreamEventPrefix.finish)) {
      await onEnd();
    } else if (event.startsWith(AIStreamEventPrefix.error)) {
      processError(AIError(
        message: event.substring(AIStreamEventPrefix.error.length),
        code: AIErrorCode.other,
      ));
    }
  }
}
```

### 3. RAG (检索增强生成)

#### 向量嵌入

**位置**: `frontend/rust-lib/flowy-ai/src/embeddings/`

**文档索引流程**:
```rust
// 1. 文档加载
let document = Document::load_from_file(file_path)?;

// 2. 分块处理
let chunks = document.split_into_chunks(chunk_size, overlap);

// 3. 生成嵌入向量
let embeddings = embedder.embed_chunks(&chunks).await?;

// 4. 存储到向量数据库
vector_store.insert(
  chat_id,
  embeddings,
  metadata,
).await?;
```

**向量存储**:
```rust
pub struct SqliteVectorStore {
  connection: Arc<Mutex<rusqlite::Connection>>,
}

impl SqliteVectorStore {
  // 插入向量
  pub async fn insert(
    &self,
    collection_id: &str,
    vectors: Vec<Vec<f32>>,
    metadata: HashMap<String, Value>,
  ) -> Result<()>;
  
  // 相似度搜索
  pub async fn search(
    &self,
    collection_id: &str,
    query_vector: Vec<f32>,
    top_k: usize,
  ) -> Result<Vec<SearchResult>>;
}
```

#### RAG 检索流程

```rust
// 1. 用户提问
let question = "如何使用 AppFlowy？";

// 2. 生成问题的嵌入向量
let question_embedding = embedder.embed(question).await?;

// 3. 在向量数据库中搜索相关文档
let relevant_docs = vector_store.search(
  chat_id,
  question_embedding,
  top_k: 5,
).await?;

// 4. 构建增强的提示词
let context = relevant_docs.join("\n\n");
let enhanced_prompt = format!(
  "基于以下上下文回答问题：\n{}\n\n问题：{}",
  context,
  question
);

// 5. 发送到 LLM
let answer = llm.complete(enhanced_prompt).await?;
```

---

## 数据流与交互

### 1. 完整的聊天消息流

```
用户输入 "帮我写一篇文章"
    │
    ▼
┌───────────────────────────────┐
│  Flutter UI (Chat Input)       │
│  • 捕获用户输入                 │
│  • 创建 StreamMessageParams    │
└───────────┬───────────────────┘
            │ FFI Call
            ▼
┌───────────────────────────────┐
│  AIManager::stream_chat_message│
│  • 验证用户权限                 │
│  • 获取当前活跃模型             │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  Chat::stream_chat_message     │
│  • 创建 question 消息          │
│  • 保存到本地数据库             │
│  • 通知 UI 显示 question       │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  Chat::stream_response (spawn) │
│  • 异步任务开始                 │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  ChatServiceMiddleware          │
│  • 选择服务 (云端/本地)         │
└───────┬───────────────────────┘
        │
        ├─ 云端 ─────────────────┐
        │                        ▼
        │              ┌──────────────────┐
        │              │ AppFlowy Cloud   │
        │              │ • HTTP POST       │
        │              │ • SSE Stream      │
        │              └─────────┬────────┘
        │                        │
        └─ 本地 ─────────────────┤
                                 ▼
                       ┌──────────────────┐
                       │ LocalAIController │
                       │ • Ollama API      │
                       │ • 本地 LLM        │
                       └─────────┬────────┘
                                 │
        ┌────────────────────────┘
        │ Stream<QuestionStreamValue>
        ▼
┌───────────────────────────────┐
│  Stream Processing             │
│  while let Some(msg) = next()  │
│    • Answer { value }          │
│    • Metadata { value }        │
│    • FollowUp { ... }          │
└───────────┬───────────────────┘
            │ IsolateSink::send()
            ▼
┌───────────────────────────────┐
│  Dart Isolate Port             │
│  • 跨语言通信                   │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  AppFlowyCompletionStream      │
│  • _handleEvent()              │
│  • processMessage()            │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  Flutter UI (Chat Display)     │
│  • 逐字显示 AI 回复            │
│  • 显示加载状态                 │
│  • 保存完整消息                 │
└───────────────────────────────┘
```

### 2. 模型切换流程

```
用户点击 "切换模型" → 选择 "deepseek-chat"
    │
    ▼
┌───────────────────────────────┐
│  Flutter UI (Model Selector)   │
└───────────┬───────────────────┘
            │ FFI Call
            ▼
┌───────────────────────────────┐
│  AIManager::update_selected_model│
│  • source: "chat_id_xxx"       │
│  • model: AIModel {            │
│      name: "deepseek-chat",    │
│      display_name: "..."       │
│    }                           │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  ModelSelectionControl          │
│  • set_active_model()          │
└───────┬───────────────┬───────┘
        │               │
        ▼               ▼
  ┌────────────┐  ┌──────────────┐
  │ LocalStorage│  │ServerStorage │
  │ (KVStore)   │  │(Cloud API)   │
  └────────────┘  └──────────────┘
        │
        ▼
┌───────────────────────────────┐
│  ChatNotification              │
│  • DidUpdateSelectedModel      │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  Flutter UI 更新                │
│  • 显示当前模型                 │
│  • 更新模型图标                 │
└───────────────────────────────┘
```

### 3. 本地 AI 切换流程

```
用户点击 "启用本地 AI"
    │
    ▼
┌───────────────────────────────┐
│  Flutter UI (Settings)         │
└───────────┬───────────────────┘
            │ FFI Call
            ▼
┌───────────────────────────────┐
│  AIManager::toggle_local_ai()  │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  LocalAIController             │
│  • 保存启用状态到 KV Store     │
│  • toggle_plugin(true)         │
└───────────┬───────────────────┘
            │
            ▼
┌───────────────────────────────┐
│  check_local_ai_resources()    │
│  • 检查 Ollama 是否运行        │
│  • 检查模型是否下载             │
│  • 检查系统资源                 │
└───────────┬───────────────────┘
            │
            ├─ 资源充足 ──────────┐
            │                    ▼
            │          ┌──────────────────┐
            │          │ 初始化 Ollama     │
            │          │ • 连接服务器       │
            │          │ • 加载模型         │
            │          │ • 初始化向量DB     │
            │          └─────────┬────────┘
            │                    │
            └─ 资源不足 ─────────┤
                                 │
                                 ▼
                       ┌──────────────────┐
                       │ 发送通知           │
                       │ • UpdateLocalAIState│
                       │ • LocalAIResourceUpdated│
                       └─────────┬────────┘
                                 │
                                 ▼
                       ┌──────────────────┐
                       │ Flutter UI 更新    │
                       │ • 显示状态         │
                       │ • 提示用户         │
                       └──────────────────┘
```

---

## 配置与部署

### 1. 开发环境配置

#### 前端配置

**Flutter 依赖** (`pubspec.yaml`):
```yaml
dependencies:
  flutter:
    sdk: flutter
  appflowy_backend: ^1.0.0
  http: ^1.0.0
  bloc: ^8.1.0
  freezed_annotation: ^2.4.0
  # ... 其他依赖

dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.4.0
```

**AI 配置文件**:
1. 复制模板: `cp ai_config_example.env .env.ai`
2. 编辑 `.env.ai`，填入真实 API 密钥
3. 确保 `.env.ai` 在 `.gitignore` 中

**pubspec.yaml 资源配置**:
```yaml
flutter:
  assets:
    - assets/built_in_prompts.json
    - .env.ai  # 可选，用于打包
```

#### Rust 配置

**Cargo.toml**:
```toml
[workspace]
members = [
  "flowy-ai",
  "flowy-ai-pub",
  # ... 其他 crates
]

[dependencies]
flowy-ai = { path = "../flowy-ai" }
tokio = { version = "1.0", features = ["full"] }
ollama-rs = "0.1"
rusqlite = { version = "0.31", features = ["bundled"] }
# ... 其他依赖
```

#### 本地 AI (Ollama) 配置

1. **安装 Ollama**:
   ```bash
   # macOS
   brew install ollama
   
   # Linux
   curl -fsSL https://ollama.com/install.sh | sh
   ```

2. **启动 Ollama 服务**:
   ```bash
   ollama serve
   ```

3. **下载模型**:
   ```bash
   # 聊天模型
   ollama pull llama3.1:latest
   
   # 嵌入模型
   ollama pull nomic-embed-text:latest
   ```

4. **验证**:
   ```bash
   ollama list
   ```

### 2. 构建与运行

#### 开发环境运行

```bash
# 进入 Flutter 目录
cd frontend/appflowy_flutter

# 安装依赖
flutter pub get

# 运行（桌面）
flutter run -d macos  # macOS
flutter run -d linux  # Linux
flutter run -d windows  # Windows

# 运行（移动端）
flutter run -d ios     # iOS
flutter run -d android # Android
```

#### 生产环境构建

```bash
# macOS
flutter build macos --release

# Linux
flutter build linux --release

# Windows
flutter build windows --release

# iOS
flutter build ios --release

# Android
flutter build apk --release  # APK
flutter build appbundle --release  # AAB
```

### 3. 环境变量

#### Rust 环境变量

```env
# Ollama 配置
OLLAMA_HOST=http://localhost:11434

# 日志级别
RUST_LOG=info,flowy_ai=debug

# 数据库路径
DATABASE_PATH=~/.appflowy/data.db
```

#### Flutter 环境变量

```env
# 开发环境
FLUTTER_ENV=development

# 生产环境
FLUTTER_ENV=production
API_BASE_URL=https://api.appflowy.io
```

---

## 关键代码示例

### 1. 创建并发送聊天消息

**Flutter 侧**:
```dart
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/protobuf.dart';

Future<void> sendChatMessage(String chatId, String message) async {
  // 创建流式消息参数
  final params = StreamMessagePB(
    chatId: chatId,
    message: message,
    messageType: ChatMessageTypePB.User,
    questionStreamPort: Int64(receivePort.sendPort.nativePort),
    answerStreamPort: Int64(answerPort.sendPort.nativePort),
  );
  
  // 调用 Rust FFI
  final result = await AIEventStreamChatMessage(params).send();
  
  result.fold(
    (question) {
      // 成功创建问题消息
      print('Question created: ${question.messageId}');
    },
    (error) {
      // 错误处理
      print('Error: ${error.msg}');
    },
  );
}
```

### 2. 处理流式响应

**Flutter 侧**:
```dart
class ChatMessageStreamHandler {
  final RawReceivePort _port = RawReceivePort();
  final StreamController<String> _controller = StreamController();
  
  String _fullResponse = '';
  
  void startListening(Function(String) onChunk, Function() onComplete) {
    _port.handler = (dynamic message) {
      final String event = message as String;
      
      if (event.startsWith('data:')) {
        final chunk = event.substring(5);
        _fullResponse += chunk;
        onChunk(chunk);
      } else if (event.startsWith('finish:')) {
        onComplete();
        _dispose();
      }
    };
  }
  
  void _dispose() {
    _port.close();
    _controller.close();
  }
}
```

### 3. 切换 AI 模型

**Flutter 侧**:
```dart
Future<void> switchAIModel(String chatId, String modelName) async {
  final model = AIModelPB(
    name: modelName,
    displayName: 'DeepSeek Chat',
    aiType: ModelTypePB.CloudAI,
  );
  
  final payload = UpdateSelectedModelPB(
    source: chatId,
    model: model,
  );
  
  final result = await AIEventUpdateSelectedModel(payload).send();
  
  result.fold(
    (_) => print('Model switched successfully'),
    (error) => print('Failed to switch model: ${error.msg}'),
  );
}
```

### 4. 使用自定义 AI 提供商

**Flutter 侧**:
```dart
import 'package:appflowy/core/config/ai_config.dart';
import 'package:appflowy/plugins/standalone_ai_chat/services/standalone_ai_service.dart';

Future<void> chatWithDeepSeek(String message) async {
  final aiService = StandaloneAiService.instance;
  
  await aiService.sendMessage(
    message: message,
    provider: AIProvider.deepseek,
    onResponse: (String chunk) {
      // 处理每个数据块
      print('Received: $chunk');
    },
    onError: (String error) {
      // 错误处理
      print('Error: $error');
    },
    onComplete: () {
      // 完成回调
      print('Completed');
    },
  );
}
```

### 5. 本地 AI 文档索引

**Rust 侧**:
```rust
use flowy_ai::local_ai::controller::LocalAIController;

async fn index_document(
  local_ai: &LocalAIController,
  chat_id: &Uuid,
  file_path: PathBuf,
) -> Result<()> {
  // 1. 读取文档
  let content = tokio::fs::read_to_string(&file_path).await?;
  
  // 2. 分块
  let chunks = split_text(&content, 512, 50);
  
  // 3. 嵌入并索引
  local_ai.embed_file(chat_id, file_path, None).await?;
  
  Ok(())
}

fn split_text(text: &str, chunk_size: usize, overlap: usize) -> Vec<String> {
  let mut chunks = Vec::new();
  let chars: Vec<char> = text.chars().collect();
  let mut start = 0;
  
  while start < chars.len() {
    let end = (start + chunk_size).min(chars.len());
    let chunk: String = chars[start..end].iter().collect();
    chunks.push(chunk);
    
    if end >= chars.len() {
      break;
    }
    
    start += chunk_size - overlap;
  }
  
  chunks
}
```

### 6. RAG 检索

**Rust 侧**:
```rust
use flowy_ai::embeddings::store::SqliteVectorStore;

async fn retrieve_relevant_docs(
  vector_store: &SqliteVectorStore,
  question: &str,
  chat_id: &str,
  top_k: usize,
) -> Result<Vec<String>> {
  // 1. 生成问题的嵌入向量
  let question_embedding = generate_embedding(question).await?;
  
  // 2. 在向量数据库中搜索
  let results = vector_store.search(
    chat_id,
    question_embedding,
    top_k,
  ).await?;
  
  // 3. 提取文档内容
  let documents = results
    .into_iter()
    .map(|result| result.content)
    .collect();
  
  Ok(documents)
}

async fn generate_embedding(text: &str) -> Result<Vec<f32>> {
  // 调用 Ollama 生成嵌入
  let ollama = Ollama::new("http://localhost:11434");
  let request = GenerateEmbeddingsRequest::new(
    "nomic-embed-text:latest".to_string(),
    EmbeddingsInput::Single(text.to_string()),
  );
  
  let response = ollama.generate_embeddings(request).await?;
  Ok(response.embeddings[0].clone())
}
```

---

## 总结

### 原生 AppFlowy AI 特点

✅ **优势**:
- 完整的企业级架构
- 本地 AI 支持（Ollama）
- RAG 检索增强
- 多模型管理
- 完善的错误处理

⚠️ **限制**:
- 依赖 AppFlowy Cloud（或需要自建）
- 本地 AI 需要安装 Ollama
- 配置相对复杂

### 自定义多模型 AI 扩展特点

✅ **优势**:
- 支持多个国内 AI 提供商
- 配置简单（仅需 API 密钥）
- 无需额外服务依赖
- 多模态支持（文本+图片）
- 流式响应体验好

⚠️ **注意事项**:
- 需要网络连接
- API 调用有费用
- 需要保护 API 密钥安全

### 使用建议

1. **企业用户**: 使用原生 AppFlowy AI + 自建云服务
2. **个人用户**: 使用自定义多模型 AI 扩展
3. **隐私敏感**: 使用本地 AI (Ollama)
4. **混合场景**: 原生 + 自定义并存

---

## 附录

### A. 相关文档

- [AppFlowy 官方文档](https://docs.appflowy.io/)
- [Ollama 文档](https://ollama.com/docs)
- [DeepSeek API 文档](https://platform.deepseek.com/docs)
- [通义千问 API 文档](https://help.aliyun.com/zh/dashscope/)
- [豆包 API 文档](https://www.volcengine.com/docs/82379)

### B. 常见问题

**Q: 如何切换 AI 提供商？**
A: 在设置页面选择不同的 AI 提供商，或通过 `AIConfigService.instance.setProvider()` 编程切换。

**Q: 本地 AI 和云端 AI 如何选择？**
A: 本地 AI 更隐私但需要本地资源；云端 AI 更强大但需要网络和费用。

**Q: 如何处理 API 密钥安全？**
A: 
- 使用 `.env.ai` 文件，确保在 `.gitignore` 中
- 生产环境使用环境变量或密钥管理服务
- 不要在代码中硬编码密钥

**Q: 流式响应卡顿怎么办？**
A: 
- 检查网络连接
- 调整 `temperature` 和 `max_tokens` 参数
- 检查服务器负载

### C. 版本历史

- **v1.0** (2024-11): 初始版本，支持 AppFlowy 原生 AI
- **v1.1** (2024-12): 新增 DeepSeek 支持
- **v1.2** (2025-01): 新增通义千问和豆包支持
- **v1.3** (2025-01): 新增多模态（图片）支持

### D. 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

**文档更新日期**: 2025-01-08
**作者**: PonyNotes 开发团队
**联系方式**: github.com/PonyNotes-IO

