use flowy_user_pub::session::Session;
use std::sync::Arc;

pub mod anon_user_workspace;
pub mod doc_key_with_workspace;
pub mod document_empty_content;
pub mod migration;
pub mod session_migration;
mod util;
pub mod workspace_and_favorite_v1;
pub mod workspace_trash_v1;
pub mod add_team_acl_tables;
pub mod add_join_requests_table;

#[derive(Clone, Debug)]
pub struct AnonUser {
  pub session: Arc<Session>,
}
