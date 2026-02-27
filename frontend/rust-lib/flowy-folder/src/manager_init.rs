use crate::manager::{FolderInitDataSource, FolderManager};
use crate::manager_observer::*;
use crate::user_default::DefaultFolderBuilder;
use collab::core::collab::DataSource;
use collab::lock::RwLock;
use collab_entity::CollabType;
use collab_folder::{Folder, FolderNotify};
use collab_integrate::CollabKVDB;
use flowy_error::{FlowyError, FlowyResult};
use std::sync::{Arc, Weak};
use tracing::{Level, event, info, error, warn};
use uuid::Uuid;

impl FolderManager {
  /// Called immediately after the application launched if the user already sign in/sign up.
  #[tracing::instrument(level = "info", skip(self, initial_data), err)]
  pub async fn initialize(
    &self,
    uid: i64,
    workspace_id: &Uuid,
    initial_data: FolderInitDataSource,
  ) -> FlowyResult<()> {
    // Update the workspace id
    event!(
      Level::INFO,
      "🚀 Init workspace: {} from: {}",
      workspace_id,
      initial_data
    );
    let _ = self.folder_ready_notifier.send_replace(false);

    if let Some(old_folder) = self.mutex_folder.swap(None) {
      let old_folder = old_folder.read().await;
      old_folder.close();
      info!(
        "🗑️ remove old folder: {}",
        old_folder.get_workspace_id().unwrap_or_default()
      );
    }

    // Get the collab db for the user with given user id.
    let collab_db = self.user.collab_db(uid)?;
    info!("✅ Got collab db for user: {}", uid);

    let (view_tx, view_rx) = tokio::sync::broadcast::channel(100);
    let (section_change_tx, section_change_rx) = tokio::sync::broadcast::channel(100);
    let folder_notifier = FolderNotify {
      view_change_tx: view_tx,
      section_change_tx,
    };

    let folder = match initial_data {
      FolderInitDataSource::LocalDisk {
        create_if_not_exist,
      } => {
        let is_exist = self
          .user
          .is_folder_exist_on_disk(uid, workspace_id)
          .unwrap_or(false);
        info!("📁 Folder exist on disk: {}, create_if_not_exist: {}", is_exist, create_if_not_exist);
        // 1. if the folder exists, open it from local disk
        if is_exist {
          event!(Level::INFO, "📂 Init folder from local disk");
          self
            .make_folder(uid, workspace_id, collab_db, None, folder_notifier)
            .await?
        } else if create_if_not_exist {
          // 2. if the folder doesn't exist and create_if_not_exist is true, create a default folder
          // Currently, this branch is only used when the server type is supabase. For appflowy cloud,
          // the default workspace is already created when the user sign up.
          event!(Level::INFO, "🆕 Create default folder");
          self
            .create_default_folder(uid, workspace_id, collab_db, folder_notifier)
            .await?
        } else {
          // 3. If the folder doesn't exist and create_if_not_exist is false, try to fetch the folder data from cloud/
          // This will happen user can't fetch the folder data when the user sign in.
          warn!("📡 Folder not found on disk, fetching from cloud...");
          match self
            .cloud_service()?
            .get_folder_doc_state(workspace_id, uid, CollabType::Folder, workspace_id)
            .await
          {
            Ok(doc_state) => {
              info!("📥 Got folder data from cloud, size: {} bytes", doc_state.len());
              self
                .make_folder(
                  uid,
                  workspace_id,
                  collab_db.clone(),
                  Some(DataSource::DocStateV1(doc_state)),
                  folder_notifier.clone(),
                )
                .await?
            },
            Err(err) => {
              error!("❌ Failed to fetch folder from cloud: {}, trying local disk fallback", err);
              // Fallback to local disk even if is_exist was false
              match self
                .make_folder(uid, workspace_id, collab_db.clone(), None, folder_notifier.clone())
                .await
              {
                Ok(folder) => {
                  warn!("⚠️ Using local folder data even though is_exist was false");
                  folder
                },
                Err(local_err) => {
                  error!("❌ All initialization methods failed: cloud error: {}, local error: {}", err, local_err);
                  return Err(local_err);
                }
              }
            }
          }
        }
      },
      FolderInitDataSource::Cloud(doc_state) => {
        if doc_state.is_empty() {
          event!(Level::ERROR, "❌ remote folder data is empty, open from local");
          self
            .make_folder(uid, workspace_id, collab_db, None, folder_notifier)
            .await?
        } else {
          event!(Level::INFO, "☁️ Restore folder from remote data, size: {} bytes", doc_state.len());
          self
            .make_folder(
              uid,
              workspace_id,
              collab_db.clone(),
              Some(DataSource::DocStateV1(doc_state)),
              folder_notifier.clone(),
            )
            .await?
        }
      },
    };

    let folder_state_rx = {
      let folder = folder.read().await;
      folder.subscribe_sync_state()
    };

    // 🔧 FIX: 在存储folder之前，确保folder已完全初始化
    info!("💾 Storing folder to mutex_folder...");
    self.mutex_folder.store(Some(folder.clone()));
    info!("✅ Folder stored successfully, workspace: {}", workspace_id);
    let _ = self.folder_ready_notifier.send_replace(true);
    info!("📢 Folder ready notifier sent, clients can now access folder data");

    let weak_mutex_folder = Arc::downgrade(&folder);
    subscribe_folder_sync_state_changed(*workspace_id, folder_state_rx, weak_mutex_folder.clone(), Arc::downgrade(&self.user));
    subscribe_folder_trash_changed(
      *workspace_id,
      section_change_rx,
      weak_mutex_folder.clone(),
      Arc::downgrade(&self.user),
    );
    subscribe_folder_view_changed(
      *workspace_id,
      view_rx,
      weak_mutex_folder.clone(),
      Arc::downgrade(&self.user),
    );

    Ok(())
  }

  async fn create_default_folder(
    &self,
    uid: i64,
    workspace_id: &Uuid,
    collab_db: Weak<CollabKVDB>,
    folder_notifier: FolderNotify,
  ) -> Result<Arc<RwLock<Folder>>, FlowyError> {
    event!(
      Level::INFO,
      "Create folder:{} with default folder builder",
      workspace_id
    );
    let folder_data =
      DefaultFolderBuilder::build(uid, workspace_id.to_string(), &self.operation_handlers).await;
    let folder = self
      .create_folder_with_data(
        uid,
        workspace_id,
        collab_db,
        Some(folder_notifier),
        Some(folder_data),
      )
      .await?;
    Ok(folder)
  }
}
