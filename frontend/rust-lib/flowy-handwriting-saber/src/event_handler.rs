use crate::entities::{
  CreateHandwritingSaberPayloadPB, HandwritingSaberDataPB, SaveHandwritingSaberPayloadPB,
  SaveHandwritingSaberResponsePB,
};
use crate::manager::HandwritingSaberManager;
use flowy_error::{FlowyError, FlowyResult};
use flowy_folder::entities::ViewIdPB;
use lib_dispatch::prelude::{data_result_ok, AFPluginData, AFPluginState, DataResult};
use std::sync::{Arc, Weak};
use tracing::{info, instrument};
use uuid::Uuid;

fn upgrade_manager(
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> FlowyResult<Arc<HandwritingSaberManager>> {
  manager
    .upgrade()
    .ok_or_else(|| {
      FlowyError::internal().with_context("The handwriting saber manager is already dropped")
    })
}

/// 创建手写笔记处理器
#[instrument(level = "info", skip_all, err)]
pub(crate) async fn create_handwriting_saber_handler(
  data: AFPluginData<CreateHandwritingSaberPayloadPB>,
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();

  let view_id = Uuid::parse_str(&payload.view_id)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  manager
    .create_handwriting_saber(&view_id, payload.initial_data)
    .await?;
  info!("[HandwritingSaber] Created handwriting saber: {}", view_id);
  Ok(())
}

/// 打开手写笔记处理器
#[instrument(level = "info", skip_all, err)]
pub(crate) async fn open_handwriting_saber_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();

  info!("[HandwritingSaber] =====================================================");
  info!("[HandwritingSaber] open_handwriting_saber_handler called");
  info!("[HandwritingSaber] ViewID: {}", payload.value);

  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  info!("[HandwritingSaber] Calling manager.open_handwriting_saber...");
  manager.open_handwriting_saber(&view_id).await?;
  info!("[HandwritingSaber] ✅ Opened handwriting saber");
  info!("[HandwritingSaber] =====================================================");
  Ok(())
}

/// 保存手写笔记处理器
#[instrument(level = "info", skip_all, err)]
pub(crate) async fn save_handwriting_saber_handler(
  data: AFPluginData<SaveHandwritingSaberPayloadPB>,
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> DataResult<SaveHandwritingSaberResponsePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();

  info!("[HandwritingSaber] =====================================================");
  info!("[HandwritingSaber] save_handwriting_saber_handler called");
  info!("[HandwritingSaber] ViewID: {}", payload.view_id);
  info!(
    "[HandwritingSaber] Version: {}, Data size: {} bytes",
    payload.version,
    payload.sbn2_bytes.len()
  );

  let view_id = Uuid::parse_str(&payload.view_id)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  info!("[HandwritingSaber] Calling manager.save_handwriting_saber_data...");
  let new_version = manager
    .save_handwriting_saber_data(&view_id, payload.sbn2_bytes, payload.version)
    .await?;
  info!(
    "[HandwritingSaber] ✅ Saved handwriting saber data, new version: {}",
    new_version
  );
  info!("[HandwritingSaber] =====================================================");

  data_result_ok(SaveHandwritingSaberResponsePB {
    new_version,
  })
}

/// 获取手写笔记数据处理器
#[instrument(level = "info", skip_all, err)]
pub(crate) async fn get_handwriting_saber_data_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> DataResult<HandwritingSaberDataPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();

  info!("[HandwritingSaber] =====================================================");
  info!("[HandwritingSaber] get_handwriting_saber_data_handler called");
  info!("[HandwritingSaber] ViewID: {}", payload.value);

  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  info!("[HandwritingSaber] Calling manager.get_handwriting_saber_data...");
  let sbn2_bytes = manager.get_handwriting_saber_data(&view_id).await?;
  info!(
    "[HandwritingSaber] ✅ Got handwriting saber data, length: {} bytes",
    sbn2_bytes.len()
  );
  info!("[HandwritingSaber] =====================================================");

  // TODO: 获取实际的版本号、更新时间等信息
  // TODO: 获取实际的版本号、更新时间等信息
  use std::time::{SystemTime, UNIX_EPOCH};
  let updated_at = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .unwrap()
    .as_secs() as i64;

  data_result_ok(HandwritingSaberDataPB {
    view_id: payload.value,
    sbn2_bytes,
    version: 1,
    preview_png: None,
    updated_at,
    updated_by: String::new(),
  })
}

/// 关闭手写笔记处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn close_handwriting_saber_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();

  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  manager.close_handwriting_saber(&view_id).await?;
  Ok(())
}

/// 删除手写笔记处理器
#[instrument(level = "debug", skip_all, err)]
pub(crate) async fn delete_handwriting_saber_handler(
  data: AFPluginData<ViewIdPB>,
  manager: AFPluginState<Weak<HandwritingSaberManager>>,
) -> FlowyResult<()> {
  let manager = upgrade_manager(manager)?;
  let payload = data.into_inner();

  let view_id = Uuid::parse_str(&payload.value)
    .map_err(|e| FlowyError::invalid_data().with_context(format!("Invalid view_id: {}", e)))?;

  manager.delete_handwriting_saber(&view_id).await?;
  Ok(())
}

