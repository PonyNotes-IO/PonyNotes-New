use crate::entities::WhiteboardData;
use anyhow::{anyhow, Error};
use collab::core::collab::DataSource;
use collab::preclude::{Collab, CollabBuilder, Map, MapRef};
use collab::util::MapExt;
use collab_entity::EncodedCollab;
use collab_entity::define::DOCUMENT_ROOT;
use serde::{Deserialize, Serialize};
use std::borrow::BorrowMut;
use std::collections::HashMap;
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

  /// 创建新白板（空白板）
  pub fn create(mut collab: Collab) -> Result<Self, Error> {
    // 使用可变事务初始化和设置数据
    let mut txn = collab.context.transact_mut();

    // ✅ 关键修复：初始化 Document 根节点
    // 白板使用 CollabType::Document 类型，需要确保有 DOCUMENT_ROOT 根节点
    // 这样 RocksDB 插件才能正确验证和保存数据
    let _document_root = collab.data.get_or_init_map(&mut txn, DOCUMENT_ROOT);

    // 初始化白板数据 Map
    let data = collab.data.get_or_init_map(&mut txn, Self::DATA_KEY);
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
  pub fn create_with_data(collab: Collab, whiteboard_data: WhiteboardData) -> Result<Self, Error> {
    let mut whiteboard = Self::create(collab)?;
    whiteboard.update_from_data(&whiteboard_data)?;
    Ok(whiteboard)
  }

  /// 更新白板数据（从 WhiteboardData）
  pub fn update_from_data(&mut self, whiteboard_data: &WhiteboardData) -> Result<(), Error> {
    let mut txn = self.collab.context.transact_mut();

    for (k, v) in &whiteboard_data.0 {
      self.data.insert(&mut txn, k.as_str(), v.as_str());
    }

    trace!("[Whiteboard] Data updated successfully and transaction committed");
    Ok(())
  }

  /// 从完整的 Excalidraw JSON 更新（直接从 Map/对象结构）
  pub fn update_from_json(&mut self, json_str: &str) -> Result<(), Error> {
    tracing::trace!("[Whiteboard] update_from_json called, len: {}", json_str.len());

    #[derive(Serialize, Deserialize)]
    struct UpdateData {
      r#type: String,
      data: String,
    }

    let update_data = serde_json::from_str::<UpdateData>(json_str)?;
    let data_map = serde_json::from_str::<HashMap<String, serde_json::Value>>(&update_data.data)
      .map_err(|e| anyhow!("Failed to parse JSON into map: {}", e))?;

    let mut txn = self.collab.context.transact_mut();
    match update_data.r#type.as_str() {
      "update" => {
        for (key, value) in data_map.iter() {
          let json = serde_json::to_string(value)
            .map_err(|e| anyhow!("Failed to serialize field '{}': {}", key, e))?;
          self.data.insert(&mut txn, key.as_str(), json.as_str());
        }
      },
      "delete" => {
        for (key, _value) in data_map.iter() {
          self.data.remove(&mut txn, key.as_str());
        }
      },
      _ => {
        unimplemented!("unknown update type {}", update_data.r#type);
      },
    }

    Ok(())
  }

  /// 获取完整白板数据
  pub fn get_data(&self) -> Result<WhiteboardData, Error> {
    let txn = self.collab.context.transact();

    let mut data_map = HashMap::new();
    for (k, v) in self.data.iter(&txn) {
      data_map.insert(k.to_string(), serde_json::from_str(&v.to_string(&txn))?);
    }
    Ok(WhiteboardData(data_map))
  }

  /// 导出为 Excalidraw JSON 格式
  pub fn to_json(&self) -> Result<String, Error> {
    let data = self.get_data()?;
    data
      .to_excalidraw_json()
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
pub fn whiteboard_data_to_encoded_collab(
  uid: i64,
  object_id: &str, // 传进来的是 view_id
  device_id: &str,
  data: Option<WhiteboardData>,
) -> Result<EncodedCollab, Error> {
  tracing::info!(
    "[Whiteboard] 🔵 whiteboard_data_to_encoded_collab called for object_id: {}, uid: {}, device_id: {}",
    object_id, uid, device_id
  );

  if device_id.is_empty() {
    return Err(anyhow!("device_id cannot be empty"));
  }

  let collab = CollabBuilder::new(uid, object_id, DataSource::Disk(None))
    .with_device_id(device_id)
    .build()
    .map_err(|e| anyhow!("Failed to create collab: {}", e))?;
  tracing::info!(
    "[Whiteboard] ✅ Collab builder created for object_id: {}",
    object_id
  );

  let whiteboard = match data {
    Some(data) => {
      tracing::info!(
        "[Whiteboard] 🔵 Creating whiteboard with data for object_id: {}",
        object_id
      );
      Whiteboard::create_with_data(collab, data)?
    },
    None => {
      tracing::info!(
        "[Whiteboard] 🔵 Creating empty whiteboard for object_id: {}",
        object_id
      );
      Whiteboard::create(collab)?
    },
  };
  tracing::info!(
    "[Whiteboard] ✅ Whiteboard created for object_id: {}",
    object_id
  );

  let encoded = whiteboard.encode_collab()?;
  tracing::info!(
    "[Whiteboard] ✅ Whiteboard encoded for object_id: {}",
    object_id
  );
  Ok(encoded)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_create_empty_whiteboard() {
    let collab = CollabBuilder::new(
      1,
      "2f6baa3b-f8e7-4551-b553-1b7f3802d299",
      DataSource::Disk(None),
    )
    .build()
    .unwrap();

    let mut whiteboard = Whiteboard::create(collab).unwrap();
    let data = whiteboard.get_data().unwrap();

    whiteboard
      .update_from_json(r#"""{ "key1": "value1"}"""#)
      .unwrap();
    whiteboard
      .update_from_json(r#"""{ "key1": "value2"}"""#)
      .unwrap();

    let data = whiteboard.get_data().unwrap();

    dbg!(data);
    // assert!(data.elements.is_empty());
    // assert!(data.files.is_empty());
  }

  #[test]
  fn test_update_and_get_data() {
    let collab = CollabBuilder::new(1, "test-whiteboard", DataSource::Disk(None))
      .build()
      .unwrap();

    let mut whiteboard = Whiteboard::create(collab).unwrap();

    let test_data = WhiteboardData::default();

    whiteboard.update_from_data(&test_data).unwrap();
    let retrieved_data = whiteboard.get_data().unwrap();

    // assert_eq!(retrieved_data.elements.len(), test_data.elements.len());
  }
}
