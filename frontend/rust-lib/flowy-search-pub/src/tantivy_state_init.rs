use crate::tantivy_state::DocumentTantivyState;
use dashmap::DashMap;
use flowy_error::{FlowyError, FlowyResult};
use once_cell::sync::Lazy;
use std::path::PathBuf;
use std::sync::{Arc, Weak};
use tokio::sync::RwLock;
use tracing::info;
use uuid::Uuid;

/// Global map: workspace_id → a *weak* handle to its index state.
type DocIndexMap = DashMap<Uuid, Arc<RwLock<DocumentTantivyState>>>;
static SEARCH_INDEX: Lazy<DocIndexMap> = Lazy::new(DocIndexMap::new);

/// Returns a strong handle, creating it if needed.
/// Uses `spawn_blocking` for the blocking I/O in `DocumentTantivyState::new`
/// to avoid "operation failed to complete synchronously" errors on Windows.
pub async fn get_or_init_document_tantivy_state(
  workspace_id: Uuid,
  data_path: PathBuf,
) -> FlowyResult<Arc<RwLock<DocumentTantivyState>>> {
  // Fast path: return existing entry without blocking
  if let Some(existing) = SEARCH_INDEX.get(&workspace_id) {
    return Ok(existing.value().clone());
  }

  // Slow path: create state in a blocking task to avoid blocking the async runtime
  let state = tokio::task::spawn_blocking(move || {
    info!(
      "[Indexing] Creating new tantivy state for workspace: {}",
      workspace_id
    );
    DocumentTantivyState::new(&workspace_id, data_path)
  })
  .await
  .map_err(|e| FlowyError::internal().with_context(format!("spawn_blocking failed: {}", e)))??;

  let arc_state = Arc::new(RwLock::new(state));

  // Insert into cache (may race with another insert, but both are valid)
  SEARCH_INDEX
    .entry(workspace_id)
    .or_insert(arc_state.clone());

  Ok(arc_state)
}

pub fn close_document_tantivy_state(workspace_id: &Uuid) {
  if SEARCH_INDEX.remove(workspace_id).is_some() {
    info!(
      "[Indexing] close tantivy state for workspace: {}",
      workspace_id
    );
  }
}

pub fn get_document_tantivy_state(
  workspace_id: &Uuid,
) -> Option<Weak<RwLock<DocumentTantivyState>>> {
  if let Some(existing) = SEARCH_INDEX.get(workspace_id) {
    return Some(Arc::downgrade(existing.value()));
  }
  None
}
