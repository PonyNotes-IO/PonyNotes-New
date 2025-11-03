use collab::entity::EncodedCollab;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// A trait for whiteboard cloud service.
/// Each kind of server should implement this trait. Check out the [AppFlowyServerProvider] of
/// [flowy-server] crate for more information.
#[async_trait]
pub trait WhiteboardCloudService: Send + Sync + 'static {
  /// Get whiteboard doc state from cloud
  async fn get_whiteboard_doc_state(
    &self,
    whiteboard_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError>;

  /// Get whiteboard snapshots from cloud
  async fn get_whiteboard_snapshots(
    &self,
    whiteboard_id: &Uuid,
    limit: usize,
    workspace_id: &str,
  ) -> Result<Vec<WhiteboardSnapshot>, FlowyError>;

  /// Get whiteboard data from cloud (as JSON string)
  async fn get_whiteboard_data(
    &self,
    whiteboard_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Option<String>, FlowyError>;

  /// Create whiteboard collab in cloud
  async fn create_whiteboard_collab(
    &self,
    workspace_id: &Uuid,
    whiteboard_id: &Uuid,
    encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError>;
}

pub struct WhiteboardSnapshot {
  pub snapshot_id: i64,
  pub whiteboard_id: String,
  pub data: Vec<u8>,
  pub created_at: i64,
}


