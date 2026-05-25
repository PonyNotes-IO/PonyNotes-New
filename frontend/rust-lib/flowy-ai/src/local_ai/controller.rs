use flowy_error::{FlowyError, FlowyResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use uuid::Uuid;
use serde_json::Value;
use flowy_ai_pub::cloud::{ResponseFormat, CompleteTextParams, StreamAnswer, StreamComplete};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalAISetting {
  pub chat_model_name: String,
  pub embedding_model_name: String,
  pub ollama_server_url: String,
}

impl Default for LocalAISetting {
  fn default() -> Self {
    Self {
      chat_model_name: String::new(),
      embedding_model_name: String::new(),
      ollama_server_url: String::new(),
    }
  }
}

/// Empty implementation of LocalAIController
/// All Ollama functionality has been removed
pub struct LocalAIController {}

impl LocalAIController {
  pub fn new() -> Arc<Self> {
    Arc::new(Self {})
  }

  pub async fn is_ready(&self) -> bool {
    false
  }

  pub fn is_enabled(&self) -> bool {
    false
  }

  pub fn is_enabled_on_workspace(&self, _workspace_id: &str) -> bool {
    false
  }

  pub async fn reload_ollama_client(&self, _workspace_id: &str) {}

  pub async fn toggle_plugin(&self, _enabled: bool) -> FlowyResult<()> {
    Ok(())
  }

  pub fn get_local_ai_setting(&self) -> LocalAISetting {
    LocalAISetting::default()
  }

  pub async fn update_local_ai_setting(&self, _setting: LocalAISetting) -> FlowyResult<()> {
    Ok(())
  }

  pub fn get_local_chat_model(&self) -> Option<String> {
    None
  }

  pub async fn restart_plugin(&self) {}

  pub async fn toggle_local_ai(&self) -> FlowyResult<bool> {
    Ok(false)
  }

  pub async fn get_local_ai_state(&self) -> crate::entities::LocalAIPB {
    crate::entities::LocalAIPB::default()
  }

  pub async fn open_chat(
    &self,
    _workspace_id: &Uuid,
    _chat_id: &Uuid,
    _model_name: &str,
    _rag_ids: Vec<String>,
    _summary: String,
  ) -> FlowyResult<()> {
    Ok(())
  }

  pub fn close_chat(&self, _chat_id: &Uuid) {}

  pub async fn set_rag_ids(&self, _chat_id: &Uuid, _rag_ids: &[String]) {}

  pub async fn stream_question(
    &self,
    _chat_id: &Uuid,
    _content: &str,
    _format: ResponseFormat,
    _model_name: &str,
  ) -> FlowyResult<StreamAnswer> {
    Err(FlowyError::local_ai_not_ready())
  }

  pub async fn ask_question(&self, _chat_id: &Uuid, _content: &str) -> FlowyResult<String> {
    Err(FlowyError::local_ai_not_ready())
  }

  pub async fn get_related_question(
    &self,
    _model_name: &str,
    _chat_id: &Uuid,
    _message_id: i64,
  ) -> FlowyResult<Vec<String>> {
    Ok(vec![])
  }

  pub async fn complete_text(
    &self,
    _model_name: &str,
    _params: CompleteTextParams,
  ) -> FlowyResult<StreamComplete> {
    Err(FlowyError::local_ai_not_ready())
  }

  pub async fn embed_file(
    &self,
    _chat_id: &Uuid,
    _file_path: PathBuf,
    _metadata: Option<HashMap<String, Value>>,
  ) -> FlowyResult<()> {
    Err(FlowyError::local_ai_not_ready())
  }
}

impl Default for LocalAIController {
  fn default() -> Self {
    Self {}
  }
}

