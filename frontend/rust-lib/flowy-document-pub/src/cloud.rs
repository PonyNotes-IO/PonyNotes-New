use collab::entity::EncodedCollab;
pub use collab_document::blocks::DocumentData;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// A trait for document cloud service.
/// Each kind of server should implement this trait. Check out the [AppFlowyServerProvider] of
/// [flowy-server] crate for more information.
#[async_trait]
pub trait DocumentCloudService: Send + Sync + 'static {
  async fn list_document_versions(
    &self,
    _document: &Uuid,
    _workspace: &Uuid,
    _offset: u32,
  ) -> Result<DocumentVersionList, FlowyError> {
    Err(FlowyError::not_support())
  }

  async fn get_document_version(
    &self,
    _document: &Uuid,
    _workspace: &Uuid,
    _snapshot: &Uuid,
  ) -> Result<DocumentData, FlowyError> {
    Err(FlowyError::not_support())
  }

  async fn save_document_version(
    &self,
    _document: &Uuid,
    _workspace: &Uuid,
    _data: DocumentData,
  ) -> Result<DocumentVersionMeta, FlowyError> {
    Err(FlowyError::not_support())
  }
  async fn get_document_doc_state(
    &self,
    document_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError>;

  async fn get_document_snapshots(
    &self,
    document_id: &Uuid,
    limit: usize,
    workspace_id: &str,
  ) -> Result<Vec<DocumentSnapshot>, FlowyError>;

  async fn get_document_data(
    &self,
    document_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Option<DocumentData>, FlowyError>;

  async fn create_document_collab(
    &self,
    workspace_id: &Uuid,
    document_id: &Uuid,
    encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError>;
}

pub struct DocumentSnapshot {
  pub snapshot_id: i64,
  pub document_id: String,
  pub data: Vec<u8>,
  pub created_at: i64,
}

pub struct DocumentVersionMeta {
  pub snapshot_id: String,
  pub object_id: String,
  pub created_at: i64,
  pub reused: bool,
}

pub struct DocumentVersionList {
  pub items: Vec<DocumentVersionMeta>,
  pub has_more: bool,
  pub retention_days: i32,
}
