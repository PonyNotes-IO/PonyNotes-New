use flowy_whiteboard::{WhiteboardManager, WhiteboardUserService};
use flowy_user::services::authenticate_user::AuthenticateUser;
use flowy_error::FlowyError;
use collab_integrate::collab_builder::AppFlowyCollabBuilder;
use collab_plugins::CollabKVDB;
use std::sync::{Arc, Weak};
use uuid::Uuid;

pub struct WhiteboardDepsResolver();

impl WhiteboardDepsResolver {
  pub fn resolve(
    authenticate_user: Weak<AuthenticateUser>,
    collab_builder: Arc<AppFlowyCollabBuilder>,
  ) -> Arc<WhiteboardManager> {
    let user_service = Arc::new(WhiteboardUserServiceImpl {
      authenticate_user,
    });
    
    Arc::new(WhiteboardManager::new(
      user_service,
      Arc::downgrade(&collab_builder),
    ))
  }
}

struct WhiteboardUserServiceImpl {
  authenticate_user: Weak<AuthenticateUser>,
}

impl WhiteboardUserService for WhiteboardUserServiceImpl {
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


