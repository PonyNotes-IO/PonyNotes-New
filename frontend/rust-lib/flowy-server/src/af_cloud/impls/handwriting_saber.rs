#![allow(unused_variables)]
use client_api::entity::{CreateCollabParams, QueryCollab, QueryCollabParams};
use collab::entity::EncodedCollab;
use collab_entity::CollabType;
use flowy_handwriting_saber_pub::cloud::HandwritingSaberCloudService;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use std::sync::Weak;
use tracing::instrument;
use uuid::Uuid;

use crate::af_cloud::AFServer;
use crate::af_cloud::define::LoggedUser;
use crate::af_cloud::impls::util::check_request_workspace_id_is_match;

pub(crate) struct AFCloudHandwritingSaberCloudServiceImpl<T> {
  pub inner: T,
  pub logged_user: Weak<dyn LoggedUser>,
}

#[async_trait]
impl<T> HandwritingSaberCloudService for AFCloudHandwritingSaberCloudServiceImpl<T>
where
  T: AFServer,
{
  #[instrument(level = "debug", skip_all, fields(handwriting_saber_id = %handwriting_saber_id))]
  async fn get_handwriting_saber_doc_state(
    &self,
    handwriting_saber_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError> {
    let params = QueryCollabParams {
      workspace_id: *workspace_id,
      inner: QueryCollab::new(*handwriting_saber_id, CollabType::Document),
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
      format!("get handwriting saber doc state:{}", handwriting_saber_id),
    )?;

    Ok(doc_state)
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
    workspace_id: &Uuid,
    handwriting_saber_id: &Uuid,
    encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError> {
    let params = CreateCollabParams {
      workspace_id: *workspace_id,
      object_id: *handwriting_saber_id,
      encoded_collab_v1: encoded_collab
        .encode_to_bytes()
        .map_err(|err| FlowyError::internal().with_context(err))?,
      collab_type: CollabType::Document,
    };
    self.inner.try_get_client()?.create_collab(params).await?;
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
