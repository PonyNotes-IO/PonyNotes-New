use crate::entities::WhiteboardData;
use crate::whiteboard::{whiteboard_data_to_encoded_collab, Whiteboard};
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
use std::sync::{Arc, Weak};
use tracing::{info, instrument, trace};
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
  ) -> Self {
    Self {
      user_service,
      collab_builder,
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
  #[instrument(level = "info", skip(self, data))]
  pub async fn create_whiteboard(
    &self,
    view_id: &Uuid,
    data: Option<WhiteboardData>,
  ) -> FlowyResult<EncodedCollab> {
    // 检查是否已存在
    if self.is_whiteboard_exist(view_id).await.unwrap_or(false) {
      return Err(FlowyError::new(
        ErrorCode::RecordAlreadyExists,
        format!("whiteboard {} already exists", view_id),
      ));
    }

    // 创建 EncodedCollab
    let encoded_collab =
      whiteboard_data_to_encoded_collab(&view_id.to_string(), data).await?;

    // 保存到磁盘
    self
      .persistence()?
      .save_collab_to_disk(&view_id.to_string(), encoded_collab.clone())
      .map_err(internal_error)?;

    info!("[Whiteboard] Created whiteboard: {}", view_id);
    Ok(encoded_collab)
  }

  /// 打开白板
  ///
  /// 如果白板已在缓存中，直接返回
  /// 否则从磁盘加载
  #[instrument(level = "info", skip(self))]
  pub async fn open_whiteboard(&self, view_id: &Uuid) -> FlowyResult<Arc<RwLock<Whiteboard>>> {
    // 检查缓存
    if let Some(whiteboard) = self.whiteboards.get(view_id) {
      trace!("[Whiteboard] Whiteboard {} found in cache", view_id);
      return Ok(whiteboard.clone());
    }

    // 从磁盘加载
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let data_source = CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id)
      .into_data_source();

    let collab = self
      .build_collab(uid, view_id, data_source, true)
      .await?;

    // 尝试打开
    let whiteboard = Whiteboard::open(collab)
      .map_err(|e| internal_error(format!("Failed to open whiteboard: {}", e)))?;

    let whiteboard = Arc::new(RwLock::new(whiteboard));
    self.whiteboards.insert(*view_id, whiteboard.clone());

    info!("[Whiteboard] Opened whiteboard: {}", view_id);
    Ok(whiteboard)
  }

  /// 更新白板数据
  #[instrument(level = "debug", skip(self, json_data))]
  pub async fn update_whiteboard(
    &self,
    view_id: &Uuid,
    json_data: &str,
  ) -> FlowyResult<()> {
    let whiteboard = self.open_whiteboard(view_id).await?;
    let mut wb = whiteboard.write().await;
    wb.update_from_json(json_data)
      .map_err(|e| internal_error(format!("Failed to update whiteboard: {}", e)))?;

    trace!("[Whiteboard] Updated whiteboard: {}", view_id);
    Ok(())
  }

  /// 获取白板数据
  #[instrument(level = "debug", skip(self))]
  pub async fn get_whiteboard_data(&self, view_id: &Uuid) -> FlowyResult<String> {
    let whiteboard = self.open_whiteboard(view_id).await?;
    let wb = whiteboard.read().await;
    wb.to_json()
      .map_err(|e| internal_error(format!("Failed to get whiteboard data: {}", e)))
  }

  /// 关闭白板
  #[instrument(level = "debug", skip(self))]
  pub async fn close_whiteboard(&self, view_id: &Uuid) -> FlowyResult<()> {
    self.whiteboards.remove(view_id);
    info!("[Whiteboard] Closed whiteboard: {}", view_id);
    Ok(())
  }

  /// 删除白板
  #[instrument(level = "debug", skip(self))]
  pub async fn delete_whiteboard(&self, view_id: &Uuid) -> FlowyResult<()> {
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
    // 先检查缓存
    if self.whiteboards.contains_key(view_id) {
      return Ok(true);
    }

    // 检查磁盘
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    if let Some(db) = collab_db.upgrade() {
      let read_txn = db.read_txn();
      return Ok(read_txn.is_exist(uid, &workspace_id.to_string(), &view_id.to_string()));
    }

    Ok(false)
  }

  /// 为白板创建 Collab 对象
  async fn build_collab(
    &self,
    uid: i64,
    view_id: &Uuid,
    data_source: DataSource,
    _sync_enable: bool,
  ) -> FlowyResult<collab::preclude::Collab> {
    let collab_builder = self.collab_builder()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let object = collab_builder.collab_object(&workspace_id, uid, view_id, CollabType::Unknown)
      .map_err(internal_error)?;

    collab_builder
      .build_collab(&object, &collab_db, data_source)
      .await
      .map_err(internal_error)
  }

  /// 获取编码的 Collab 数据
  pub async fn get_encoded_collab(
    &self,
    view_id: &Uuid,
  ) -> FlowyResult<EncodedCollab> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let collab_db = self.user_service.collab_db(uid)?;

    let data_source =
      CollabPersistenceImpl::new(collab_db.clone(), uid, workspace_id).into_data_source();

    let collab = self
      .build_collab(uid, view_id, data_source, false)
      .await?;

    let encoded_collab = collab
      .encode_collab_v1(|_collab| Ok::<(), collab::error::CollabError>(()))
      .map_err(internal_error)?;

    Ok(encoded_collab)
  }
}
