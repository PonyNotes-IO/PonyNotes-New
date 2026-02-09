use bytes::Bytes;
use collab::entity::EncodedCollab;
use collab_folder::hierarchy_builder::NestedViewBuilder;
use collab_folder::ViewLayout;
use flowy_document::entities::DocumentDataPB;
use flowy_document::manager::DocumentManager;
use flowy_error::FlowyError;
use flowy_folder::entities::{CreateViewParams, ViewLayoutPB};
use flowy_folder::manager::FolderUser;
use flowy_folder::share::ImportType;
use flowy_folder::view_operation::{
  FolderOperationHandler, GatherEncodedCollab, ImportedData, ViewData,
};
use lib_dispatch::prelude::ToBytes;
use lib_infra::async_trait::async_trait;
use std::convert::TryFrom;
use std::sync::{Arc, Weak};
use tokio::sync::RwLock;
use tracing::{error, info};
use uuid::Uuid;

/// Notebook 视图的操作处理器
/// Notebook 是一个容器类型的视图，用于组织和分组其他视图
/// 它的行为类似于 Document，但是：
/// 1. 标题左边的图标不同（笔记本图标 vs 文档图标）
/// 2. 可以包含子视图
/// 3. 可以被打开和显示（显示其包含的子视图列表）
pub struct NotebookFolderOperation(pub Weak<DocumentManager>);

impl NotebookFolderOperation {
  fn document_manager(&self) -> Result<Arc<DocumentManager>, FlowyError> {
    self
      .0
      .upgrade()
      .ok_or_else(|| FlowyError::internal().with_context("DocumentManager is already dropped"))
  }
}

#[async_trait]
impl FolderOperationHandler for NotebookFolderOperation {
  fn name(&self) -> &str {
    "NotebookFolderOperationHandler"
  }

  async fn create_workspace_view(
    &self,
    _uid: i64,
    _workspace_view_builder: Arc<RwLock<NestedViewBuilder>>,
  ) -> Result<(), FlowyError> {
    // Notebook 不需要在工作空间创建时自动创建
    Ok(())
  }

  async fn open_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    info!("[NotebookFolderOperation] Opening notebook view: {}", view_id);
    // Notebook 使用 Document 的底层实现来存储其元数据
    self.document_manager()?.open_document(view_id, None).await?;
    Ok(())
  }

  async fn close_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    info!("[NotebookFolderOperation] Closing notebook view: {}", view_id);
    self.document_manager()?.close_document(view_id).await?;
    Ok(())
  }

  async fn delete_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    info!("[NotebookFolderOperation] Deleting notebook view: {}", view_id);
    match self.document_manager()?.delete_document(view_id).await {
      Ok(_) => {
        info!("[NotebookFolderOperation] Deleted notebook: {}", view_id);
        Ok(())
      },
      Err(e) => {
        error!("[NotebookFolderOperation] Failed to delete notebook: {}, error: {}", view_id, e);
        Err(e)
      },
    }
  }

  async fn duplicate_view(&self, view_id: &Uuid) -> Result<Bytes, FlowyError> {
    info!("[NotebookFolderOperation] Duplicating notebook view: {}", view_id);
    // Notebook 可以被复制
    let data: DocumentDataPB = self
      .document_manager()?
      .get_document_data(view_id)
      .await?
      .into();
    let data_bytes = data.into_bytes().map_err(|_| FlowyError::invalid_data())?;
    Ok(data_bytes)
  }

  async fn gather_publish_encode_collab(
    &self,
    _user: &Arc<dyn FolderUser>,
    _view_id: &Uuid,
  ) -> Result<GatherEncodedCollab, FlowyError> {
    // Notebook 暂不支持发布
    Err(FlowyError::not_support().with_context("Notebook publishing is not supported yet"))
  }

  async fn create_view_with_view_data(
    &self,
    user_id: i64,
    params: CreateViewParams,
  ) -> Result<Option<EncodedCollab>, FlowyError> {
    info!(
      "[NotebookFolderOperation] Creating notebook with view data: {}",
      params.view_id
    );
    
    // 检查是否是 Notebook 类型
    if params.layout != ViewLayoutPB::Notebook {
      error!(
        "[NotebookFolderOperation] Invalid layout type: {:?}, expected Notebook",
        params.layout
      );
      return Err(FlowyError::invalid_data().with_context("Invalid view layout for notebook"));
    }

    let data = match params.initial_data {
      ViewData::DuplicateData(data) => Some(DocumentDataPB::try_from(data)?),
      ViewData::Data(data) => Some(DocumentDataPB::try_from(data)?),
      ViewData::Empty => None,
    };
    
    let encoded_collab = self
      .document_manager()?
      .create_document(user_id, &params.view_id, data.map(|d| d.into()))
      .await?;
    
    info!(
      "[NotebookFolderOperation] Created notebook with view data: {}",
      params.view_id
    );
    Ok(Some(encoded_collab))
  }

  async fn create_default_view(
    &self,
    user_id: i64,
    _parent_view_id: &Uuid,
    view_id: &Uuid,
    _name: &str,
    _layout: ViewLayout,
  ) -> Result<(), FlowyError> {
    info!(
      "[NotebookFolderOperation] Creating default notebook view: {}",
      view_id
    );
    
    match self
      .document_manager()?
      .create_document(user_id, view_id, None)
      .await
    {
      Ok(_) => {
        info!("[NotebookFolderOperation] Created default notebook: {}", view_id);
        Ok(())
      },
      Err(err) => {
        if err.is_already_exists() {
          info!("[NotebookFolderOperation] Notebook already exists: {}", view_id);
          Ok(())
        } else {
          error!("[NotebookFolderOperation] Failed to create notebook: {}, error: {}", view_id, err);
          Err(err)
        }
      },
    }
  }

  async fn import_from_bytes(
    &self,
    uid: i64,
    view_id: &Uuid,
    _name: &str,
    _import_type: ImportType,
    bytes: Vec<u8>,
  ) -> Result<Vec<ImportedData>, FlowyError> {
    info!("[NotebookFolderOperation] Importing notebook from bytes: {}", view_id);
    let data = DocumentDataPB::try_from(Bytes::from(bytes))?;
    let encoded_collab = self
      .document_manager()?
      .create_document(uid, view_id, Some(data.into()))
      .await?;
    Ok(vec![(
      view_id.to_string(),
      collab_entity::CollabType::Document,
      encoded_collab,
    )])
  }

  async fn import_from_file_path(
    &self,
    _view_id: &str,
    _name: &str,
    _path: String,
  ) -> Result<(), FlowyError> {
    // Notebook 暂不支持从文件导入
    Err(FlowyError::not_support().with_context("Notebook file import is not supported yet"))
  }
}


