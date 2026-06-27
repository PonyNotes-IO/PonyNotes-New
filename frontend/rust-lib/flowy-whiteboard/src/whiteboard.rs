use crate::entities::WhiteboardData;
use crate::notification::{whiteboard_notification_send_json, WhiteboardNotification};
use anyhow::{anyhow, Error};
use collab::core::collab::DataSource;
use collab::preclude::{Collab, CollabBuilder, DeepObservable, Map, MapRef};
use collab::preclude::Subscription;
use collab::preclude::Event;
use collab::util::MapExt;
use collab_entity::EncodedCollab;
use collab_entity::define::DOCUMENT_ROOT;

use std::borrow::BorrowMut;
use std::collections::HashMap;
use tokio::sync::broadcast;
use tokio::time::{Duration, Instant};
use tracing::info;

/// Large data threshold: 50KB
const LARGE_DATA_THRESHOLD: usize = 50 * 1024;

/// Debounce duration for local changes: 100ms
const DEBOUNCE_DURATION: Duration = Duration::from_millis(100);

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
      _subscription: None,
    })
  }

  /// 从现有 Collab 对象打开白板
  ///
  /// 通过 yrs 原生的 observe_deep 监听所有 collab 变更，
  /// 在变更发生时通过事务是否有 origin 来区分本地/远程。
  pub fn open(collab: Collab) -> Result<Self, Error> {
    let txn = collab.context.transact();
    let data: MapRef = collab
      .data
      .get_with_txn(&txn, Self::DATA_KEY)
      .ok_or_else(|| anyhow!("Whiteboard data not found"))?;
    drop(txn);

    let (notifier, _) = broadcast::channel(100);

    let data_clone = data.clone();
    let notifier_clone = notifier.clone();

    // observe_deep 回调签名：(txn, events)
    // 有 origin 的事务是远程推送的变更
    let subscription = data.observe_deep(move |txn, events| {
      for event in events.iter() {
        // 通过事务是否有 origin 来判断是否为远程变更
        // 有 origin -> 远程变更（云端推送）
        // 无 origin -> 本地变更
        let origin = txn.origin();
        let is_remote = origin.is_some();

        // 匹配 Event::Map 事件并获取键变更
        if let Event::Map(map_event) = event {
          let key_changes = map_event.keys(txn);
          for (key, change) in key_changes.iter() {
            let key_str = key.to_string();

            // Read the actual value from the data map.
            // If the key was deleted, get() returns None.
            let actual_value = data_clone.get(txn, key_str.as_str());
            let (value_json, is_large) = match actual_value {
              Some(v) => {
                let s = v.to_string(txn);
                let size = s.len();
                // For large payloads on "elements", signal Dart to fetch via RPC.
                if size > LARGE_DATA_THRESHOLD && key_str == "elements" {
                  (serde_json::Value::Null, true)
                } else {
                  let parsed = serde_json::from_str::<serde_json::Value>(&s)
                    .unwrap_or(serde_json::Value::String(s));
                  (parsed, false)
                }
              }
              // Key was removed or has no value
              None => (serde_json::Value::Null, false),
            };

            let mut event_json = serde_json::json!({
              "key": key_str,
              "value": value_json,
              "is_remote": is_remote,
            });

            if is_large {
              event_json["large_data"] = serde_json::Value::Bool(true);
            }

            let event_json_str = event_json.to_string();

            info!(
              "[WBCollab] observe_deep: key={}, is_remote={}, change={:?}, large_data={}",
              key_str, is_remote, change, is_large
            );

            let changed = WhiteboardChanged {
              key: key_str,
              value: event_json_str,
              is_remote,
            };
            let _ = notifier_clone.send(changed);
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
      self.data.insert(&mut txn, k.as_str(), v.as_str());
    }

    tracing::trace!("[WBCollab] Data updated successfully and transaction committed");
    Ok(())
  }

  /// 从完整的 Excalidraw JSON 更新
  pub fn update_from_json(&mut self, json_str: &str) -> Result<(), Error> {
    tracing::trace!("[WBCollab] update_from_json called, len: {}", json_str.len());

    #[derive(serde::Deserialize)]
    struct UpdateWrapper {
      #[serde(default)]
      r#type: String,
      #[serde(default)]
      data: serde_json::Value,
    }

    let wrapper: UpdateWrapper = serde_json::from_str(json_str)
      .map_err(|e| anyhow!("Failed to parse wrapper JSON: {}", e))?;

    let data_map: HashMap<String, serde_json::Value> = match wrapper.data {
      serde_json::Value::String(data_str) => {
        serde_json::from_str(&data_str)
          .map_err(|e| anyhow!("Failed to parse nested data JSON: {}", e))?
      },
      serde_json::Value::Object(map) => map.into_iter().collect(),
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
        tracing::trace!("[WBCollab] Stored {} fields from update", data_map.len());
      },
      "delete" => {
        for (key, _) in data_map.iter() {
          self.data.remove(&mut txn, key.as_str());
        }
        tracing::trace!("[WBCollab] Deleted {} fields", data_map.len());
      },
      _ => {
        tracing::warn!("[WBCollab] Unknown update type: {}", wrapper.r#type);
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

  /// 获取变更通知的 receiver（用于 subscribe_changed）
  pub fn subscribe_changed(&self) -> broadcast::Receiver<WhiteboardChanged> {
    self.notifier.subscribe()
  }
  /// 启动监听任务：在 tokio spawn 中监听 channel，收到变更后发给 Dart
  ///
  /// Debounce strategy:
  /// - Remote changes (is_remote=true) and appState changes are forwarded immediately.
  /// - Local changes are debounced per-key: after 100ms of no new changes for a given key,
  ///   the latest value is flushed as a single notification.
  pub fn start_change_listener(&self) {
    let view_id = self.object_id();
    let mut rx = self.subscribe_changed();

    tokio::spawn(async move {
      // Per-key buffer: key -> latest pending change
      let mut buffer: HashMap<String, WhiteboardChanged> = HashMap::new();
      // Per-key deadline: key -> when to flush
      let mut deadlines: HashMap<String, Instant> = HashMap::new();

      loop {
        // Compute the soonest deadline from all buffered keys
        let next_deadline = deadlines.values().min().copied();

        tokio::select! {
          biased;

          result = rx.recv() => {
            match result {
              Ok(changed) => {
                if changed.is_remote || changed.key == "appState" {
                  // Remote or appState changes: forward immediately.
                  // Flush any buffered local change for the same key first.
                  if let Some(buf) = buffer.remove(&changed.key) {
                    deadlines.remove(&changed.key);
                    info!(
                      "[WBCollab] Flushing buffered change before remote: key={}",
                      buf.key
                    );
                    Self::send_notification(&view_id, &buf);
                  }
                  Self::send_notification(&view_id, &changed);
                } else {
                  // Local non-appState change: debounce per-key.
                  // Each new change resets the deadline for that key.
                  let key = changed.key.clone();
                  buffer.insert(key.clone(), changed);
                  deadlines.insert(key, Instant::now() + DEBOUNCE_DURATION);
                }
              }
              Err(broadcast::error::RecvError::Lagged(n)) => {
                tracing::warn!("[WBCollab] Listener lagged by {} messages", n);
              }
              Err(broadcast::error::RecvError::Closed) => {
                // Channel closed; flush remaining buffered changes
                for (_, changed) in buffer.drain() {
                  Self::send_notification(&view_id, &changed);
                }
                break;
              }
            }
          }

          _ = async {
            match next_deadline {
              Some(dl) => tokio::time::sleep_until(dl).await,
              // No pending changes: park until a new message arrives
              None => std::future::pending::<()>().await,
            }
          } => {
            // Flush all keys whose debounce deadline has passed
            let now = Instant::now();
            let expired_keys: Vec<String> = deadlines
              .iter()
              .filter(|(_, &dl)| now >= dl)
              .map(|(k, _)| k.clone())
              .collect();

            for key in expired_keys {
              deadlines.remove(&key);
              if let Some(changed) = buffer.remove(&key) {
                info!(
                  "[WBCollab] Debounced flush: key={}, is_remote={}",
                  changed.key, changed.is_remote
                );
                Self::send_notification(&view_id, &changed);
              }
            }
          }
        }
      }
    });
  }

  /// Send a single change notification to Dart.
  fn send_notification(view_id: &str, changed: &WhiteboardChanged) {
    info!(
      "[WBCollab] Broadcasting change: key={}, is_remote={}",
      changed.key, changed.is_remote
    );
    whiteboard_notification_send_json(
      view_id.to_string(),
      WhiteboardNotification::DidReceiveUpdate,
      changed.value.clone(),
    );
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
    object_id, uid
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
      .update_from_json(r#"{"type": "update", "data": {"key1": "value1"}}"#)
      .unwrap();
    whiteboard
      .update_from_json(r#"{"type": "update", "data": {"key1": "value2"}}"#)
      .unwrap();

    let data = whiteboard.get_data().unwrap();
    dbg!(data);
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
    assert_eq!(retrieved_data.0.len(), test_data.0.len());
  }
}
