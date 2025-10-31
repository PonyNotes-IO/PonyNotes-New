use crate::entities::WhiteboardData;
use anyhow::{anyhow, Error};
use collab::core::collab::DataSource;
use collab::preclude::{Collab, CollabBuilder, MapRef, Map, ReadTxn, Out, Any};
use collab::util::MapExt;
use collab_entity::EncodedCollab;
use std::borrow::BorrowMut;
use tracing::trace;

/// Whiteboard Collab 对象
/// 使用 CRDT (Yrs) 来管理白板数据
pub struct Whiteboard {
  /// 底层 Collab 对象
  collab: Collab,
  /// 数据 Map
  data: MapRef,
}

impl Whiteboard {
  /// 数据键
  const DATA_KEY: &'static str = "data";
  const ELEMENTS_KEY: &'static str = "elements";
  const APP_STATE_KEY: &'static str = "appState";
  const FILES_KEY: &'static str = "files";

  /// 创建新白板（空白板）
  pub fn create(mut collab: Collab) -> Result<Self, Error> {
    // 使用可变事务初始化和设置数据
    let mut txn = collab.context.transact_mut();
    let data = collab.data.get_or_init_map(&mut txn, Self::DATA_KEY);
    data.insert(&mut txn, Self::ELEMENTS_KEY, "[]");
    data.insert(&mut txn, Self::APP_STATE_KEY, "{}");
    data.insert(&mut txn, Self::FILES_KEY, "{}");
    drop(txn);

    Ok(Self { collab, data })
  }

  /// 从现有 Collab 对象打开白板
  pub fn open(collab: Collab) -> Result<Self, Error> {
    let txn = collab.context.transact();
    let data = collab
      .data
      .get_with_txn(&txn, Self::DATA_KEY)
      .ok_or_else(|| anyhow!("Whiteboard data not found"))?;
    drop(txn);
    Ok(Self { collab, data })
  }

  /// 从 WhiteboardData 创建白板
  pub fn create_with_data(
    collab: Collab,
    whiteboard_data: WhiteboardData,
  ) -> Result<Self, Error> {
    let mut whiteboard = Self::create(collab)?;
    whiteboard.update_from_data(&whiteboard_data)?;
    Ok(whiteboard)
  }

  /// 更新白板数据（从 WhiteboardData）
  pub fn update_from_data(&mut self, whiteboard_data: &WhiteboardData) -> Result<(), Error> {
    let mut txn = self.collab.context.transact_mut();

    // 更新 elements
    let elements_json = serde_json::to_string(&whiteboard_data.elements)
      .map_err(|e| anyhow!("Failed to serialize elements: {}", e))?;
    self.data.insert(&mut txn, Self::ELEMENTS_KEY, elements_json.as_str());

    // 更新 appState
    let app_state_json = serde_json::to_string(&whiteboard_data.app_state)
      .map_err(|e| anyhow!("Failed to serialize appState: {}", e))?;
    self.data.insert(&mut txn, Self::APP_STATE_KEY, app_state_json.as_str());

    // 更新 files
    let files_json = serde_json::to_string(&whiteboard_data.files)
      .map_err(|e| anyhow!("Failed to serialize files: {}", e))?;
    self.data.insert(&mut txn, Self::FILES_KEY, files_json.as_str());

    trace!("[Whiteboard] Data updated successfully");
    Ok(())
  }

  /// 从完整的 Excalidraw JSON 更新
  pub fn update_from_json(&mut self, json_str: &str) -> Result<(), Error> {
    let value: serde_json::Value = serde_json::from_str(json_str)
      .map_err(|e| anyhow!("Failed to parse JSON: {}", e))?;

    let mut txn = self.collab.context.transact_mut();

    // 更新 elements
    if let Some(elements) = value.get("elements") {
      let json = serde_json::to_string(elements)
        .map_err(|e| anyhow!("Failed to serialize elements: {}", e))?;
      self.data.insert(&mut txn, Self::ELEMENTS_KEY, json.as_str());
    }

    // 更新 appState
    if let Some(app_state) = value.get("appState") {
      let json = serde_json::to_string(app_state)
        .map_err(|e| anyhow!("Failed to serialize appState: {}", e))?;
      self.data.insert(&mut txn, Self::APP_STATE_KEY, json.as_str());
    }

    // 更新 files
    if let Some(files) = value.get("files") {
      let json = serde_json::to_string(files)
        .map_err(|e| anyhow!("Failed to serialize files: {}", e))?;
      self.data.insert(&mut txn, Self::FILES_KEY, json.as_str());
    }

    trace!("[Whiteboard] Data updated from JSON successfully");
    Ok(())
  }

  /// 辅助函数：从 MapRef 获取字符串值
  fn get_string_value<T: ReadTxn>(map: &MapRef, txn: &T, key: &str, default: &str) -> String {
    match map.get(txn, key) {
      Some(Out::Any(Any::String(s))) => s.to_string(),
      _ => default.to_string(),
    }
  }

  /// 获取完整白板数据
  pub fn get_data(&self) -> Result<WhiteboardData, Error> {
    let txn = self.collab.context.transact();

    let elements_json = Self::get_string_value(&self.data, &txn, Self::ELEMENTS_KEY, "[]");
    let app_state_json = Self::get_string_value(&self.data, &txn, Self::APP_STATE_KEY, "{}");
    let files_json = Self::get_string_value(&self.data, &txn, Self::FILES_KEY, "{}");

    let elements = serde_json::from_str(&elements_json).unwrap_or_default();
    let app_state = serde_json::from_str(&app_state_json).unwrap_or_default();
    let files = serde_json::from_str(&files_json).unwrap_or_default();

    Ok(WhiteboardData {
      elements,
      app_state,
      files,
    })
  }

  /// 导出为 Excalidraw JSON 格式
  pub fn to_json(&self) -> Result<String, Error> {
    let data = self.get_data()?;
    data.to_excalidraw_json()
      .map_err(|e| anyhow!("Failed to convert to JSON: {}", e))
  }

  /// 编码为 EncodedCollab
  pub fn encode_collab(&self) -> Result<EncodedCollab, Error> {
    self
      .collab
      .encode_collab_v1(|_| Ok::<(), collab::error::CollabError>(()))
      .map_err(|e| anyhow!("Failed to encode collab: {}", e))
  }

  /// 获取对象 ID
  pub fn object_id(&self) -> String {
    self.collab.object_id().to_string()
  }

  /// 获取底层 Collab 对象的引用
  pub fn get_collab(&self) -> &Collab {
    &self.collab
  }
}

impl BorrowMut<Collab> for Whiteboard {
  fn borrow_mut(&mut self) -> &mut Collab {
    &mut self.collab
  }
}

impl std::borrow::Borrow<Collab> for Whiteboard {
  fn borrow(&self) -> &Collab {
    &self.collab
  }
}

/// 从 WhiteboardData 创建 EncodedCollab
pub async fn whiteboard_data_to_encoded_collab(
  object_id: &str,
  data: Option<WhiteboardData>,
) -> Result<EncodedCollab, Error> {
  let collab = CollabBuilder::new(1, object_id, DataSource::Disk(None))
    .build()
    .map_err(|e| anyhow!("Failed to create collab: {}", e))?;

  let whiteboard = match data {
    Some(data) => Whiteboard::create_with_data(collab, data)?,
    None => Whiteboard::create(collab)?,
  };

  whiteboard.encode_collab()
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_create_empty_whiteboard() {
    let collab = CollabBuilder::new(1, "test-whiteboard", DataSource::Disk(None))
      .build()
      .unwrap();

    let whiteboard = Whiteboard::create(collab).unwrap();
    let data = whiteboard.get_data().unwrap();

    assert!(data.elements.is_empty());
    assert!(data.files.is_empty());
  }

  #[test]
  fn test_update_and_get_data() {
    let collab = CollabBuilder::new(1, "test-whiteboard", DataSource::Disk(None))
      .build()
      .unwrap();

    let mut whiteboard = Whiteboard::create(collab).unwrap();

    let test_data = WhiteboardData {
      elements: vec![],
      app_state: Default::default(),
      files: Default::default(),
    };

    whiteboard.update_from_data(&test_data).unwrap();
    let retrieved_data = whiteboard.get_data().unwrap();

    assert_eq!(retrieved_data.elements.len(), test_data.elements.len());
  }
}
