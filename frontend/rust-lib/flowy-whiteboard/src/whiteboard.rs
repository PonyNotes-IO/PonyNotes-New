use crate::entities::WhiteboardData;
use crate::notification::{whiteboard_notification_send_json, WhiteboardNotification};
use anyhow::{anyhow, Error};
use collab::core::collab::DataSource;
use collab::preclude::Event;
use collab::preclude::Subscription;
use collab::preclude::{
  Any, Collab, CollabBuilder, DeepObservable, GetString, Map, MapRef, Out, ReadTxn,
};
use collab::util::MapExt;
use collab_entity::define::DOCUMENT_ROOT;
use collab_entity::EncodedCollab;

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
  /// observe_deep subscription，用于取消订阅
  #[allow(dead_code)]
  _subscription: Option<Subscription>,
}

impl Whiteboard {
  /// 数据键
  const DATA_KEY: &'static str = "data";
  const ELEMENTS_KEY: &'static str = "elements";
  /// 图片二进制表的键。与 elements 一样必须按 id 合并（union），
  /// 不能整块覆盖，否则陈旧端的全量保存会抹掉其他端新加的图片，
  /// 表现为「图片在其他用户处变占位图」「他人进入白板导致图片丢失」。
  const FILES_KEY: &'static str = "files";

  /// 创建新白板（空白板）
  pub fn create(mut collab: Collab) -> Result<Self, Error> {
    let mut txn = collab.context.transact_mut();

    let _document_root = collab.data.get_or_init_map(&mut txn, DOCUMENT_ROOT);
    let data = collab.data.get_or_init_map(&mut txn, Self::DATA_KEY);
    Self::ensure_elements_map(&data, &mut txn);
    drop(txn);

    let (notifier, _) = broadcast::channel(100);
    Ok(Self {
      collab,
      data,
      notifier,
      _subscription: None,
    })
  }

  /// 从现有 Collab 对象打开白板
  ///
  /// 通过 yrs 原生的 observe_deep 监听所有 collab 变更，
  /// 在变更发生时通过事务是否有 origin 来区分本地/远程。
  pub fn open(mut collab: Collab) -> Result<Self, Error> {
    let mut txn = collab.context.transact_mut();
    let _document_root = collab.data.get_or_init_map(&mut txn, DOCUMENT_ROOT);
    let data = collab.data.get_or_init_map(&mut txn, Self::DATA_KEY);
    Self::ensure_elements_map(&data, &mut txn);

    // 检查现有的数据结构中是否有 roomId/roomKey
    if let Some(room_id) = Self::map_string_value(data.get(&txn, "roomId"), &txn) {
      tracing::info!(
        "[WBCollab] ✅ Whiteboard::open found existing roomId: {}",
        room_id
      );
    }
    if let Some(room_key) = Self::map_string_value(data.get(&txn, "roomKey"), &txn) {
      tracing::info!(
        "[WBCollab] ✅ Whiteboard::open found existing roomKey: {}",
        room_key
      );
    }

    drop(txn);

    let (notifier, _) = broadcast::channel(100);

    let notifier_clone = notifier.clone();

    tracing::info!("[WBCollab] 🔍 Whiteboard::open creating observe_deep subscription...");

    // observe_deep 回调签名：(txn, events)
    // 有 origin 的事务是远程推送的变更
    let subscription = data.observe_deep(move |txn, events| {
      for event in events.iter() {
        // 通过事务是否有 origin 来判断是否为远程变更
        // 有 origin -> 远程变更（云端推送）
        // 无 origin -> 本地变更
        let origin = txn.origin();
        let is_remote = origin.is_some();

        if let Event::Map(map_event) = event {
          let target = map_event.target();
          let key_changes = map_event.keys(txn);
          let is_elements_map = !map_event.path().is_empty();

          if is_elements_map {
            let mut changed_elements = Vec::new();
            for (key, _change) in key_changes.iter() {
              let id = key.to_string();
              let element = Self::map_string_value_to_json(target.get(txn, id.as_str()), txn);
              // 【元素丢失根因修复 2026-07-01】读到 null（键被移除/值不可解析的异常态）绝不能
              // 作为“删除”广播出去。union-only 模型下元素键从不删除、合法删除是 isDeleted:true 的
              // 非空元素；把 null 发给客户端会被 _mergeElementsDelta 当成删除，导致其他端元素莫名
              // 消失。跳过 null，不发射该 delta。
              if element.is_null() {
                tracing::warn!(
                  "[WBLoss] observe_deep skip null element id={}, is_remote={}",
                  id,
                  is_remote
                );
                continue;
              }
              changed_elements.push(serde_json::json!({
                "id": id,
                "element": element,
              }));

              trace!(
                "[WBCollab] observe_deep: elements.{}, is_remote={}",
                key,
                is_remote
              );
            }

            if changed_elements.is_empty() {
              continue;
            }

            let event_json = serde_json::json!({
              "key": Self::ELEMENTS_KEY,
              "is_remote": is_remote,
              "value": { "changed": changed_elements },
            })
            .to_string();
            let changed = WhiteboardChanged {
              key: Self::ELEMENTS_KEY.to_string(),
              value: event_json,
              is_remote,
            };
            let _ = notifier_clone.send(changed);
          } else {
            for (key, change) in key_changes.iter() {
              let key_str = key.to_string();
              let value = Self::map_string_value_to_json(target.get(txn, key_str.as_str()), txn);

              let event_json = serde_json::json!({
                "key": key_str,
                "is_remote": is_remote,
                "value": value,
                "change_type": format!("{:?}", change),
              })
              .to_string();

              trace!(
                "[WBCollab] observe_deep: key={}, is_remote={}",
                key_str,
                is_remote
              );

              let changed = WhiteboardChanged {
                key: key_str,
                value: event_json,
                is_remote,
              };
              let _ = notifier_clone.send(changed);
            }
          }
        }
      }
    });

    Ok(Self {
      collab,
      data,
      notifier,
      _subscription: Some(subscription),
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
      if k == Self::ELEMENTS_KEY {
        Self::update_elements_map(&self.data, &mut txn, v)?;
      } else if k == Self::FILES_KEY {
        Self::merge_files_map(&self.data, &mut txn, v)?;
      } else {
        let json = serde_json::to_string(v)
          .map_err(|e| anyhow!("Failed to serialize field '{}': {}", k, e))?;
        self.data.insert(&mut txn, k.as_str(), json.as_str());
      }
    }

    tracing::trace!("[WBCollab] Data updated successfully and transaction committed");
    Ok(())
  }

  /// 从完整的 Excalidraw JSON 更新
  /// 前端发送格式：{"type": "update", "data": "{\"elements\":..., \"files\":..., \"appState\":...}"}
  /// 这里的 data 字段是 JSON 字符串，需要二次解析
  pub fn update_from_json(&mut self, json_str: &str) -> Result<(), Error> {
    // 每次保存都会打印，Windows 上每条日志都有成本；降为 debug/trace（trace 才输出全量 JSON）。
    tracing::debug!(
      "[WBCollab] update_from_json called, len: {}",
      json_str.len()
    );
    tracing::trace!("[WBCollab] update_from_json raw: {}", json_str);

    #[derive(serde::Deserialize)]
    struct UpdateWrapper {
      #[serde(default)]
      r#type: String,
      #[serde(default)]
      data: serde_json::Value,
    }

    let wrapper: UpdateWrapper =
      serde_json::from_str(json_str).map_err(|e| anyhow!("Failed to parse wrapper JSON: {}", e))?;

    let data_map: HashMap<String, serde_json::Value> = match wrapper.data {
      serde_json::Value::String(data_str) => {
        tracing::trace!("[WBCollab] update_from_json nested data_str: {}", data_str);
        serde_json::from_str(&data_str)
          .map_err(|e| anyhow!("Failed to parse nested data JSON: {}", e))?
      },
      serde_json::Value::Object(map) => {
        tracing::debug!("[WBCollab] update_from_json object keys: {:?}", map.keys());
        map.into_iter().collect()
      },
      _ => HashMap::new(),
    };

    tracing::debug!(
      "[WBCollab] update_from_json data_map keys: {:?}",
      data_map.keys()
    );
    if data_map.contains_key("roomId") {
      tracing::debug!(
        "[WBCollab] roomId found in update data: {}",
        data_map["roomId"]
      );
    }
    if data_map.contains_key("roomKey") {
      tracing::debug!(
        "[WBCollab] roomKey found in update data: {}",
        data_map["roomKey"]
      );
    }

    // 【协作丢元素修复 2026-07-01】移除文档级 revision 门控。
    // 白板 elements 以 id→element 的 YMap 存储、按“元素级 version”合并（update_elements_map：
    // 仅当 incoming_version < existing_version 才跳过“单个元素”），这才是正确的冲突粒度。
    // 而文档级 revision 是单调标量，多端各自独立递增、天然乱序；用它“拒绝更旧”会把并发的合法
    // 更新连同其中的新元素“整条”丢弃（日志实测 380 次 Reject stale，incoming/current 仅差 1~2
    // 也被拒），这正是“多端大量绘制时元素一点一点丢失”的根因。这里不再按 revision 拒绝整条
    // 更新，排序完全交由逐元素 version 合并处理。revision 字段仍随更新写入，仅留作调试/审计。
    let incoming_is_blank = Self::is_blank_update_payload(&data_map);

    if matches!(wrapper.r#type.as_str(), "update" | "")
      && incoming_is_blank
      && (data_map.contains_key(Self::ELEMENTS_KEY) || data_map.contains_key(Self::FILES_KEY))
      && !self.is_blank_scene()
    {
      tracing::debug!("[WBCollab] Reject blank whiteboard overwrite against non-empty scene");
      return Ok(());
    }

    let mut txn = self.collab.context.transact_mut();
    match wrapper.r#type.as_str() {
      "update" | "" => {
        for (key, value) in data_map.iter() {
          if key == Self::ELEMENTS_KEY {
            Self::update_elements_map(&self.data, &mut txn, value)?;
          } else if key == Self::FILES_KEY {
            Self::merge_files_map(&self.data, &mut txn, value)?;
          } else {
            let json = serde_json::to_string(value)
              .map_err(|e| anyhow!("Failed to serialize field '{}': {}", key, e))?;
            tracing::trace!(
              "[WBCollab] Inserting key='{}' with value='{}' (type={})",
              key,
              json,
              value.as_str().unwrap_or("non-string")
            );
            if key == "roomId" || key == "roomKey" {
              tracing::debug!("[WBCollab] Saving {} to collab: {}", key, json);
            }
            self.data.insert(&mut txn, key.as_str(), json.as_str());
          }
        }
        // 验证保存后的数据
        if data_map.contains_key("roomId") || data_map.contains_key("roomKey") {
          tracing::debug!("[WBCollab] Verifying roomId/roomKey after insert:");
          if let Some(saved_room_id) = Self::map_string_value(self.data.get(&txn, "roomId"), &txn) {
            tracing::debug!("[WBCollab] Verified roomId: {}", saved_room_id);
          } else {
            tracing::error!("[WBCollab] ❌ roomId not found after insert!");
          }
          if let Some(saved_room_key) = Self::map_string_value(self.data.get(&txn, "roomKey"), &txn)
          {
            tracing::debug!("[WBCollab] Verified roomKey: {}", saved_room_key);
          } else {
            tracing::error!("[WBCollab] ❌ roomKey not found after insert!");
          }
        }
        tracing::trace!("[WBCollab] Stored {} fields from update", data_map.len());
      },
      "replace" => {
        let existing_keys = self
          .data
          .iter(&txn)
          .map(|(key, _)| key.to_string())
          .collect::<Vec<_>>();
        for key in existing_keys {
          self.data.remove(&mut txn, &key);
        }
        for (key, value) in data_map.iter() {
          if key == Self::ELEMENTS_KEY {
            Self::update_elements_map(&self.data, &mut txn, value)?;
          } else if key == Self::FILES_KEY {
            Self::merge_files_map(&self.data, &mut txn, value)?;
          } else {
            let json = serde_json::to_string(value)
              .map_err(|e| anyhow!("Failed to serialize field '{}': {}", key, e))?;
            self.data.insert(&mut txn, key.as_str(), json.as_str());
          }
        }
        tracing::debug!(
          "[WBCollab] Replaced whiteboard with {} fields",
          data_map.len()
        );
      },
      "delete" => {
        for (key, _) in data_map.iter() {
          if key != Self::ELEMENTS_KEY {
            self.data.remove(&mut txn, key.as_str());
          }
        }
        tracing::trace!("[WBCollab] Deleted {} fields", data_map.len());
      },
      unsupported => {
        tracing::error!("[WBCollab] Unknown update type: {}", unsupported);
        return Err(anyhow!("Unknown whiteboard update type: {}", unsupported));
      },
    }

    Ok(())
  }

  /// 获取完整白板数据
  pub fn get_data(&self) -> Result<WhiteboardData, Error> {
    let txn = self.collab.context.transact();

    let mut data_map = HashMap::new();
    for (k, v) in self.data.iter(&txn) {
      let key = k.to_string();
      if key == Self::ELEMENTS_KEY {
        continue;
      }
      let value = Self::map_string_value_to_json(Some(v), &txn);
      if !value.is_null() {
        data_map.insert(key.clone(), value);
        if key == "roomId" || key == "roomKey" {
          tracing::debug!(
            "[WBCollab] Found {} in stored data: {}",
            key,
            data_map[&key]
          );
        }
      } else {
        tracing::warn!("[WBCollab] ⚠️ Value for key '{}' is null", key);
      }
    }

    tracing::debug!("[WBCollab] get_data returning keys: {:?}", data_map.keys());

    let mut elements = Vec::new();
    if let Some(Out::YMap(elements_map)) = self.data.get(&txn, Self::ELEMENTS_KEY) {
      for (_id, value) in elements_map.iter(&txn) {
        let element = Self::map_string_value_to_json(Some(value), &txn);
        if !element.is_null() {
          elements.push(element);
        }
      }
    }
    data_map.insert(
      Self::ELEMENTS_KEY.to_string(),
      serde_json::Value::Array(elements),
    );
    Ok(WhiteboardData(data_map))
  }

  // revision 门控已移除（改用逐元素 version 合并），此读取器暂保留供调试/未来使用。
  #[allow(dead_code)]
  fn stored_revision(&self) -> Option<i64> {
    let txn = self.collab.context.transact();
    self
      .data
      .get(&txn, "revision")
      .and_then(|value| Self::map_string_value_to_json(Some(value), &txn).as_i64())
  }

  fn is_blank_scene(&self) -> bool {
    let txn = self.collab.context.transact();
    let has_elements = matches!(
      self.data.get(&txn, Self::ELEMENTS_KEY),
      Some(Out::YMap(elements_map)) if elements_map.iter(&txn).next().is_some()
    );
    if has_elements {
      return false;
    }

    match self.data.get(&txn, Self::FILES_KEY) {
      Some(Out::Any(Any::String(files_json))) => {
        serde_json::from_str::<serde_json::Value>(&files_json)
          .ok()
          .and_then(|value| value.as_object().map(|object| object.is_empty()))
          .unwrap_or(true)
      },
      _ => true,
    }
  }

  fn is_blank_update_payload(data_map: &HashMap<String, serde_json::Value>) -> bool {
    let elements_blank = data_map
      .get(Self::ELEMENTS_KEY)
      .and_then(|value| value.as_array())
      .map(|elements| elements.is_empty())
      .unwrap_or(true);
    let files_blank = data_map
      .get(Self::FILES_KEY)
      .and_then(|value| value.as_object())
      .map(|files| files.is_empty())
      .unwrap_or(true);
    elements_blank && files_blank
  }

  fn ensure_elements_map(data: &MapRef, txn: &mut collab::preclude::TransactionMut) -> MapRef {
    match data.get(txn, Self::ELEMENTS_KEY) {
      Some(Out::YMap(map)) => map,
      Some(Out::Any(Any::String(elements_json))) => {
        data.remove(txn, Self::ELEMENTS_KEY);
        let map = data.get_or_init_map(txn, Self::ELEMENTS_KEY);
        if let Ok(elements) = serde_json::from_str::<Vec<serde_json::Value>>(&elements_json) {
          for element in elements {
            if let Some(id) = element.get("id").and_then(|value| value.as_str()) {
              if let Ok(json) = serde_json::to_string(&element) {
                map.insert(txn, id, json.as_str());
              }
            }
          }
        }
        map
      },
      _ => data.get_or_init_map(txn, Self::ELEMENTS_KEY),
    }
  }

  fn update_elements_map(
    data: &MapRef,
    txn: &mut collab::preclude::TransactionMut,
    value: &serde_json::Value,
  ) -> Result<(), Error> {
    let Some(incoming) = value.as_array() else {
      return Ok(());
    };

    let elements_map = Self::ensure_elements_map(data, txn);
    for element in incoming {
      let Some(id) = element.get("id").and_then(|value| value.as_str()) else {
        continue;
      };

      let incoming_version = Self::element_version(element);
      let existing_json = Self::map_string_value(elements_map.get(txn, id), txn);
      let existing_version = existing_json
        .as_deref()
        .and_then(|json| serde_json::from_str::<serde_json::Value>(json).ok())
        .as_ref()
        .map(Self::element_version)
        .unwrap_or(-1);

      if incoming_version < existing_version {
        continue;
      }

      let json = serde_json::to_string(element)
        .map_err(|e| anyhow!("Failed to serialize element '{}': {}", id, e))?;
      if existing_json.as_deref() != Some(json.as_str()) {
        elements_map.insert(txn, id, json.as_str());
      }
    }

    Ok(())
  }

  /// 按图片 id 合并 files 表（union），而不是整块覆盖。
  ///
  /// 图片是内容寻址（fileId = 内容 SHA-1）且不可变，因此 union 永远安全：
  /// - 已存在的 id：用新值覆盖（通常带更完整的云 url 元数据）；
  /// - 仅本端有的 id：保留，绝不被陈旧端的全量保存抹掉。
  ///
  /// 这样即便某个端带着旧的 files 快照做全量保存，也不会丢失其他端新加的图片，
  /// 并会在后续保存中收敛到所有端图片的并集。删除图片元素时 Excalidraw 仍保留
  /// 其文件条目（孤儿文件，导出时清理），因此无需通过覆盖来「删」文件。
  fn merge_files_map(
    data: &MapRef,
    txn: &mut collab::preclude::TransactionMut,
    value: &serde_json::Value,
  ) -> Result<(), Error> {
    let Some(incoming) = value.as_object() else {
      return Ok(());
    };
    if incoming.is_empty() {
      // 空表不应清空已有图片
      return Ok(());
    }

    // 读取并解析已有的 files 字符串
    let mut merged = Self::map_string_value(data.get(txn, Self::FILES_KEY), txn)
      .and_then(|json| {
        serde_json::from_str::<serde_json::Map<String, serde_json::Value>>(&json).ok()
      })
      .unwrap_or_default();

    let mut changed = false;
    for (id, file) in incoming.iter() {
      if merged.get(id) != Some(file) {
        merged.insert(id.clone(), file.clone());
        changed = true;
      }
    }

    if !changed {
      return Ok(());
    }

    let json = serde_json::to_string(&serde_json::Value::Object(merged))
      .map_err(|e| anyhow!("Failed to serialize files map: {}", e))?;
    data.insert(txn, Self::FILES_KEY, json.as_str());
    Ok(())
  }

  fn element_version(element: &serde_json::Value) -> i64 {
    element
      .get("version")
      .and_then(|value| value.as_i64())
      .unwrap_or(0)
  }

  fn map_string_value<T: ReadTxn>(value: Option<Out>, txn: &T) -> Option<String> {
    match value {
      Some(Out::Any(Any::String(value))) => Some(value.to_string()),
      Some(Out::YText(value)) => Some(value.get_string(txn)),
      _ => None,
    }
  }

  fn map_string_value_to_json<T: ReadTxn>(value: Option<Out>, txn: &T) -> serde_json::Value {
    if let Some(string_value) = Self::map_string_value(value, txn) {
      if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(&string_value) {
        json_value
      } else {
        serde_json::Value::String(string_value)
      }
    } else {
      serde_json::Value::Null
    }
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
        trace!(
          "[WBCollab] Broadcasting change: key={}, is_remote={}",
          changed.key,
          changed.is_remote
        );
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
  object_id: &str,
  device_id: &str,
  data: Option<WhiteboardData>,
) -> Result<EncodedCollab, Error> {
  tracing::info!(
    "[WBCollab] whiteboard_data_to_encoded_collab: object_id={}, uid={}",
    object_id,
    uid
  );

  if device_id.is_empty() {
    return Err(anyhow!("device_id cannot be empty"));
  }

  let collab = CollabBuilder::new(uid, object_id, DataSource::Disk(None))
    .with_device_id(device_id)
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

  fn test_collab(object_id: &str) -> Collab {
    CollabBuilder::new(1, object_id, DataSource::Disk(None))
      .with_device_id("whiteboard-test-device")
      .build()
      .unwrap()
  }

  #[test]
  fn test_create_empty_whiteboard() {
    let collab = test_collab("2f6baa3b-f8e7-4551-b553-1b7f3802d299");

    let mut whiteboard = Whiteboard::create(collab).unwrap();
    let data = whiteboard.get_data().unwrap();
    assert_eq!(data.0["elements"].as_array().unwrap().len(), 0);

    whiteboard
      .update_from_json(r#"{"type":"update","data":{"appState":{"theme":"light"}}}"#)
      .unwrap();
    whiteboard
      .update_from_json(r#"{"type":"update","data":{"appState":{"theme":"dark"}}}"#)
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    assert_eq!(data.0["appState"]["theme"], "dark");
  }

  #[test]
  fn test_update_and_get_data() {
    let collab = test_collab("test-whiteboard");

    let mut whiteboard = Whiteboard::create(collab).unwrap();

    let test_data = WhiteboardData::default();
    whiteboard.update_from_data(&test_data).unwrap();
    let retrieved_data = whiteboard.get_data().unwrap();
    assert_eq!(retrieved_data.0["elements"].as_array().unwrap().len(), 0);
  }

  #[test]
  fn test_elements_stored_as_nested_map_roundtrip() {
    let collab = test_collab("wb-nested");
    let mut whiteboard = Whiteboard::create(collab).unwrap();

    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"elements":[
          {"id":"a","type":"rectangle","version":1},
          {"id":"b","type":"ellipse","version":1}
        ]}}"#,
      )
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    let elements = data.0["elements"].as_array().unwrap();
    let ids: Vec<&str> = elements
      .iter()
      .filter_map(|element| element["id"].as_str())
      .collect();
    assert_eq!(elements.len(), 2);
    assert!(ids.contains(&"a"));
    assert!(ids.contains(&"b"));
  }

  #[test]
  fn test_lower_version_does_not_overwrite() {
    let collab = test_collab("wb-version");
    let mut whiteboard = Whiteboard::create(collab).unwrap();

    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"elements":[{"id":"a","type":"rectangle","version":5}]}}"#,
      )
      .unwrap();
    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"elements":[{"id":"a","type":"rectangle","version":3}]}}"#,
      )
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    let elements = data.0["elements"].as_array().unwrap();
    let element = elements
      .iter()
      .find(|element| element["id"] == "a")
      .unwrap();
    assert_eq!(element["version"], 5);
  }

  #[test]
  fn test_deleted_tombstone_overwrites_visible_element() {
    let collab = test_collab("wb-delete");
    let mut whiteboard = Whiteboard::create(collab).unwrap();

    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"elements":[{"id":"a","type":"rectangle","version":1}]}}"#,
      )
      .unwrap();
    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"elements":[{"id":"a","type":"rectangle","version":2,"isDeleted":true}]}}"#,
      )
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    let elements = data.0["elements"].as_array().unwrap();
    let element = elements
      .iter()
      .find(|element| element["id"] == "a")
      .unwrap();
    assert_eq!(element["version"], 2);
    assert_eq!(element["isDeleted"], true);
  }

  #[test]
  fn test_files_union_merge_does_not_drop_existing_images() {
    let collab = test_collab("wb-files-merge");
    let mut whiteboard = Whiteboard::create(collab).unwrap();

    // 端 A 添加图片 imgA
    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"files":{"imgA":{"id":"imgA","url":"http://h/blob/a","mimeType":"image/png"}}}}"#,
      )
      .unwrap();

    // 端 B 带着只含 imgB 的陈旧/局部快照做全量保存（旧代码会整块覆盖丢掉 imgA）
    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"files":{"imgB":{"id":"imgB","url":"http://h/blob/b","mimeType":"image/png"}}}}"#,
      )
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    let files = data.0["files"].as_object().unwrap();
    assert!(files.contains_key("imgA"), "imgA must survive union-merge");
    assert!(files.contains_key("imgB"), "imgB must be present");

    // 空 files 表不应清空已有图片
    whiteboard
      .update_from_json(r#"{"type":"update","data":{"files":{}}}"#)
      .unwrap();
    let data = whiteboard.get_data().unwrap();
    let files = data.0["files"].as_object().unwrap();
    assert!(files.contains_key("imgA"));
    assert!(files.contains_key("imgB"));
  }

  #[test]
  fn test_replace_removes_stale_scene_data() {
    let collab = test_collab("wb-replace");
    let mut whiteboard = Whiteboard::create(collab).unwrap();

    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"roomId":"old-room","elements":[{"id":"old","version":9}],"files":{"old-file":{"id":"old-file"}}}}"#,
      )
      .unwrap();
    whiteboard
      .update_from_json(
        r#"{"type":"replace","data":{"elements":[{"id":"new","version":1}],"files":{},"appState":{}}}"#,
      )
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    let elements = data.0["elements"].as_array().unwrap();
    assert_eq!(elements.len(), 1);
    assert_eq!(elements[0]["id"], "new");
    assert!(data.0.get("roomId").is_none());
    assert!(data
      .0
      .get("files")
      .and_then(|files| files.as_object())
      .is_none_or(|files| files.is_empty()));

    whiteboard
      .update_from_json(r#"{"type":"replace","data":{"elements":[],"files":{}}}"#)
      .unwrap();
    assert!(whiteboard.get_data().unwrap().0["elements"]
      .as_array()
      .unwrap()
      .is_empty());
  }

  #[test]
  fn test_unknown_update_type_returns_error() {
    let collab = test_collab("wb-unknown-update");
    let mut whiteboard = Whiteboard::create(collab).unwrap();

    let error = whiteboard
      .update_from_json(r#"{"type":"unsupported","data":{"elements":[]}}"#)
      .unwrap_err();

    assert!(error
      .to_string()
      .contains("Unknown whiteboard update type: unsupported"));
  }

  #[test]
  fn test_observe_emits_element_value() {
    let collab = test_collab("wb-notify");
    let mut whiteboard = Whiteboard::open(collab).unwrap();
    let mut rx = whiteboard.subscribe_changed();

    whiteboard
      .update_from_json(
        r#"{"type":"update","data":{"elements":[{"id":"a","type":"rectangle","version":1}]}}"#,
      )
      .unwrap();

    let changed = rx.try_recv().expect("should receive element change");
    let payload: serde_json::Value = serde_json::from_str(&changed.value).unwrap();
    assert_eq!(payload["key"], "elements");
    let first = &payload["value"]["changed"][0];
    assert_eq!(first["id"], "a");
    assert_eq!(first["element"]["version"], 1);
  }
}
