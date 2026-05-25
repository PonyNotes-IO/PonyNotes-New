-- SQLite doesn't support DROP COLUMN in older versions, so we recreate the table
CREATE TABLE workspace_shared_view_backup AS SELECT uid, workspace_id, view_id, permission_id, created_at FROM workspace_shared_view;
DROP TABLE workspace_shared_view;
CREATE TABLE workspace_shared_view (
  uid BigInt NOT NULL,
  workspace_id TEXT NOT NULL,
  view_id TEXT NOT NULL,
  permission_id INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (uid, workspace_id, view_id)
);
INSERT INTO workspace_shared_view SELECT uid, workspace_id, view_id, permission_id, created_at FROM workspace_shared_view_backup;
DROP TABLE workspace_shared_view_backup;
