use crate::migrations::migration::UserDataMigration;
use collab_integrate::CollabKVDB;
use diesel::SqliteConnection;
use flowy_error::FlowyResult;
use flowy_sqlite::kv::KVStorePreferences;
use flowy_sqlite::RunQueryDsl;
use flowy_user_pub::entities::AuthType;
use flowy_user_pub::session::Session;
use std::sync::{Arc, Weak};
use tracing::instrument;

pub struct AddJoinRequestsTableMigration;

impl UserDataMigration for AddJoinRequestsTableMigration {
  fn name(&self) -> &str {
    "add_join_requests_table"
  }

  fn run_when(&self, _first_installed_version: &Option<semver::Version>, _current_version: &semver::Version) -> bool {
    true
  }

  #[instrument(name = "AddJoinRequestsTableMigration", skip_all, err)]
  fn run(
    &self,
    _user: &Session,
    _collab_db: &Weak<CollabKVDB>,
    _user_auth_type: &AuthType,
    db: &mut SqliteConnection,
    _store_preferences: &Arc<KVStorePreferences>,
  ) -> FlowyResult<()> {
    // Create join_requests table
    diesel::sql_query(
      r#"
      CREATE TABLE IF NOT EXISTS join_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id TEXT NOT NULL,
        space_id TEXT NOT NULL,
        requester_id INTEGER NOT NULL,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER,
        updated_at INTEGER
      );
      "#,
    )
    .execute(db)?;

    // Index for fast lookup by workspace_id and space_id
    diesel::sql_query(
      r#"
      CREATE INDEX IF NOT EXISTS idx_join_requests_space ON join_requests(workspace_id, space_id);
      "#,
    )
    .execute(db)?;

    Ok(())
  }
}


