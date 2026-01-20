use crate::local_ai::controller::LocalAIController;
use crate::ai_session_client::stream_ai_session_with_attachments;
use flowy_ai_pub::persistence::{select_message_content, select_message};
use std::collections::HashMap;

use flowy_ai_pub::cloud::{
  AIModel, ChatCloudService, ChatMessage, ChatMessageType, ChatSettings, CompleteTextParams,
  MessageCursor, ModelList, RelatedQuestion, RepeatedChatMessage, RepeatedRelatedQuestion,
  ResponseFormat, StreamAnswer, StreamComplete, UpdateChatParams,
};
use flowy_error::{FlowyError, FlowyResult};
use lib_infra::async_trait::async_trait;

use flowy_ai_pub::user_service::AIUserService;
use flowy_storage_pub::storage::StorageService;
use serde_json::Value;
use std::path::Path;
use std::sync::{Arc, Weak};
use tracing::{error, info, trace, warn};
use uuid::Uuid;

pub struct ChatServiceMiddleware {
  cloud_service: Arc<dyn ChatCloudService>,
  user_service: Arc<dyn AIUserService>,
  local_ai: Arc<LocalAIController>,
  #[allow(dead_code)]
  storage_service: Weak<dyn StorageService>,
}

impl ChatServiceMiddleware {
  pub fn new(
    user_service: Arc<dyn AIUserService>,
    cloud_service: Arc<dyn ChatCloudService>,
    local_ai: Arc<LocalAIController>,
    storage_service: Weak<dyn StorageService>,
  ) -> Self {
    Self {
      user_service,
      cloud_service,
      local_ai,
      storage_service,
    }
  }

  /// 将模型显示名称映射到API所需的模型ID
  /// 根据 https://api.xiaomabiji.com/api/ai/chat/models 返回的模型列表进行映射
  fn map_model_name_to_id(model_name: &str) -> String {
    match model_name {
      "DeepSeek" => "deepseek-chat".to_string(),
      "豆包" => "doubao".to_string(),
      "Auto" => {
        // "Auto"表示自动选择，使用默认模型
        info!("[Middleware] 模型名称为Auto，使用默认模型deepseek-chat");
        "deepseek-chat".to_string()
      },
      // 如果名称不匹配，尝试转换为小写并添加连字符
      _ => {
        // 尝试通过名称推断ID
        let lower_name = model_name.to_lowercase();
        if lower_name == "auto" {
          info!("[Middleware] 模型名称为auto（小写），使用默认模型deepseek-chat");
          "deepseek-chat".to_string()
        } else if lower_name.contains("deepseek") {
          "deepseek-chat".to_string()
        } else if model_name.contains("通义") || lower_name.contains("qwen") {
          // 通义千问模型统一使用qwen3-vl-plus
          "qwen3-vl-plus".to_string()
        } else if model_name.contains("豆包") || lower_name.contains("doubao") {
          "doubao".to_string()
        } else {
          // 如果完全不匹配，使用默认模型而不是返回原始名称
          warn!("[Middleware] 未知的模型名称: {}, 使用默认模型deepseek-chat", model_name);
          "deepseek-chat".to_string()
        }
      }
    }
  }

  fn get_message_content(&self, message_id: i64) -> FlowyResult<String> {
    let uid = self.user_service.user_id()?;
    let conn = self.user_service.sqlite_connection(uid)?;
    let content = select_message_content(conn, message_id)?.ok_or_else(|| {
      FlowyError::record_not_found().with_context(format!("Message not found: {}", message_id))
    })?;
    Ok(content)
  }

  /// 从消息metadata中提取图片和文件附件
  fn get_message_attachments(
    &self,
    message_id: i64,
  ) -> FlowyResult<(Option<Vec<String>>, Option<Vec<serde_json::Value>>)> {
    let uid = self.user_service.user_id()?;
    let conn = self.user_service.sqlite_connection(uid)?;
    
    // 读取完整消息（包含metadata）
    let message = select_message(conn, message_id)?;
    
    if let Some(msg) = message {
      // 解析metadata
      let metadata: serde_json::Value = serde_json::from_str(&msg.metadata.as_ref().unwrap_or(&String::new()))
        .unwrap_or(serde_json::Value::Null);
      
      let mut images = None;
      let mut files = None;
      
      // 提取图片数组
      if let Some(images_array) = metadata.get("images").and_then(|v| v.as_array()) {
        let image_strings: Vec<String> = images_array
          .iter()
          .filter_map(|v| v.as_str().map(|s| s.to_string()))
          .collect();
        if !image_strings.is_empty() {
          info!("[Middleware] 从metadata提取到 {} 张图片", image_strings.len());
          images = Some(image_strings);
        }
      }
      
      // 提取文件数组
      if let Some(files_array) = metadata.get("files").and_then(|v| v.as_array()) {
        if !files_array.is_empty() {
          info!("[Middleware] 从metadata提取到 {} 个文件", files_array.len());
          files = Some(files_array.clone());
        }
      }
      
      Ok((images, files))
    } else {
      // 消息不存在，返回空
      Ok((None, None))
    }
  }
}

#[async_trait]
impl ChatCloudService for ChatServiceMiddleware {
  async fn create_chat(
    &self,
    uid: &i64,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    rag_ids: Vec<Uuid>,
    name: &str,
    metadata: serde_json::Value,
  ) -> Result<(), FlowyError> {
    self
      .cloud_service
      .create_chat(uid, workspace_id, chat_id, rag_ids, name, metadata)
      .await
  }

  async fn create_question(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    message: &str,
    message_type: ChatMessageType,
    prompt_id: Option<String>,
  ) -> Result<ChatMessage, FlowyError> {
    self
      .cloud_service
      .create_question(workspace_id, chat_id, message, message_type, prompt_id)
      .await
  }

  async fn create_answer(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    message: &str,
    question_id: i64,
    metadata: Option<serde_json::Value>,
  ) -> Result<ChatMessage, FlowyError> {
    self
      .cloud_service
      .create_answer(workspace_id, chat_id, message, question_id, metadata)
      .await
  }

  async fn stream_answer(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    question_id: i64,
    format: ResponseFormat,
    ai_model: AIModel,
  ) -> Result<StreamAnswer, FlowyError> {
    // 默认不启用深度思考和全网搜索
    self.stream_answer_with_thinking(workspace_id, chat_id, question_id, format, ai_model, false, false).await
  }

  async fn stream_answer_with_thinking(
    &self,
    _workspace_id: &Uuid,
    chat_id: &Uuid,
    question_id: i64,
    format: ResponseFormat,
    ai_model: AIModel,
    enable_thinking: bool,
    enable_web_search: bool,
  ) -> Result<StreamAnswer, FlowyError> {
    info!("[Middleware] stream_answer_with_thinking use model: {:?}, enable_thinking: {}, enable_web_search: {}", ai_model, enable_thinking, enable_web_search);
    if ai_model.is_local {
      if self.local_ai.is_ready().await {
        let content = self.get_message_content(question_id)?;
        self
          .local_ai
          .stream_question(chat_id, &content, format, &ai_model.name)
          .await
      } else {
        Err(FlowyError::local_ai_not_ready())
      }
    } else {
      // 使用新的 AI 会话接口
      use crate::ai_session_client::{stream_ai_session, AISessionStreamValue};
      use flowy_ai_pub::cloud::QuestionStreamValue;
      use futures_util::StreamExt;

      info!("[Middleware] 使用新的 AI 会话接口");
      
      // 从本地数据库获取问题内容和metadata
      let content = self.get_message_content(question_id)?;
      trace!("[Middleware] 问题内容: {}", content);
      
      // 读取消息metadata，提取图片数据
      let (images, files) = self.get_message_attachments(question_id)?;
      if images.is_some() {
        info!("[Middleware] 检测到图片附件，数量: {}", images.as_ref().unwrap().len());
      }
      if files.is_some() {
        info!("[Middleware] 检测到文件附件，数量: {}", files.as_ref().unwrap().len());
      }
      
      // 获取服务器地址（这里硬编码，后续可以从配置获取）
      let base_url = "https://api.xiaomabiji.com";
      
      // 将模型显示名称映射到API所需的模型ID
      let model_id = Self::map_model_name_to_id(&ai_model.name);
      info!("[Middleware] 模型名称: {}, 映射到ID: {}", ai_model.name, model_id);
      
      // 获取 token
      let token = {
        let uid = self.user_service.user_id()?;
        let mut conn = self.user_service.sqlite_connection(uid)?;
        let token_result = flowy_user_pub::sql::select_user_token(uid, &mut conn);
        match token_result {
          Ok(token_str) => {
            // 打印原始token信息用于调试
            let token_preview = if token_str.len() > 30 {
              format!("{}...", &token_str[..30])
            } else {
              token_str.clone()
            };
            info!("[Middleware] 原始token信息 - 长度: {}, 前30个字符: {}", token_str.len(), token_preview);
            
            // 检查 token 格式：JWT token 应该以 "eyJ" 开头（Base64 编码的 JSON）
            if token_str.starts_with("eyJ") {
              info!("[Middleware] Token 是有效的 JWT 格式，直接使用");
              Some(token_str)
            } else {
              // Token 不是以 "eyJ" 开头，可能是 JSON 格式
              let trimmed = token_str.trim();
              info!("[Middleware] Token 不是 JWT 格式，检查是否为 JSON 格式");
              
              // 如果 token 是 JSON 格式，尝试解析并提取 access_token
              if trimmed.starts_with('{') {
                info!("[Middleware] 检测到 JSON 格式 token，开始解析");
                match serde_json::from_str::<serde_json::Value>(trimmed) {
                  Ok(json) => {
                    info!("[Middleware] JSON 解析成功，查找 access_token 字段");
                    if let Some(access_token) = json.get("access_token").and_then(|v| v.as_str()) {
                      info!("[Middleware] 从 JSON 中提取 access_token 成功，长度: {}", access_token.len());
                      // 验证提取的 token 是否是有效的 JWT
                      if access_token.starts_with("eyJ") {
                        info!("[Middleware] access_token 是有效的 JWT 格式");
                        Some(access_token.to_string())
                      } else {
                        error!("[Middleware] 提取的 access_token 不是有效的 JWT token，前20字符: {}", 
                          if access_token.len() > 20 { &access_token[..20] } else { access_token });
                        None
                      }
                    } else {
                      // 尝试查找其他可能的字段名
                      if let Some(token_val) = json.get("token").and_then(|v| v.as_str()) {
                        info!("[Middleware] 从 JSON 'token' 字段中提取成功，长度: {}", token_val.len());
                        if token_val.starts_with("eyJ") {
                          Some(token_val.to_string())
                        } else {
                          error!("[Middleware] 'token' 字段不是有效的 JWT token");
                          None
                        }
                      } else {
                        error!("[Middleware] JSON 中没有找到 access_token 或 token 字段，可用字段: {:?}", 
                          json.as_object().map(|o| o.keys().collect::<Vec<_>>()));
                        None
                      }
                    }
                  },
                  Err(e) => {
                    error!("[Middleware] JSON 解析失败: {:?}, 原始token前50字符: {}", e, 
                      if trimmed.len() > 50 { &trimmed[..50] } else { trimmed });
                    None
                  }
                }
              } else {
                // 既不是 JWT 也不是 JSON，打印详细信息并尝试直接使用
                error!("[Middleware] Token 格式异常 - 不是JWT(不以eyJ开头)，也不是JSON(不以{{开头)");
                error!("[Middleware] Token 首字符: '{}', ASCII: {}", 
                  trimmed.chars().next().unwrap_or('?'), 
                  trimmed.bytes().next().unwrap_or(0));
                // 尝试直接使用，可能是其他有效格式
                warn!("[Middleware] 尝试直接使用原始 token");
                Some(token_str)
              }
            }
          },
          Err(e) => {
            error!("[Middleware] 获取 token 失败: {:?}", e);
            None
          }
        }
      };
      
      if token.is_none() {
        error!("[Middleware] 无法获取有效的 token，请求将失败");
      }
      
      // 调用新的 AI 会话接口，传递深度思考和全网搜索参数
      info!("[Middleware] 调用 AI 会话接口，enable_thinking: {}, enable_web_search: {}", enable_thinking, enable_web_search);
      
      // 如果有图片或文件附件，使用带附件的版本
      let stream = if images.is_some() || files.is_some() {
        info!("[Middleware] 使用带附件的AI会话接口");
        stream_ai_session_with_attachments(
          base_url,
          &content,
          Some(model_id),
          token,
          enable_thinking,
          enable_web_search,
          images,
          files,
        ).await?
      } else {
        info!("[Middleware] 使用普通AI会话接口");
        stream_ai_session(base_url, &content, Some(model_id), token, enable_thinking, enable_web_search).await?
      };
      
      // 将 AISessionStreamValue 转换为 QuestionStreamValue
      let converted_stream = stream.map(|result| {
        result.map(|value| match value {
          AISessionStreamValue::Answer { value } => QuestionStreamValue::Answer { value },
          AISessionStreamValue::Metadata { value } => QuestionStreamValue::Metadata { value },
        })
      });
      
      Ok(converted_stream.boxed())
    }
  }

  async fn get_answer(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    question_id: i64,
  ) -> Result<ChatMessage, FlowyError> {
    if self.local_ai.is_ready().await {
      let content = self.get_message_content(question_id)?;
      let answer = self.local_ai.ask_question(chat_id, &content).await?;

      let message = self
        .cloud_service
        .create_answer(workspace_id, chat_id, &answer, question_id, None)
        .await?;
      Ok(message)
    } else {
      self
        .cloud_service
        .get_answer(workspace_id, chat_id, question_id)
        .await
    }
  }

  async fn get_chat_messages(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    offset: MessageCursor,
    limit: u64,
  ) -> Result<RepeatedChatMessage, FlowyError> {
    self
      .cloud_service
      .get_chat_messages(workspace_id, chat_id, offset, limit)
      .await
  }

  async fn get_question_from_answer_id(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    answer_message_id: i64,
  ) -> Result<ChatMessage, FlowyError> {
    self
      .cloud_service
      .get_question_from_answer_id(workspace_id, chat_id, answer_message_id)
      .await
  }

  async fn get_related_message(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    message_id: i64,
    ai_model: AIModel,
  ) -> Result<RepeatedRelatedQuestion, FlowyError> {
    if ai_model.is_local {
      if self.local_ai.is_ready().await {
        let questions = self
          .local_ai
          .get_related_question(&ai_model.name, chat_id, message_id)
          .await?;
        trace!("LocalAI related questions: {:?}", questions);
        let items = questions
          .into_iter()
          .map(|content| RelatedQuestion {
            content,
            metadata: None,
          })
          .collect::<Vec<_>>();

        Ok(RepeatedRelatedQuestion { message_id, items })
      } else {
        Ok(RepeatedRelatedQuestion {
          message_id,
          items: vec![],
        })
      }
    } else {
      self
        .cloud_service
        .get_related_message(workspace_id, chat_id, message_id, ai_model)
        .await
    }
  }

  async fn stream_complete(
    &self,
    workspace_id: &Uuid,
    params: CompleteTextParams,
    ai_model: AIModel,
  ) -> Result<StreamComplete, FlowyError> {
    info!("stream_complete use custom model: {:?}", ai_model);
    if ai_model.is_local {
      if self.local_ai.is_ready().await {
        self.local_ai.complete_text(&ai_model.name, params).await
      } else {
        Err(FlowyError::local_ai_not_ready())
      }
    } else {
      self
        .cloud_service
        .stream_complete(workspace_id, params, ai_model)
        .await
    }
  }

  async fn embed_file(
    &self,
    workspace_id: &Uuid,
    file_path: &Path,
    chat_id: &Uuid,
    metadata: Option<HashMap<String, Value>>,
  ) -> Result<(), FlowyError> {
    if self.local_ai.is_ready().await {
      self
        .local_ai
        .embed_file(chat_id, file_path.to_path_buf(), metadata)
        .await?;
      Ok(())
    } else {
      self
        .cloud_service
        .embed_file(workspace_id, file_path, chat_id, metadata)
        .await
    }
  }

  async fn get_chat_settings(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
  ) -> Result<ChatSettings, FlowyError> {
    self
      .cloud_service
      .get_chat_settings(workspace_id, chat_id)
      .await
  }

  async fn update_chat_settings(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    params: UpdateChatParams,
  ) -> Result<(), FlowyError> {
    self
      .cloud_service
      .update_chat_settings(workspace_id, chat_id, params)
      .await
  }

  async fn delete_chat(&self, workspace_id: &Uuid, chat_id: &Uuid) -> Result<(), FlowyError> {
    self.cloud_service.delete_chat(workspace_id, chat_id).await
  }

  async fn get_available_models(&self, workspace_id: &Uuid) -> Result<ModelList, FlowyError> {
    self.cloud_service.get_available_models(workspace_id).await
  }

  async fn get_workspace_default_model(&self, workspace_id: &Uuid) -> Result<String, FlowyError> {
    self
      .cloud_service
      .get_workspace_default_model(workspace_id)
      .await
  }

  async fn set_workspace_default_model(
    &self,
    workspace_id: &Uuid,
    model: &str,
  ) -> Result<(), FlowyError> {
    self
      .cloud_service
      .set_workspace_default_model(workspace_id, model)
      .await
  }
}
