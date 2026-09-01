use bytes::Bytes;
use collab::entity::EncodedCollab;
use collab_folder::hierarchy_builder::NestedViewBuilder;
use collab_folder::ViewLayout;
use flowy_error::FlowyError;
use flowy_folder::entities::{CreateViewParams, ViewLayoutPB};
use flowy_folder::manager::FolderUser;
use flowy_folder::share::ImportType;
use flowy_folder::view_operation::{
  FolderOperationHandler, GatherEncodedCollab, ImportedData, ViewData,
};
use flowy_whiteboard::manager::WhiteboardManager;
use lib_infra::async_trait::async_trait;
use std::sync::{Arc, Weak};
use tokio::sync::RwLock;
use tracing::{error, info, trace};
use uuid::Uuid;

pub struct WhiteboardFolderOperation(pub Weak<WhiteboardManager>);

impl WhiteboardFolderOperation {
  fn whiteboard_manager(&self) -> Result<Arc<WhiteboardManager>, FlowyError> {
    self
      .0
      .upgrade()
      .ok_or_else(|| FlowyError::internal().with_context("WhiteboardManager is already dropped"))
  }

  fn sanitize_duplicate_data(json_data: &str) -> Result<String, FlowyError> {
    let mut data: serde_json::Value = serde_json::from_str(json_data).map_err(|e| {
      FlowyError::invalid_data().with_context(format!("Failed to parse whiteboard data: {}", e))
    })?;
    if let Some(object) = data.as_object_mut() {
      object.remove("roomId");
      object.remove("roomKey");
    } else {
      return Err(FlowyError::invalid_data().with_context("Whiteboard data must be a JSON object"));
    }
    serde_json::to_string(&data).map_err(|e| {
      FlowyError::invalid_data().with_context(format!("Failed to encode whiteboard data: {}", e))
    })
  }
}

#[async_trait]
impl FolderOperationHandler for WhiteboardFolderOperation {
  fn name(&self) -> &str {
    "WhiteboardFolderOperationHandler"
  }

  async fn create_workspace_view(
    &self,
    _uid: i64,
    _workspace_view_builder: Arc<RwLock<NestedViewBuilder>>,
  ) -> Result<(), FlowyError> {
    // 白板不需要在工作空间创建时自动创建
    Ok(())
  }

  async fn open_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    info!(
      "[WhiteboardFolderOperation] Opening whiteboard view: {}",
      view_id
    );
    self.whiteboard_manager()?.open_whiteboard(view_id).await?;
    Ok(())
  }

  async fn close_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    info!(
      "[WhiteboardFolderOperation] Closing whiteboard view: {}",
      view_id
    );
    self.whiteboard_manager()?.close_whiteboard(view_id).await?;
    Ok(())
  }

  async fn delete_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    info!(
      "[WhiteboardFolderOperation] Deleting whiteboard view: {}",
      view_id
    );
    // 白板暂不支持删除操作，但需要实现接口
    trace!("Delete whiteboard: {}", view_id);
    Ok(())
  }

  async fn duplicate_view(&self, view_id: &Uuid) -> Result<Bytes, FlowyError> {
    info!(
      "[WhiteboardFolderOperation] Duplicating whiteboard view: {}",
      view_id
    );
    let json_data = self
      .whiteboard_manager()?
      .get_whiteboard_data(view_id)
      .await?;
    // roomId/roomKey are credentials for the source Excalidraw collaboration room.
    // Keeping them would make the duplicated view open the source room instead of
    // creating an independent room on the first open (especially on iOS, where the
    // remote whiteboard path reads these fields before local collab data is loaded).
    let sanitized_json = Self::sanitize_duplicate_data(&json_data)?;
    Ok(Bytes::from(sanitized_json.into_bytes()))
  }

  async fn gather_publish_encode_collab(
    &self,
    _user: &Arc<dyn FolderUser>,
    _view_id: &Uuid,
  ) -> Result<GatherEncodedCollab, FlowyError> {
    // 白板暂不支持发布
    Err(FlowyError::not_support().with_context("Whiteboard publishing is not supported yet"))
  }

  async fn create_view_with_view_data(
    &self,
    _user_id: i64,
    params: CreateViewParams,
  ) -> Result<Option<EncodedCollab>, FlowyError> {
    info!(
      "[WhiteboardFolderOperation] Creating whiteboard with view data: {}",
      params.view_id
    );

    // 检查是否是白板类型
    if params.layout != ViewLayoutPB::Whiteboard {
      error!(
        "[WhiteboardFolderOperation] Invalid layout type: {:?}, expected Whiteboard",
        params.layout
      );
      return Err(FlowyError::invalid_data().with_context("Invalid view layout for whiteboard"));
    }

    let whiteboard_data = match params.initial_data {
      ViewData::Data(data) | ViewData::DuplicateData(data) => {
        // 解析 JSON 数据
        let json_str = String::from_utf8(data.to_vec())
          .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid UTF-8: {}", e)))?;
        Some(serde_json::from_str(&json_str).map_err(|e| {
          FlowyError::invalid_data().with_context(format!("Failed to parse whiteboard data: {}", e))
        })?)
      },
      ViewData::Empty => None,
    };

    let encoded_collab = self
      .whiteboard_manager()?
      .create_whiteboard(&params.view_id, whiteboard_data)
      .await?;

    info!(
      "[WhiteboardFolderOperation] Created whiteboard with view data: {}",
      params.view_id
    );
    Ok(Some(encoded_collab))
  }

  async fn create_default_view(
    &self,
    _user_id: i64,
    _parent_view_id: &Uuid,
    view_id: &Uuid,
    _name: &str,
    layout: ViewLayout,
  ) -> Result<(), FlowyError> {
    info!(
      "[WhiteboardFolderOperation] 🔵 Creating default whiteboard view: {}, layout: {:?}",
      view_id, layout
    );

    // 验证 layout 类型（因为路由可能有问题）
    // 由于 ViewLayout 没有 Whiteboard 枚举值，这里需要检查
    // 暂时跳过验证，直接创建

    info!(
      "[WhiteboardFolderOperation] 🔵 Getting whiteboard manager for view: {}",
      view_id
    );
    let manager = match self.whiteboard_manager() {
      Ok(m) => {
        info!(
          "[WhiteboardFolderOperation] ✅ Got whiteboard manager for view: {}",
          view_id
        );
        m
      },
      Err(e) => {
        error!(
          "[WhiteboardFolderOperation] ❌ Failed to get whiteboard manager for view: {}, error: {}",
          view_id, e
        );
        return Err(e);
      },
    };

    info!(
      "[WhiteboardFolderOperation] 🔵 Calling create_whiteboard for view: {}",
      view_id
    );
    match manager.create_whiteboard(view_id, None).await {
      Ok(_) => {
        info!(
          "[WhiteboardFolderOperation] ✅ Created default whiteboard: {}",
          view_id
        );
        Ok(())
      },
      Err(err) => {
        if err.is_already_exists() {
          info!(
            "[WhiteboardFolderOperation] ℹ️ Whiteboard already exists: {}",
            view_id
          );
          Ok(())
        } else {
          error!(
            "[WhiteboardFolderOperation] ❌ Failed to create whiteboard: {}, error: {}",
            view_id, err
          );
          Err(err)
        }
      },
    }
  }

  async fn import_from_bytes(
    &self,
    _uid: i64,
    _view_id: &Uuid,
    _name: &str,
    _import_type: ImportType,
    _bytes: Vec<u8>,
  ) -> Result<Vec<ImportedData>, FlowyError> {
    // 白板暂不支持导入
    Err(FlowyError::not_support().with_context("Whiteboard import is not supported yet"))
  }

  async fn import_from_file_path(
    &self,
    _view_id: &str,
    _name: &str,
    _path: String,
  ) -> Result<(), FlowyError> {
    // 白板暂不支持从文件导入
    Err(FlowyError::not_support().with_context("Whiteboard file import is not supported yet"))
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn duplicate_data_does_not_reuse_source_room() {
    let sanitized = WhiteboardFolderOperation::sanitize_duplicate_data(
      r##"{"roomId":"source-room","roomKey":"source-key","elements":[{"id":"e1"}],"appState":{"viewBackgroundColor":"#fff"}}"##,
    )
    .unwrap();
    let data: serde_json::Value = serde_json::from_str(&sanitized).unwrap();

    assert!(data.get("roomId").is_none());
    assert!(data.get("roomKey").is_none());
    assert_eq!(data["elements"][0]["id"], "e1");
    assert_eq!(data["appState"]["viewBackgroundColor"], "#fff");
  }
}
