DROP INDEX IF EXISTS idx_note_link_state_workspace;
ALTER TABLE note_link_state DROP COLUMN workspace_id;
