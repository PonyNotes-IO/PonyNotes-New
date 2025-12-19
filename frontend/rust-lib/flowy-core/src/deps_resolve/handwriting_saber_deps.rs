use flowy_handwriting_saber::{HandwritingSaberManager, HandwritingSaberUserService};
use flowy_handwriting_saber_pub::cloud::HandwritingSaberCloudService;
use flowy_user::services::authenticate_user::AuthenticateUser;
use flowy_error::FlowyError;
use collab_integrate::collab_builder::AppFlowyCollabBuilder;
use collab_plugins::CollabKVDB;
use std::sync::{Arc, Weak};
use uuid::Uuid;

pub struct HandwritingSaberDepsResolver();

impl HandwritingSaberDepsResolver {
  pub fn resolve(
    authenticate_user: Weak<AuthenticateUser>,
    collab_builder: Weak<AppFlowyCollabBuilder>,
    cloud_service: Arc<dyn HandwritingSaberCloudService>,
  ) -> Arc<HandwritingSaberManager> {
    let user_service = Arc::new(HandwritingSaberUserServiceImpl {
      authenticate_user,
    });
    
    Arc::new(HandwritingSaberManager::new(
      user_service,
      collab_builder,
      cloud_service,
    ))
  }
}

struct HandwritingSaberUserServiceImpl {
  authenticate_user: Weak<AuthenticateUser>,
}

impl HandwritingSaberUserService for HandwritingSaberUserServiceImpl {
  fn user_id(&self) -> Result<i64, FlowyError> {
    self
      .authenticate_user
      .upgrade()
      .ok_or(FlowyError::internal().with_context("Authenticate user is dropped"))?
      .user_id()
  }
  
  fn device_id(&self) -> Result<String, FlowyError> {
    self
      .authenticate_user
      .upgrade()
      .ok_or(FlowyError::internal().with_context("Authenticate user is dropped"))?
      .device_id()
  }
  
  fn workspace_id(&self) -> Result<Uuid, FlowyError> {
    self
      .authenticate_user
      .upgrade()
      .ok_or(FlowyError::internal().with_context("Authenticate user is dropped"))?
      .workspace_id()
  }
  
  fn collab_db(&self, uid: i64) -> Result<Weak<CollabKVDB>, FlowyError> {
    self
      .authenticate_user
      .upgrade()
      .ok_or(FlowyError::internal().with_context("Authenticate user is dropped"))?
      .get_collab_db(uid)
  }
}

