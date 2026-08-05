#![allow(unused_variables)]
use client_api::entity::{CreateCollabParams, QueryCollab, QueryCollabParams};
use collab::core::collab::DataSource;
use collab::core::origin::CollabOrigin;
use collab::entity::EncodedCollab;
use collab::preclude::Collab;
use collab_document::document::Document;
use collab_entity::CollabType;
use flowy_document_pub::cloud::*;
use flowy_error::FlowyError;
use lib_infra::async_trait::async_trait;
use std::sync::Weak;
use tracing::instrument;
use uuid::Uuid;

use crate::af_cloud::AFServer;
use crate::af_cloud::define::LoggedUser;
use crate::af_cloud::impls::util::check_request_workspace_id_is_match;

pub(crate) struct AFCloudDocumentCloudServiceImpl<T> {
  pub inner: T,
  pub logged_user: Weak<dyn LoggedUser>,
}

#[async_trait]
impl<T> DocumentCloudService for AFCloudDocumentCloudServiceImpl<T>
where
  T: AFServer,
{
  #[instrument(level = "debug", skip_all, fields(document_id = %document_id))]
  async fn get_document_doc_state(
    &self,
    document_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Vec<u8>, FlowyError> {
    let params = QueryCollabParams {
      workspace_id: *workspace_id,
      inner: QueryCollab::new(*document_id, CollabType::Document),
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

    // 【共享文档修复 2026-07-03】不再用"当前 workspace"比对拦截显式 workspace 请求。
    // 该检查的本意是防"请求期间用户切换 workspace"的竞态;但共享文档的拉取本来就显式
    // 指向文档 owner 的 workspace,与当前 workspace 天然不等,数据已按 document_id 成功
    // 取回却在此被丢弃,导致被分享者打开共享文档报 Internal。参数即显式意图,按
    // document_id 使用结果不存在串仓风险,降级为日志。
    if let Err(err) = check_request_workspace_id_is_match(
      workspace_id,
      &self.logged_user,
      format!("get document doc state:{}", document_id),
    ) {
      tracing::info!(
        "get_document_doc_state: cross-workspace fetch for shared document {} ({})",
        document_id,
        err
      );
    }

    Ok(doc_state)
  }

  async fn get_document_snapshots(
    &self,
    document_id: &Uuid,
    limit: usize,
    workspace_id: &str,
  ) -> Result<Vec<DocumentSnapshot>, FlowyError> {
    Ok(vec![])
  }

  #[instrument(level = "debug", skip_all)]
  async fn get_document_data(
    &self,
    document_id: &Uuid,
    workspace_id: &Uuid,
  ) -> Result<Option<DocumentData>, FlowyError> {
    let params = QueryCollabParams {
      workspace_id: *workspace_id,
      inner: QueryCollab::new(*document_id, CollabType::Document),
    };
    let doc_state = self
      .inner
      .try_get_client()?
      .get_collab(params)
      .await?
      .encode_collab
      .doc_state
      .to_vec();
    // 【共享文档修复 2026-07-03】同上:显式 workspace 拉取不因当前 workspace 不同而丢弃。
    if let Err(err) = check_request_workspace_id_is_match(
      workspace_id,
      &self.logged_user,
      format!("Get {} document", document_id),
    ) {
      tracing::info!(
        "get_document_data: cross-workspace fetch for shared document {} ({})",
        document_id,
        err
      );
    }
    let collab = Collab::new_with_source(
      CollabOrigin::Empty,
      document_id.to_string().as_str(),
      DataSource::DocStateV1(doc_state),
      vec![],
      false,
    )?;
    let document = Document::open(collab).map_err(|e| {
      FlowyError::internal().with_context(format!("Failed to open document: {:?}", e))
    })?;
    Ok(document.get_document_data().ok())
  }

  async fn create_document_collab(
    &self,
    workspace_id: &Uuid,
    document_id: &Uuid,
    encoded_collab: EncodedCollab,
  ) -> Result<(), FlowyError> {
    let params = CreateCollabParams {
      workspace_id: *workspace_id,
      object_id: *document_id,
      encoded_collab_v1: encoded_collab
        .encode_to_bytes()
        .map_err(|err| FlowyError::internal().with_context(err))?,
      collab_type: CollabType::Document,
    };
    self.inner.try_get_client()?.create_collab(params).await?;
    Ok(())
  }
}
