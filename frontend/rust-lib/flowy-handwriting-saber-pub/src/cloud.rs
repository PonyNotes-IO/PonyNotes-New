use collab::entity::EncodedCollab;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// A trait for handwriting saber cloud service.
/// Each kind of server should implement this trait. Check out the [AppFlowyServerProvider] of
/// [flowy-server] crate for more information.
#[async_trait]
pub trait HandwritingSaberCloudService: Send + Sync + 'static {
  /// Get handwriting saber doc state from cloud
  async fn get_handwriting_saber_doc_state(
    &self,
    handwriting_saber_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError>;

  /// Get handwriting saber data from cloud (as .sbn2 bytes)
  async fn get_handwriting_saber_data(
    &self,
    handwriting_saber_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Option<Vec<u8>>, FlowyError>;

  /// Create handwriting saber collab in cloud
  async fn create_handwriting_saber_collab(
    &self,
    workspace_id: &Uuid,
    handwriting_saber_id: &Uuid,
    encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError>;

  /// Save handwriting saber data to cloud
  async fn save_handwriting_saber_data(
    &self,
    handwriting_saber_id: &Uuid,
    workspace_id: &Uuid,
    sbn2_bytes: Vec<u8>,
    version: i64,
  ) -> Result<i64, FlowyError>;
}

