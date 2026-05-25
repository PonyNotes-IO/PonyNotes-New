use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateCloudData {
  pub id: String,
  pub user_id: i64,
  pub template_id: String,
  pub title: String,
  pub description: String,
  pub category: String,
  pub author: String,
  pub preview_url: String,
  pub featured: bool,
  pub tags: Vec<String>,
  pub download_url: String,
  pub created_at: i64,
  pub updated_at: i64,
  pub sync_version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateSyncRequest {
  pub user_id: i64,
  pub workspace_id: String,
  pub templates: Vec<TemplateCloudData>,
  pub last_sync_timestamp: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateSyncResponse {
  pub templates: Vec<TemplateCloudData>,
  pub sync_timestamp: i64,
  pub has_more: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateSyncStatus {
  pub user_id: i64,
  pub last_sync_timestamp: i64,
  pub pending_changes: bool,
  pub sync_in_progress: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateConflictResolution {
  pub template_id: String,
  pub resolution: ConflictResolution,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConflictResolution {
  UseLocal,
  UseRemote,
  Merge,
}
