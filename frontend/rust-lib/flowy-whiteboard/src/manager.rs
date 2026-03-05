use crate::entities::WhiteboardData;
use crate::whiteboard::{whiteboard_data_to_encoded_collab, Whiteboard};
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
use flowy_whiteboard_pub::cloud::WhiteboardCloudService;
use std::sync::{Arc, Weak};
use tracing::{error, info, trace};
use uuid::Uuid;

/// 白板用户服务 trait
pub trait WhiteboardUserService: Send + Sync {
  fn user_id(&self) -> Result<i64, FlowyError>;
  fn device_id(&self) -> Result<String, FlowyError>;
  fn workspace_id(&self) -> Result<Uuid, FlowyError>;
  fn collab_db(&self, uid: i64) -> Result<Weak<CollabKVDB>, FlowyError>;
}

/// 白板管理器
/// 负责白板的创建、打开、更新和关闭
pub struct WhiteboardManager {
  user_service: Arc<dyn WhiteboardUserService>,
  collab_builder: Weak<AppFlowyCollabBuilder>,
  cloud_service: Arc<dyn WhiteboardCloudService>,
  /// 已打开的白板缓存
  whiteboards: Arc<DashMap<Uuid, Arc<RwLock<Whiteboard>>>>,
}

impl Drop for WhiteboardManager {
  fn drop(&mut self) {
    trace!("[Drop] drop whiteboard manager");
  }
}

impl WhiteboardManager {
  pub fn new(
    user_service: Arc<dyn WhiteboardUserService>,
    collab_builder: Weak<AppFlowyCollabBuilder>,
    cloud_service: Arc<dyn WhiteboardCloudService>,
  ) -> Self {
    Self {
      user_service,
      collab_builder,
      cloud_service,
      whiteboards: Arc::new(Default::default()),
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
    trace!("[Whiteboard] initialize whiteboard manager");
    self.whiteboards.clear();
    Ok(())
  }

  /// 用户登录后初始化
  pub async fn initialize_after_sign_in(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await?;
    Ok(())
  }

  /// 用户注册后初始化
  pub async fn initialize_after_sign_up(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await?;
    Ok(())
  }

  /// 打开工作空间后初始化
  pub async fn initialize_after_open_workspace(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await?;
    Ok(())
  }

  /// 创建新白板
  ///
  /// 如果白板已存在，返回错误
  /// 如果 data 为 None，将创建空白板
  pub async fn create_whiteboard(
    &self,
    view_id: &Uuid,
    data: Option<WhiteboardData>,
  ) -> FlowyResult<EncodedCollab> {
    info!("[Whiteboard] 🔵 create_whiteboard called for view: {}", view_id);
    
    // 检查是否已存在
    info!("[Whiteboard] 🔵 Checking if whiteboard exists: {}", view_id);
    if self.is_whiteboard_exist(view_id).await.unwrap_or(false) {
      info!("[Whiteboard] ⚠️ Whiteboard already exists: {}", view_id);
      return Err(FlowyError::new(
        ErrorCode::RecordAlreadyExists,
        format!("whiteboard {} already exists", view_id),
      ));
    }
    info!("[Whiteboard] ✅ Whiteboard does not exist, proceeding with creation: {}", view_id);

    // 创建 EncodedCollab
    info!("[Whiteboard] 🔵 Creating EncodedCollab for view: {}", view_id);
    let uid = self.user_service.user_id()?;
    let device_id = self.user_service.device_id()?;
    info!("[Whiteboard] 🔵 Got uid: {}, device_id: {}", uid, device_id);
    let encoded_collab =
      whiteboard_data_to_encoded_collab(uid, &view_id.to_string(), &device_id, data)?;
    info!("[Whiteboard] ✅ EncodedCollab created for view: {}", view_id);

    // 保存到磁盘
    info!("[Whiteboard] 🔵 Getting persistence for view: {}", view_id);
    let persistence = match self.persistence() {
      Ok(p) => {
        info!("[Whiteboard] ✅ Got persistence for view: {}", view_id);
        p
      },
      Err(e) => {
        error!("[Whiteboard] ❌ Failed to get persistence for view: {}, error: {}", view_id, e);
        return Err(e);
      }
    };
    
    info!("[Whiteboard] 🔵 Saving to disk for view: {}", view_id);
    persistence
      .save_collab_to_disk(&view_id.to_string(), encoded_collab.clone())
      .map_err(|e| {
        error!("[Whiteboard] ❌ Failed to save to disk for view: {}, error: {}", view_id, e);
        internal_error(e)
      })?;

    // Send the collab data to server with a background task.
    let cloud_service = self.cloud_service.clone();
    let cloned_encoded_collab = encoded_collab.clone();
    let workspace_id = self.user_service.workspace_id()?;
    let whiteboard_id = *view_id;
    tokio::spawn(async move {
      info!("[Whiteboard] 🔵 Uploading to cloud for whiteboard: {}", whiteboard_id);
      let result = cloud_service
        .create_whiteboard_collab(&workspace_id, &whiteboard_id, cloned_encoded_collab)
        .await;
      match result {
        Ok(_) => info!("[Whiteboard] ✅ Successfully uploaded to cloud: {}", whiteboard_id),
        Err(e) => error!("[Whiteboard] ❌ Failed to upload to cloud: {}, error: {}", whiteboard_id, e),
      }
    });

    info!("[Whiteboard] ✅ Created and saved whiteboard: {}", view_id);
    Ok(encoded_collab)
  }

  /// 打开白板
  ///
  /// 如果白板已在缓存中，直接返回
  /// 否则从磁盘加载，如果本地不存在则尝试从云端获取
  pub async fn open_whiteboard(&self, view_id: &Uuid) -> FlowyResult<Arc<RwLock<Whiteboard>>> {
    info!("[Whiteboard] 🔵 open_whiteboard called for view: {}", view_id);
    
    // 检查缓存
    if let Some(whiteboard) = self.whiteboards.get(view_id) {
      trace!("[Whiteboard] Whiteboard {} found in cache", view_id);
      return Ok(whiteboard.clone());
    }

    // 创建白板实例（会自动配置持久化）
    let whiteboard = self.create_whiteboard_instance(view_id, true).await?;
    
    // 缓存
    self.whiteboards.insert(*view_id, whiteboard.clone());

    info!("[Whiteboard] ✅ Opened whiteboard: {}", view_id);
    Ok(whiteboard)
  }

  /// 创建白板实例（内部方法）
  /// 
  /// sync_enable: 是否启用云端同步（WebSocket 实时同步）
  async fn create_whiteboard_instance(
    &self,
    view_id: &Uuid,
    sync_enable: bool,
  ) -> FlowyResult<Arc<RwLock<Whiteboard>>> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    // 获取 CollabObject（用于 finalize 时添加云端同步插件）
    let collab_builder = self.collab_builder()?;
    let object = collab_builder
      .collab_object(&workspace_id, uid, view_id, CollabType::Document)
      .map_err(internal_error)?;

    // 检查白板是否已存在于本地磁盘
    let exists = self.is_whiteboard_exist(view_id).await.unwrap_or(false);
    info!("[Whiteboard] Whiteboard {} exists on local disk: {}", view_id, exists);

    // 确定数据源：本地磁盘 或 云端
    let data_source = if exists {
      // 从本地磁盘加载
      CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source()
    } else {
      // 本地不存在，尝试从云端获取
      // This happens when user_device_a creates a whiteboard and user_device_b opens the whiteboard.
      info!(
        "[Whiteboard] Whiteboard {} not found in local disk, trying to get from cloud",
        view_id
      );
      match self.cloud_service.get_whiteboard_doc_state(view_id, &workspace_id).await {
        Ok(doc_state) => {
          if doc_state.is_empty() {
            info!("[Whiteboard] Cloud returned empty doc_state for {}, creating new whiteboard", view_id);
            DataSource::Disk(None)
          } else {
            info!("[Whiteboard] ✅ Got whiteboard doc_state from cloud for {}", view_id);
            DataSource::DocStateV1(doc_state)
          }
        },
        Err(e) => {
          info!("[Whiteboard] Failed to get from cloud: {}, creating new whiteboard", e);
          DataSource::Disk(None)
        }
      }
    };

    // 使用 build_collab 构建 Collab（会自动添加 RocksdbDiskPlugin，但尚未 initialize）
    let collab = self
      .build_collab(uid, view_id, data_source)
      .await?;

    // 尝试打开白板，如果失败则创建新的数据结构
    let whiteboard = match Whiteboard::open(collab) {
      Ok(wb) => {
        info!("[Whiteboard] ✅ Successfully opened whiteboard: {}", view_id);
        wb
      },
      Err(e) => {
        info!("[Whiteboard] ⚠️ Failed to open whiteboard ({}), creating new data structure", e);
        // Collab 文档存在但数据结构未初始化，重新创建数据结构
        let data_source = if exists {
          CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source()
        } else {
          DataSource::Disk(None)
        };
        
        let collab = self
          .build_collab(uid, view_id, data_source)
          .await?;
          
        let wb = Whiteboard::create(collab)
          .map_err(|e| internal_error(format!("Failed to create whiteboard data structure: {}", e)))?;
        
        // 保存初始化后的数据结构到磁盘
        let encoded = wb.encode_collab()
          .map_err(internal_error)?;
        self
          .persistence()?
          .save_collab_to_disk(&view_id.to_string(), encoded)
          .map_err(internal_error)?;
        
        info!("[Whiteboard] ✅ Initialized whiteboard data structure and saved: {}", view_id);
        wb
      }
    };

    // 包装为 Arc<RwLock<Whiteboard>>
    let arc_whiteboard = Arc::new(RwLock::new(whiteboard));

    // ✅ 关键修复：调用 finalize() 添加 WebSocket 云端实时同步插件
    // 这是 AppFlowy 实现多端实时同步的核心机制
    // finalize() 会：1）添加 WebSocket 同步插件；2）调用 initialize() 启动所有插件
    let builder_config = CollabBuilderConfig::default().sync_enable(sync_enable);
    let arc_whiteboard = collab_builder
      .finalize(object, builder_config, arc_whiteboard)
      .map_err(internal_error)?;

    // ✅ 开启数据变更订阅，监听来自云端的同步数据
    {
      let wb = arc_whiteboard.read().await;
      wb.subscribe_changed();
    }

    info!("[Whiteboard] ✅ Whiteboard {} finalized with sync_enable={}", view_id, sync_enable);
    Ok(arc_whiteboard)
  }

  /// 更新白板数据
  pub async fn update_whiteboard(
    &self,
    view_id: &Uuid,
    json_data: &str,
  ) -> FlowyResult<()> {
    info!("[Whiteboard] Manager.update_whiteboard called");
    info!("[Whiteboard] ViewID: {}", view_id);
    info!("[Whiteboard] JSON data length: {} bytes", json_data.len());
    
    info!("[Whiteboard] Opening whiteboard...");
    let whiteboard = self.open_whiteboard(view_id).await?;
    info!("[Whiteboard] ✅ Whiteboard opened");
    
    info!("[Whiteboard] Acquiring write lock...");
    let mut wb = whiteboard.write().await;
    info!("[Whiteboard] ✅ Write lock acquired");
    
    info!("[Whiteboard] Calling wb.update_from_json...");
    wb.update_from_json(json_data)
      .map_err(|e| internal_error(format!("Failed to update whiteboard: {}", e)))?;

    info!("[Whiteboard] ✅✅✅ Updated whiteboard successfully: {}", view_id);
    Ok(())
  }

  /// 获取白板数据
  pub async fn get_whiteboard_data(&self, view_id: &Uuid) -> FlowyResult<String> {
    info!("[Whiteboard] 🔵 get_whiteboard_data called for view: {}", view_id);
    let whiteboard = self.open_whiteboard(view_id).await?;
    let wb = whiteboard.read().await;
    wb.to_json()
      .map_err(|e| internal_error(format!("Failed to get whiteboard data: {}", e)))
  }

  /// 关闭白板
  pub async fn close_whiteboard(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[Whiteboard] 🔵 close_whiteboard called for view: {}", view_id);
    self.whiteboards.remove(view_id);
    info!("[Whiteboard] Closed whiteboard: {}", view_id);
    Ok(())
  }

  /// 删除白板
  pub async fn delete_whiteboard(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[Whiteboard] 🔵 delete_whiteboard called for view: {}", view_id);
    // 从缓存中移除
    self.whiteboards.remove(view_id);

    // 从磁盘删除
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

    info!("[Whiteboard] Deleted whiteboard: {}", view_id);
    Ok(())
  }

  /// 检查白板是否存在
  async fn is_whiteboard_exist(&self, view_id: &Uuid) -> FlowyResult<bool> {
    info!("[Whiteboard] 🔵 Checking whiteboard existence for view: {}", view_id);
    
    // 先检查缓存
    if self.whiteboards.contains_key(view_id) {
      info!("[Whiteboard] ✅ Whiteboard found in cache: {}", view_id);
      return Ok(true);
    }
    info!("[Whiteboard] 🔵 Whiteboard not in cache, checking disk for view: {}", view_id);

    // 检查磁盘
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;
    info!("[Whiteboard] 🔵 Got collab_db for view: {}", view_id);

    if let Some(db) = collab_db.upgrade() {
      info!("[Whiteboard] 🔵 Creating read transaction for view: {}", view_id);
      let read_txn = db.read_txn();
      let exists = read_txn.is_exist(uid, &workspace_id.to_string(), &view_id.to_string());
      info!("[Whiteboard] ✅ Whiteboard exists on disk: {} for view: {}", exists, view_id);
      return Ok(exists);
    }

    info!("[Whiteboard] ⚠️ Could not upgrade collab_db for view: {}", view_id);
    Ok(false)
  }

  /// 为白板创建 Collab 对象（带 RocksDB 持久化插件，但尚未 initialize）
  /// 
  /// 注意：此方法只添加 RocksDB 插件，不添加 WebSocket 同步插件，也不调用 initialize()。
  /// 调用者需要在构建完 Whiteboard 后，调用 collab_builder.finalize() 来添加同步插件并初始化。
  async fn build_collab(
    &self,
    uid: i64,
    view_id: &Uuid,
    data_source: DataSource,
  ) -> FlowyResult<collab::preclude::Collab> {
    let collab_builder = self.collab_builder()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    // 使用 Document 类型（TODO: 等 collab-entity 添加 CollabType::Whiteboard 后改用）
    let object = collab_builder.collab_object(&workspace_id, uid, view_id, CollabType::Document)
      .map_err(internal_error)?;

    // 构建带 RocksdbDiskPlugin 的 Collab，但不 initialize（由 finalize() 统一处理）
    let collab = collab_builder
      .build_collab(&object, &collab_db, data_source)
      .await
      .map_err(internal_error)?;
    
    Ok(collab)
  }

  /// 获取编码的 Collab 数据（只读，不需要同步）
  pub async fn get_encoded_collab(
    &self,
    view_id: &Uuid,
  ) -> FlowyResult<EncodedCollab> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let data_source =
      CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source();

    let mut collab = self
      .build_collab(uid, view_id, data_source)
      .await?;

    // 只读操作，只需 initialize RocksDB 插件即可（不需要 WebSocket 同步）
    collab.initialize();

    let encoded_collab = collab
      .encode_collab_v1(|_collab| Ok::<(), collab::error::CollabError>(()))
      .map_err(internal_error)?;

    Ok(encoded_collab)
  }
}
