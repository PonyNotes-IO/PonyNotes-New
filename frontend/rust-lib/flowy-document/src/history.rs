use crate::{entities::*, manager::DocumentManager};
use collab::lock::RwLock;
use collab_document::{
  blocks::DocumentData,
  document::{Document, DocumentBody},
};
use flowy_document_pub::cloud::{DocumentCloudService, DocumentVersionMeta};
use flowy_error::{FlowyError, FlowyResult};
use lib_dispatch::prelude::{AFPluginData, AFPluginState, DataResult, data_result_ok};
use std::sync::Weak;
use uuid::Uuid;

#[derive(Default, flowy_derive::ProtoBuf)]
pub struct DocumentHistoryQueryPB {
  #[pb(index = 1)]
  pub document_id: String,
  #[pb(index = 2)]
  pub workspace_id: String,
  #[pb(index = 3)]
  pub snapshot_id: String,
  #[pb(index = 4)]
  pub offset: i32,
}

#[derive(Default, flowy_derive::ProtoBuf)]
pub struct DocumentHistoryListPB {
  #[pb(index = 1)]
  pub items: Vec<DocumentSnapshotMetaPB>,
  #[pb(index = 2)]
  pub has_more: bool,
  #[pb(index = 3)]
  pub retention_days: i32,
  #[pb(index = 4)]
  pub storage_limited: bool,
}

#[derive(Default, flowy_derive::ProtoBuf)]
pub struct DocumentHistoryIndexQueryPB {
  #[pb(index = 1)]
  pub search: String,
  #[pb(index = 2)]
  pub workspace_id: String,
  #[pb(index = 3)]
  pub before: i64,
  #[pb(index = 4)]
  pub before_document: String,
}

#[derive(Default, flowy_derive::ProtoBuf)]
pub struct DocumentHistoryIndexPB {
  #[pb(index = 1)]
  pub items: Vec<DocumentHistorySummaryPB>,
  #[pb(index = 2)]
  pub has_more: bool,
}

#[derive(Default, flowy_derive::ProtoBuf)]
pub struct DocumentHistorySummaryPB {
  #[pb(index = 1)]
  pub workspace_id: String,
  #[pb(index = 2)]
  pub document_id: String,
  #[pb(index = 3)]
  pub name: String,
  #[pb(index = 4)]
  pub workspace_name: String,
  #[pb(index = 5)]
  pub path: Vec<String>,
  #[pb(index = 6)]
  pub latest_version_at: i64,
}

pub(crate) async fn list_documents_with_history_handler(
  data: AFPluginData<DocumentHistoryIndexQueryPB>,
  manager: AFPluginState<Weak<DocumentManager>>,
) -> DataResult<DocumentHistoryIndexPB, FlowyError> {
  let manager = manager.upgrade().ok_or_else(FlowyError::ref_drop)?;
  let query = data.into_inner();
  let result = manager
    .cloud_service
    .list_documents_with_history(
      &query.search,
      &query.workspace_id,
      query.before,
      &query.before_document,
    )
    .await?;
  data_result_ok(DocumentHistoryIndexPB {
    items: result
      .items
      .into_iter()
      .map(|item| DocumentHistorySummaryPB {
        workspace_id: item.workspace_id,
        document_id: item.document_id,
        name: item.name,
        workspace_name: item.workspace_name,
        path: item.path,
        latest_version_at: item.latest_version_at,
      })
      .collect(),
    has_more: result.has_more,
  })
}

fn parse(manager: &DocumentManager, query: &DocumentHistoryQueryPB) -> FlowyResult<(Uuid, Uuid)> {
  let document = Uuid::parse_str(&query.document_id).map_err(|_| FlowyError::invalid_data())?;
  let workspace = if !query.workspace_id.is_empty() {
    Uuid::parse_str(&query.workspace_id).map_err(|_| FlowyError::invalid_data())?
  } else if let Some(source) = manager
    .user_service
    .shared_view_source_workspace_id(&query.document_id)
  {
    Uuid::parse_str(&source).map_err(|_| FlowyError::invalid_data())?
  } else {
    manager.user_service.workspace_id()?
  };
  Ok((document, workspace))
}

impl From<flowy_document_pub::cloud::DocumentVersionMeta> for DocumentSnapshotMetaPB {
  fn from(v: flowy_document_pub::cloud::DocumentVersionMeta) -> Self {
    Self {
      snapshot_id: v.snapshot_id,
      object_id: v.object_id,
      created_at: v.created_at,
      reused: v.reused,
      source: v.source,
    }
  }
}

pub(crate) async fn list_document_versions_handler(
  data: AFPluginData<DocumentHistoryQueryPB>,
  manager: AFPluginState<Weak<DocumentManager>>,
) -> DataResult<DocumentHistoryListPB, FlowyError> {
  let manager = manager.upgrade().ok_or_else(FlowyError::ref_drop)?;
  let query = data.into_inner();
  let (document, workspace) = parse(&manager, &query)?;
  let offset = u32::try_from(query.offset).map_err(|_| FlowyError::invalid_data())?;
  let result = manager
    .cloud_service
    .list_document_versions(&document, &workspace, offset)
    .await?;
  data_result_ok(DocumentHistoryListPB {
    items: result.items.into_iter().map(Into::into).collect(),
    has_more: result.has_more,
    retention_days: result.retention_days,
    storage_limited: result.storage_limited,
  })
}

pub(crate) async fn get_document_version_handler(
  data: AFPluginData<DocumentHistoryQueryPB>,
  manager: AFPluginState<Weak<DocumentManager>>,
) -> DataResult<DocumentDataPB, FlowyError> {
  let manager = manager.upgrade().ok_or_else(FlowyError::ref_drop)?;
  let query = data.into_inner();
  let (document, workspace) = parse(&manager, &query)?;
  let snapshot = Uuid::parse_str(&query.snapshot_id).map_err(|_| FlowyError::invalid_data())?;
  let data = manager
    .cloud_service
    .get_document_version(&document, &workspace, &snapshot)
    .await?;
  data_result_ok(data.into())
}

pub(crate) async fn save_document_version_handler(
  data: AFPluginData<DocumentHistoryQueryPB>,
  manager: AFPluginState<Weak<DocumentManager>>,
) -> DataResult<DocumentSnapshotMetaPB, FlowyError> {
  let manager = manager.upgrade().ok_or_else(FlowyError::ref_drop)?;
  let query = data.into_inner();
  let (document, workspace) = parse(&manager, &query)?;
  // Read the live editor's collab, including changes not yet synchronized to the server.
  let live = manager.editable_document(&document).await?;
  let data = live
    .read()
    .await
    .get_document_data()
    .map_err(|e| FlowyError::internal().with_context(e))?;
  let result = manager
    .cloud_service
    .save_document_version(&document, &workspace, data)
    .await?;
  data_result_ok(result.into())
}

pub(crate) async fn restore_document_version_handler(
  data: AFPluginData<DocumentHistoryQueryPB>,
  manager: AFPluginState<Weak<DocumentManager>>,
) -> DataResult<DocumentSnapshotMetaPB, FlowyError> {
  let manager = manager.upgrade().ok_or_else(FlowyError::ref_drop)?;
  let query = data.into_inner();
  let (document, workspace) = parse(&manager, &query)?;
  let snapshot = Uuid::parse_str(&query.snapshot_id).map_err(|_| FlowyError::invalid_data())?;
  let target = manager
    .cloud_service
    .get_document_version(&document, &workspace, &snapshot)
    .await?;
  let live = manager.editable_document(&document).await?;
  if !query.workspace_id.is_empty() {
    let remote = manager
      .get_cloud_document_data(&document, Some(workspace))
      .await?;
    let current = live.read().await.get_document_data()?;
    if serde_json::to_value(&current)? != serde_json::to_value(remote)? {
      return Err(FlowyError::invalid_data().with_context("history_document_changed"));
    }
  }
  let backup = restore_with_backup(
    &live,
    manager.cloud_service.as_ref(),
    &document,
    &workspace,
    target,
  )
  .await?;
  manager.mark_document_dirty(&document);
  data_result_ok(backup.into())
}

async fn restore_with_backup(
  live: &RwLock<Document>,
  cloud: &dyn DocumentCloudService,
  document: &Uuid,
  workspace: &Uuid,
  target: DocumentData,
) -> FlowyResult<DocumentVersionMeta> {
  Document::create(&document.to_string(), target.clone())?;
  let current = live.read().await.get_document_data()?;
  let backup = cloud
    .save_document_backup(document, workspace, current.clone())
    .await?;
  replace_if_unchanged(&mut *live.write().await, &current, target)?;
  Ok(backup)
}

fn replace_if_unchanged(
  document: &mut Document,
  expected: &DocumentData,
  target: DocumentData,
) -> FlowyResult<()> {
  let mut body = DocumentBody::from_collab(document).ok_or_else(FlowyError::invalid_data)?;
  let mut txn = document.transact_mut();
  let actual = body.get_document_data(&txn)?;
  if serde_json::to_value(&actual)? != serde_json::to_value(expected)? {
    return Err(FlowyError::invalid_data().with_context("history_document_changed"));
  }
  // reset_with_data appends text deltas; remove old text and child maps first.
  for id in actual
    .meta
    .text_map
    .as_ref()
    .into_iter()
    .flat_map(|map| map.keys())
  {
    body.text_operation.delete_text_with_txn(&mut txn, id);
  }
  for id in actual.meta.children_map.keys() {
    body
      .children_operation
      .delete_children_with_txn(&mut txn, id);
  }
  body.reset_with_data(&mut txn, Some(target))?;
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;
  use collab::entity::EncodedCollab;
  use collab_document::document_data::default_document_data;
  use flowy_document_pub::cloud::DocumentSnapshot;
  use std::sync::{Arc, Mutex};

  #[derive(Default)]
  struct TestCloud {
    saved: Mutex<Vec<DocumentData>>,
    fail: bool,
    concurrent: Option<Arc<RwLock<Document>>>,
  }

  #[lib_infra::async_trait::async_trait]
  impl DocumentCloudService for TestCloud {
    async fn save_document_version(
      &self,
      document: &Uuid,
      _: &Uuid,
      data: DocumentData,
    ) -> FlowyResult<DocumentVersionMeta> {
      if self.fail {
        return Err(FlowyError::internal().with_context("cloud_storage_full"));
      }
      let reused = {
        let mut saved = self.saved.lock().unwrap();
        let reused = saved
          .iter()
          .any(|item| serde_json::to_value(item).unwrap() == serde_json::to_value(&data).unwrap());
        if !reused {
          saved.push(data);
        }
        reused
      };
      if let Some(live) = &self.concurrent {
        live
          .write()
          .await
          .apply_text_delta("concurrent", r#"[{"insert":"incoming edit"}]"#.into());
      }
      Ok(DocumentVersionMeta {
        snapshot_id: Uuid::new_v4().to_string(),
        object_id: document.to_string(),
        created_at: 0,
        reused,
        source: String::new(),
      })
    }
    async fn get_document_doc_state(&self, _: &Uuid, _: &Uuid) -> FlowyResult<Vec<u8>> {
      unreachable!()
    }
    async fn get_document_snapshots(
      &self,
      _: &Uuid,
      _: usize,
      _: &str,
    ) -> FlowyResult<Vec<DocumentSnapshot>> {
      unreachable!()
    }
    async fn get_document_data(&self, _: &Uuid, _: &Uuid) -> FlowyResult<Option<DocumentData>> {
      unreachable!()
    }
    async fn create_document_collab(
      &self,
      _: &Uuid,
      _: &Uuid,
      _: EncodedCollab,
    ) -> FlowyResult<()> {
      unreachable!()
    }
  }

  #[tokio::test]
  async fn each_switch_saves_the_content_being_replaced() {
    let id = Uuid::new_v4();
    let workspace = Uuid::new_v4();
    let mut document =
      Document::create(&id.to_string(), default_document_data(&id.to_string())).unwrap();
    let older = document.get_document_data().unwrap();
    document.apply_text_delta("new-text", r#"[{"insert":"newer content"}]"#.into());
    let newer = document.get_document_data().unwrap();
    let live = RwLock::new(document);
    let cloud = TestCloud::default();
    restore_with_backup(&live, &cloud, &id, &workspace, older.clone())
      .await
      .unwrap();
    assert_eq!(
      serde_json::to_value(live.read().await.get_document_data().unwrap()).unwrap(),
      serde_json::to_value(&older).unwrap()
    );
    let saved_newer = cloud.saved.lock().unwrap()[0].clone();
    assert_eq!(
      serde_json::to_value(&saved_newer).unwrap(),
      serde_json::to_value(&newer).unwrap()
    );
    restore_with_backup(&live, &cloud, &id, &workspace, saved_newer)
      .await
      .unwrap();
    assert_eq!(
      serde_json::to_value(live.read().await.get_document_data().unwrap()).unwrap(),
      serde_json::to_value(&newer).unwrap()
    );
    assert_eq!(
      serde_json::to_value(&cloud.saved.lock().unwrap()[1]).unwrap(),
      serde_json::to_value(&older).unwrap()
    );
    let result = restore_with_backup(&live, &cloud, &id, &workspace, older.clone())
      .await
      .unwrap();
    assert!(result.reused);
    assert_eq!(cloud.saved.lock().unwrap().len(), 2);
    assert_eq!(
      serde_json::to_value(live.read().await.get_document_data().unwrap()).unwrap(),
      serde_json::to_value(older).unwrap()
    );
  }

  #[tokio::test]
  async fn failed_backup_never_changes_the_document() {
    let id = Uuid::new_v4();
    let document =
      Document::create(&id.to_string(), default_document_data(&id.to_string())).unwrap();
    let before = document.get_document_data().unwrap();
    let mut target = before.clone();
    target
      .meta
      .text_map
      .as_mut()
      .unwrap()
      .insert("target".into(), r#"[{"insert":"old content"}]"#.into());
    let live = RwLock::new(document);
    let cloud = TestCloud {
      fail: true,
      ..Default::default()
    };
    assert!(
      restore_with_backup(&live, &cloud, &id, &Uuid::new_v4(), target)
        .await
        .is_err()
    );
    assert!(cloud.saved.lock().unwrap().is_empty());
    assert_eq!(
      serde_json::to_value(live.read().await.get_document_data().unwrap()).unwrap(),
      serde_json::to_value(before).unwrap()
    );
  }

  #[tokio::test]
  async fn edits_arriving_during_backup_abort_restore() {
    let id = Uuid::new_v4();
    let document =
      Document::create(&id.to_string(), default_document_data(&id.to_string())).unwrap();
    let target = document.get_document_data().unwrap();
    let live = Arc::new(RwLock::new(document));
    let cloud = TestCloud {
      concurrent: Some(live.clone()),
      ..Default::default()
    };
    let error = restore_with_backup(&live, &cloud, &id, &Uuid::new_v4(), target)
      .await
      .err()
      .unwrap();
    assert!(error.msg.contains("history_document_changed"));
    assert_eq!(cloud.saved.lock().unwrap().len(), 1);
    assert!(
      live
        .read()
        .await
        .get_document_data()
        .unwrap()
        .meta
        .text_map
        .unwrap()
        .contains_key("concurrent")
    );
  }

  #[test]
  fn restoring_back_and_forth_replaces_text_without_appending() {
    let id = Uuid::new_v4().to_string();
    let initial = default_document_data(&id);
    let mut document = Document::create(&id, initial).unwrap();
    // Use the same external text identity in both versions.
    document.apply_text_delta("shared-text", r#"[{"insert":"new content"}]"#.into());
    let newer = document.get_document_data().unwrap();
    document.apply_text_delta(
      "shared-text",
      r#"[{"delete":11},{"insert":"old content"}]"#.into(),
    );
    let older = document.get_document_data().unwrap();
    for (from, to) in [(&older, &newer), (&newer, &older), (&older, &newer)] {
      replace_if_unchanged(&mut document, from, to.clone()).unwrap();
      assert_eq!(
        serde_json::to_value(document.get_document_data().unwrap()).unwrap(),
        serde_json::to_value(to).unwrap()
      );
    }
  }

  #[test]
  fn changed_document_is_not_overwritten() {
    let id = Uuid::new_v4().to_string();
    let mut document = Document::create(&id, default_document_data(&id)).unwrap();
    let backup = document.get_document_data().unwrap();
    document.apply_text_delta("new-text", r#"[{"insert":"concurrent edit"}]"#.into());
    let current = document.get_document_data().unwrap();
    let error = replace_if_unchanged(&mut document, &backup, backup.clone()).unwrap_err();
    assert!(error.msg.contains("history_document_changed"));
    assert_eq!(
      serde_json::to_value(document.get_document_data().unwrap()).unwrap(),
      serde_json::to_value(current).unwrap()
    );
  }
}
