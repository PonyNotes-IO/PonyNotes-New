use crate::local_ai::controller::LocalAIController;
use arc_swap::ArcSwapOption;
use flowy_ai_pub::cloud::{AIModel, ChatCloudService};
use flowy_error::{ErrorCode, FlowyError, FlowyResult};
use flowy_sqlite::kv::KVStorePreferences;
use lib_infra::async_trait::async_trait;
use lib_infra::util::timestamp;
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, trace, warn};
use uuid::Uuid;
use serde::Deserialize;

type Model = AIModel;
pub const GLOBAL_ACTIVE_MODEL_KEY: &str = "global_active_model";

/// Manages multiple sources and provides operations for model selection
pub struct ModelSelectionControl {
  sources: Vec<Box<dyn ModelSource>>,
  default_model: Model,
  local_storage: ArcSwapOption<Box<dyn UserModelStorage>>,
  server_storage: ArcSwapOption<Box<dyn UserModelStorage>>,
  unset_sources: RwLock<HashSet<String>>,
}

impl ModelSelectionControl {
  /// Create a new manager with the given storage backends
  pub fn new() -> Self {
    let default_model = Model::default();
    Self {
      sources: Vec::new(),
      default_model,
      local_storage: ArcSwapOption::new(None),
      server_storage: ArcSwapOption::new(None),
      unset_sources: Default::default(),
    }
  }

  /// Replace the local storage backend at runtime
  pub fn set_local_storage(&self, storage: impl UserModelStorage + 'static) {
    self.local_storage.store(Some(Arc::new(Box::new(storage))));
  }

  /// Replace the server storage backend at runtime
  pub fn set_server_storage(&self, storage: impl UserModelStorage + 'static) {
    self.server_storage.store(Some(Arc::new(Box::new(storage))));
  }

  /// Add a new model source at runtime
  pub fn add_source(&mut self, source: Box<dyn ModelSource>) {
    info!("[Model Selection] Adding source: {}", source.source_name());
    // remove existing source with the same name
    self
      .sources
      .retain(|s| s.source_name() != source.source_name());

    self.sources.push(source);
  }

  /// Remove all sources matching the given name
  pub fn remove_local_source(&mut self) {
    info!("[Model Selection] Removing local source");
    self
      .sources
      .retain(|source| source.source_name() != "local");
  }

  /// Asynchronously aggregate models from all sources, or return the default if none found
  pub async fn get_models(&self, workspace_id: &Uuid) -> Vec<Model> {
    let mut models = Vec::new();
    for source in &self.sources {
      let mut list = source.list_chat_models(workspace_id).await;
      models.append(&mut list);
    }
    if models.is_empty() {
      vec![self.default_model.clone()]
    } else {
      models
    }
  }

  /// Fetches all server‐side models and, if specified, a single local model by name.
  ///
  /// First collects models from any source named `"server"`. Then it fetches all local models
  /// (from the `"local"` source) and:
  /// - If `local_model_name` is `Some(name)`, it will append exactly that local model
  ///   if it exists.
  /// - If `local_model_name` is `None`, it will append *all* local models.
  ///
  pub async fn get_models_with_specific_local_model(
    &self,
    workspace_id: &Uuid,
    local_model_name: Option<String>,
  ) -> Vec<Model> {
    let mut models = Vec::new();
    // add server models
    for source in &self.sources {
      if source.source_name() == "server" {
        let mut list = source.list_chat_models(workspace_id).await;
        models.append(&mut list);
      }
    }

    // check input local  model present in local models
    let local_models = self.get_local_models(workspace_id).await;
    match local_model_name {
      Some(name) => {
        local_models.into_iter().for_each(|model| {
          if model.name == name {
            models.push(model);
          }
        });
      },
      None => {
        models.extend(local_models);
      },
    }

    models
  }

  pub async fn get_local_models(&self, workspace_id: &Uuid) -> Vec<Model> {
    for source in &self.sources {
      if source.source_name() == "local" {
        return source.list_chat_models(workspace_id).await;
      }
    }
    vec![]
  }

  pub async fn get_all_unset_sources(&self) -> Vec<String> {
    let unset_sources = self.unset_sources.read().await;
    unset_sources.iter().cloned().collect()
  }

  pub async fn get_global_active_model(&self, workspace_id: &Uuid) -> Model {
    self
      .get_active_model(
        workspace_id,
        &SourceKey::new(GLOBAL_ACTIVE_MODEL_KEY.to_string()),
      )
      .await
  }

  /// Retrieves the active model: first tries local storage, then server storage. Ensures validity in the model list.
  /// If neither storage yields a valid model, falls back to default.
  pub async fn get_active_model(&self, workspace_id: &Uuid, source_key: &SourceKey) -> Model {
    let available = self.get_models(workspace_id).await;
    // Try local storage
    if let Some(storage) = self.local_storage.load_full() {
      trace!("[Model Selection] Checking local storage");
      if let Some(local_model) = storage.get_selected_model(workspace_id, source_key).await {
        trace!("[Model Selection] Found local model: {}", local_model.name);
        if available.iter().any(|m| m.name == local_model.name) {
          return local_model;
        } else {
          trace!(
            "[Model Selection] Local {} not found in available list, available: {:?}",
            local_model.name,
            available.iter().map(|m| &m.name).collect::<Vec<_>>()
          );
        }
      } else {
        self
          .unset_sources
          .write()
          .await
          .insert(source_key.key.clone());
      }
    }

    // use local model if user doesn't set the model for given source
    if self
      .sources
      .iter()
      .any(|source| source.source_name() == "local")
    {
      trace!("[Model Selection] Checking global active model");
      let global_source = SourceKey::new(GLOBAL_ACTIVE_MODEL_KEY.to_string());
      if let Some(storage) = self.local_storage.load_full() {
        if let Some(local_model) = storage
          .get_selected_model(workspace_id, &global_source)
          .await
        {
          trace!(
            "[Model Selection] Found global active model: {}",
            local_model.name
          );
          if available.iter().any(|m| m.name == local_model.name) {
            return local_model;
          }
        }
      }
    }

    // Try server storage
    if let Some(storage) = self.server_storage.load_full() {
      trace!("[Model Selection] Checking server storage");
      if let Some(server_model) = storage.get_selected_model(workspace_id, source_key).await {
        trace!(
          "[Model Selection] Found server model: {}",
          server_model.name
        );
        if available.iter().any(|m| m.name == server_model.name) {
          return server_model;
        } else {
          trace!(
            "[Model Selection] Server {} not found in available list, available: {:?}",
            server_model.name,
            available.iter().map(|m| &m.name).collect::<Vec<_>>()
          );
        }
      }
    }
    // Fallback: default
    info!(
      "[Model Selection] No active model found, using default: {}",
      self.default_model.name
    );
    self.default_model.clone()
  }

  /// Sets the active model in both local and server storage
  pub async fn set_active_model(
    &self,
    workspace_id: &Uuid,
    source_key: &SourceKey,
    model: Model,
  ) -> Result<(), FlowyError> {
    info!(
      "[Model Selection] active model: {} for source: {}",
      model.name, source_key.key
    );
    self.unset_sources.write().await.remove(&source_key.key);

    let available = self.get_models(workspace_id).await;
    
    // 【关键修复】使用名称和 is_local 来匹配模型，而不是使用 contains（因为 desc 字段可能不同）
    // 这样可以避免因为 desc 字段不匹配而拒绝用户选择的模型
    let model_matched = available.iter().any(|m| {
      m.name == model.name && m.is_local == model.is_local
    });
    
    // 【关键修复】当可用模型列表为空或只包含默认模型时，允许设置任何模型
    // 这样可以处理新工作区/新 Chat 的情况，避免因为模型列表未加载而拒绝用户选择的模型
    let is_empty_or_only_default = available.is_empty() 
      || (available.len() == 1 && available.iter().any(|m| m.name == self.default_model.name && m.is_local == self.default_model.is_local));
    
    if model_matched || is_empty_or_only_default {
      // 如果可用列表为空或只包含默认模型，记录警告但不拒绝
      if is_empty_or_only_default && !model_matched {
        warn!(
          "[Model Selection] 可用模型列表为空或只包含默认模型，允许设置模型: {}",
          model.name
        );
      }
      
      // Update local storage
      if let Some(storage) = self.local_storage.load_full() {
        storage
          .set_selected_model(workspace_id, source_key, model.clone())
          .await?;
      }

      // Update server storage
      if let Some(storage) = self.server_storage.load_full() {
        storage
          .set_selected_model(workspace_id, source_key, model)
          .await?;
      }
      Ok(())
    } else {
      Err(
        FlowyError::internal()
          .with_context(format!("Model '{:?}' not found in available list", model)),
      )
    }
  }
}

/// Namespaced key for model selection storage
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SourceKey {
  key: String,
}

impl SourceKey {
  /// Create a new SourceKey
  pub fn new(key: String) -> Self {
    Self { key }
  }

  /// Combine the UUID key with a model's is_local flag and name to produce a storage identifier
  pub fn storage_id(&self) -> String {
    format!("ai_models_{}", self.key)
  }
}

/// A trait that defines an asynchronous source of AI models
#[async_trait]
pub trait ModelSource: Send + Sync {
  /// Identifier for this source (e.g., "local" or "server")
  fn source_name(&self) -> &'static str;

  /// Asynchronously returns a list of available models from this source
  async fn list_chat_models(&self, workspace_id: &Uuid) -> Vec<Model>;
}

pub struct LocalAiSource {
  controller: Arc<LocalAIController>,
}

impl LocalAiSource {
  pub fn new(controller: Arc<LocalAIController>) -> Self {
    Self { controller }
  }
}

#[async_trait]
impl ModelSource for LocalAiSource {
  fn source_name(&self) -> &'static str {
    "local"
  }

  async fn list_chat_models(&self, _workspace_id: &Uuid) -> Vec<Model> {
    // Local AI (Ollama) functionality has been removed
    vec![]
  }
}

/// A server-side AI source (e.g., cloud API)
#[derive(Debug, Default)]
struct ServerModelsCache {
  models: Vec<Model>,
  timestamp: Option<i64>,
}

pub struct ServerAiSource {
  cached_models: Arc<RwLock<ServerModelsCache>>,
  cloud_service: Arc<dyn ChatCloudService>,
}

impl ServerAiSource {
  pub fn new(cloud_service: Arc<dyn ChatCloudService>) -> Self {
    Self {
      cached_models: Arc::new(Default::default()),
      cloud_service,
    }
  }

  async fn update_models_cache(&self, models: &[Model], timestamp: i64) -> FlowyResult<()> {
    match self.cached_models.try_write() {
      Ok(mut cache) => {
        cache.models = models.to_vec();
        cache.timestamp = Some(timestamp);
        Ok(())
      },
      Err(_) => {
        Err(FlowyError::internal().with_context("Failed to acquire write lock for models cache"))
      },
    }
  }
}

#[async_trait]
impl ModelSource for ServerAiSource {
  fn source_name(&self) -> &'static str {
    "server"
  }

  async fn list_chat_models(&self, _workspace_id: &Uuid) -> Vec<Model> {
    let now = timestamp();
    let should_fetch = {
      let cached = self.cached_models.read().await;
      cached.models.is_empty() || cached.timestamp.is_none_or(|ts| now - ts >= 300)
    };
    if !should_fetch {
      return self.cached_models.read().await.models.clone();
    }
    
    // 使用自定义的AI模型接口而不是AppFlowy Cloud的接口
    match Self::fetch_models_from_custom_api().await {
      Ok(models) => {
        info!("[ModelSelect] 从自定义API获取到 {} 个模型", models.len());
        if let Err(e) = self.update_models_cache(&models, now).await {
          error!("Failed to update cache: {}", e);
        }
        models
      },
      Err(err) => {
        error!("Failed to fetch models from custom API: {}", err);
        let cached = self.cached_models.read().await;
        if !cached.models.is_empty() {
          info!("Returning expired cache due to error");
          return cached.models.clone();
        }
        Vec::new()
      },
    }
  }
}

impl ServerAiSource {
  /// 从自定义API获取模型列表
  /// API: https://api.xiaomabiji.com/api/ai/chat/models
  async fn fetch_models_from_custom_api() -> FlowyResult<Vec<AIModel>> {
    use reqwest::Client;
    use serde::Deserialize;
    
    #[derive(Deserialize)]
    struct ModelsResponse {
      data: ModelsData,
    }
    
    #[derive(Deserialize)]
    struct ModelsData {
      models: Vec<ModelInfo>,
    }
    
    #[derive(Deserialize)]
    struct ModelInfo {
      id: String,
      name: String,
      description: String,
      is_default: bool,
    }
    
    let url = "https://api.xiaomabiji.com/api/ai/chat/models";
    info!("[ModelSelect] 准备从自定义API获取模型列表: {}", url);
    
    let client = Client::builder()
      .danger_accept_invalid_certs(true)  // 接受自签名证书
      .user_agent("AppFlowyClient/0.9.9")  // 添加User-Agent
      .timeout(std::time::Duration::from_secs(30))  // 添加超时
      .build()
      .map_err(|e| {
        error!("[ModelSelect] 创建HTTP客户端失败: {}", e);
        FlowyError::new(ErrorCode::Internal, format!("创建HTTP客户端失败: {}", e))
      })?;
    
    info!("[ModelSelect] 开始发送GET请求到: {}", url);
    
    let request = client
      .get(url)
      .header("Content-Type", "application/json");
      
    info!("[ModelSelect] 请求headers构建完成");
    
    let resp = request
      .send()
      .await
      .map_err(|e| {
        error!("[ModelSelect] 请求失败: {}", e);
        error!("[ModelSelect] 错误详情: {:?}", e);
        // 检查是否是连接问题
        if e.is_connect() {
          error!("[ModelSelect] 连接错误 - 可能是网络问题或服务器不可达");
        } else if e.is_timeout() {
          error!("[ModelSelect] 请求超时");
        } else if e.is_request() {
          error!("[ModelSelect] 请求构建错误");
        }
        FlowyError::new(ErrorCode::Internal, format!("HTTP请求失败: {}", e))
      })?;
    
    let status = resp.status();
    let response_url = resp.url().clone();
    info!("[ModelSelect] 收到响应");
    info!("[ModelSelect]   - 状态码: {}", status);
    info!("[ModelSelect]   - 实际请求URL: {}", response_url);
    
    if !resp.status().is_success() {
      let error_text = resp.text().await.unwrap_or_else(|_| "无法读取错误信息".to_string());
      error!("[ModelSelect] 服务器返回错误: {} - {}", status, error_text);
      error!("[ModelSelect] 请求的URL: {}", response_url);
      error!("[ModelSelect] 请求URL长度: {}, 响应URL长度: {}", url.len(), response_url.as_str().len());
      
      // 如果是404错误，提供更详细的诊断信息
      if status == 404 {
        error!("[ModelSelect] 404错误 - 可能的原因:");
        error!("[ModelSelect]   1. Nginx路由配置问题");
        error!("[ModelSelect]   2. 后端服务未正确启动");
        error!("[ModelSelect]   3. 路由注册顺序问题");
        error!("[ModelSelect]   4. URL路径不正确");
      }
      
      return Err(FlowyError::new(
        ErrorCode::Internal,
        format!("服务器返回错误: {} - {}", status, error_text),
      ));
    }
    
    let response: ModelsResponse = resp.json().await.map_err(|e| {
      error!("[ModelSelect] JSON解析失败: {}", e);
      FlowyError::new(ErrorCode::Internal, format!("JSON解析失败: {}", e))
    })?;
    
    let models: Vec<AIModel> = response.data.models
      .into_iter()
      .map(|m| {
        info!("[ModelSelect] 模型: {} ({}), 默认: {}", m.name, m.id, m.is_default);
        AIModel {
          name: m.name,
          is_local: false,
          desc: m.description,
        }
      })
      .collect();
    
    info!("[ModelSelect] 成功获取 {} 个模型", models.len());
    Ok(models)
  }
}

#[async_trait]
pub trait UserModelStorage: Send + Sync {
  async fn get_selected_model(&self, workspace_id: &Uuid, source_key: &SourceKey) -> Option<Model>;
  async fn set_selected_model(
    &self,
    workspace_id: &Uuid,
    source_key: &SourceKey,
    model: Model,
  ) -> Result<(), FlowyError>;
}

pub struct ServerModelStorageImpl(pub Arc<dyn ChatCloudService>);

#[async_trait]
impl UserModelStorage for ServerModelStorageImpl {
  async fn get_selected_model(
    &self,
    workspace_id: &Uuid,
    _source_key: &SourceKey,
  ) -> Option<Model> {
    let name = self
      .0
      .get_workspace_default_model(workspace_id)
      .await
      .ok()?;
    Some(Model::server(name, String::new()))
  }

  async fn set_selected_model(
    &self,
    workspace_id: &Uuid,
    source_key: &SourceKey,
    model: Model,
  ) -> Result<(), FlowyError> {
    if model.is_local {
      // local model does not need to be set
      return Ok(());
    }

    if source_key.key != GLOBAL_ACTIVE_MODEL_KEY {
      return Ok(());
    }

    self
      .0
      .set_workspace_default_model(workspace_id, &model.name)
      .await?;
    Ok(())
  }
}

pub struct LocalModelStorageImpl(pub Arc<KVStorePreferences>);

#[async_trait]
impl UserModelStorage for LocalModelStorageImpl {
  async fn get_selected_model(
    &self,
    _workspace_id: &Uuid,
    source_key: &SourceKey,
  ) -> Option<Model> {
    self.0.get_object::<AIModel>(&source_key.storage_id())
  }

  async fn set_selected_model(
    &self,
    _workspace_id: &Uuid,
    source_key: &SourceKey,
    model: Model,
  ) -> Result<(), FlowyError> {
    self
      .0
      .set_object::<AIModel>(&source_key.storage_id(), &model)?;
    Ok(())
  }
}
