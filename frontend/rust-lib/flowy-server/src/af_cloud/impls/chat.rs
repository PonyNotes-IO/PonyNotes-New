#![allow(unused_variables)]
use crate::af_cloud::AFServer;
use client_api::entity::ai_dto::{
  ChatQuestionQuery, CompleteTextParams, RepeatedRelatedQuestion, ResponseFormat,
};
use client_api::entity::chat_dto::{
  CreateAnswerMessageParams, CreateChatMessageParams, CreateChatParams, MessageCursor,
  RepeatedChatMessage,
};
use flowy_ai_pub::cloud::{
  AFWorkspaceSettingsChange, AIModel, ChatCloudService, ChatMessage, ChatMessageType, ChatSettings,
  ModelList, StreamAnswer, StreamComplete, UpdateChatParams,
};
use flowy_error::FlowyError;
use futures_util::{StreamExt, TryStreamExt};
use lib_infra::async_trait::async_trait;
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;
use tracing::{info, trace};
use uuid::Uuid;

pub(crate) struct CloudChatServiceImpl<T> {
  pub inner: T,
}

#[async_trait]
impl<T> ChatCloudService for CloudChatServiceImpl<T>
where
  T: AFServer,
{
  async fn create_chat(
    &self,
    uid: &i64,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    rag_ids: Vec<Uuid>,
    name: &str,
    metadata: serde_json::Value,
  ) -> Result<(), FlowyError> {
    let chat_id = chat_id.to_string();
    let try_get_client = self.inner.try_get_client();
    let params = CreateChatParams {
      chat_id,
      name: name.to_string(),
      rag_ids,
    };
    try_get_client?
      .create_chat(workspace_id, params)
      .await
      .map_err(FlowyError::from)?;

    Ok(())
  }

  async fn create_question(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    message: &str,
    message_type: ChatMessageType,
    prompt_id: Option<String>,
  ) -> Result<ChatMessage, FlowyError> {
    let chat_id = chat_id.to_string();
    let try_get_client = self.inner.try_get_client();
    let params = CreateChatMessageParams {
      content: message.to_string(),
      message_type,
      prompt_id,
      metadata: None,
    };

    let message = try_get_client?
      .create_question(workspace_id, &chat_id, params)
      .await
      .map_err(FlowyError::from)?;
    Ok(message)
  }

  async fn create_answer(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    message: &str,
    question_id: i64,
    metadata: Option<serde_json::Value>,
  ) -> Result<ChatMessage, FlowyError> {
    let try_get_client = self.inner.try_get_client();
    let params = CreateAnswerMessageParams {
      content: message.to_string(),
      metadata,
      question_message_id: question_id,
    };
    let message = try_get_client?
      .save_answer(workspace_id, chat_id.to_string().as_str(), params)
      .await
      .map_err(FlowyError::from)?;
    Ok(message)
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
    workspace_id: &Uuid,
    chat_id: &Uuid,
    question_id: i64,
    format: ResponseFormat,
    ai_model: AIModel,
    enable_thinking: bool,
    enable_web_search: bool,
  ) -> Result<StreamAnswer, FlowyError> {
    trace!(
      "[客户端] stream_answer_with_thinking: workspace_id={}, chat_id={}, question_id={}, format={:?}, model: {:?}, enable_thinking: {}",
      workspace_id, chat_id, question_id, format, ai_model, enable_thinking,
    );
    let try_get_client = self.inner.try_get_client();
    
    // TODO: 后续需要修改 stream_answer_v3 方法支持 enable_thinking 参数
    // 目前先忽略 enable_thinking 参数，直接调用现有API
    let result = try_get_client?
      .stream_answer_v3(
        workspace_id,
        ChatQuestionQuery {
          chat_id: chat_id.to_string(),
          question_id,
          format,
        },
        Some(ai_model.name),
      )
      .await;

    let stream = result.map_err(FlowyError::from)?.map_err(FlowyError::from);
    Ok(stream.boxed())
  }

  async fn get_answer(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    question_id: i64,
  ) -> Result<ChatMessage, FlowyError> {
    let try_get_client = self.inner.try_get_client();
    let resp = try_get_client?
      .get_answer(workspace_id, chat_id.to_string().as_str(), question_id)
      .await
      .map_err(FlowyError::from)?;
    Ok(resp)
  }

  async fn get_chat_messages(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    offset: MessageCursor,
    limit: u64,
  ) -> Result<RepeatedChatMessage, FlowyError> {
    let try_get_client = self.inner.try_get_client();
    let resp = try_get_client?
      .get_chat_messages(workspace_id, chat_id.to_string().as_str(), offset, limit)
      .await
      .map_err(FlowyError::from)?;

    Ok(resp)
  }

  async fn get_question_from_answer_id(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    answer_message_id: i64,
  ) -> Result<ChatMessage, FlowyError> {
    let try_get_client = self.inner.try_get_client()?;
    let resp = try_get_client
      .get_question_message_from_answer_id(
        workspace_id,
        chat_id.to_string().as_str(),
        answer_message_id,
      )
      .await
      .map_err(FlowyError::from)?
      .ok_or_else(FlowyError::record_not_found)?;

    Ok(resp)
  }

  async fn get_related_message(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    message_id: i64,
    ai_model: AIModel,
  ) -> Result<RepeatedRelatedQuestion, FlowyError> {
    let try_get_client = self.inner.try_get_client();
    let resp = try_get_client?
      .get_chat_related_question(workspace_id, chat_id.to_string().as_str(), message_id)
      .await
      .map_err(FlowyError::from)?;

    Ok(resp)
  }

  async fn stream_complete(
    &self,
    workspace_id: &Uuid,
    params: CompleteTextParams,
    ai_model: AIModel,
  ) -> Result<StreamComplete, FlowyError> {
    use flowy_ai::ai_session_client::stream_ai_session;
    use flowy_ai_pub::cloud::CompletionStreamValue;
    use futures_util::StreamExt;
    
    let client = self.inner.try_get_client()?;
    let base_url = client.base_url();
    // 使用 access_token（JWT），避免将 JSON token 直接传给 AI 会话接口
    let token = client.get_access_token().ok();
    
    // 将 CompleteTextParams 转换为 ChatRequestParams 格式
    let message = params.text;
    let preferred_model = Some(ai_model.name);
    
    info!("[StreamComplete] 使用 /api/ai/chat/session 接口，message_len: {}", message.len());
    
    // 调用 /api/ai/chat/session 接口
    let session_stream = stream_ai_session(
      base_url,
      &message,
      preferred_model,
      token,
      false, // enable_thinking - 文档内问AI暂时不支持深度思考
      false, // enable_web_search - 文档内问AI暂时不支持全网搜索
    ).await?;
    
    // 将 AISessionStreamValue 转换为 CompletionStreamValue
    let converted_stream = session_stream.map(|result| {
      result.map(|value| match value {
        flowy_ai::ai_session_client::AISessionStreamValue::Answer { value } => {
          CompletionStreamValue::Answer { value }
        },
        flowy_ai::ai_session_client::AISessionStreamValue::Metadata { value: _ } => {
          // 忽略metadata，只返回答案
          CompletionStreamValue::Answer { value: String::new() }
        },
      })
    });
    
    Ok(converted_stream.boxed())
  }

  async fn embed_file(
    &self,
    workspace_id: &Uuid,
    file_path: &Path,
    chat_id: &Uuid,
    metadata: Option<HashMap<String, Value>>,
  ) -> Result<(), FlowyError> {
    Err(
      FlowyError::not_support()
        .with_context("indexing file with appflowy cloud is not suppotred yet"),
    )
  }

  async fn get_chat_settings(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
  ) -> Result<ChatSettings, FlowyError> {
    let settings = self
      .inner
      .try_get_client()?
      .get_chat_settings(workspace_id, chat_id.to_string().as_str())
      .await?;
    Ok(settings)
  }

  async fn update_chat_settings(
    &self,
    workspace_id: &Uuid,
    chat_id: &Uuid,
    params: UpdateChatParams,
  ) -> Result<(), FlowyError> {
    self
      .inner
      .try_get_client()?
      .update_chat_settings(workspace_id, chat_id.to_string().as_str(), params)
      .await?;
    Ok(())
  }

  async fn delete_chat(&self, workspace_id: &Uuid, chat_id: &Uuid) -> Result<(), FlowyError> {
    self
      .inner
      .try_get_client()?
      .delete_chat(workspace_id, chat_id.to_string().as_str())
      .await
      .map_err(FlowyError::from)
  }

  async fn get_available_models(&self, workspace_id: &Uuid) -> Result<ModelList, FlowyError> {
    // 方案：由于 client-api 的 ModelInfo/ModelList 定义与我们后端不兼容，
    // 而且 client-api 是官方仓库的版本，我们无法修改，
    // 因此这里直接返回一个硬编码的模型列表，避免调用需要认证的API
    
    tracing::info!("📋 使用本地硬编码的AI模型列表");
    
    // 直接使用原有的 get_model_list 方法（会调用官方API）
    // 如果失败，则降级到本地硬编码列表
    match self.inner.try_get_client()?.get_model_list(workspace_id).await {
      Ok(list) => {
        tracing::info!("✅ 从服务器获取到 {} 个模型", list.models.len());
        Ok(list)
      }
      Err(e) => {
        tracing::warn!("⚠️  从服务器获取模型列表失败: {:?}, 返回错误", e);
        // 直接返回错误，不进行降级处理
        Err(FlowyError::from(e))
      }
    }
  }

  async fn get_workspace_default_model(&self, workspace_id: &Uuid) -> Result<String, FlowyError> {
    let setting = self
      .inner
      .try_get_client()?
      .get_workspace_settings(workspace_id.to_string().as_str())
      .await?;
    Ok(setting.ai_model)
  }

  async fn set_workspace_default_model(
    &self,
    workspace_id: &Uuid,
    model: &str,
  ) -> Result<(), FlowyError> {
    let change = AFWorkspaceSettingsChange::new().ai_model(model.to_string());
    let setting = self
      .inner
      .try_get_client()?
      .update_workspace_settings(workspace_id.to_string().as_str(), &change)
      .await?;
    Ok(())
  }
}
