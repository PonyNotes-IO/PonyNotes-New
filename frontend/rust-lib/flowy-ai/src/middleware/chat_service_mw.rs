use crate::local_ai::controller::LocalAIController;
use flowy_ai_pub::persistence::select_message_content;
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
  /// 根据 http://8.152.101.166/api/ai/chat/models 返回的模型列表进行映射
  fn map_model_name_to_id(model_name: &str) -> String {
    match model_name {
      "DeepSeek" => "deepseek-chat".to_string(),
      "通义千问 Turbo" => "qwen-turbo".to_string(),
      "通义千问 Max" => "qwen-max".to_string(),
      "豆包" => "doubao".to_string(),
      // 如果名称不匹配，尝试转换为小写并添加连字符
      _ => {
        // 尝试通过名称推断ID
        if model_name.to_lowercase().contains("deepseek") {
          "deepseek-chat".to_string()
        } else if model_name.contains("通义") || model_name.to_lowercase().contains("qwen") {
          if model_name.contains("Turbo") || model_name.contains("turbo") {
            "qwen-turbo".to_string()
          } else if model_name.contains("Max") || model_name.contains("max") {
            "qwen-max".to_string()
          } else {
            "qwen-turbo".to_string() // 默认使用turbo
          }
        } else if model_name.contains("豆包") || model_name.to_lowercase().contains("doubao") {
          "doubao".to_string()
        } else {
          // 如果完全不匹配，返回原始名称，让后端使用默认模型
          warn!("[Middleware] 未知的模型名称: {}, 使用默认模型", model_name);
          model_name.to_string()
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
    _workspace_id: &Uuid,
    chat_id: &Uuid,
    question_id: i64,
    format: ResponseFormat,
    ai_model: AIModel,
  ) -> Result<StreamAnswer, FlowyError> {
    info!("[Middleware] stream_answer use model: {:?}", ai_model);
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
      
      // 从本地数据库获取问题内容
      let content = self.get_message_content(question_id)?;
      trace!("[Middleware] 问题内容: {}", content);
      
      // 获取服务器地址（这里硬编码，后续可以从配置获取）
      let base_url = "http://8.152.101.166";
      
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
            // 检查 token 格式：JWT token 应该以 "eyJ" 开头（Base64 编码的 JSON）
            if token_str.starts_with("eyJ") {
              trace!("[Middleware] 获取到 token，长度: {}, 前10个字符: {}", token_str.len(), &token_str[..token_str.len().min(10)]);
              Some(token_str)
            } else {
              error!("[Middleware] Token 格式不正确，不是 JWT token。前20个字符: {}", &token_str[..token_str.len().min(20)]);
              // 如果 token 是 JSON 格式，尝试解析并提取 access_token
              if token_str.trim_start().starts_with('{') {
                info!("[Middleware] 检测到 JSON 格式 token，开始解析，长度: {}", token_str.len());
                match serde_json::from_str::<serde_json::Value>(&token_str) {
                  Ok(json) => {
                    info!("[Middleware] JSON 解析成功");
                    if let Some(access_token) = json.get("access_token").and_then(|v| v.as_str()) {
                      info!("[Middleware] 从 JSON 中提取 access_token 成功，长度: {}", access_token.len());
                      Some(access_token.to_string())
                    } else {
                      error!("[Middleware] JSON 中没有找到 access_token 字段。JSON keys: {:?}", json.as_object().map(|o| o.keys().collect::<Vec<_>>()));
                      None
                    }
                  },
                  Err(e) => {
                    error!("[Middleware] Token 不是有效的 JSON，解析错误: {:?}", e);
                    None
                  }
                }
              } else {
                error!("[Middleware] Token 不是 JSON 格式（不以 {{ 开头），实际开头字符: {:?}", token_str.chars().take(5).collect::<String>());
                None
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
      
      // 调用新的 AI 会话接口
      // TODO: 从view的extra字段或配置中读取深度思考状态
      let enable_thinking = false; // 暂时设为false，后续可以从view的extra字段读取
      let stream = stream_ai_session(base_url, &content, Some(model_id), token, enable_thinking).await?;
      
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
