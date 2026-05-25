use flowy_error::FlowyResult;
use flowy_sqlite::DBConnection;

/// 迁移在 flowy-sqlite 中统一由 embed_migrations 管理。此处提供占位函数，避免重复迁移。
pub fn run_migrations(_conn: &mut DBConnection) -> FlowyResult<()> { Ok(()) }

pub fn has_pending_migrations(_conn: &mut DBConnection) -> FlowyResult<bool> { Ok(false) }

#[derive(Debug, Clone)]
pub struct MigrationStatus {
    pub has_pending: bool,
    pub pending_count: usize,
    pub pending_migrations: Vec<String>,
}

pub fn get_migration_status(_conn: &mut DBConnection) -> FlowyResult<MigrationStatus> {
    Ok(MigrationStatus { has_pending: false, pending_count: 0, pending_migrations: vec![] })
}
