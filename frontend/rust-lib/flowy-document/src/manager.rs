use std::sync::Arc;
use std::sync::Weak;

use collab::core::collab::DataSource;
use collab::core::collab_plugin::CollabPersistence;
use collab::core::origin::CollabOrigin;
use collab::entity::EncodedCollab;
use collab::lock::RwLock;
use collab::preclude::Collab;
use collab::preclude::Transact;
use collab_document::blocks::DocumentData;
use collab_document::document::Document;
use collab_document::document::DocumentBody;
use collab_document::document_awareness::DocumentAwarenessState;
use collab_document::document_awareness::DocumentAwarenessUser;
use collab_document::document_data::default_document_data;
use collab_entity::CollabType;

use crate::document::{
  subscribe_document_changed, subscribe_document_snapshot_state, subscribe_document_sync_state,
};
use collab_integrate::collab_builder::{
  AppFlowyCollabBuilder, CollabBuilderConfig, CollabPersistenceImpl,
};
use collab_plugins::CollabKVDB;
use dashmap::DashMap;
use dashmap::DashSet;
use flowy_document_pub::cloud::DocumentCloudService;
use flowy_error::{internal_error, ErrorCode, FlowyError, FlowyResult};
use flowy_link::LinkIndexService;
use flowy_sqlite::ConnectionPool;
use flowy_storage_pub::storage::{CreatedUpload, StorageService};
use lib_infra::util::timestamp;
use tracing::{event, instrument};
use tracing::{info, trace, warn};
use uuid::Uuid;

use crate::entities::UpdateDocumentAwarenessStatePB;
use crate::entities::{
  DocumentSnapshotData, DocumentSnapshotMeta, DocumentSnapshotMetaPB, DocumentSnapshotPB,
};
use crate::reminder::DocumentReminderAction;

pub trait DocumentUserService: Send + Sync {
  fn user_id(&self) -> Result<i64, FlowyError>;
  fn device_id(&self) -> Result<String, FlowyError>;
  fn workspace_id(&self) -> Result<Uuid, FlowyError>;
  fn collab_db(&self, uid: i64) -> Result<Weak<CollabKVDB>, FlowyError>;

  /// Resolve the OWNER workspace id for a (possibly shared) view from the local
  /// `workspace_shared_view` table.
  ///
  /// Returns `None` when the view is not a cross-workspace shared view (i.e. it
  /// belongs to the current workspace). Real-time collab is routed per
  /// workspace on the server, so a shared document opened by a recipient MUST
  /// sync under the owner's workspace, not the recipient's current workspace.
  fn shared_view_source_workspace_id(&self, _view_id: &str) -> Option<String> {
    None
  }

  /// 本地 SQLite 连接池，供双向链接索引写入。
  ///
  /// 用默认实现返回错误而不是声明成必需方法：链接索引是可选的派生能力，
  /// 纯内存环境（单元测试、无本地库的宿主）不实现它，索引会自动跳过，
  /// 文档读写行为完全不受影响。
  fn sqlite_pool(&self) -> Result<Arc<ConnectionPool>, FlowyError> {
    Err(FlowyError::internal().with_context("sqlite pool is not available, link index is disabled"))
  }
}

pub trait DocumentSnapshotService: Send + Sync {
  fn get_document_snapshot_metas(
    &self,
    document_id: &str,
  ) -> FlowyResult<Vec<DocumentSnapshotMeta>>;
  fn get_document_snapshot(&self, snapshot_id: &str) -> FlowyResult<DocumentSnapshotData>;
}

pub struct DocumentManager {
  pub user_service: Arc<dyn DocumentUserService>,
  collab_builder: Weak<AppFlowyCollabBuilder>,
  documents: Arc<DashMap<Uuid, Arc<RwLock<Document>>>>,
  removing_documents: Arc<DashMap<Uuid, Arc<RwLock<Document>>>>,
  /// 本轮打开后发生过写入的文档。关闭时据此立即刷新搜索索引，
  /// 避免只改一次的文档落在 30 秒轮询窗口之外。
  dirty_documents: Arc<DashSet<Uuid>>,
  pub(crate) cloud_service: Arc<dyn DocumentCloudService>,
  storage_service: Weak<dyn StorageService>,
  snapshot_service: Arc<dyn DocumentSnapshotService>,
  /// 是否启用双向链接索引。
  ///
  /// 索引所需的连接池通过 `DocumentUserService::sqlite_pool` 按需获取，
  /// 而不是在构造时注入 —— 因为连接池是**按用户、按会话**隔离的，
  /// 而 DocumentManager 的构造早于登录。
  link_index_enabled: bool,
}

impl Drop for DocumentManager {
  fn drop(&mut self) {
    trace!("[Drop] drop document manager");
  }
}

/// 把 `EncodedCollab`（CRDT 二进制快照）还原成结构化的 `DocumentData`。
///
/// 这里刻意**新建一个临时 Collab 实例**，而不是去借用已打开的文档：
/// 索引发生在文档关闭的路径上，此刻原实例的状态与锁都不适合再取。
/// 临时实例是一次纯反序列化，成本远低于冲突或死锁的风险。
fn decode_document_data(doc_id: &Uuid, encoded_collab: &EncodedCollab) -> Option<DocumentData> {
  let collab = Collab::new_with_source(
    CollabOrigin::Empty,
    &doc_id.to_string(),
    DataSource::DocStateV1(encoded_collab.doc_state.to_vec()),
    vec![],
    false,
  )
  .ok()?;

  let body = DocumentBody::from_collab(&collab)?;
  let txn = collab.transact();
  body.get_document_data(&txn).ok()
}

impl DocumentManager {
  pub fn new(
    user_service: Arc<dyn DocumentUserService>,
    collab_builder: Weak<AppFlowyCollabBuilder>,
    cloud_service: Arc<dyn DocumentCloudService>,
    storage_service: Weak<dyn StorageService>,
    snapshot_service: Arc<dyn DocumentSnapshotService>,
  ) -> Self {
    Self {
      user_service,
      collab_builder,
      documents: Arc::new(Default::default()),
      removing_documents: Arc::new(Default::default()),
      dirty_documents: Arc::new(DashSet::new()),
      cloud_service,
      storage_service,
      snapshot_service,
      link_index_enabled: true,
    }
  }

  /// 开关双向链接索引。
  ///
  /// 默认开启；提供这个开关是为了让测试和特定宿主环境可以完全关掉它，
  /// 而不必改造依赖注入链。
  pub fn with_link_index(mut self, enabled: bool) -> Self {
    self.link_index_enabled = enabled;
    self
  }

  fn collab_builder(&self) -> FlowyResult<Arc<AppFlowyCollabBuilder>> {
    self
      .collab_builder
      .upgrade()
      .ok_or_else(FlowyError::ref_drop)
  }

  /// 标记文档在本次打开期间发生过写入，关闭时立即刷新索引。
  pub fn mark_document_dirty(&self, doc_id: &Uuid) {
    self.dirty_documents.insert(*doc_id);
  }

  async fn index_encoded_collab(&self, doc_id: &Uuid, encoded_collab: &EncodedCollab) {
    let builder = match self.collab_builder() {
      Ok(builder) => builder,
      Err(err) => {
        warn!("[Indexing] skip indexing document {}: {:?}", doc_id, err);
        return;
      },
    };
    let workspace_id = match self.user_service.workspace_id() {
      Ok(workspace_id) => workspace_id,
      Err(err) => {
        warn!("[Indexing] skip indexing document {}: {:?}", doc_id, err);
        return;
      },
    };
    if let Err(err) = builder
      .index_encoded_collab_now(
        workspace_id,
        *doc_id,
        encoded_collab.clone(),
        CollabType::Document,
      )
      .await
    {
      warn!("[Indexing] failed to index document {}: {:?}", doc_id, err);
    }

    // 链接索引挂在这里而不是另开一条事件流：全文索引和链接索引必须
    // 共用同一个「文档已变更」的汇聚点，否则会出现「搜索能搜到、反链没更新」
    // 这种用户无法理解的错位。
    self.index_links(*doc_id, workspace_id, encoded_collab);
  }

  /// 刷新一页的双向链接索引。
  ///
  /// 失败只记日志：索引是派生数据，它坏了不该连累文档保存。
  /// 用户下次打开或编辑该页时会自动重算，最坏情况是反链短暂不全。
  ///
  /// 这里直接做同步 SQLite 写入。单页链接数量是 O(十) 量级，耗时为毫秒级，
  /// 在当前的调用频率下不会阻塞执行器。若将来改成「每次编辑都触发」，
  /// 需要移到 `spawn_blocking`，否则会占住 async 工作线程。
  fn index_links(&self, doc_id: Uuid, workspace_id: Uuid, encoded_collab: &EncodedCollab) {
    if !self.link_index_enabled
      || self
        .user_service
        .shared_view_source_workspace_id(&doc_id.to_string())
        .is_some_and(|owner| owner != workspace_id.to_string())
    {
      return;
    }

    // 连接池按用户隔离，且随会话变化，所以每次取而不是缓存。
    // `open_sqlite_db` 内部有 DashMap 缓存，重复调用不会真的重开库。
    let pool = match self.user_service.sqlite_pool() {
      Ok(pool) => pool,
      Err(_) => {
        // 该环境没有本地库（测试、内存模式），安静跳过即可，不是错误。
        trace!("[Link] sqlite pool unavailable, skip link indexing");
        return;
      },
    };
    let service = LinkIndexService::new(pool);

    let Some(document_data) = decode_document_data(&doc_id, encoded_collab) else {
      warn!(
        "[Link] failed to decode document {} for link indexing",
        doc_id
      );
      return;
    };

    match service.index_document_for(&workspace_id, &doc_id.to_string(), &document_data, false) {
      Ok(outcome) => {
        if outcome.is_written() {
          crate::notification::document_notification_builder(
            &workspace_id.to_string(),
            crate::notification::DocumentNotification::DidUpdateLinks,
          )
          .send();
        }
        trace!("[Link] indexed document {}: {:?}", doc_id, outcome);
      },
      Err(err) => {
        // 索引失败不影响主流程，但要留痕，便于排查「反链一直不出现」类问题
        warn!(
          "[Link] failed to index links for document {}: {}",
          doc_id, err
        );
      },
    }
  }

  /// 删除页面时清理它的出链索引。
  ///
  /// 指向它的入链会保留 —— 那表示「别处引用了已删除的页面」，
  /// 这条信息对用户有用，不该静默消失。
  pub fn remove_link_index(&self, workspace_id: &Uuid, page_id: &Uuid) {
    if !self.link_index_enabled {
      return;
    }
    let Ok(pool) = self.user_service.sqlite_pool() else {
      return;
    };
    let service = LinkIndexService::new(pool);
    if let Err(err) = service.on_page_deleted(workspace_id, &page_id.to_string()) {
      warn!(
        "[Link] failed to remove link index for {}: {}",
        page_id, err
      );
    } else {
      crate::notification::document_notification_builder(
        &workspace_id.to_string(),
        crate::notification::DocumentNotification::DidUpdateLinks,
      )
      .send();
    }
  }

  /// Get the encoded collab of the document.
  pub async fn get_encoded_collab_with_view_id(&self, doc_id: &Uuid) -> FlowyResult<EncodedCollab> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let doc_state =
      CollabPersistenceImpl::new(self.user_service.collab_db(uid)?, uid, workspace_id)
        .into_data_source();
    let collab = self
      .collab_for_document(uid, doc_id, doc_state, false, None)
      .await?;
    let encoded_collab = collab
      .try_read()
      .unwrap()
      .encode_collab_v1(|collab| CollabType::Document.validate_require_data(collab))
      .map_err(internal_error)?;
    Ok(encoded_collab)
  }

  pub async fn initialize(&self, _uid: i64) -> FlowyResult<()> {
    trace!("initialize document manager");
    self.documents.clear();
    self.removing_documents.clear();
    Ok(())
  }

  #[instrument(
    name = "document_initialize_after_sign_up",
    level = "debug",
    skip_all,
    err
  )]
  pub async fn initialize_after_sign_up(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await?;
    Ok(())
  }

  pub async fn initialize_after_open_workspace(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await?;
    Ok(())
  }

  #[instrument(level = "debug", skip_all, err)]
  pub async fn initialize_after_sign_in(&self, uid: i64) -> FlowyResult<()> {
    self.initialize(uid).await?;
    Ok(())
  }

  pub async fn handle_reminder_action(&self, action: DocumentReminderAction) {
    match action {
      DocumentReminderAction::Add { reminder: _ } => {},
      DocumentReminderAction::Remove { reminder_id: _ } => {},
      DocumentReminderAction::Update { reminder: _ } => {},
    }
  }

  fn persistence(&self) -> FlowyResult<CollabPersistenceImpl> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    let db = self.user_service.collab_db(uid)?;
    Ok(CollabPersistenceImpl::new(db, uid, workspace_id))
  }

  /// Create a new document.
  ///
  /// if the document already exists, return the existing document.
  /// if the data is None, will create a document with default data.
  #[instrument(level = "info", skip(self, data))]
  pub async fn create_document(
    &self,
    _uid: i64,
    doc_id: &Uuid,
    data: Option<DocumentData>,
  ) -> FlowyResult<EncodedCollab> {
    if self.is_doc_exist(doc_id).await.unwrap_or(false) {
      // Document record exists. Try to load existing document from persistence and return its encoded collab.
      match self.create_document_instance(doc_id, false, None).await {
        Ok(document) => {
          // encode and return existing collab
          let encoded = document
            .try_read()
            .map_err(internal_error)?
            .encode_collab()
            .map_err(internal_error)?;
          return Ok(encoded);
        },
        Err(err) => {
          // If data is invalid (incomplete collab), try to regenerate using provided data (or default)
          if err.is_invalid_data() {
            // regenerate encoded collab from given data
            let encoded_collab = doc_state_from_document_data(doc_id, data).await?;
            self
              .persistence()?
              .save_collab_to_disk(doc_id.to_string().as_str(), encoded_collab.clone())
              .map_err(internal_error)?;
            self.index_encoded_collab(doc_id, &encoded_collab).await;

            // Send the collab data to server with a background task to ensure cloud has the collab.
            let cloud_service = self.cloud_service.clone();
            let cloned_encoded_collab = encoded_collab.clone();
            let workspace_id = self.user_service.workspace_id()?;
            let doc_id = *doc_id;
            tokio::spawn(async move {
              let _ = cloud_service
                .create_document_collab(&workspace_id, &doc_id, cloned_encoded_collab)
                .await;
            });
            return Ok(encoded_collab);
          } else {
            // Other errors: propagate RecordAlreadyExists-like behavior
            return Err(FlowyError::new(
              ErrorCode::RecordAlreadyExists,
              format!("document {} already exists", doc_id),
            ));
          }
        },
      }
    } else {
      let encoded_collab = doc_state_from_document_data(doc_id, data).await?;
      self
        .persistence()?
        .save_collab_to_disk(doc_id.to_string().as_str(), encoded_collab.clone())
        .map_err(internal_error)?;
      self.index_encoded_collab(doc_id, &encoded_collab).await;

      // Send the collab data to server with a background task.
      let cloud_service = self.cloud_service.clone();
      let cloned_encoded_collab = encoded_collab.clone();
      let workspace_id = self.user_service.workspace_id()?;
      let doc_id = *doc_id;
      tokio::spawn(async move {
        let _ = cloud_service
          .create_document_collab(&workspace_id, &doc_id, cloned_encoded_collab)
          .await;
      });
      Ok(encoded_collab)
    }
  }

  async fn collab_for_document(
    &self,
    uid: i64,
    doc_id: &Uuid,
    data_source: DataSource,
    sync_enable: bool,
    workspace_id: Option<Uuid>,
  ) -> FlowyResult<Arc<RwLock<Document>>> {
    let db = self.user_service.collab_db(uid)?;
    let current_workspace_id = self.user_service.workspace_id()?;
    let workspace_id = workspace_id.unwrap_or(current_workspace_id);
    // 【共享文档修复 2026-07-03】跨 workspace 共享文档(owner workspace ≠ 当前 workspace)
    // 使用显式 workspace 构建 collab:上游(2fd263730)已按 owner workspace 路由权限与同步,
    // 但 collab_object 的一致性硬检查会拒绝不等于当前 workspace 的值,导致共享文档一律
    // "workspace_id not match" 打不开(Internal)。普通文档仍走带硬检查的原路径。
    let collab_object = if workspace_id != current_workspace_id {
      self
        .collab_builder()?
        .collab_object_with_explicit_workspace(&workspace_id, uid, doc_id, CollabType::Document)?
    } else {
      self
        .collab_builder()?
        .collab_object(&workspace_id, uid, doc_id, CollabType::Document)?
    };
    let document = self
      .collab_builder()?
      .create_document(
        collab_object,
        data_source,
        db,
        CollabBuilderConfig::default().sync_enable(sync_enable),
        None,
      )
      .await?;
    Ok(document)
  }

  /// Return a document instance if the document is already opened.
  pub async fn editable_document(&self, doc_id: &Uuid) -> FlowyResult<Arc<RwLock<Document>>> {
    if let Some(doc) = self.documents.get(doc_id).map(|item| item.value().clone()) {
      return Ok(doc);
    }

    if let Some(doc) = self.restore_document_from_removing(doc_id) {
      return Ok(doc);
    }

    Err(FlowyError::internal().with_context("Call open document first"))
  }

  /// Returns Document for given object id
  /// If the document does not exist in local disk, try get the doc state from the cloud.
  /// If the document exists, open the document and cache it
  #[tracing::instrument(level = "info", skip(self), err)]
  async fn create_document_instance(
    &self,
    doc_id: &Uuid,
    enable_sync: bool,
    workspace_id: Option<Uuid>,
  ) -> FlowyResult<Arc<RwLock<Document>>> {
    let uid = self.user_service.user_id()?;
    // For a cross-workspace shared document opened by a recipient (e.g. via the
    // shared list, or an invite deep link that passes no workspace_id), fall
    // back to the OWNER workspace recorded locally in `workspace_shared_view`.
    // Real-time collab is routed per workspace on the server, so without this
    // the document would sync under the recipient's current workspace stream
    // and neither side would see the other's edits.
    let workspace_id = workspace_id.or_else(|| {
      self
        .user_service
        .shared_view_source_workspace_id(&doc_id.to_string())
        .and_then(|ws| Uuid::parse_str(&ws).ok())
    });
    let mut doc_state = self.persistence()?.into_data_source();
    // If the document does not exist in local disk, try get the doc state from the cloud. This happens
    // When user_device_a create a document and user_device_b open the document.
    if !self.is_doc_exist(doc_id).await? {
      info!(
        "document {} not found in local disk, try to get the doc state from the cloud",
        doc_id
      );
      // Use the provided workspace_id or fallback to the current user's workspace_id
      let target_workspace_id = workspace_id.unwrap_or(self.user_service.workspace_id()?);
      doc_state = DataSource::DocStateV1(
        self
          .cloud_service
          .get_document_doc_state(doc_id, &target_workspace_id)
          .await?,
      );

      // the doc_state should not be empty if remote return the doc state without error.
      if doc_state.is_empty() {
        return Err(FlowyError::new(
          ErrorCode::RecordNotFound,
          format!("document {} not found", doc_id),
        ));
      }
    }

    event!(
      tracing::Level::DEBUG,
      "Initialize document: {}, workspace_id: {:?}",
      doc_id,
      workspace_id.unwrap_or(self.user_service.workspace_id().unwrap_or_default())
    );
    let result = self
      .collab_for_document(uid, doc_id, doc_state, enable_sync, workspace_id)
      .await;
    match result {
      Ok(document) => {
        // Only push the document to the cache if the sync is enabled.
        if enable_sync {
          {
            let mut lock = document.write().await;
            subscribe_document_changed(doc_id, &mut lock);
            subscribe_document_snapshot_state(&lock);
            subscribe_document_sync_state(&lock);
          }
          self.subscribe_link_index(*doc_id, &document).await;
          self.documents.insert(*doc_id, document.clone());
        }
        Ok(document)
      },
      Err(err) => {
        if err.is_invalid_data() {
          self.delete_document(doc_id).await?;
        }
        return Err(err);
      },
    }
  }

  /// A debounced observer covers local edits, undo and remote CRDT merges.
  /// The pool/workspace belong to this session; a task never resolves a later user's pool.
  async fn subscribe_link_index(&self, doc_id: Uuid, document: &Arc<RwLock<Document>>) {
    if !self.link_index_enabled {
      return;
    }
    let (Ok(pool), Ok(workspace_id)) = (
      self.user_service.sqlite_pool(),
      self.user_service.workspace_id(),
    ) else {
      return;
    };
    // Shared documents owned by another workspace must not leak into this graph.
    if self
      .user_service
      .shared_view_source_workspace_id(&doc_id.to_string())
      .is_some_and(|owner| owner != workspace_id.to_string())
    {
      return;
    }
    let (sender, mut receiver) = tokio::sync::watch::channel(0u64);
    let weak_document = Arc::downgrade(document);
    document
      .write()
      .await
      .subscribe_block_changed("note_link", move |_, _| {
        sender.send_modify(|version| *version = version.wrapping_add(1));
      });
    tokio::spawn(async move {
      let service = LinkIndexService::new(pool);
      loop {
        // Also index once on open, including existing notes without links.
        loop {
          match tokio::time::timeout(std::time::Duration::from_millis(500), receiver.changed())
            .await
          {
            Ok(Ok(())) => continue,
            Ok(Err(_)) => return,
            Err(_) => break,
          }
        }
        let Some(document) = weak_document.upgrade() else {
          return;
        };
        let data = document.read().await.get_document_data();
        drop(document);
        if let Ok(data) = data {
          match service.index_document_for(&workspace_id, &doc_id.to_string(), &data, false) {
            Ok(outcome) if outcome.is_written() => {
              crate::notification::document_notification_builder(
                &workspace_id.to_string(),
                crate::notification::DocumentNotification::DidUpdateLinks,
              )
              .send();
            },
            Err(err) => warn!("[Link] live indexing {} failed: {}", doc_id, err),
            _ => {},
          }
        }
        if receiver.changed().await.is_err() {
          return;
        }
      }
    });
  }

  /// Query current-workspace derived data. Empty page id requests the graph snapshot.
  pub async fn document_links(
    &self,
    page_id: Option<Uuid>,
    reindex: bool,
  ) -> FlowyResult<crate::entities::DocumentLinksPB> {
    use crate::entities::{DocumentLinksPB, UnresolvedNoteLinkPB};
    use flowy_link::store::LinkIndexStore;
    let workspace_id = self.user_service.workspace_id()?;
    let pool = self.user_service.sqlite_pool()?;
    let service = LinkIndexService::new(pool.clone());
    if reindex {
      let id = page_id.ok_or_else(FlowyError::invalid_data)?;
      if self
        .user_service
        .shared_view_source_workspace_id(&id.to_string())
        .is_some_and(|owner| owner != workspace_id.to_string())
      {
        return Err(
          FlowyError::invalid_data().with_context("shared document belongs to another workspace"),
        );
      }
      // Repair is local-only and must not fetch every remote document.
      if !self.is_doc_exist(&id).await? {
        return Err(FlowyError::record_not_found());
      }
      let data = self.get_document_data(&id).await?;
      service
        .index_document_for(&workspace_id, &id.to_string(), &data, true)
        .map_err(internal_error)?;
      crate::notification::document_notification_builder(
        &workspace_id.to_string(),
        crate::notification::DocumentNotification::DidUpdateLinks,
      )
      .send();
    }
    let store = LinkIndexStore::new(pool);
    let mut result = DocumentLinksPB {
      indexed_pages: store
        .indexed_page_count(&workspace_id)
        .map_err(internal_error)?
        .min(i32::MAX as i64) as i32,
      ..Default::default()
    };
    if let Some(id) = page_id {
      let id = id.to_string();
      let mut incoming = service
        .get_backlinks(&workspace_id, &id, 1000)
        .map_err(internal_error)?;
      result.truncated = incoming.len() > 999;
      incoming.truncate(999);
      result.incoming = incoming.into_iter().map(Into::into).collect();
      result.outgoing = service
        .get_outgoing(&workspace_id, &id)
        .map_err(internal_error)?
        .into_iter()
        .map(Into::into)
        .collect();
      result.unresolved = service
        .get_unresolved(&workspace_id, &id)
        .map_err(internal_error)?
        .into_iter()
        .map(|link| UnresolvedNoteLinkPB {
          src_block_id: link.src_block_id,
          raw_title: link.raw_title,
          char_offset: link.char_offset,
        })
        .collect();
    } else {
      let mut edges = store
        .workspace_edges(&workspace_id, 20001)
        .map_err(internal_error)?;
      result.truncated = edges.len() > 20000;
      edges.truncate(20000);
      result.outgoing = edges.into_iter().map(Into::into).collect();
    }
    Ok(result)
  }

  pub async fn get_document_data(&self, doc_id: &Uuid) -> FlowyResult<DocumentData> {
    let document = self.get_document(doc_id).await?;
    let document = document.read().await;
    document.get_document_data().map_err(internal_error)
  }

  pub async fn get_cloud_document_data(
    &self,
    doc_id: &Uuid,
    workspace_id: Option<Uuid>,
  ) -> FlowyResult<DocumentData> {
    let workspace_id = workspace_id.unwrap_or(self.user_service.workspace_id()?);
    self
      .cloud_service
      .get_document_data(doc_id, &workspace_id)
      .await?
      .ok_or_else(|| {
        FlowyError::new(
          ErrorCode::RecordNotFound,
          format!("document {} not found in cloud", doc_id),
        )
      })
  }

  pub async fn get_document_text(&self, doc_id: &Uuid) -> FlowyResult<String> {
    let document = self.get_document(doc_id).await?;
    let document = document.read().await;
    let text = document.paragraphs().join("\n");
    Ok(text)
  }

  /// Return a document instance.
  /// The returned document might or might not be able to sync with the cloud.
  async fn get_document(&self, doc_id: &Uuid) -> FlowyResult<Arc<RwLock<Document>>> {
    if let Some(doc) = self.documents.get(doc_id).map(|item| item.value().clone()) {
      return Ok(doc);
    }

    if let Some(doc) = self.restore_document_from_removing(doc_id) {
      return Ok(doc);
    }

    let document = self.create_document_instance(doc_id, false, None).await?;
    Ok(document)
  }

  pub async fn open_document(&self, doc_id: &Uuid, workspace_id: Option<Uuid>) -> FlowyResult<()> {
    if let Some(mutex_document) = self.restore_document_from_removing(doc_id) {
      let lock = mutex_document.read().await;
      lock.start_init_sync();
    }

    if self.documents.contains_key(doc_id) {
      return Ok(());
    }

    let _ = self
      .create_document_instance(doc_id, true, workspace_id)
      .await?;
    Ok(())
  }

  pub async fn close_document(&self, doc_id: &Uuid) -> FlowyResult<()> {
    if let Some((doc_id, document)) = self.documents.remove(doc_id) {
      {
        // clear the awareness state when close the document
        let mut lock = document.write().await;
        lock.clean_awareness_local_state();
      }

      // 这次打开期间写过内容：关闭前同步刷新索引，让紧接着的搜索能命中。
      if self.dirty_documents.remove(&doc_id).is_some() {
        match document.read().await.encode_collab() {
          Ok(encoded_collab) => self.index_encoded_collab(&doc_id, &encoded_collab).await,
          Err(err) => warn!("[Indexing] failed to encode document {}: {:?}", doc_id, err),
        }
      }

      let clone_doc_id = doc_id;
      trace!("move document to removing_documents: {}", doc_id);
      self.removing_documents.insert(doc_id, document);

      let weak_removing_documents = Arc::downgrade(&self.removing_documents);
      tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(120)).await;
        if let Some(removing_documents) = weak_removing_documents.upgrade() {
          if removing_documents.remove(&clone_doc_id).is_some() {
            trace!("drop document from removing_documents: {}", clone_doc_id);
          }
        }
      });
    }

    Ok(())
  }

  pub async fn delete_document(&self, doc_id: &Uuid) -> FlowyResult<()> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    if let Some(db) = self.user_service.collab_db(uid)?.upgrade() {
      db.delete_doc(uid, &workspace_id.to_string(), &doc_id.to_string())
        .await?;
      // When deleting a document, we need to remove it from the cache.
      self.documents.remove(doc_id);
    }
    // 清理本页的出链索引；指向它的入链刻意保留（引用了已删除页面对用户有价值）。
    self.remove_link_index(&workspace_id, doc_id);
    Ok(())
  }

  #[instrument(level = "debug", skip_all, err)]
  pub async fn set_document_awareness_local_state(
    &self,
    doc_id: &Uuid,
    state: UpdateDocumentAwarenessStatePB,
  ) -> FlowyResult<bool> {
    let uid = self.user_service.user_id()?;
    let device_id = self.user_service.device_id()?;
    if let Ok(doc) = self.editable_document(doc_id).await {
      let doc = doc.write().await;
      let user = DocumentAwarenessUser { uid, device_id };
      let selection = state.selection.map(|s| s.into());
      let state = DocumentAwarenessState {
        version: 1,
        user,
        selection,
        metadata: state.metadata,
        timestamp: timestamp(),
      };
      doc.set_awareness_local_state(state);
      return Ok(true);
    }
    Ok(false)
  }

  /// Return the list of snapshots of the document.
  pub async fn get_document_snapshot_meta(
    &self,
    document_id: &Uuid,
    _limit: usize,
  ) -> FlowyResult<Vec<DocumentSnapshotMetaPB>> {
    let metas = self
      .snapshot_service
      .get_document_snapshot_metas(document_id.to_string().as_str())?
      .into_iter()
      .map(|meta| DocumentSnapshotMetaPB {
        snapshot_id: meta.snapshot_id,
        object_id: meta.object_id,
        created_at: meta.created_at,
        reused: false,
      })
      .collect::<Vec<_>>();

    Ok(metas)
  }

  pub async fn get_document_snapshot(&self, snapshot_id: &str) -> FlowyResult<DocumentSnapshotPB> {
    let snapshot = self
      .snapshot_service
      .get_document_snapshot(snapshot_id)
      .map(|snapshot| DocumentSnapshotPB {
        object_id: snapshot.object_id,
        encoded_v1: snapshot.encoded_v1,
      })?;
    Ok(snapshot)
  }

  #[instrument(level = "debug", skip_all, err)]
  pub async fn upload_file(
    &self,
    workspace_id: String,
    document_id: &str,
    local_file_path: &str,
  ) -> FlowyResult<CreatedUpload> {
    let storage_service = self.storage_service_upgrade()?;
    let upload = storage_service
      .create_upload(&workspace_id, document_id, local_file_path)
      .await?
      .0;
    Ok(upload)
  }

  pub async fn download_file(&self, local_file_path: String, url: String) -> FlowyResult<()> {
    let storage_service = self.storage_service_upgrade()?;
    storage_service.download_object(url, local_file_path)?;
    Ok(())
  }

  pub async fn delete_file(&self, url: String) -> FlowyResult<()> {
    let storage_service = self.storage_service_upgrade()?;
    storage_service.delete_object(url).await?;
    Ok(())
  }

  async fn is_doc_exist(&self, doc_id: &Uuid) -> FlowyResult<bool> {
    let uid = self.user_service.user_id()?;
    let workspace_id = self.user_service.workspace_id()?;
    if let Some(collab_db) = self.user_service.collab_db(uid)?.upgrade() {
      let is_exist = collab_db
        .is_exist(uid, &workspace_id.to_string(), &doc_id.to_string())
        .await?;
      Ok(is_exist)
    } else {
      Ok(false)
    }
  }

  fn storage_service_upgrade(&self) -> FlowyResult<Arc<dyn StorageService>> {
    let storage_service = self.storage_service.upgrade().ok_or_else(|| {
      FlowyError::internal().with_context("The file storage service is already dropped")
    })?;
    Ok(storage_service)
  }

  /// Only expose this method for testing
  #[cfg(debug_assertions)]
  pub fn get_cloud_service(&self) -> &Arc<dyn DocumentCloudService> {
    &self.cloud_service
  }
  /// Only expose this method for testing
  #[cfg(debug_assertions)]
  pub fn get_file_storage_service(&self) -> &Weak<dyn StorageService> {
    &self.storage_service
  }

  fn restore_document_from_removing(&self, doc_id: &Uuid) -> Option<Arc<RwLock<Document>>> {
    let (doc_id, doc) = self.removing_documents.remove(doc_id)?;
    trace!(
      "move document {} from removing_documents to documents",
      doc_id
    );
    self.documents.insert(doc_id, doc.clone());
    Some(doc)
  }
}

async fn doc_state_from_document_data(
  doc_id: &Uuid,
  data: Option<DocumentData>,
) -> Result<EncodedCollab, FlowyError> {
  let doc_id = doc_id.to_string();
  let data = data.unwrap_or_else(|| {
    trace!(
      "{} document data is None, use default document data",
      doc_id.to_string()
    );
    default_document_data(&doc_id)
  });
  // spawn_blocking is used to avoid blocking the tokio thread pool if the document is large.
  let encoded_collab = tokio::task::spawn_blocking(move || {
    let collab = Collab::new_with_origin(CollabOrigin::Empty, doc_id, vec![], false);
    let document = Document::create_with_data(collab, data).map_err(internal_error)?;
    let encode_collab = document.encode_collab()?;
    Ok::<_, FlowyError>(encode_collab)
  })
  .await??;
  Ok(encoded_collab)
}
