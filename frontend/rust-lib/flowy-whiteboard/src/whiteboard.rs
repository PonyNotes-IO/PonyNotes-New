use crate::entities::WhiteboardData;
use crate::notification::{whiteboard_notification_send_json, WhiteboardNotification};
use anyhow::{anyhow, Error};
use collab::core::collab::DataSource;
use collab::preclude::{Collab, CollabBuilder, Map, MapRef};
use collab::util::MapExt;
use collab_entity::EncodedCollab;
use collab_entity::define::DOCUMENT_ROOT;

use std::borrow::BorrowMut;
use std::collections::HashMap;
use tokio::sync::broadcast;
use tracing::trace;

/// 通知类型：数据变更
#[derive(Debug, Clone)]
pub struct WhiteboardChanged {
  pub key: String,
  pub value: String,
  pub is_remote: bool,
}

/// Whiteboard Collab 对象
/// 使用 CRDT (Yrs) 来管理白板数据
pub struct Whiteboard {
  /// 底层 Collab 对象
  collab: Collab,
  /// 数据 Map
  data: MapRef,
  /// 变更通知 channel
  notifier: broadcast::Sender<WhiteboardChanged>,
}

impl Whiteboard {
  /// 数据键
  const DATA_KEY: &'static str = "data";

  /// 创建新白板（空白板）
  pub fn create(mut collab: Collab) -> Result<Self, Error> {
    let mut txn = collab.context.transact_mut();

    let _document_root = collab.data.get_or_init_map(&mut txn, DOCUMENT_ROOT);
    let data = collab.data.get_or_init_map(&mut txn, Self::DATA_KEY);
    drop(txn);

    let (notifier, _) = broadcast::channel(100);
    Ok(Self {
      collab,
      data,
      notifier,
    })
  }

  /// 从现有 Collab 对象打开白板
  pub fn open(collab: Collab) -> Result<Self, Error> {
    let txn = collab.context.transact();
    let data = collab
      .data
      .get_with_txn(&txn, Self::DATA_KEY)
      .ok_or_else(|| anyhow!("Whiteboard data not found"))?;
    drop(txn);

    let (notifier, _) = broadcast::channel(100);
    Ok(Self {
      collab,
      data,
      notifier,
    })
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

  /// 从完整的 Excalidraw JSON 更新
  /// 前端发送格式：{"type": "update", "data": "{\"elements\":..., \"files\":..., \"appState\":...}"}
  /// 这里的 data 字段是 JSON 字符串，需要二次解析
  pub fn update_from_json(&mut self, json_str: &str) -> Result<(), Error> {
    tracing::trace!("[Whiteboard] update_from_json called, len: {}", json_str.len());

    // ✅ 解析外层 JSON
    #[derive(serde::Deserialize)]
    struct UpdateWrapper {
      #[serde(default)]
      r#type: String,
      // data 字段可能是字符串（嵌套JSON）或直接是对象
      #[serde(default)]
      data: serde_json::Value,
    }

    let wrapper: UpdateWrapper = serde_json::from_str(json_str)
      .map_err(|e| anyhow!("Failed to parse wrapper JSON: {}", e))?;

    // ✅ 提取实际数据：如果是字符串则二次解析，否则直接使用
    let data_map: HashMap<String, serde_json::Value> = match wrapper.data {
      serde_json::Value::String(data_str) => {
        // data 是嵌套的 JSON 字符串，需要解析
        serde_json::from_str(&data_str)
          .map_err(|e| anyhow!("Failed to parse nested data JSON: {}", e))?
      },
      serde_json::Value::Object(map) => map
        .into_iter()
        .map(|(k, v)| (k, v))
        .collect(),
      _ => HashMap::new(),
    };

    let mut txn = self.collab.context.transact_mut();
    match wrapper.r#type.as_str() {
      "update" | "" => {
        for (key, value) in data_map.iter() {
          let json = serde_json::to_string(value)
            .map_err(|e| anyhow!("Failed to serialize field '{}': {}", key, e))?;
          self.data.insert(&mut txn, key.as_str(), json.as_str());
        }
        tracing::trace!("[Whiteboard] Stored {} fields from update", data_map.len());
      },
      "delete" => {
        for (key, _) in data_map.iter() {
          self.data.remove(&mut txn, key.as_str());
        }
        tracing::trace!("[Whiteboard] Deleted {} fields", data_map.len());
      },
      _ => {
        tracing::warn!("[Whiteboard] Unknown update type: {}", wrapper.r#type);
      },
    }

    // ✅ 广播所有变更给订阅者（手动通知模式）
    // 不依赖 observe_deep（它只监听远程 sync 事件），改为在事务提交后主动通知
    for (key, value) in data_map.iter() {
      let event_json = serde_json::json!({
        "key": key.to_string(),
        "value": value.to_string(),
        "is_remote": false,
      })
      .to_string();

      let _ = self.notifier.send(WhiteboardChanged {
        key: key.clone(),
        value: event_json,
        is_remote: false,
      });
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

  /// 获取变更通知的 receiver（用于 subscribe_changed）
  pub fn subscribe_changed(&self) -> broadcast::Receiver<WhiteboardChanged> {
    self.notifier.subscribe()
  }

  /// 启动监听任务：在 tokio spawn 中监听 channel，收到变更后发给 Dart
  pub fn start_change_listener(&self) {
    let view_id = self.object_id();
    let mut rx = self.subscribe_changed();

    tokio::spawn(async move {
      while let Ok(changed) = rx.recv().await {
        whiteboard_notification_send_json(
          view_id.clone(),
          WhiteboardNotification::DidReceiveUpdate,
          changed.value,
        );
      }
    });
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
