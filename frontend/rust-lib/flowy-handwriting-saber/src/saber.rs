use anyhow::{anyhow, Error};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use collab::core::collab::DataSource;
use collab::preclude::{Collab, CollabBuilder, Map, MapRef};
use collab::util::MapExt;
use collab_entity::EncodedCollab;
use collab_entity::define::DOCUMENT_ROOT;
use std::borrow::BorrowMut;
use tracing::trace;

/// 手写笔记 Collab 对象
/// 使用 CRDT (Yrs) 存储 .sbn2 二进制数据（base64 编码）
pub struct HandwritingSaber {
  collab: Collab,
  data: MapRef,
}

impl HandwritingSaber {
  const DATA_KEY: &'static str = "data";
  const SBN2_FIELD: &'static str = "sbn2_data";
  const VERSION_FIELD: &'static str = "version";

  /// 创建新手写笔记（空数据）
  pub fn create(mut collab: Collab) -> Result<Self, Error> {
    let mut txn = collab.context.transact_mut();
    // 初始化 Document 根节点（确保 RocksDB 插件能正确验证数据）
    let _document_root = collab.data.get_or_init_map(&mut txn, DOCUMENT_ROOT);
    // 初始化数据 Map
    let data = collab.data.get_or_init_map(&mut txn, Self::DATA_KEY);
    // 初始化版本号为 0
    data.insert(&mut txn, Self::VERSION_FIELD, "0");
    drop(txn);
    Ok(Self { collab, data })
  }

  /// 从现有 Collab 打开手写笔记
  pub fn open(collab: Collab) -> Result<Self, Error> {
    let txn = collab.context.transact();
    let data = collab
      .data
      .get_with_txn(&txn, Self::DATA_KEY)
      .ok_or_else(|| anyhow!("HandwritingSaber data not found"))?;
    drop(txn);
    Ok(Self { collab, data })
  }

  /// 创建带初始数据的手写笔记
  pub fn create_with_data(collab: Collab, sbn2_bytes: Vec<u8>) -> Result<Self, Error> {
    let mut saber = Self::create(collab)?;
    saber.update_sbn2_data(sbn2_bytes, 1)?;
    Ok(saber)
  }

  /// 更新 .sbn2 数据（版本号自动递增）
  pub fn update_sbn2_data(&mut self, sbn2_bytes: Vec<u8>, version: i64) -> Result<(), Error> {
    let base64_data = BASE64.encode(&sbn2_bytes);
    let mut txn = self.collab.context.transact_mut();
    self
      .data
      .insert(&mut txn, Self::SBN2_FIELD, base64_data.as_str());
    self
      .data
      .insert(&mut txn, Self::VERSION_FIELD, version.to_string().as_str());
    trace!(
      "[HandwritingSaber] Updated sbn2 data: {} bytes (base64: {} chars), version: {}",
      sbn2_bytes.len(),
      base64_data.len(),
      version
    );
    Ok(())
  }

  fn get_str_field_read(data: &MapRef, txn: &collab::preclude::Transaction, key: &str) -> String {
    for (k, v) in data.iter(txn) {
      if k == key {
        return v.to_string(txn);
      }
    }
    String::new()
  }

  /// 获取 .sbn2 数据
  pub fn get_sbn2_data(&self) -> Result<Vec<u8>, Error> {
    let txn = self.collab.context.transact();
    let base64_data = Self::get_str_field_read(&self.data, &txn, Self::SBN2_FIELD);

    if base64_data.is_empty() {
      return Ok(Vec::new());
    }

    BASE64
      .decode(&base64_data)
      .map_err(|e| anyhow!("Failed to decode base64 sbn2 data: {}", e))
  }

  /// 获取版本号
  pub fn get_version(&self) -> i64 {
    let txn = self.collab.context.transact();
    let version_str = Self::get_str_field_read(&self.data, &txn, Self::VERSION_FIELD);
    version_str.parse::<i64>().unwrap_or(0)
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

  /// 获取底层 Collab 引用
  pub fn get_collab(&self) -> &Collab {
    &self.collab
  }
}

impl BorrowMut<Collab> for HandwritingSaber {
  fn borrow_mut(&mut self) -> &mut Collab {
    &mut self.collab
  }
}

impl std::borrow::Borrow<Collab> for HandwritingSaber {
  fn borrow(&self) -> &Collab {
    &self.collab
  }
}

/// 从 sbn2_bytes 创建 EncodedCollab
pub fn sbn2_to_encoded_collab(
  uid: i64,
  object_id: &str,
  device_id: &str,
  sbn2_bytes: Option<Vec<u8>>,
) -> Result<EncodedCollab, Error> {
  tracing::info!(
    "[HandwritingSaber] sbn2_to_encoded_collab called for object_id: {}",
    object_id
  );

  if device_id.is_empty() {
    return Err(anyhow!("device_id cannot be empty"));
  }

  let collab = CollabBuilder::new(uid, object_id, DataSource::Disk(None))
    .with_device_id(device_id)
    .build()
    .map_err(|e| anyhow!("Failed to create collab: {}", e))?;

  let saber = match sbn2_bytes {
    Some(bytes) if !bytes.is_empty() => HandwritingSaber::create_with_data(collab, bytes)?,
    _ => HandwritingSaber::create(collab)?,
  };

  let encoded = saber.encode_collab()?;
  tracing::info!(
    "[HandwritingSaber] ✅ Encoded collab for object_id: {}",
    object_id
  );
  Ok(encoded)
}
