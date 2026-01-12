use crate::migrations::migration::UserDataMigration;
use crate::migrations::util::load_collab;
use flowy_error::FlowyResult;
use flowy_sqlite::kv::KVStorePreferences;
use flowy_user_pub::session::Session;
use flowy_user_pub::entities::AuthType;
use collab_integrate::CollabKVDB;
use diesel::SqliteConnection;
use semver::Version;
use tracing::instrument;

pub struct AddTeamsAclMigration;

impl UserDataMigration for AddTeamsAclMigration {
  fn name(&self) -> &str {
    "add_teams_and_team_acls_migration"
  }

  fn run_when(&self, _first_installed_version: &Option<Version>, _current_version: &Version) -> bool {
    true
  }

  #[instrument(name = "AddTeamsAclMigration", skip_all, err)]
  fn run(
    &self,
    _user: &Session,
    _collab_db: &std::sync::Weak<CollabKVDB>,
    _user_auth_type: &AuthType,
    db: &mut SqliteConnection,
    _store_preferences: &std::sync::Arc<KVStorePreferences>,
  ) -> FlowyResult<()> {
    // Create teams table
    diesel::sql_query(r#"
      CREATE TABLE IF NOT EXISTS teams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id TEXT NOT NULL UNIQUE,
        workspace_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        created_at INTEGER,
        updated_at INTEGER
      );
    "#).execute(db)?;

    // Create team_acls table
    diesel::sql_query(r#"
      CREATE TABLE IF NOT EXISTS team_acls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id TEXT NOT NULL,
        user_id INTEGER,
        email TEXT,
        UNIQUE(team_id, user_id, email)
      );
    "#).execute(db)?;

    Ok(())
  }
}


