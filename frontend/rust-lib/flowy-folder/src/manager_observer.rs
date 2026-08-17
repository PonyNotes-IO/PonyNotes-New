use crate::entities::{
  ChildViewUpdatePB, FolderSyncStatePB, RepeatedTrashPB, RepeatedViewPB, SectionViewsPB, ViewPB,
  ViewSectionPB, view_pb_with_child_views, view_pb_without_child_views,
};
use crate::manager::{FolderUser, get_workspace_private_view_pbs, get_workspace_public_view_pbs};
use crate::notification::{FolderNotification, folder_notification_builder};
use collab::core::collab_state::SyncState;
use collab::lock::RwLock;
use collab_folder::{
  Folder, SectionChange, SectionChangeReceiver, TrashSectionChange, View, ViewChange,
  ViewChangeReceiver,
};
use lib_infra::sync_trace;

use std::collections::HashSet;
use std::str::FromStr;
use std::sync::Weak;
use tokio_stream::StreamExt;
use tokio_stream::wrappers::WatchStream;
use tracing::{Level, event, trace};
use uuid::Uuid;

/// Listen on the [ViewChange] after create/delete/update events happened
pub(crate) fn subscribe_folder_view_changed(
  workspace_id: Uuid,
  mut rx: ViewChangeReceiver,
  weak_mutex_folder: Weak<RwLock<Folder>>,
  user: Weak<dyn FolderUser>,
) {
  tokio::spawn(async move {
    loop {
      // 【2026-08-17 修复：Lagged 会让监听器永久退出】
      // rx 是容量 100 的 broadcast。原写法 `while let Ok(value) = rx.recv().await`
      // 在 Err 上一律退出循环，而 broadcast 在接收方落后于发送方时返回的是
      // Err(Lagged(n)) —— 它的含义只是「你漏掉了 n 条」，通道本身完全正常。
      // 断线重连后批量应用远端 folder 更新（例如休眠十几小时后唤醒）很容易一次
      // 产生超过 100 条 ViewChange，于是监听器被永久杀掉：此后视图的
      // 创建/删除/重命名再也不会通知到 Dart，侧边栏与中间栏静默停止更新。
      // 现在改为：Lagged 只记日志并继续接收，仅在 Closed（发送端已全部释放）时退出。
      let value = match rx.recv().await {
        Ok(value) => value,
        Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
          tracing::warn!(
            "[Folder] view change 监听落后，跳过 {} 条事件，继续接收（不退出监听）",
            skipped
          );
          continue;
        },
        Err(tokio::sync::broadcast::error::RecvError::Closed) => {
          trace!("[Folder] view change 通道已关闭，退出监听");
          break;
        },
      };
      if let Some(user) = user.upgrade() {
        if let Ok(actual_workspace_id) = user.workspace_id() {
          if actual_workspace_id != workspace_id {
            trace!("Did break the loop when the workspace id is not matched");
            // break the loop when the workspace id is not matched.
            break;
          }
        }
      }

      if let Some(lock) = weak_mutex_folder.upgrade() {
        trace!("Did receive view change: {:?}", value);
        match value {
          ViewChange::DidCreateView { view } => {
            notify_child_views_changed(
              view_pb_without_child_views(view.clone()),
              ChildViewChangeReason::Create,
            );
            let folder = lock.read().await;
            if let Ok(parent_view_id) = Uuid::from_str(&view.parent_view_id) {
              notify_parent_view_did_change(workspace_id, &folder, vec![parent_view_id]);
              sync_trace!("[Folder] create view: {:?}", view);
            }
          },
          ViewChange::DidDeleteView { views } => {
            for view in views {
              sync_trace!("[Folder] delete view: {:?}", view);

              notify_child_views_changed(
                view_pb_without_child_views(view.as_ref().clone()),
                ChildViewChangeReason::Delete,
              );
            }
          },
          ViewChange::DidUpdate { view } => {
            sync_trace!("[Folder] update view: {:?}", view);

            notify_view_did_change(view.clone());
            notify_child_views_changed(
              view_pb_without_child_views(view.clone()),
              ChildViewChangeReason::Update,
            );
            let folder = lock.read().await;
            if let Ok(parent_view_id) = Uuid::from_str(&view.parent_view_id) {
              notify_parent_view_did_change(workspace_id, &folder, vec![parent_view_id]);
            }
          },
        };
      }
    }
  });
}

pub(crate) fn subscribe_folder_sync_state_changed(
  workspace_id: Uuid,
  mut folder_sync_state_rx: WatchStream<SyncState>,
  weak_mutex_folder: Weak<RwLock<Folder>>,
  user: Weak<dyn FolderUser>,
) {
  tokio::spawn(async move {
    let mut was_syncing = false;
    while let Some(state) = folder_sync_state_rx.next().await {
      if let Some(user) = user.upgrade() {
        if let Ok(actual_workspace_id) = user.workspace_id() {
          if actual_workspace_id != workspace_id {
            // 首次安装/首次登录阶段 workspace_id 可能短暂未对齐。
            // 这里如果直接 break，会把同步状态监听永久退出，导致前端一直停留在“同步中”。
            // 改为跳过本次事件，等待后续 workspace 状态稳定后继续接收同步更新。
            continue;
          }
        }
      }

      let is_syncing = state.is_syncing();
      let is_finished = state.is_sync_finished();

      folder_notification_builder(
        workspace_id.to_string(),
        FolderNotification::DidUpdateFolderSyncUpdate,
      )
      .payload(FolderSyncStatePB::from(state))
      .send();

      if was_syncing && is_finished && !is_syncing {
        if let Some(lock) = weak_mutex_folder.upgrade() {
          let folder = lock.read().await;
          notify_did_update_workspace(&workspace_id, &folder);
          notify_did_update_section_views(&workspace_id, &folder);
          let repeated_trash: RepeatedTrashPB = folder.get_my_trash_info().into();
          folder_notification_builder("trash", FolderNotification::DidUpdateTrash)
            .payload(repeated_trash)
            .send();
        }
      }

      was_syncing = is_syncing;
    }
  });
}

/// Listen on the [TrashChange]s and notify the frontend some views were changed.
pub(crate) fn subscribe_folder_trash_changed(
  workspace_id: Uuid,
  mut rx: SectionChangeReceiver,
  weak_mutex_folder: Weak<RwLock<Folder>>,
  user: Weak<dyn FolderUser>,
) {
  tokio::spawn(async move {
    loop {
      // 【2026-08-17 修复】同 subscribe_folder_view_changed：Lagged 只表示漏收，
      // 不能据此退出监听，否则回收站变更此后永久不再通知前端。
      let value = match rx.recv().await {
        Ok(value) => value,
        Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
          tracing::warn!(
            "[Folder] trash change 监听落后，跳过 {} 条事件，继续接收（不退出监听）",
            skipped
          );
          continue;
        },
        Err(tokio::sync::broadcast::error::RecvError::Closed) => {
          trace!("[Folder] trash change 通道已关闭，退出监听");
          break;
        },
      };
      if let Some(user) = user.upgrade() {
        if let Ok(actual_workspace_id) = user.workspace_id() {
          if actual_workspace_id != workspace_id {
            // break the loop when the workspace id is not matched.
            break;
          }
        }
      }

      if let Some(lock) = weak_mutex_folder.upgrade() {
        let mut unique_ids = HashSet::new();
        tracing::trace!("Did receive trash change: {:?}", value);

        match value {
          SectionChange::Trash(change) => {
            let ids = match change {
              TrashSectionChange::TrashItemAdded { ids } => ids,
              TrashSectionChange::TrashItemRemoved { ids } => ids,
            };
            let folder = lock.read().await;
            let views = folder.get_views(&ids);
            for view in views {
              if let Ok(parent_view_id) = Uuid::from_str(&view.parent_view_id) {
                unique_ids.insert(parent_view_id);
              }
            }

            let repeated_trash: RepeatedTrashPB = folder.get_my_trash_info().into();
            folder_notification_builder("trash", FolderNotification::DidUpdateTrash)
              .payload(repeated_trash)
              .send();

            let parent_view_ids = unique_ids.into_iter().collect();
            notify_parent_view_did_change(workspace_id, &folder, parent_view_ids);
          },
        }
      }
    }
  });
}

/// Notify the list of parent view ids that its child views were changed.
#[tracing::instrument(level = "debug", skip(folder, parent_view_ids))]
pub(crate) fn notify_parent_view_did_change(
  workspace_id: Uuid,
  folder: &Folder,
  parent_view_ids: Vec<Uuid>,
) -> Option<()> {
  let trash_ids = folder
    .get_all_trash_sections()
    .into_iter()
    .map(|trash| trash.id)
    .collect::<Vec<String>>();

  for parent_view_id in parent_view_ids {
    // if the view's parent id equal to workspace id. Then it will fetch the current
    // workspace views. Because the workspace is not a view stored in the views map.
    if parent_view_id == workspace_id {
      notify_did_update_workspace(&workspace_id, folder);
      notify_did_update_section_views(&workspace_id, folder);
    } else {
      // Parent view can contain a list of child views. Currently, only get the first level
      // child views.
      let parent_view_id = parent_view_id.to_string();
      let parent_view = folder.get_view(&parent_view_id)?;
      let mut child_views = folder.get_views_belong_to(&parent_view_id);
      child_views.retain(|view| !trash_ids.contains(&view.id));
      event!(Level::DEBUG, child_views_count = child_views.len());

      // Post the notification
      let parent_view_pb = view_pb_with_child_views(parent_view, child_views);
      folder_notification_builder(&parent_view_id, FolderNotification::DidUpdateView)
        .payload(parent_view_pb)
        .send();
    }
  }

  None
}

pub(crate) fn notify_did_update_section_views(workspace_id: &Uuid, folder: &Folder) {
  let public_views = get_workspace_public_view_pbs(workspace_id, folder);
  let private_views = get_workspace_private_view_pbs(workspace_id, folder);
  trace!(
    "Did update section views: public len = {}, private len = {}",
    public_views.len(),
    private_views.len()
  );

  // Notify the public views
  folder_notification_builder(workspace_id, FolderNotification::DidUpdateSectionViews)
    .payload(SectionViewsPB {
      section: ViewSectionPB::Public,
      views: public_views,
    })
    .send();

  // Notify the private views
  folder_notification_builder(workspace_id, FolderNotification::DidUpdateSectionViews)
    .payload(SectionViewsPB {
      section: ViewSectionPB::Private,
      views: private_views,
    })
    .send();
}

pub(crate) fn notify_did_update_workspace(workspace_id: &Uuid, folder: &Folder) {
  let repeated_view: RepeatedViewPB = get_workspace_public_view_pbs(workspace_id, folder).into();
  folder_notification_builder(workspace_id, FolderNotification::DidUpdateWorkspaceViews)
    .payload(repeated_view)
    .send();
}

fn notify_view_did_change(view: View) -> Option<()> {
  let view_id = view.id.clone();
  let view_pb = view_pb_without_child_views(view);
  folder_notification_builder(&view_id, FolderNotification::DidUpdateView)
    .payload(view_pb)
    .send();
  None
}

pub enum ChildViewChangeReason {
  Create,
  Delete,
  Update,
}

/// Notify the list of parent view ids that its child views were changed.
#[tracing::instrument(level = "debug", skip_all)]
pub(crate) fn notify_child_views_changed(view_pb: ViewPB, reason: ChildViewChangeReason) {
  let parent_view_id = view_pb.parent_view_id.clone();
  let mut payload = ChildViewUpdatePB {
    parent_view_id: view_pb.parent_view_id.clone(),
    ..Default::default()
  };

  match reason {
    ChildViewChangeReason::Create => {
      payload.create_child_views.push(view_pb);
    },
    ChildViewChangeReason::Delete => {
      payload.delete_child_views.push(view_pb.id);
    },
    ChildViewChangeReason::Update => {
      payload.update_child_views.push(view_pb);
    },
  }

  folder_notification_builder(&parent_view_id, FolderNotification::DidUpdateChildViews)
    .payload(payload)
    .send();
}
