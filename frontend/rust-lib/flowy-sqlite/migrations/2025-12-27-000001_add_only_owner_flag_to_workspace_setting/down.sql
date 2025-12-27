-- Remove column only_owner_can_create_team_workspace from workspace_setting table
-- SQLite does not support DROP COLUMN in older versions; recreate table if necessary.
PRAGMA foreign_keys=off;
BEGIN TRANSACTION;
CREATE TABLE workspace_setting_new (
  id TEXT PRIMARY KEY,
  disable_search_indexing INTEGER NOT NULL,
  ai_model TEXT NOT NULL
);
INSERT INTO workspace_setting_new (id, disable_search_indexing, ai_model)
  SELECT id, disable_search_indexing, ai_model FROM workspace_setting;
DROP TABLE workspace_setting;
ALTER TABLE workspace_setting_new RENAME TO workspace_setting;
COMMIT;
PRAGMA foreign_keys=on;


