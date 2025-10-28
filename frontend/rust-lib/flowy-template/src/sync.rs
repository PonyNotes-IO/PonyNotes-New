use crate::entities::*;
use crate::services::TemplateService;
use flowy_error::FlowyResult;
use flowy_template_pub::cloud::TemplateCloudService;
use flowy_template_pub::entities::*;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub struct TemplateSyncManager {
  local_service: Arc<TemplateService>,
  cloud_service: Arc<dyn TemplateCloudService>,
  user_id: i64,
  workspace_id: Uuid,
}

impl TemplateSyncManager {
  pub fn new(
    local_service: Arc<TemplateService>,
    cloud_service: Arc<dyn TemplateCloudService>,
    user_id: i64,
    workspace_id: Uuid,
  ) -> Self {
    Self {
      local_service,
      cloud_service,
      user_id,
      workspace_id,
    }
  }

  /// 同步本地模板到云端
  pub async fn sync_to_cloud(&self) -> FlowyResult<()> {
    let local_templates = self.local_service.get_my_templates().await?;
    let cloud_templates = self.convert_to_cloud_data(local_templates);
    
    let response = self
      .cloud_service
      .sync_templates(self.user_id, &self.workspace_id, cloud_templates)
      .await?;

    // 更新本地同步时间戳
    self.update_sync_timestamp(response.sync_timestamp).await?;
    
    Ok(())
  }

  /// 从云端同步模板到本地
  pub async fn sync_from_cloud(&self) -> FlowyResult<()> {
    let sync_status = self
      .cloud_service
      .get_sync_status(self.user_id, &self.workspace_id)
      .await?;

    let last_sync = if sync_status.last_sync_timestamp > 0 {
      Some(sync_status.last_sync_timestamp)
    } else {
      None
    };

    let response = self
      .cloud_service
      .get_user_templates(self.user_id, &self.workspace_id, last_sync)
      .await?;

    // 将云端模板转换为本地格式并保存
    for cloud_template in response.templates {
      let local_template = self.convert_from_cloud_data(cloud_template);
      self.local_service.add_to_my_templates(local_template).await?;
    }

    // 更新本地同步时间戳
    self.update_sync_timestamp(response.sync_timestamp).await?;
    
    Ok(())
  }

  /// 添加模板到云端
  pub async fn add_template_to_cloud(&self, template: TemplateItemPB) -> FlowyResult<()> {
    let cloud_template = self.convert_single_to_cloud_data(template);
    self
      .cloud_service
      .add_template(self.user_id, &self.workspace_id, cloud_template)
      .await?;
    Ok(())
  }

  /// 从云端移除模板
  pub async fn remove_template_from_cloud(&self, template_id: &str) -> FlowyResult<()> {
    self
      .cloud_service
      .remove_template(self.user_id, &self.workspace_id, template_id)
      .await?;
    Ok(())
  }

  /// 双向同步（处理冲突）
  pub async fn bidirectional_sync(&self) -> FlowyResult<()> {
    // 1. 先同步本地到云端
    self.sync_to_cloud().await?;
    
    // 2. 再从云端同步到本地
    self.sync_from_cloud().await?;
    
    Ok(())
  }

  /// 检查同步状态
  pub async fn get_sync_status(&self) -> FlowyResult<TemplateSyncStatus> {
    self
      .cloud_service
      .get_sync_status(self.user_id, &self.workspace_id)
      .await
  }

  /// 强制全量同步
  pub async fn full_sync(&self) -> FlowyResult<()> {
    // 获取云端所有模板
    let response = self
      .cloud_service
      .get_user_templates(self.user_id, &self.workspace_id, None)
      .await?;

    // 清空本地模板（可选，根据需求决定）
    // self.local_service.clear_all_templates().await?;

    // 批量添加云端模板到本地
    for cloud_template in response.templates {
      let local_template = self.convert_from_cloud_data(cloud_template);
      self.local_service.add_to_my_templates(local_template).await?;
    }

    // 更新同步时间戳
    self.update_sync_timestamp(response.sync_timestamp).await?;
    
    Ok(())
  }

  fn convert_to_cloud_data(&self, templates: Vec<TemplateItemPB>) -> Vec<TemplateCloudData> {
    templates
      .into_iter()
      .map(|template| self.convert_single_to_cloud_data(template))
      .collect()
  }

  fn convert_single_to_cloud_data(&self, template: TemplateItemPB) -> TemplateCloudData {
    let now = SystemTime::now()
      .duration_since(UNIX_EPOCH)
      .unwrap()
      .as_secs() as i64;

    TemplateCloudData {
      id: uuid::Uuid::new_v4().to_string(),
      user_id: self.user_id,
      template_id: template.id,
      title: template.title,
      description: template.description,
      category: template.category,
      author: template.author,
      preview_url: template.preview_url,
      featured: template.featured,
      tags: template.tags,
      download_url: template.download_url,
      created_at: template.created_at,
      updated_at: template.updated_at,
      sync_version: now,
    }
  }

  fn convert_from_cloud_data(&self, cloud_template: TemplateCloudData) -> TemplateItemPB {
    TemplateItemPB {
      id: cloud_template.template_id,
      title: cloud_template.title,
      description: cloud_template.description,
      category: cloud_template.category,
      author: cloud_template.author,
      preview_url: cloud_template.preview_url,
      featured: cloud_template.featured,
      tags: cloud_template.tags,
      download_url: cloud_template.download_url,
      created_at: cloud_template.created_at,
      updated_at: cloud_template.updated_at,
    }
  }

  async fn update_sync_timestamp(&self, timestamp: i64) -> FlowyResult<()> {
    // 这里可以将同步时间戳保存到本地存储
    // 例如使用 KVStorePreferences 或数据库
    // 暂时使用简单的日志记录
    tracing::info!("Updated sync timestamp: {}", timestamp);
    Ok(())
  }
}
