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

pub struct AddTeamAclTablesMigration;

impl UserDataMigration for AddTeamAclTablesMigration {
  fn name(&self) -> &str {
    "add_team_and_team_acl_tables"
  }

  fn run_when(&self, _first_installed_version: &Option<semver::Version>, _current_version: &semver::Version) -> bool {
    true
  }

  #[instrument(name = "AddTeamAclTablesMigration", skip_all, err)]
  fn run(
    &self,
    _user: &Session,
    _collab_db: &Weak<CollabKVDB>,
    _user_auth_type: &AuthType,
    db: &mut SqliteConnection,
    _store_preferences: &Arc<KVStorePreferences>,
  ) -> FlowyResult<()> {
    // Create teams table
    diesel::sql_query(
      r#"
      CREATE TABLE IF NOT EXISTS teams (
        team_id TEXT PRIMARY KEY,
        workspace_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        created_at INTEGER,
        updated_at INTEGER
      );
      "#,
    )
    .execute(db)?;

    // Create team_acls table
    diesel::sql_query(
      r#"
      CREATE TABLE IF NOT EXISTS team_acls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id TEXT NOT NULL,
        user_id INTEGER,
        email TEXT,
        UNIQUE(team_id, user_id, email)
      );
      "#,
    )
    .execute(db)?;

    // Index for fast lookup by team_id
    diesel::sql_query(
      r#"
      CREATE INDEX IF NOT EXISTS idx_team_acls_team_id ON team_acls(team_id);
      "#,
    )
    .execute(db)?;

    Ok(())
  }
}


