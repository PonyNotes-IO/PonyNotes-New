use crate::entities::{
  ChatMessageErrorPB, ChatMessageListPB, ChatMessagePB, PredefinedFormatPB,
  RepeatedRelatedQuestionPB, StreamMessageParams,
};
use crate::middleware::chat_service_mw::ChatServiceMiddleware;
use crate::notification::{ChatNotification, chat_notification_builder};
use crate::stream_message::{sanitize_ai_error_message, AIFollowUpData, StreamMessage};
use allo_isolate::Isolate;
use flowy_ai_pub::cloud::{
  AIModel, ChatCloudService, ChatMessage, ChatMessageType, MessageCursor, QuestionStreamValue, ResponseFormat,
};
use flowy_ai_pub::persistence::{
  ChatMessageTable, select_answer_where_match_reply_message_id, select_chat_messages,
  upsert_chat_messages, upsert_chat_messages_preserve_images,
};
use lib_infra::util::timestamp;
use flowy_ai_pub::user_service::AIUserService;
use flowy_error::{ErrorCode, FlowyError, FlowyResult};
use flowy_sqlite::DBConnection;
use futures::{SinkExt, StreamExt};
use lib_infra::isolate_stream::IsolateSink;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI64};
use tokio::sync::{Mutex, RwLock};
use tracing::{error, instrument, trace, warn};
use uuid::Uuid;

enum PrevMessageState {
  HasMore,
  NoMore,
  Loading,
}

pub struct Chat {
  chat_id: Uuid,
  uid: i64,
  user_service: Arc<dyn AIUserService>,
  chat_service: Arc<ChatServiceMiddleware>,
  prev_message_state: Arc<RwLock<PrevMessageState>>,
  latest_message_id: Arc<AtomicI64>,
  stop_stream: Arc<AtomicBool>,
  stream_buffer: Arc<Mutex<StringBuffer>>,
}

impl Chat {
  pub fn new(
    uid: i64,
    chat_id: Uuid,
    user_service: Arc<dyn AIUserService>,
    chat_service: Arc<ChatServiceMiddleware>,
  ) -> Chat {
    Chat {
      uid,
      chat_id,
      chat_service,
      user_service,
      prev_message_state: Arc::new(RwLock::new(PrevMessageState::HasMore)),
      latest_message_id: Default::default(),
      stop_stream: Arc::new(AtomicBool::new(false)),
      stream_buffer: Arc::new(Mutex::new(StringBuffer::default())),
    }
  }

  pub fn close(&self) {}

  pub async fn stop_stream_message(&self) {
    self
      .stop_stream
      .store(true, std::sync::atomic::Ordering::SeqCst);
  }

  #[instrument(level = "info", skip_all, err)]
  pub async fn stream_chat_message(
    &self,
    params: &StreamMessageParams,
    preferred_ai_model: AIModel,
  ) -> Result<ChatMessagePB, FlowyError> {
    trace!(
      "[Chat] stream chat message: chat_id={}, message={}, message_type={:?}, format={:?}",
      self.chat_id, params.message, params.message_type, params.format,
    );

    // clear
    self
      .stop_stream
      .store(false, std::sync::atomic::Ordering::SeqCst);
    self.stream_buffer.lock().await.clear();

    let mut question_sink = IsolateSink::new(Isolate::new(params.question_stream_port));
    let answer_stream_buffer = self.stream_buffer.clone();
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;

    // 构建消息 metadata：将图片数据（base64）一并保存到服务端，
    // 以便协作区其他用户加载历史消息时能看到图片。
    let question_metadata = if params.has_images && !params.images.is_empty() {
      Some(serde_json::json!({
        "images": params.images,
        "has_images": true,
      }))
    } else {
      None
    };

    // 尝试创建问题，如果失败且是数据同步禁用错误，则在本地创建
    let question = match self
      .chat_service
      .create_question(
        &workspace_id,
        &self.chat_id,
        &params.message,
        params.message_type.clone(),
        params.prompt_id.clone(),
        question_metadata,
      )
      .await
    {
      Ok(question) => question,
      Err(err) => {
        // 如果是数据同步禁用错误，在本地创建问题记录，然后继续执行流式响应
        if err.code == ErrorCode::DataSyncRequired {
          warn!(
            "[Chat] Data sync disabled, creating question locally: chat_id={}, message={}",
            self.chat_id, params.message
          );
          
          // 生成本地message_id（使用时间戳）
          let message_id = timestamp();
          
          // 创建本地问题记录
          let question = match params.message_type {
            ChatMessageType::System => ChatMessage::new_system(message_id, params.message.clone()),
            ChatMessageType::User => ChatMessage::new_human(message_id, params.message.clone(), None),
          };
          
          // 保存到本地数据库
          let conn = self.user_service.sqlite_connection(uid)?;
          let record = ChatMessageTable::from_message(self.chat_id.to_string(), question.clone(), false);
          upsert_chat_messages(conn, &[record])?;
          
          question
        } else {
          error!("Failed to send question: {}", err);
          return Err(err);
        }
      }
    };

    let _ = question_sink
      .send(StreamMessage::MessageId(question.message_id).to_string())
      .await;

    let mut question_with_images = question.clone();
    if params.has_images && !params.images.is_empty() {
      tracing::info!(
        "[Chat] 将 {} 张图片添加到消息 metadata，message_id={}",
        params.images.len(),
        question_with_images.message_id
      );
      
      let mut metadata = question_with_images.metadata.clone();
      if let Some(obj) = metadata.as_object_mut() {
        obj.insert("images".to_string(), serde_json::json!(params.images));
        obj.insert("has_images".to_string(), serde_json::json!(true));
      } else {
        metadata = serde_json::json!({
          "images": params.images,
          "has_images": true,
        });
      }
      question_with_images.metadata = metadata;
      
      // 【重要】将带图片的消息保存到本地数据库
      // 中间件会从数据库读取消息的 metadata 来获取图片数据
      let conn = self.user_service.sqlite_connection(uid)?;
      let record = ChatMessageTable::from_message(self.chat_id.to_string(), question_with_images.clone(), false);
      tracing::info!(
        "[Chat] 保存带图片的消息到本地数据库，message_id={}, metadata_len={}",
        record.message_id,
        record.metadata.as_ref().map(|m| m.len()).unwrap_or(0)
      );
      upsert_chat_messages(conn, &[record])?;
    }

    // Save message to disk（包含图片 metadata）
    notify_message(&self.chat_id, question_with_images)?;
    let format = params.format.clone().map(Into::into).unwrap_or_default();
    self.stream_response(
      params.answer_stream_port,
      answer_stream_buffer,
      uid,
      workspace_id,
      question.message_id,
      format,
      preferred_ai_model,
      params.enable_thinking,
      params.enable_web_search,
    );

    let question_pb = ChatMessagePB::from(question);
    Ok(question_pb)
  }

  #[instrument(level = "info", skip_all, err)]
  pub async fn stream_regenerate_response(
    &self,
    question_id: i64,
    answer_stream_port: i64,
    format: Option<PredefinedFormatPB>,
    ai_model: AIModel,
  ) -> FlowyResult<()> {
    trace!(
      "[Chat] regenerate and stream chat message: chat_id={}",
      self.chat_id,
    );

    // clear
    self
      .stop_stream
      .store(false, std::sync::atomic::Ordering::SeqCst);
    self.stream_buffer.lock().await.clear();

    let format = format.map(Into::into).unwrap_or_default();
    let answer_stream_buffer = self.stream_buffer.clone();
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;

    self.stream_response(
      answer_stream_port,
      answer_stream_buffer,
      uid,
      workspace_id,
      question_id,
      format,
      ai_model,
      false, // enable_thinking默认为false
      false, // enable_web_search默认为false
    );

    Ok(())
  }

  #[allow(clippy::too_many_arguments)]
  fn stream_response(
    &self,
    answer_stream_port: i64,
    answer_stream_buffer: Arc<Mutex<StringBuffer>>,
    _uid: i64,
    workspace_id: Uuid,
    question_id: i64,
    format: ResponseFormat,
    ai_model: AIModel,
    enable_thinking: bool,
    enable_web_search: bool,
  ) {
    let stop_stream = self.stop_stream.clone();
    let chat_id = self.chat_id;
    let cloud_service = self.chat_service.clone();
    tokio::spawn(async move {
      let mut answer_sink = IsolateSink::new(Isolate::new(answer_stream_port));
      match cloud_service
        .stream_answer_with_thinking(&workspace_id, &chat_id, question_id, format, ai_model, enable_thinking, enable_web_search)
        .await
      {
        Ok(mut stream) => {
          while let Some(message) = stream.next().await {
            match message {
              Ok(message) => {
                if stop_stream.load(std::sync::atomic::Ordering::Relaxed) {
                  trace!("[Chat] client stop streaming message");
                  break;
                }
                match message {
                  QuestionStreamValue::Answer { value } => {
                    answer_stream_buffer.lock().await.push_str(&value);
                    if let Err(err) = answer_sink
                      .send(StreamMessage::OnData(value).to_string())
                      .await
                    {
                      error!("Failed to stream answer via IsolateSink: {}", err);
                    }
                  },
                  QuestionStreamValue::Thinking { value } => {
                    // 同时积累到 buffer，流结束后存入 metadata 持久化
                    answer_stream_buffer.lock().await.push_thinking(&value);
                    let _ = answer_sink
                      .send(StreamMessage::OnThinking(value).to_string())
                      .await;
                  },
                  QuestionStreamValue::Metadata { value } => {
                    if let Ok(s) = serde_json::to_string(&value) {
                      answer_stream_buffer.lock().await.set_metadata(value);
                      let _ = answer_sink
                        .send(StreamMessage::Metadata(s).to_string())
                        .await;
                    }
                  },
                  QuestionStreamValue::SuggestedQuestion {
                    context_suggested_questions: _,
                  } => {},
                  QuestionStreamValue::FollowUp {
                    should_generate_related_question,
                  } => {
                    let _ = answer_sink
                      .send(
                        StreamMessage::OnFollowUp(AIFollowUpData {
                          should_generate_related_question,
                        })
                        .to_string(),
                      )
                      .await;
                  },
                }
              },
              Err(err) => {
                if err.code == ErrorCode::RequestTimeout || err.code == ErrorCode::Internal {
                  error!("[Chat] unexpected stream error: {}", err);
                  let _ = answer_sink.send(StreamMessage::Done.to_string()).await;
                  break; // 跳出循环，避免无限重试
                } else {
                  error!("[Chat] failed to stream answer: {}", err);
                  let message = sanitize_ai_error_message(&err.msg);
                  let _ = answer_sink
                    .send(StreamMessage::OnError(message).to_string())
                    .await;
                  let pb = ChatMessageErrorPB {
                    chat_id: chat_id.to_string(),
                    error_message: err.to_string(),
                  };
                  chat_notification_builder(chat_id, ChatNotification::StreamChatMessageError)
                    .payload(pb)
                    .send();
                  return Err(err);
                }
              },
            }
          }
        },
        Err(err) => {
          error!("[Chat] failed to start streaming: {}", err);
          if err.is_ai_response_limit_exceeded() {
            let _ = answer_sink
              .send(StreamMessage::AIResponseLimitExceeded.to_string())
              .await;
          } else if err.is_ai_image_response_limit_exceeded() {
            let _ = answer_sink
              .send(StreamMessage::AIImageResponseLimitExceeded.to_string())
              .await;
          } else if err.is_ai_max_required() {
            let _ = answer_sink
              .send(StreamMessage::AIMaxRequired(err.msg.clone()).to_string())
              .await;
          } else if err.is_limited_by_workspace_plan() {
            // 处理未订阅用户的错误，复用 AIMaxRequired 消息类型显示错误消息
            let _ = answer_sink
              .send(StreamMessage::AIMaxRequired(err.msg.clone()).to_string())
              .await;
          } else if err.is_local_ai_not_ready() {
            let _ = answer_sink
              .send(StreamMessage::LocalAINotReady(err.msg.clone()).to_string())
              .await;
          } else if err.is_local_ai_disabled() {
            let _ = answer_sink
              .send(StreamMessage::LocalAIDisabled(err.msg.clone()).to_string())
              .await;
          } else {
            let message = sanitize_ai_error_message(&err.msg);
            let _ = answer_sink
              .send(StreamMessage::OnError(message).to_string())
              .await;
          }

          let pb = ChatMessageErrorPB {
            chat_id: chat_id.to_string(),
            error_message: err.to_string(),
          };
          chat_notification_builder(chat_id, ChatNotification::StreamChatMessageError)
            .payload(pb)
            .send();
          return Err(err);
        },
      }

      chat_notification_builder(chat_id, ChatNotification::FinishStreaming).send();
      trace!("[Chat] finish streaming");

      if answer_stream_buffer.lock().await.is_empty() {
        return Ok(());
      }
      let content = answer_stream_buffer.lock().await.take_content();
      let mut metadata = answer_stream_buffer.lock().await.take_metadata();
      let thinking_text = answer_stream_buffer.lock().await.take_thinking();
      // 将思考过程写入 metadata，持久化到本地 SQLite
      if !thinking_text.is_empty() {
        let meta = metadata.get_or_insert_with(|| serde_json::json!({}));
        if let Some(obj) = meta.as_object_mut() {
          obj.insert("thinking_text".to_string(), serde_json::Value::String(thinking_text));
        }
      }
      let answer = cloud_service
        .create_answer(
          &workspace_id,
          &chat_id,
          content.trim(),
          question_id,
          metadata,
        )
        .await?;
      notify_message(&chat_id, answer)?;
      Ok::<(), FlowyError>(())
    });
  }

  /// Load chat messages for a given `chat_id`.
  ///
  /// 1. When opening a chat:
  ///    - Loads local chat messages.
  ///    - `after_message_id` and `before_message_id` are `None`.
  ///    - Spawns a task to load messages from the remote server, notifying the user when the remote messages are loaded.
  ///
  /// 2. Loading more messages in an existing chat with `after_message_id`:
  ///    - `after_message_id` is the last message ID in the current chat messages.
  ///
  /// 3. Loading more messages in an existing chat with `before_message_id`:
  ///    - `before_message_id` is the first message ID in the current chat messages.
  pub async fn load_prev_chat_messages(
    &self,
    limit: u64,
    before_message_id: Option<i64>,
  ) -> Result<ChatMessageListPB, FlowyError> {
    trace!(
      "[Chat] Loading messages from disk: chat_id={}, limit={}, before_message_id={:?}",
      self.chat_id, limit, before_message_id
    );

    let offset = before_message_id.map_or(MessageCursor::NextBack, MessageCursor::BeforeMessageId);
    let messages = self.load_local_chat_messages(limit, offset).await?;

    // If the number of messages equals the limit, then no need to load more messages from remote
    if messages.len() == limit as usize {
      let pb = ChatMessageListPB {
        messages,
        has_more: true,
        total: 0,
      };
      chat_notification_builder(self.chat_id, ChatNotification::DidLoadPrevChatMessage)
        .payload(pb.clone())
        .send();
      return Ok(pb);
    }

    if matches!(
      *self.prev_message_state.read().await,
      PrevMessageState::HasMore
    ) {
      *self.prev_message_state.write().await = PrevMessageState::Loading;
      if let Err(err) = self
        .load_remote_chat_messages(limit, before_message_id, None)
        .await
      {
        error!("Failed to load previous chat messages: {}", err);
      }
    }

    Ok(ChatMessageListPB {
      messages,
      has_more: true,
      total: 0,
    })
  }

  pub async fn load_latest_chat_messages(
    &self,
    limit: u64,
    after_message_id: Option<i64>,
  ) -> Result<ChatMessageListPB, FlowyError> {
    trace!(
      "[Chat] Loading new messages: chat_id={}, limit={}, after_message_id={:?}",
      self.chat_id, limit, after_message_id,
    );
    let offset = after_message_id.map_or(MessageCursor::NextBack, MessageCursor::AfterMessageId);
    let messages = self.load_local_chat_messages(limit, offset).await?;

    trace!(
      "[Chat] Loaded local chat messages: chat_id={}, messages={}",
      self.chat_id,
      messages.len()
    );

    // If the number of messages equals the limit, then no need to load more messages from remote
    let has_more = !messages.is_empty();
    let _ = self
      .load_remote_chat_messages(limit, None, after_message_id)
      .await;
    Ok(ChatMessageListPB {
      messages,
      has_more,
      total: 0,
    })
  }

  async fn load_remote_chat_messages(
    &self,
    limit: u64,
    before_message_id: Option<i64>,
    after_message_id: Option<i64>,
  ) -> FlowyResult<()> {
    trace!(
      "[Chat] start loading messages from remote: chat_id={}, limit={}, before_message_id={:?}, after_message_id={:?}",
      self.chat_id, limit, before_message_id, after_message_id
    );
    let workspace_id = self.user_service.workspace_id()?;
    let chat_id = self.chat_id;
    let cloud_service = self.chat_service.clone();
    let user_service = self.user_service.clone();
    let uid = self.uid;
    let prev_message_state = self.prev_message_state.clone();
    let latest_message_id = self.latest_message_id.clone();
    tokio::spawn(async move {
      let cursor = match (before_message_id, after_message_id) {
        (Some(bid), _) => MessageCursor::BeforeMessageId(bid),
        (_, Some(aid)) => MessageCursor::AfterMessageId(aid),
        _ => MessageCursor::NextBack,
      };
      match cloud_service
        .get_chat_messages(&workspace_id, &chat_id, cursor.clone(), limit)
        .await
      {
        Ok(resp) => {
          // Save chat messages to local disk
          if let Err(err) = save_chat_message_disk(
            user_service.sqlite_connection(uid)?,
            &chat_id,
            resp.messages.clone(),
            true,
          ) {
            error!("Failed to save chat:{} messages: {}", chat_id, err);
          }

          // Update latest message ID
          if !resp.messages.is_empty() {
            latest_message_id.store(
              resp.messages[0].message_id,
              std::sync::atomic::Ordering::Relaxed,
            );
          }

          let pb = ChatMessageListPB::from(resp);
          trace!(
            "[Chat] Loaded messages from remote: chat_id={}, messages={}, hasMore: {}, cursor:{:?}",
            chat_id,
            pb.messages.len(),
            pb.has_more,
            cursor,
          );
          if matches!(cursor, MessageCursor::BeforeMessageId(_)) {
            if pb.has_more {
              *prev_message_state.write().await = PrevMessageState::HasMore;
            } else {
              *prev_message_state.write().await = PrevMessageState::NoMore;
            }
            chat_notification_builder(chat_id, ChatNotification::DidLoadPrevChatMessage)
              .payload(pb)
              .send();
          } else {
            chat_notification_builder(chat_id, ChatNotification::DidLoadLatestChatMessage)
              .payload(pb)
              .send();
          }
        },
        Err(err) => error!("Failed to load chat messages: {}", err),
      }
      Ok::<(), FlowyError>(())
    });
    Ok(())
  }

  pub async fn get_question_id_from_answer_id(
    &self,
    chat_id: &Uuid,
    answer_message_id: i64,
  ) -> Result<i64, FlowyError> {
    let conn = self.user_service.sqlite_connection(self.uid)?;

    let local_result =
      select_answer_where_match_reply_message_id(conn, &chat_id.to_string(), answer_message_id)?
        .map(|message| message.message_id);

    if let Some(message_id) = local_result {
      return Ok(message_id);
    }

    let workspace_id = self.user_service.workspace_id()?;
    let chat_id = self.chat_id;
    let cloud_service = self.chat_service.clone();

    let question = cloud_service
      .get_question_from_answer_id(&workspace_id, &chat_id, answer_message_id)
      .await?;

    Ok(question.message_id)
  }

  pub async fn get_related_question(
    &self,
    message_id: i64,
    ai_model: AIModel,
  ) -> Result<RepeatedRelatedQuestionPB, FlowyError> {
    let workspace_id = self.user_service.workspace_id()?;
    let resp = self
      .chat_service
      .get_related_message(&workspace_id, &self.chat_id, message_id, ai_model)
      .await?;

    trace!(
      "[Chat] related messages: chat_id={}, message_id={}, messages:{:?}",
      self.chat_id, message_id, resp.items
    );
    Ok(RepeatedRelatedQuestionPB::from(resp))
  }

  #[instrument(level = "debug", skip_all, err)]
  pub async fn generate_answer(&self, question_message_id: i64) -> FlowyResult<ChatMessagePB> {
    trace!(
      "[Chat] generate answer: chat_id={}, question_message_id={}",
      self.chat_id, question_message_id
    );
    let workspace_id = self.user_service.workspace_id()?;
    let answer = self
      .chat_service
      .get_answer(&workspace_id, &self.chat_id, question_message_id)
      .await?;

    notify_message(&self.chat_id, answer.clone())?;
    let pb = ChatMessagePB::from(answer);
    Ok(pb)
  }

  async fn load_local_chat_messages(
    &self,
    limit: u64,
    offset: MessageCursor,
  ) -> Result<Vec<ChatMessagePB>, FlowyError> {
    trace!(
      "[Chat] Loading messages from disk: chat_id={}, limit={}, offset={:?}",
      self.chat_id, limit, offset
    );
    let conn = self.user_service.sqlite_connection(self.uid)?;
    let rows = select_chat_messages(conn, &self.chat_id.to_string(), limit, offset)?.messages;
    let messages = rows
      .into_iter()
      .map(|record| ChatMessagePB {
        message_id: record.message_id,
        content: record.content,
        created_at: record.created_at,
        author_type: record.author_type,
        author_id: record.author_id,
        reply_message_id: record.reply_message_id,
        metadata: record.metadata,
      })
      .collect::<Vec<_>>();

    Ok(messages)
  }

  #[instrument(level = "debug", skip_all, err)]
  pub async fn index_file(&self, file_path: PathBuf) -> FlowyResult<()> {
    if !file_path.exists() {
      return Err(
        FlowyError::record_not_found().with_context(format!("{:?} not exist", file_path)),
      );
    }

    if !file_path.is_file() {
      return Err(
        FlowyError::invalid_data().with_context(format!("{:?} is not a file ", file_path)),
      );
    }

    trace!(
      "[Chat] index file: chat_id={}, file_path={:?}",
      self.chat_id, file_path
    );
    self
      .chat_service
      .embed_file(
        &self.user_service.workspace_id()?,
        &file_path,
        &self.chat_id,
        None,
      )
      .await?;

    trace!(
      "[Chat] created index file record: chat_id={}, file_path={:?}",
      self.chat_id, file_path
    );

    Ok(())
  }
}

fn save_chat_message_disk(
  conn: DBConnection,
  chat_id: &Uuid,
  messages: Vec<ChatMessage>,
  is_sync: bool,
) -> FlowyResult<()> {
  let records = messages
    .into_iter()
    .map(|message| ChatMessageTable {
      message_id: message.message_id,
      chat_id: chat_id.to_string(),
      content: message.content,
      created_at: message.created_at.timestamp(),
      author_type: message.author.author_type as i64,
      author_id: message.author.author_id.to_string(),
      reply_message_id: message.reply_message_id,
      metadata: Some(serde_json::to_string(&message.metadata).unwrap_or_default()),
      is_sync,
    })
    .collect::<Vec<_>>();
  upsert_chat_messages_preserve_images(conn, &records)?;
  Ok(())
}

#[derive(Debug, Default)]
struct StringBuffer {
  content: String,
  metadata: Option<serde_json::Value>,
  thinking_text: String,
}

impl StringBuffer {
  fn clear(&mut self) {
    self.content.clear();
    self.metadata = None;
    self.thinking_text.clear();
  }

  fn push_str(&mut self, value: &str) {
    self.content.push_str(value);
  }

  fn push_thinking(&mut self, value: &str) {
    self.thinking_text.push_str(value);
  }

  fn set_metadata(&mut self, value: serde_json::Value) {
    self.metadata = Some(value);
  }

  fn is_empty(&self) -> bool {
    self.content.is_empty()
  }

  fn take_metadata(&mut self) -> Option<serde_json::Value> {
    self.metadata.take()
  }

  fn take_content(&mut self) -> String {
    std::mem::take(&mut self.content)
  }

  fn take_thinking(&mut self) -> String {
    std::mem::take(&mut self.thinking_text)
  }
}

pub(crate) fn notify_message(chat_id: &Uuid, message: ChatMessage) -> Result<(), FlowyError> {
  trace!("[Chat] save answer: answer={:?}", message);
  let pb = ChatMessagePB::from(message);
  chat_notification_builder(chat_id, ChatNotification::DidReceiveChatMessage)
    .payload(pb)
    .send();

  Ok(())
}
