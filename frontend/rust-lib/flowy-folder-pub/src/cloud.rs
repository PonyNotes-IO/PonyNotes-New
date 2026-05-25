use crate::entities::PublishPayload;
pub use anyhow::Error;
use client_api::entity::{
  PublishInfo,
  guest_dto::{
    ListSharedViewResponse, RevokeSharedViewAccessRequest, ShareViewWithGuestRequest,
    SharedViewDetails,
  },
  workspace_dto::PublishInfoView,
};
use collab::entity::EncodedCollab;
use collab_entity::CollabType;
pub use collab_folder::{Folder, FolderData, Workspace};
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// 所有发布的文档列表项（包含发布者和接收者的信息）
#[derive(Debug, Clone)]
pub struct AllPublishedCollabItem {
  pub published_view_id: Uuid,
  pub view_id: Uuid,
  pub workspace_id: Uuid,
  pub name: String,
  pub publish_name: String,
  pub publisher_email: Option<String>,
  pub published_at: chrono::DateTime<chrono::Utc>,
  pub is_received: bool,
  pub is_readonly: bool,
}

/// 获取所有发布的文档列表响应
#[derive(Debug, Clone)]
pub struct ListAllPublishedCollabResponse {
  pub items: Vec<AllPublishedCollabItem>,
}

/// 用户接收的发布文档请求
#[derive(Debug, Clone)]
pub struct ReceivePublishedCollabRequest {
  pub published_view_id: Uuid,
  pub dest_workspace_id: Uuid,
  pub dest_view_id: Uuid,
}

/// 用户接收的发布文档响应
#[derive(Debug, Clone)]
pub struct ReceivePublishedCollabResponse {
  pub view_id: Uuid,
  pub is_readonly: bool,
}

/// [FolderCloudService] represents the cloud service for folder.
#[async_trait]
pub trait FolderCloudService: Send + Sync + 'static {
  async fn get_folder_snapshots(
    &self,
    workspace_id: &str,
    limit: usize,
  ) -> Result<Vec<FolderSnapshot>, FlowyError>;

  async fn get_folder_doc_state(
    &self,
    workspace_id: &Uuid,
    uid: i64,
    collab_type: CollabType,
    object_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError>;

  async fn full_sync_collab_object(
    &self,
    workspace_id: &Uuid,
    params: FullSyncCollabParams,
  ) -> Result<(), FlowyError>;

  async fn batch_create_folder_collab_objects(
    &self,
    workspace_id: &Uuid,
    objects: Vec<FolderCollabParams>,
  ) -> Result<(), FlowyError>;

  fn service_name(&self) -> String;

  async fn publish_view(
    &self,
    workspace_id: &Uuid,
    payload: Vec<PublishPayload>,
  ) -> Result<(), FlowyError>;

  async fn unpublish_views(
    &self,
    workspace_id: &Uuid,
    view_ids: Vec<Uuid>,
  ) -> Result<(), FlowyError>;

  async fn get_publish_info(&self, view_id: &Uuid) -> Result<PublishInfo, FlowyError>;

  async fn set_publish_name(
    &self,
    workspace_id: &Uuid,
    view_id: Uuid,
    new_name: String,
  ) -> Result<(), FlowyError>;

  async fn set_publish_namespace(
    &self,
    workspace_id: &Uuid,
    new_namespace: String,
  ) -> Result<(), FlowyError>;

  async fn list_published_views(
    &self,
    workspace_id: &Uuid,
  ) -> Result<Vec<PublishInfoView>, FlowyError>;

  /// 获取所有发布的笔记列表（不限制 workspace_id）
  /// 用于侧边栏发布菜单显示所有发布的笔记
  async fn list_all_published_views(
    &self,
  ) -> Result<ListAllPublishedCollabResponse, FlowyError>;

  /// 接收发布的文档（复制到自己的工作区）
  /// 发布的文档对接收者默认是只读的，不能协作同步
  async fn receive_published_collab(
    &self,
    request: &ReceivePublishedCollabRequest,
  ) -> Result<ReceivePublishedCollabResponse, FlowyError>;

  async fn get_default_published_view_info(
    &self,
    workspace_id: &Uuid,
  ) -> Result<PublishInfo, FlowyError>;

  async fn set_default_published_view(
    &self,
    workspace_id: &Uuid,
    view_id: uuid::Uuid,
  ) -> Result<(), FlowyError>;

  async fn remove_default_published_view(&self, workspace_id: &Uuid) -> Result<(), FlowyError>;

  async fn get_publish_namespace(&self, workspace_id: &Uuid) -> Result<String, FlowyError>;

  async fn import_zip(&self, file_path: &str) -> Result<(), FlowyError>;

  /// Share a page with a user (member or guest)
  async fn share_page_with_user(
    &self,
    workspace_id: &Uuid,
    params: ShareViewWithGuestRequest,
  ) -> Result<(), FlowyError>;

  /// Revoke access to a page for a user (member or guest)
  async fn revoke_shared_page_access(
    &self,
    workspace_id: &Uuid,
    view_id: &Uuid,
    params: RevokeSharedViewAccessRequest,
  ) -> Result<(), FlowyError>;

  /// Get the shared members/guests of a page
  async fn get_shared_page_details(
    &self,
    workspace_id: &Uuid,
    view_id: &Uuid,
  ) -> Result<SharedViewDetails, FlowyError>;

  /// Get the shared views of a workspace
  async fn get_shared_views(
    &self,
    workspace_id: &Uuid,
  ) -> Result<ListSharedViewResponse, FlowyError>;
}

#[derive(Debug)]
pub struct FolderCollabParams {
  pub object_id: Uuid,
  pub encoded_collab_v1: Vec<u8>,
  pub collab_type: CollabType,
}

#[derive(Debug)]
pub struct FullSyncCollabParams {
  pub object_id: Uuid,
  pub encoded_collab: EncodedCollab,
  pub collab_type: CollabType,
}

pub struct FolderSnapshot {
  pub snapshot_id: i64,
  pub database_id: String,
  pub data: Vec<u8>,
  pub created_at: i64,
}

pub fn gen_workspace_id() -> Uuid {
  uuid::Uuid::new_v4()
}

pub fn gen_view_id() -> Uuid {
  uuid::Uuid::new_v4()
}

#[derive(Debug)]
pub struct WorkspaceRecord {
  pub id: String,
  pub name: String,
  pub created_at: i64,
}
