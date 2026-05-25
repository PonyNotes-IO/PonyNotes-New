#![allow(unused_variables)]
use collab::entity::EncodedCollab;
use flowy_whiteboard_pub::cloud::*;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use uuid::Uuid;

/// Local implementation of WhiteboardCloudService
/// For local-only mode, whiteboard data is only stored locally
pub(crate) struct LocalServerWhiteboardCloudServiceImpl();

#[async_trait]
impl WhiteboardCloudService for LocalServerWhiteboardCloudServiceImpl {
  async fn get_whiteboard_doc_state(
    &self,
    _whiteboard_id: &Uuid,
    _workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError> {
    // In local mode, we don't have cloud storage
    // Return empty to indicate no cloud data available
    Ok(vec![])
  }

  async fn get_whiteboard_snapshots(
    &self,
    _whiteboard_id: &Uuid,
    _limit: usize,
    _workspace_id: &str,
  ) -> Result<Vec<WhiteboardSnapshot>, FlowyError> {
    // No snapshots in local mode
    Ok(vec![])
  }

  async fn get_whiteboard_data(
    &self,
    _whiteboard_id: &Uuid,
    _workspace_id: &Uuid,
  ) -> Result<Option<String>, FlowyError> {
    // No cloud data in local mode
    Ok(None)
  }

  async fn create_whiteboard_collab(
    &self,
    _workspace_id: &Uuid,
    _whiteboard_id: &Uuid,
    _encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError> {
    // In local mode, we don't need to upload to cloud
    // Just return Ok to indicate success
    Ok(())
  }
}
