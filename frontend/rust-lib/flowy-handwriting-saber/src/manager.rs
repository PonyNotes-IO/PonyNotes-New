use collab::core::collab::DataSource;
use collab::core::collab_plugin::CollabPersistence;
use collab::entity::EncodedCollab;
use collab::lock::RwLock;
use collab_entity::CollabType;
use collab_integrate::collab_builder::{
  AppFlowyCollabBuilder, CollabPersistenceImpl,
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
pub struct HandwritingSaberManager {
  user_service: Arc<dyn HandwritingSaberUserService>,
  collab_builder: Weak<AppFlowyCollabBuilder>,
  cloud_service: Arc<dyn HandwritingSaberCloudService>,
  /// 已打开的手写笔记缓存（view_id -> sbn2_bytes）
  handwriting_sabers: Arc<DashMap<Uuid, Vec<u8>>>,
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
    trace!("[HandwritingSaber] initialize handwriting saber manager");
    self.handwriting_sabers.clear();
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

  /// 创建新手写笔记
  ///
  /// 如果手写笔记已存在，返回错误
  pub async fn create_handwriting_saber(
    &self,
    view_id: &Uuid,
    initial_data: Option<Vec<u8>>,
  ) -> FlowyResult<()> {
    info!("[HandwritingSaber] Creating handwriting saber: {}", view_id);

    if self.handwriting_sabers.contains_key(view_id) {
      return Err(FlowyError::new(
        ErrorCode::RecordAlreadyExists,
        format!("Handwriting saber {} already exists", view_id),
      ));
    }

    // 存储初始数据（如果提供）
    let data = initial_data.unwrap_or_default();
    self.handwriting_sabers.insert(*view_id, data);

    info!("[HandwritingSaber] ✅ Created handwriting saber: {}", view_id);
    Ok(())
  }

  /// 打开手写笔记
  ///
  /// 如果手写笔记不存在，从 Collab 或 Cloud 加载
  pub async fn open_handwriting_saber(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[HandwritingSaber] Opening handwriting saber: {}", view_id);

    // 如果已经在缓存中，直接返回
    if self.handwriting_sabers.contains_key(view_id) {
      info!("[HandwritingSaber] Handwriting saber already in cache: {}", view_id);
      return Ok(());
    }

    // TODO: 从 Collab 或 Cloud 加载数据
    // 当前阶段：创建空数据
    self.handwriting_sabers.insert(*view_id, Vec::new());

    info!("[HandwritingSaber] ✅ Opened handwriting saber: {}", view_id);
    Ok(())
  }

  /// 获取手写笔记数据
  pub async fn get_handwriting_saber_data(&self, view_id: &Uuid) -> FlowyResult<Vec<u8>> {
    info!("[HandwritingSaber] Getting handwriting saber data: {}", view_id);

    // 先从缓存获取
    if let Some(data) = self.handwriting_sabers.get(view_id) {
      info!("[HandwritingSaber] ✅ Got data from cache: {} bytes", data.len());
      return Ok(data.clone());
    }

    // TODO: 从 Collab 或 Cloud 加载
    // 当前阶段：返回空数据
    info!("[HandwritingSaber] Handwriting saber not found, returning empty data");
    Ok(Vec::new())
  }

  /// 保存手写笔记数据
  pub async fn save_handwriting_saber_data(
    &self,
    view_id: &Uuid,
    sbn2_bytes: Vec<u8>,
    version: i64,
  ) -> FlowyResult<i64> {
    info!(
      "[HandwritingSaber] Saving handwriting saber data: {}, version: {}, size: {} bytes",
      view_id,
      version,
      sbn2_bytes.len()
    );

    // TODO: 版本冲突检查
    // TODO: 保存到 Collab
    // TODO: 同步到 Cloud

    // 更新缓存
    self.handwriting_sabers.insert(*view_id, sbn2_bytes);

    // 返回新版本号（当前简单递增）
    let new_version = version + 1;

    info!("[HandwritingSaber] ✅ Saved handwriting saber data, new version: {}", new_version);
    Ok(new_version)
  }

  /// 关闭手写笔记
  ///
  /// 从内存中移除，但保留数据
  pub async fn close_handwriting_saber(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[HandwritingSaber] Closing handwriting saber: {}", view_id);

    // TODO: 确保数据已保存到 Collab

    // 从缓存中移除
    self.handwriting_sabers.remove(view_id);

    info!("[HandwritingSaber] ✅ Closed handwriting saber: {}", view_id);
    Ok(())
  }

  /// 删除手写笔记
  pub async fn delete_handwriting_saber(&self, view_id: &Uuid) -> FlowyResult<()> {
    info!("[HandwritingSaber] Deleting handwriting saber: {}", view_id);

    // TODO: 从 Collab 删除
    // TODO: 从 Cloud 删除

    // 从缓存中移除
    self.handwriting_sabers.remove(view_id);

    info!("[HandwritingSaber] ✅ Deleted handwriting saber: {}", view_id);
    Ok(())
  }
}

