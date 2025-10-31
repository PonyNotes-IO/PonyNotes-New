use crate::entities::{CreateWhiteboardPayloadPB, UpdateWhiteboardPayloadPB, WhiteboardDataPB};
use crate::manager::WhiteboardManager;
use flowy_error::{FlowyError, FlowyResult};
use flowy_folder::entities::ViewIdPB;
use lib_dispatch::prelude::{AFPluginData, AFPluginState, data_result_ok, DataResult};
use std::sync::{Arc, Weak};
use tracing::{info, instrument};
use uuid::Uuid;

fn upgrade_manager(
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> FlowyResult<Arc<WhiteboardManager>> {
  manager
    .upgrade()
    .ok_or_else(|| FlowyError::internal().with_context("The whiteboard manager is already dropped"))
}

/// 创建白板处理器
#[instrument(level = "info", skip_all, err)]
pub(crate) async fn create_whiteboard_handler(
  data: AFPluginData<CreateWhiteboardPayloadPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.view_id)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  let whiteboard_data = if let Some(ref data) = payload.initial_data {
    if !data.is_empty() {
      Some(serde_json::from_str(data).map_err(|e| {
        FlowyError::invalid_data().with_context(format!("Failed to parse whiteboard data: {}", e))
      })?)
    } else {
      None
    }
  } else {
    None
  };

  manager.create_whiteboard(&view_id, whiteboard_data).await?;
  info!("[Whiteboard] Created whiteboard: {}", view_id);
  Ok(())
}

/// 打开白板处理器
#[instrument(level = "info", skip_all, err)]
pub(crate) async fn open_whiteboard_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> DataResult<WhiteboardDataPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  let json_data = manager.get_whiteboard_data(&view_id).await?;
  
  data_result_ok(WhiteboardDataPB {
    view_id: payload.value,
    json_data,
  })
}

/// 更新白板处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn update_whiteboard_handler(
  data: AFPluginData<UpdateWhiteboardPayloadPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.view_id)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  manager.update_whiteboard(&view_id, &payload.json_data).await?;
  Ok(())
}

/// 关闭白板处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn close_whiteboard_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  manager.close_whiteboard(&view_id).await?;
  Ok(())
}

/// 删除白板处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn delete_whiteboard_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  manager.delete_whiteboard(&view_id).await?;
  Ok(())
}

/// 获取白板数据处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_whiteboard_data_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> DataResult<WhiteboardDataPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  let json_data = manager.get_whiteboard_data(&view_id).await?;
  
  data_result_ok(WhiteboardDataPB {
    view_id: payload.value,
    json_data,
  })
}

/// 获取编码的 Collab 数据处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_encoded_collab_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<WhiteboardManager>>,
) -> DataResult<WhiteboardDataPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();
  
  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  let encoded_collab = manager.get_encoded_collab(&view_id).await?;
  let json = serde_json::to_string(&encoded_collab)
    .map_err(|e| FlowyError::internal().with_context(format!("Failed to serialize encoded collab: {}", e)))?;

  data_result_ok(WhiteboardDataPB {
    view_id: payload.value,
    json_data: json,
  })
}
