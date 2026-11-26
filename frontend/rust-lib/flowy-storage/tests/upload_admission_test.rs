use async_trait::async_trait;
use flowy_error::{ErrorCode, FlowyError, FlowyResult};
use flowy_sqlite::{DBConnection, Database};
use flowy_storage::manager::{StorageManager, StorageUserService};
use flowy_storage::sqlite_sql::{batch_select_upload_file, select_upload_file};
use flowy_storage_pub::cloud::{ObjectIdentity, ObjectValue, StorageCloudService};
use flowy_storage_pub::storage::{CompletedPartRequest, CreateUploadResponse, UploadPartResponse};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

struct TestUser {
  root: String,
  db: Database,
  workspace: Uuid,
}

impl StorageUserService for TestUser {
  fn user_id(&self) -> FlowyResult<i64> {
    Ok(1)
  }
  fn workspace_id(&self) -> FlowyResult<Uuid> {
    Ok(self.workspace)
  }
  fn sqlite_connection(&self, _: i64) -> FlowyResult<DBConnection> {
    self
      .db
      .get_connection()
      .map_err(|e| FlowyError::internal().with_context(e))
  }
  fn get_application_root_dir(&self) -> &str {
    &self.root
  }
}

struct TestCloud {
  error: Mutex<Option<ErrorCode>>,
  admissions: Mutex<Vec<u64>>,
}

#[async_trait]
impl StorageCloudService for TestCloud {
  async fn get_object_url(&self, _: ObjectIdentity) -> FlowyResult<String> {
    unreachable!()
  }
  async fn put_object(&self, _: String, _: ObjectValue) -> FlowyResult<()> {
    unreachable!()
  }
  async fn delete_object(&self, _: &str) -> FlowyResult<()> {
    unreachable!()
  }
  async fn get_object(&self, _: String) -> FlowyResult<ObjectValue> {
    unreachable!()
  }
  async fn get_object_url_v1(
    &self,
    workspace: &Uuid,
    parent: &str,
    file: &str,
  ) -> FlowyResult<String> {
    Ok(format!("https://example.test/{workspace}/{parent}/{file}"))
  }
  async fn parse_object_url_v1(&self, url: &str) -> Option<(Uuid, String, String)> {
    let mut fields = url.strip_prefix("https://example.test/")?.split('/');
    Some((
      fields.next()?.parse().ok()?,
      fields.next()?.into(),
      fields.next()?.into(),
    ))
  }
  async fn check_object_exists(&self, _: &Uuid, _: &str, _: &str) -> FlowyResult<()> {
    Err(FlowyError::record_not_found())
  }
  async fn create_upload(
    &self,
    _: &Uuid,
    _: &str,
    file: &str,
    _: &str,
    size: u64,
  ) -> FlowyResult<CreateUploadResponse> {
    self.admissions.lock().unwrap().push(size);
    if let Some(code) = self.error.lock().unwrap().clone() {
      return Err(FlowyError::new(code, "admission rejected"));
    }
    Ok(CreateUploadResponse {
      file_id: file.into(),
      upload_id: "admitted-session".into(),
    })
  }
  async fn upload_part(
    &self,
    _: &Uuid,
    _: &str,
    upload_id: &str,
    _: &str,
    part_num: i32,
    body: Vec<u8>,
  ) -> FlowyResult<UploadPartResponse> {
    assert_eq!(upload_id, "admitted-session");
    assert_eq!(body, b"video");
    Ok(UploadPartResponse {
      part_num,
      e_tag: "part-1".into(),
    })
  }
  async fn complete_upload(
    &self,
    _: &Uuid,
    _: &str,
    upload_id: &str,
    _: &str,
    parts: Vec<CompletedPartRequest>,
  ) -> FlowyResult<()> {
    assert_eq!(upload_id, "admitted-session");
    assert_eq!(parts.len(), 1);
    Ok(())
  }
}

#[tokio::test]
async fn quota_rejection_returns_no_url_or_task_and_offline_still_queues() {
  let root = std::env::temp_dir().join(format!("upload-admission-{}", Uuid::new_v4()));
  std::fs::create_dir(&root).unwrap();
  let user = Arc::new(TestUser {
    root: root.to_str().unwrap().into(),
    db: flowy_sqlite::init(root.join("user.db")).unwrap(),
    workspace: Uuid::new_v4(),
  });
  let cloud = Arc::new(TestCloud {
    error: Mutex::new(Some(ErrorCode::FileStorageLimitExceeded)),
    admissions: Mutex::new(vec![]),
  });
  let manager = StorageManager::new(cloud.clone(), user.clone());
  let workspace = user.workspace.to_string();
  let file = root.join("video.mp4");
  std::fs::write(&file, b"video").unwrap();
  let file = file.to_str().unwrap();
  for code in [
    ErrorCode::FileStorageLimitExceeded,
    ErrorCode::SingleUploadLimitExceeded,
  ] {
    *cloud.error.lock().unwrap() = Some(code.clone());
    let err = match manager
      .storage_service
      .create_upload(&workspace, "document", file)
      .await
    {
      Err(err) => err,
      Ok(_) => panic!("a quota rejection must not return an attachment URL"),
    };
    assert_eq!(err.code, code);
    assert!(manager.get_all_tasks().await.unwrap().is_empty());
    assert!(
      batch_select_upload_file(user.db.get_connection().unwrap(), &workspace, 100, false)
        .unwrap()
        .is_empty()
    );
    assert_eq!(
      std::fs::read_dir(root.join("cache_files")).unwrap().count(),
      0
    );
  }
  assert_eq!(*cloud.admissions.lock().unwrap(), vec![5, 5]);

  *cloud.error.lock().unwrap() = None;
  let (upload, _) = manager
    .storage_service
    .create_upload(&workspace, "document", file)
    .await
    .unwrap();
  let saved = select_upload_file(
    &mut user.db.get_connection().unwrap(),
    &workspace,
    "document",
    &upload.file_id,
  )
  .unwrap()
  .unwrap();
  assert_eq!(saved.upload_id, "admitted-session");
  assert_eq!(manager.get_all_tasks().await.unwrap().len(), 1);
  assert!(
    !manager
      .query_file_state(&upload.url)
      .await
      .unwrap()
      .upload_failed
  );

  // The uploader consumes the admitted session without creating it again.
  manager
    .storage_service
    .resume_upload(&workspace, "document", &upload.file_id)
    .await
    .unwrap();
  assert!(
    manager
      .query_file_state(&upload.url)
      .await
      .unwrap()
      .is_finish
  );
  assert_eq!(*cloud.admissions.lock().unwrap(), vec![5, 5, 5]);

  *cloud.error.lock().unwrap() = Some(ErrorCode::NetworkError);
  let (network_error, _) = manager
    .storage_service
    .create_upload(&workspace, "network", file)
    .await
    .unwrap();
  let saved = select_upload_file(
    &mut user.db.get_connection().unwrap(),
    &workspace,
    "network",
    &network_error.file_id,
  )
  .unwrap()
  .unwrap();
  assert!(saved.upload_id.is_empty());

  manager.update_network_reachable(false);
  *cloud.error.lock().unwrap() = Some(ErrorCode::FileStorageLimitExceeded);
  let (offline, _) = manager
    .storage_service
    .create_upload(&workspace, "offline", file)
    .await
    .unwrap();
  let saved = select_upload_file(
    &mut user.db.get_connection().unwrap(),
    &workspace,
    "offline",
    &offline.file_id,
  )
  .unwrap()
  .unwrap();
  assert!(saved.upload_id.is_empty());
  assert_eq!(*cloud.admissions.lock().unwrap(), vec![5, 5, 5, 5]);
  assert_eq!(manager.get_all_tasks().await.unwrap().len(), 3);
}
