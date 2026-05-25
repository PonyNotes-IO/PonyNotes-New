use crate::entities::*;
use crate::services::TemplateService;
use crate::sync::TemplateSyncManager;
use crate::cloud_impl::AppFlowyTemplateCloudService;
use flowy_error::{FlowyError, FlowyResult};
use flowy_sqlite::ConnectionPool;
use std::sync::Arc;
use uuid::Uuid;

pub struct TemplateManager {
  service: Arc<TemplateService>,
  sync_manager: Option<TemplateSyncManager>,
}

impl TemplateManager {
  pub fn new(pool: Arc<ConnectionPool>) -> Self {
    Self {
      service: Arc::new(TemplateService::new(pool)),
      sync_manager: None,
    }
  }

  pub fn with_cloud_sync(
    pool: Arc<ConnectionPool>,
    user_id: i64,
    workspace_id: Uuid,
  ) -> Self {
    let service = Arc::new(TemplateService::new(pool));
    let cloud_service = Arc::new(AppFlowyTemplateCloudService::new());
    let sync_manager = TemplateSyncManager::new(
      service.clone(),
      cloud_service,
      user_id,
      workspace_id,
    );

    Self {
      service,
      sync_manager: Some(sync_manager),
    }
  }

  pub async fn initialize(&self) -> FlowyResult<()> {
    self.service.initialize().await
  }

  pub async fn get_my_templates(&self) -> FlowyResult<Vec<TemplateItemPB>> {
    self.service.get_my_templates().await
  }

  pub async fn add_to_my_templates(&self, template: TemplateItemPB) -> FlowyResult<()> {
    // 添加到本地数据库
    self.service.add_to_my_templates(template.clone()).await?;

    // 如果启用了云同步，也添加到云端
    if let Some(sync_manager) = &self.sync_manager {
      if let Err(e) = sync_manager.add_template_to_cloud(template).await {
        tracing::warn!("Failed to sync template to cloud: {}", e);
        // 不返回错误，因为本地保存已经成功
      }
    }

    Ok(())
  }

  pub async fn remove_from_my_templates(&self, template_id: &str) -> FlowyResult<()> {
    // 从本地数据库移除
    self.service.remove_from_my_templates(template_id).await?;

    // 如果启用了云同步，也从云端移除
    if let Some(sync_manager) = &self.sync_manager {
      if let Err(e) = sync_manager.remove_template_from_cloud(template_id).await {
        tracing::warn!("Failed to remove template from cloud: {}", e);
        // 不返回错误，因为本地删除已经成功
      }
    }

    Ok(())
  }

  pub async fn get_all_templates(&self) -> FlowyResult<Vec<TemplateItemPB>> {
    self.service.get_all_templates().await
  }

  pub async fn get_templates_by_category(&self, category: &str) -> FlowyResult<Vec<TemplateItemPB>> {
    self.service.get_templates_by_category(category).await
  }

  pub async fn search_templates(&self, query: &str) -> FlowyResult<Vec<TemplateItemPB>> {
    self.service.search_templates(query).await
  }

  pub async fn get_featured_templates(&self) -> FlowyResult<Vec<TemplateItemPB>> {
    self.service.get_featured_templates().await
  }

  /// 同步到云端
  pub async fn sync_to_cloud(&self) -> FlowyResult<()> {
    if let Some(sync_manager) = &self.sync_manager {
      sync_manager.sync_to_cloud().await
    } else {
      Err(FlowyError::internal().with_context("Cloud sync not enabled"))
    }
  }

  /// 从云端同步
  pub async fn sync_from_cloud(&self) -> FlowyResult<()> {
    if let Some(sync_manager) = &self.sync_manager {
      sync_manager.sync_from_cloud().await
    } else {
      Err(FlowyError::internal().with_context("Cloud sync not enabled"))
    }
  }

  /// 双向同步
  pub async fn bidirectional_sync(&self) -> FlowyResult<()> {
    if let Some(sync_manager) = &self.sync_manager {
      sync_manager.bidirectional_sync().await
    } else {
      Err(FlowyError::internal().with_context("Cloud sync not enabled"))
    }
  }

  /// 检查同步状态
  pub async fn get_sync_status(&self) -> FlowyResult<Option<flowy_template_pub::entities::TemplateSyncStatus>> {
    if let Some(sync_manager) = &self.sync_manager {
      Ok(Some(sync_manager.get_sync_status().await?))
    } else {
      Ok(None)
    }
  }
}
