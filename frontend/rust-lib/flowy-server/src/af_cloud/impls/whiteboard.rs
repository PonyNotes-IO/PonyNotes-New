#![allow(unused_variables)]
use client_api::entity::{CreateCollabParams, QueryCollab, QueryCollabParams};
use collab::entity::EncodedCollab;
use collab_entity::CollabType;
use flowy_whiteboard_pub::cloud::*;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use std::sync::Weak;
use tracing::instrument;
use uuid::Uuid;

use crate::af_cloud::AFServer;
use crate::af_cloud::define::LoggedUser;
use crate::af_cloud::impls::util::check_request_workspace_id_is_match;

pub(crate) struct AFCloudWhiteboardCloudServiceImpl<T> {
  pub inner: T,
  pub logged_user: Weak<dyn LoggedUser>,
}

#[async_trait]
impl<T> WhiteboardCloudService for AFCloudWhiteboardCloudServiceImpl<T>
where
  T: AFServer,
{
  #[instrument(level = "debug", skip_all, fields(whiteboard_id = %whiteboard_id))]
  async fn get_whiteboard_doc_state(
    &self,
    whiteboard_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError> {
    let params = QueryCollabParams {
      workspace_id: *workspace_id,
      // Use Document type for now, will change to Whiteboard when CollabType::Whiteboard is added
      inner: QueryCollab::new(*whiteboard_id, CollabType::Document),
    };
    let doc_state = self
      .inner
      .try_get_client()?
      .get_collab(params)
      .await
      .map_err(FlowyError::from)?
      .encode_collab
      .doc_state
      .to_vec();

    check_request_workspace_id_is_match(
      workspace_id,
      &self.logged_user,
      format!("get whiteboard doc state:{}", whiteboard_id),
    )?;

    Ok(doc_state)
  }

  async fn get_whiteboard_snapshots(
    &self,
    whiteboard_id: &Uuid,
    limit: usize,
    workspace_id: &str,
  ) -> Result<Vec<WhiteboardSnapshot>, FlowyError> {
    // TODO: Implement whiteboard snapshots when server support is added
    Ok(vec![])
  }

  #[instrument(level = "debug", skip_all)]
  async fn get_whiteboard_data(
    &self,
    whiteboard_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Option<String>, FlowyError> {
    // TODO: Implement get whiteboard data when needed
    // For now, we just use doc_state
    Ok(None)
  }

  async fn create_whiteboard_collab(
    &self,
    workspace_id: &Uuid,
    whiteboard_id: &Uuid,
    encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError> {
    let params = CreateCollabParams {
      workspace_id: *workspace_id,
      object_id: *whiteboard_id,
      encoded_collab_v1: encoded_collab
        .encode_to_bytes()
        .map_err(|err| FlowyError::internal().with_context(err))?,
      // Use Document type for now, will change to Whiteboard when CollabType::Whiteboard is added
      collab_type: CollabType::Document,
    };
    self.inner.try_get_client()?.create_collab(params).await?;
    Ok(())
  }
}

