use crate::entities::*;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// Template cloud service trait for syncing user templates to cloud storage
#[async_trait]
pub trait TemplateCloudService: Send + Sync + 'static {
  /// Sync user templates to cloud
  async fn sync_templates(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    templates: Vec<TemplateCloudData>,
  ) -> Result<TemplateSyncResponse, FlowyError>;

  /// Get user templates from cloud
  async fn get_user_templates(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    last_sync_timestamp: Option<i64>,
  ) -> Result<TemplateSyncResponse, FlowyError>;

  /// Add a single template to cloud
  async fn add_template(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    template: TemplateCloudData,
  ) -> Result<(), FlowyError>;

  /// Update a template in cloud
  async fn update_template(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    template: TemplateCloudData,
  ) -> Result<(), FlowyError>;

  /// Remove a template from cloud
  async fn remove_template(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    template_id: &str,
  ) -> Result<(), FlowyError>;

  /// Get sync status for user
  async fn get_sync_status(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
  ) -> Result<TemplateSyncStatus, FlowyError>;

  /// Resolve conflicts between local and remote templates
  async fn resolve_conflicts(
    &self,
    user_id: i64,
    workspace_id: &Uuid,
    conflicts: Vec<TemplateConflictResolution>,
  ) -> Result<(), FlowyError>;
}
