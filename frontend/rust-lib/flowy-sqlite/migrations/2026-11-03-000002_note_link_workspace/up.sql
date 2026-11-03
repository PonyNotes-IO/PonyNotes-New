-- Existing derived rows are rebuilt with workspace ownership on next use.
ALTER TABLE note_link_state ADD COLUMN workspace_id TEXT NOT NULL DEFAULT '';
CREATE INDEX idx_note_link_state_workspace ON note_link_state(workspace_id);
