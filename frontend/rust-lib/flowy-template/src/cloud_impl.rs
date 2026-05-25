use flowy_error::FlowyError;
use flowy_template_pub::cloud::TemplateCloudService;
use flowy_template_pub::entities::*;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// AppFlowy Cloud implementation of TemplateCloudService
pub struct AppFlowyTemplateCloudService {
  // 这里可以添加HTTP客户端或其他云服务相关的依赖
  // 例如: http_client: Arc<dyn HttpClient>,
}

impl AppFlowyTemplateCloudService {
  pub fn new() -> Self {
    Self {}
  }
}

#[async_trait]
impl TemplateCloudService for AppFlowyTemplateCloudService {
  async fn sync_templates(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    templates: Vec<TemplateCloudData>,
  ) -> Result<TemplateSyncResponse, FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    // 这里先返回模拟数据
    tracing::info!(
      "Syncing {} templates for user {} in workspace {}",
      templates.len(),
      user_id,
      workspace_id
    );

    let now = std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .unwrap()
      .as_secs() as i64;

    Ok(TemplateSyncResponse {
      templates,
      sync_timestamp: now,
      has_more: false,
    })
  }

  async fn get_user_templates(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    last_sync_timestamp: Option<i64>,
  ) -> Result<TemplateSyncResponse, FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    tracing::info!(
      "Getting templates for user {} in workspace {} since {:?}",
      user_id,
      workspace_id,
      last_sync_timestamp
    );

    let now = std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .unwrap()
      .as_secs() as i64;

    // 返回空列表，表示没有云端模板
    Ok(TemplateSyncResponse {
      templates: vec![],
      sync_timestamp: now,
      has_more: false,
    })
  }

  async fn add_template(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    template: TemplateCloudData,
  ) -> Result<(), FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    tracing::info!(
      "Adding template {} for user {} in workspace {}",
      template.template_id,
      user_id,
      workspace_id
    );
    Ok(())
  }

  async fn update_template(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    template: TemplateCloudData,
  ) -> Result<(), FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    tracing::info!(
      "Updating template {} for user {} in workspace {}",
      template.template_id,
      user_id,
      workspace_id
    );
    Ok(())
  }

  async fn remove_template(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    template_id: &str,
  ) -> Result<(), FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    tracing::info!(
      "Removing template {} for user {} in workspace {}",
      template_id,
      user_id,
      workspace_id
    );
    Ok(())
  }

  async fn get_sync_status(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
  ) -> Result<TemplateSyncStatus, FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    tracing::info!(
      "Getting sync status for user {} in workspace {}",
      user_id,
      workspace_id
    );

    let now = std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .unwrap()
      .as_secs() as i64;

    Ok(TemplateSyncStatus {
      user_id,
      last_sync_timestamp: now,
      pending_changes: false,
      sync_in_progress: false,
    })
  }

  async fn resolve_conflicts(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    conflicts: Vec<TemplateConflictResolution>,
  ) -> Result<(), FlowyError> {
    // TODO: 实现实际的HTTP API调用到AppFlowy Cloud
    tracing::info!(
      "Resolving {} conflicts for user {} in workspace {}",
      conflicts.len(),
      user_id,
      workspace_id
    );
    Ok(())
  }
}
