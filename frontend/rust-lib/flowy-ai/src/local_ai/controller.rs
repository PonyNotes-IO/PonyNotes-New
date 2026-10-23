use flowy_ai_pub::cloud::{CompleteTextParams, ResponseFormat, StreamAnswer, StreamComplete};
use flowy_error::{FlowyError, FlowyResult};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalAISetting {
  pub chat_model_name: String,
  pub embedding_model_name: String,
  pub ollama_server_url: String,
  /// 用户自行配置的外部模型服务 API Key（OpenAI 兼容端点）。
  /// 与 MCP Token 相互独立：MCP Token 用于 Agent 访问小马，这里用于小马访问模型服务。
  #[serde(default)]
  pub api_key: String,
}

impl Default for LocalAISetting {
  fn default() -> Self {
    Self {
      chat_model_name: String::new(),
      embedding_model_name: String::new(),
      ollama_server_url: String::new(),
      api_key: String::new(),
    }
  }
}

impl LocalAISetting {
  /// 落盘时使用的文件内容。API Key 不参与任何日志输出。
  fn is_empty(&self) -> bool {
    self.chat_model_name.is_empty()
      && self.embedding_model_name.is_empty()
      && self.ollama_server_url.is_empty()
      && self.api_key.is_empty()
  }
}

/// 本地 AI 设置的文件名，存放在应用数据根目录下。
const LOCAL_AI_SETTING_FILE: &str = "local_ai_setting.json";

/// 本地 AI 设置控制器。
///
/// 原 Ollama 推理能力已被移除，`stream_question` / `complete_text` 等推理接口仍为占位实现。
/// 但设置本身必须真正持久化：内部 AI 要使用用户配置的模型地址、模型名与 API Key，
/// 重启后丢失会让配置界面变成假的。
pub struct LocalAIController {
  /// 应用数据根目录。首次访问时惰性解析，避免在 ServerProvider 构造期依赖用户路径。
  root_dir: Mutex<Option<PathBuf>>,
  /// 内存缓存，避免每次读取都访问磁盘。
  cached: Mutex<LocalAISetting>,
}

impl LocalAIController {
  pub fn new() -> Arc<Self> {
    Arc::new(Self {
      root_dir: Mutex::new(None),
      cached: Mutex::new(LocalAISetting::default()),
    })
  }

  /// 绑定应用数据根目录，并立即加载已保存的设置。
  ///
  /// 由持有 `AIUserService` 的一方在用户上下文就绪后调用。
  pub fn bind_root_dir(&self, root: PathBuf) {
    {
      let mut guard = self.root_dir.lock().unwrap();
      *guard = Some(root);
    }
    if let Ok(setting) = self.load_from_disk() {
      *self.cached.lock().unwrap() = setting;
    }
  }

  fn setting_path(&self) -> Option<PathBuf> {
    let guard = self.root_dir.lock().unwrap();
    guard.as_ref().map(|root| root.join(LOCAL_AI_SETTING_FILE))
  }

  fn load_from_disk(&self) -> FlowyResult<LocalAISetting> {
    let Some(path) = self.setting_path() else {
      return Ok(LocalAISetting::default());
    };
    read_setting_file(&path)
  }

  fn save_to_disk(&self, setting: &LocalAISetting) -> FlowyResult<()> {
    let Some(path) = self.setting_path() else {
      // 未绑定根目录时保持内存态，不报错：早期启动阶段可能还没有用户上下文。
      return Ok(());
    };
    write_setting_file(&path, setting)
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
    self.cached.lock().unwrap().clone()
  }

  pub async fn update_local_ai_setting(&self, setting: LocalAISetting) -> FlowyResult<()> {
    // 先写盘再更新缓存：写失败时内存态保持旧值，避免界面显示「保存成功」但实际没落盘。
    self.save_to_disk(&setting)?;
    *self.cached.lock().unwrap() = setting;
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
    Self {
      root_dir: Mutex::new(None),
      cached: Mutex::new(LocalAISetting::default()),
    }
  }
}

/// 从磁盘读取本地 AI 设置。
///
/// 文件不存在或内容损坏时返回默认值而不是错误：设置文件损坏不应该阻止客户端启动。
fn read_setting_file(path: &Path) -> FlowyResult<LocalAISetting> {
  if !path.exists() {
    return Ok(LocalAISetting::default());
  }
  let content = match fs::read_to_string(path) {
    Ok(content) => content,
    Err(err) => {
      tracing::warn!("read local ai setting failed: {}", err);
      return Ok(LocalAISetting::default());
    },
  };
  match serde_json::from_str::<LocalAISetting>(&content) {
    Ok(setting) => Ok(setting),
    Err(err) => {
      // 不打印文件内容：里面可能有 api_key。
      tracing::warn!("parse local ai setting failed: {}", err);
      Ok(LocalAISetting::default())
    },
  }
}

/// 写入本地 AI 设置。文件权限在 Unix 上收紧为 0600，因为内容含 API Key。
fn write_setting_file(path: &Path, setting: &LocalAISetting) -> FlowyResult<()> {
  if setting.is_empty() {
    // 清空配置时直接删除文件，避免残留旧密钥。
    if path.exists() {
      if let Err(err) = fs::remove_file(path) {
        tracing::warn!("remove local ai setting failed: {}", err);
      }
    }
    return Ok(());
  }

  if let Some(parent) = path.parent() {
    if let Err(err) = fs::create_dir_all(parent) {
      tracing::warn!("create local ai setting dir failed: {}", err);
      return Err(FlowyError::internal().with_context(format!("create dir failed: {}", err)));
    }
  }

  let content = serde_json::to_string_pretty(setting).map_err(|err| {
    FlowyError::internal().with_context(format!("serialize setting failed: {}", err))
  })?;

  if let Err(err) = fs::write(path, content) {
    tracing::warn!("write local ai setting failed: {}", err);
    return Err(FlowyError::internal().with_context(format!("write setting failed: {}", err)));
  }

  #[cfg(unix)]
  {
    use std::os::unix::fs::PermissionsExt;
    if let Err(err) = fs::set_permissions(path, fs::Permissions::from_mode(0o600)) {
      tracing::warn!("chmod local ai setting failed: {}", err);
    }
  }

  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;

  fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("flowy_local_ai_test_{}", name));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
  }

  #[tokio::test]
  async fn update_then_get_round_trips_through_disk() {
    let dir = temp_dir("round_trip");
    let controller = LocalAIController::new();
    controller.bind_root_dir(dir.clone());

    let setting = LocalAISetting {
      chat_model_name: "gpt-4o-mini".to_string(),
      embedding_model_name: "text-embedding-3-small".to_string(),
      ollama_server_url: "https://api.example.com/v1".to_string(),
      api_key: "sk-test-key".to_string(),
    };
    controller
      .update_local_ai_setting(setting.clone())
      .await
      .unwrap();

    // 内存态
    assert_eq!(controller.get_local_ai_setting().api_key, "sk-test-key");

    // 新建实例模拟重启，从磁盘读回
    let restarted = LocalAIController::new();
    restarted.bind_root_dir(dir.clone());
    let loaded = restarted.get_local_ai_setting();
    assert_eq!(loaded.chat_model_name, setting.chat_model_name);
    assert_eq!(loaded.ollama_server_url, setting.ollama_server_url);
    assert_eq!(loaded.api_key, setting.api_key);

    let _ = fs::remove_dir_all(&dir);
  }

  #[tokio::test]
  async fn empty_setting_removes_file() {
    let dir = temp_dir("empty_removes");
    let controller = LocalAIController::new();
    controller.bind_root_dir(dir.clone());

    controller
      .update_local_ai_setting(LocalAISetting {
        chat_model_name: "m".to_string(),
        ..Default::default()
      })
      .await
      .unwrap();
    assert!(dir.join(LOCAL_AI_SETTING_FILE).exists());

    controller
      .update_local_ai_setting(LocalAISetting::default())
      .await
      .unwrap();
    assert!(!dir.join(LOCAL_AI_SETTING_FILE).exists());

    let _ = fs::remove_dir_all(&dir);
  }

  #[test]
  fn missing_file_returns_default() {
    let dir = temp_dir("missing");
    let controller = LocalAIController::new();
    controller.bind_root_dir(dir.clone());
    let setting = controller.get_local_ai_setting();
    assert!(setting.api_key.is_empty());
    let _ = fs::remove_dir_all(&dir);
  }

  #[test]
  fn corrupt_file_returns_default_instead_of_error() {
    let dir = temp_dir("corrupt");
    fs::write(dir.join(LOCAL_AI_SETTING_FILE), "{not json").unwrap();
    let controller = LocalAIController::new();
    controller.bind_root_dir(dir.clone());
    assert!(controller.get_local_ai_setting().api_key.is_empty());
    let _ = fs::remove_dir_all(&dir);
  }

  #[test]
  fn legacy_file_without_api_key_still_deserializes() {
    let dir = temp_dir("legacy");
    let legacy = r#"{"chat_model_name":"m","embedding_model_name":"e","ollama_server_url":"u"}"#;
    fs::write(dir.join(LOCAL_AI_SETTING_FILE), legacy).unwrap();
    let controller = LocalAIController::new();
    controller.bind_root_dir(dir.clone());
    let loaded = controller.get_local_ai_setting();
    assert_eq!(loaded.chat_model_name, "m");
    assert!(loaded.api_key.is_empty());
    let _ = fs::remove_dir_all(&dir);
  }
}
