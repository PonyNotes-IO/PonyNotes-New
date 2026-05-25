use crate::saber::{sbn2_to_encoded_collab, HandwritingSaber};
use collab::core::collab::DataSource;
use collab::core::collab_plugin::CollabPersistence;
use collab::entity::EncodedCollab;
use collab::lock::RwLock;
use collab_entity::CollabType;
use collab_integrate::collab_builder::{
  AppFlowyCollabBuilder, CollabBuilderConfig, CollabPersistenceImpl,
};
use collab_integrate::CollabKVAction;
use collab_plugins::local_storage::kv::KVTransactionDB;
use collab_plugins::CollabKVDB;
use dashmap::DashMap;
use flowy_error::{internal_error, ErrorCode, FlowyError, FlowyResult};
use flowy_handwriting_saber_pub::cloud::HandwritingSaberCloudService;
use std::sync::{Arc, Weak};
use tracing::{error, info, trace};
use uuid::Uuid;

/// 手写笔记用户服务 trait
pub trait HandwritingSaberUserService: Send + Sync {
  fn user_id(&self) -> Result<i64, FlowyError>;
  fn device_id(&self) -> Result<String, FlowyError>;
  fn workspace_id(&self) -> Result<Uuid, FlowyError>;
  fn collab_db(&self, uid: i64) -> Result<Weak<CollabKVDB>, FlowyError>;
}

/// 手写笔记管理器
/// 负责手写笔记的创建、打开、更新和关闭
/// 使用 Collab 存储 .sbn2 数据（base64 编码），通过 WebSocket 实现实时同步
pub struct HandwritingSaberManager {
  user_service: Arc<dyn HandwritingSaberUserService>,
  collab_builder: Weak<AppFlowyCollabBuilder>,
  cloud_service: Arc<dyn HandwritingSaberCloudService>,
  /// 已打开的手写笔记缓存
  handwriting_sabers: Arc<DashMap<Uuid, Arc<RwLock<HandwritingSaber>>>>,
}

impl Drop for HandwritingSaberManager {
  fn drop(&mut self) {
    trace!("[Drop] drop handwriting saber manager");
  }
}

impl HandwritingSaberManager {
  pub fn new(
    user_service: Arc<dyn HandwritingSaberUserService>,
    collab_builder: Weak<AppFlowyCollabBuilder>,
    cloud_service: Arc<dyn HandwritingSaberCloudService>,
  ) -> Self {
    Self {
      user_service,
      collab_builder,
      cloud_service,
      handwriting_sabers: Arc::new(Default::default()),
    }
  }

  fn collab_builder(&self) -> FlowyResult<Arc<AppFlowyCollabBuilder>> {
    self
      .collab_builder
      .upgrade()
      .ok_or_else(FlowyError::ref_drop)
  }

  fn persistence(&self) -> FlowyResult<CollabPersistenceImpl> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let db = self.user_service.collab_db(uid)?;
    Ok(CollabPersistenceImpl::new(db, uid, workspace_id))
  }

  /// 初始化
  pub async fn initialize(&self, _uid: i64) -> FlowyResult<()> {
    trace!("[HandwritingSaber] initialize manager");
    self.handwriting_sabers.clear();
    Ok(())
  }

  pub async fn initialize_after_sign_in(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await
  }

  pub async fn initialize_after_sign_up(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await
  }

  pub async fn initialize_after_open_workspace(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await
  }

  /// 创建新手写笔记
  pub async fn create_handwriting_saber(
    &self,
    view_id: &Uuid,
    initial_data: Option<Vec<u8>>,
  ) -> FlowyResult<EncodedCollab> {
    info!("[HandwritingSaber] 🔵 create_handwriting_saber: {}", view_id);

    if self.is_handwriting_saber_exist(view_id).await.unwrap_or(false) {
      info!("[HandwritingSaber] ⚠️ Already exists: {}", view_id);
      return Err(FlowyError::new(
        ErrorCode::RecordAlreadyExists,
        format!("handwriting saber {} already exists", view_id),
      ));
    }

    let uid = self.user_service.user_id()?;
    let device_id = self.user_service.device_id()?;
    let encoded_collab =
      sbn2_to_encoded_collab(uid, &view_id.to_string(), &device_id, initial_data)
        .map_err(internal_error)?;

    // 保存到磁盘
    let persistence = self.persistence()?;
    persistence
      .save_collab_to_disk(&view_id.to_string(), encoded_collab.clone())
      .map_err(internal_error)?;

    // 上传到云端（后台任务）
    let cloud_service = self.cloud_service.clone();
    let cloned_encoded = encoded_collab.clone();
    let workspace_id = self.user_service.workspace_id()?;
    let saber_id = *view_id;
    tokio::spawn(async move {
      match cloud_service
        .create_handwriting_saber_collab(&workspace_id, &saber_id, cloned_encoded)
        .await
      {
        Ok(_) => info!("[HandwritingSaber] ✅ Uploaded to cloud: {}", saber_id),
        Err(e) => error!(
          "[HandwritingSaber] ❌ Failed to upload to cloud: {}, error: {}",
          saber_id, e
        ),
      }
    });

    info!("[HandwritingSaber] ✅ Created: {}", view_id);
    Ok(encoded_collab)
  }

  /// 打开手写笔记
  pub async fn open_handwriting_saber(
    &self,
    view_id: &Uuid,
  ) -> FlowyResult<Arc<RwLock<HandwritingSaber>>> {
    info!("[HandwritingSaber] 🔵 open_handwriting_saber: {}", view_id);

    if let Some(saber) = self.handwriting_sabers.get(view_id) {
      trace!("[HandwritingSaber] Found in cache: {}", view_id);
      return Ok(saber.clone());
    }

    let saber = self.create_saber_instance(view_id, true).await?;
    self.handwriting_sabers.insert(*view_id, saber.clone());

    info!("[HandwritingSaber] ✅ Opened: {}", view_id);
    Ok(saber)
  }

  /// 获取手写笔记数据（.sbn2 字节）
  pub async fn get_handwriting_saber_data(&self, view_id: &Uuid) -> FlowyResult<Vec<u8>> {
    info!("[HandwritingSaber] 🔵 get_handwriting_saber_data: {}", view_id);
    let saber = self.open_handwriting_saber(view_id).await?;
    let saber_read = saber.read().await;
    saber_read
      .get_sbn2_data()
      .map_err(|e| internal_error(format!("Failed to get sbn2 data: {}", e)))
  }

  /// 保存手写笔记数据
  pub async fn save_handwriting_saber_data(
    &self,
    view_id: &Uuid,
    sbn2_bytes: Vec<u8>,
    version: i64,
  ) -> FlowyResult<i64> {
    info!(
      "[HandwritingSaber] 🔵 save_handwriting_saber_data: {}, size: {} bytes, version: {}",
      view_id,
      sbn2_bytes.len(),
      version
    );

    let saber = self.open_handwriting_saber(view_id).await?;
    let new_version = version + 1;

    {
      let mut saber_write = saber.write().await;
      saber_write
        .update_sbn2_data(sbn2_bytes, new_version)
        .map_err(|e| internal_error(format!("Failed to update sbn2 data: {}", e)))?;
    }

    info!(
      "[HandwritingSaber] ✅ Saved, new version: {}",
      new_version
    );
    Ok(new_version)
  }

  /// 关闭手写笔记（从内存中移除）
  pub async fn close_handwriting_saber(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[HandwritingSaber] 🔵 close_handwriting_saber: {}", view_id);
    self.handwriting_sabers.remove(view_id);
    Ok(())
  }

  /// 删除手写笔记
  pub async fn delete_handwriting_saber(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[HandwritingSaber] 🔵 delete_handwriting_saber: {}", view_id);
    self.handwriting_sabers.remove(view_id);

    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    if let Some(db) = collab_db.upgrade() {
      let write_txn = db.write_txn();
      write_txn
        .delete_doc(uid, &workspace_id.to_string(), &view_id.to_string())
        .map_err(internal_error)?;
      write_txn.commit_transaction().map_err(internal_error)?;
    }

    info!("[HandwritingSaber] ✅ Deleted: {}", view_id);
    Ok(())
  }

  /// 创建手写笔记实例（内部方法）
  async fn create_saber_instance(
    &self,
    view_id: &Uuid,
    sync_enable: bool,
  ) -> FlowyResult<Arc<RwLock<HandwritingSaber>>> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let collab_builder = self.collab_builder()?;
    let object = collab_builder
      .collab_object(&workspace_id, uid, view_id, CollabType::Document)
      .map_err(internal_error)?;

    let exists = self.is_handwriting_saber_exist(view_id).await.unwrap_or(false);
    info!(
      "[HandwritingSaber] Exists on disk: {} for view: {}",
      exists, view_id
    );

    let data_source = if exists {
      CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source()
    } else {
      info!(
        "[HandwritingSaber] Not found locally, trying cloud for: {}",
        view_id
      );
      match self
        .cloud_service
        .get_handwriting_saber_doc_state(view_id, &workspace_id)
        .await
      {
        Ok(doc_state) if !doc_state.is_empty() => {
          info!(
            "[HandwritingSaber] ✅ Got doc_state from cloud for: {}",
            view_id
          );
          DataSource::DocStateV1(doc_state)
        },
        _ => {
          info!(
            "[HandwritingSaber] Cloud empty or error, creating new for: {}",
            view_id
          );
          DataSource::Disk(None)
        },
      }
    };

    let collab = self.build_collab(uid, view_id, data_source).await?;

    let saber = match HandwritingSaber::open(collab) {
      Ok(s) => {
        info!("[HandwritingSaber] ✅ Opened existing: {}", view_id);
        s
      },
      Err(e) => {
        info!(
          "[HandwritingSaber] ⚠️ Failed to open ({}), creating new: {}",
          e, view_id
        );
        let data_source = if exists {
          CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source()
        } else {
          DataSource::Disk(None)
        };
        let collab = self.build_collab(uid, view_id, data_source).await?;
        let s = HandwritingSaber::create(collab)
          .map_err(|e| internal_error(format!("Failed to create saber: {}", e)))?;

        let encoded = s.encode_collab().map_err(internal_error)?;
        self
          .persistence()?
          .save_collab_to_disk(&view_id.to_string(), encoded)
          .map_err(internal_error)?;

        info!(
          "[HandwritingSaber] ✅ Initialized and saved new saber: {}",
          view_id
        );
        s
      },
    };

    let arc_saber = Arc::new(RwLock::new(saber));

    // ✅ 关键：调用 finalize() 添加 WebSocket 云端实时同步插件
    let builder_config = CollabBuilderConfig::default().sync_enable(sync_enable);
    let arc_saber = collab_builder
      .finalize(object, builder_config, arc_saber)
      .map_err(internal_error)?;

    info!(
      "[HandwritingSaber] ✅ Finalized with sync_enable={}: {}",
      sync_enable, view_id
    );
    Ok(arc_saber)
  }

  /// 构建带 RocksDB 插件的 Collab（不 initialize，由 finalize 统一处理）
  async fn build_collab(
    &self,
    uid: i64,
    view_id: &Uuid,
    data_source: DataSource,
  ) -> FlowyResult<collab::preclude::Collab> {
    let collab_builder = self.collab_builder()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let object = collab_builder
      .collab_object(&workspace_id, uid, view_id, CollabType::Document)
      .map_err(internal_error)?;

    collab_builder
      .build_collab(&object, &collab_db, data_source)
      .await
      .map_err(internal_error)
  }

  /// 获取编码的 Collab 数据（只读，不需要同步）
  pub async fn get_encoded_collab(&self, view_id: &Uuid) -> FlowyResult<EncodedCollab> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let data_source =
      CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source();

    let mut collab = self.build_collab(uid, view_id, data_source).await?;
    collab.initialize();

    collab
      .encode_collab_v1(|_| Ok::<(), collab::error::CollabError>(()))
      .map_err(internal_error)
  }

  /// 检查手写笔记是否存在于本地磁盘
  async fn is_handwriting_saber_exist(&self, view_id: &Uuid) -> FlowyResult<bool> {
    if self.handwriting_sabers.contains_key(view_id) {
      return Ok(true);
    }

    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    if let Some(db) = collab_db.upgrade() {
      let read_txn = db.read_txn();
      let exists = read_txn.is_exist(uid, &workspace_id.to_string(), &view_id.to_string());
      return Ok(exists);
    }

    Ok(false)
  }
}
