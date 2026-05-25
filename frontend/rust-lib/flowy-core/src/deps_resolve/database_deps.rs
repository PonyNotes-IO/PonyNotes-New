use collab_integrate::collab_builder::AppFlowyCollabBuilder;
use collab_integrate::CollabKVDB;
use flowy_ai::ai_manager::AIManager;
use flowy_database2::{DatabaseManager, DatabaseUser};
use flowy_database_pub::cloud::{
  DatabaseAIService, DatabaseCloudService, SummaryRowContent, TranslateRowContent,
  TranslateRowResponse,
};
use flowy_error::FlowyError;
use flowy_user::services::authenticate_user::AuthenticateUser;
use lib_infra::async_trait::async_trait;
use lib_infra::priority_task::TaskDispatcher;
use std::sync::{Arc, Weak};
use tokio::sync::RwLock;
use uuid::Uuid;

pub struct DatabaseDepsResolver();

impl DatabaseDepsResolver {
  pub async fn resolve(
    authenticate_user: Weak<AuthenticateUser>,
    task_scheduler: Arc<RwLock<TaskDispatcher>>,
    collab_builder: Weak<AppFlowyCollabBuilder>,
    cloud_service: Arc<dyn DatabaseCloudService>,
    ai_service: Arc<dyn DatabaseAIService>,
    ai_manager: Arc<AIManager>,
  ) -> Arc<DatabaseManager> {
    let user = Arc::new(DatabaseUserImpl(authenticate_user));
    Arc::new(DatabaseManager::new(
      user,
      task_scheduler,
      collab_builder,
      cloud_service,
      Arc::new(DatabaseAIServiceMiddleware {
        ai_manager,
        ai_service,
      }),
    ))
  }
}

struct DatabaseAIServiceMiddleware {
  #[allow(dead_code)]
  ai_manager: Arc<AIManager>,
  ai_service: Arc<dyn DatabaseAIService>,
}
#[async_trait]
impl DatabaseAIService for DatabaseAIServiceMiddleware {
  async fn summary_database_row(
    &self,
    workspace_id: &Uuid,
    object_id: &Uuid,
    summary_row: SummaryRowContent,
  ) -> Result<String, FlowyError> {
    // Local AI is disabled, always use cloud service
    self
      .ai_service
      .summary_database_row(workspace_id, object_id, summary_row)
      .await
  }

  async fn translate_database_row(
    &self,
    workspace_id: &Uuid,
    translate_row: TranslateRowContent,
    language: &str,
  ) -> Result<TranslateRowResponse, FlowyError> {
    // Local AI is disabled, always use cloud service
    self
      .ai_service
      .translate_database_row(workspace_id, translate_row, language)
      .await
  }
}

struct DatabaseUserImpl(Weak<AuthenticateUser>);
impl DatabaseUserImpl {
  fn upgrade_user(&self) -> Result<Arc<AuthenticateUser>, FlowyError> {
    let user = self
      .0
      .upgrade()
      .ok_or(FlowyError::internal().with_context("Unexpected error: UserSession is None"))?;
    Ok(user)
  }
}

impl DatabaseUser for DatabaseUserImpl {
  fn user_id(&self) -> Result<i64, FlowyError> {
    self.upgrade_user()?.user_id()
  }

  fn collab_db(&self, uid: i64) -> Result<Weak<CollabKVDB>, FlowyError> {
    self.upgrade_user()?.get_collab_db(uid)
  }

  fn workspace_id(&self) -> Result<Uuid, FlowyError> {
    self.upgrade_user()?.workspace_id()
  }

  fn workspace_database_object_id(&self) -> Result<Uuid, FlowyError> {
    self.upgrade_user()?.workspace_database_object_id()
  }

  fn shared_view_source_workspace_id(&self, view_id: &str) -> Option<String> {
    use flowy_sqlite::prelude::*;
    use flowy_sqlite::schema::workspace_shared_view;

    let user = self.upgrade_user().ok()?;
    let uid = user.user_id().ok()?;
    let mut conn = user.get_sqlite_connection(uid).ok()?;

    let result: Option<String> = workspace_shared_view::table
      .filter(workspace_shared_view::view_id.eq(view_id))
      .filter(workspace_shared_view::uid.eq(uid))
      .select(workspace_shared_view::workspace_id)
      .first::<String>(&mut conn)
      .ok();

    result
  }
}
