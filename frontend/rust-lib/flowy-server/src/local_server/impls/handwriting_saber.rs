#![allow(unused_variables)]
use collab::entity::EncodedCollab;
use flowy_handwriting_saber_pub::cloud::HandwritingSaberCloudService;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// Local implementation of HandwritingSaberCloudService
/// In local-only mode, handwriting saber data is only stored locally
pub(crate) struct LocalServerHandwritingSaberCloudServiceImpl();

#[async_trait]
impl HandwritingSaberCloudService for LocalServerHandwritingSaberCloudServiceImpl {
  async fn get_handwriting_saber_doc_state(
    &self,
    _handwriting_saber_id: &Uuid,
    _workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError> {
    Ok(vec![])
  }

  async fn get_handwriting_saber_data(
    &self,
    _handwriting_saber_id: &Uuid,
    _workspace_id: &Uuid,
  ) -> Result<Option<Vec<u8>>, FlowyError> {
    Ok(None)
  }

  async fn create_handwriting_saber_collab(
    &self,
    _workspace_id: &Uuid,
    _handwriting_saber_id: &Uuid,
    _encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError> {
    Ok(())
  }

  async fn save_handwriting_saber_data(
    &self,
    _handwriting_saber_id: &Uuid,
    _workspace_id: &Uuid,
    _sbn2_bytes: Vec<u8>,
    _version: i64,
  ) -> Result<i64, FlowyError> {
    Ok(_version + 1)
  }
}
