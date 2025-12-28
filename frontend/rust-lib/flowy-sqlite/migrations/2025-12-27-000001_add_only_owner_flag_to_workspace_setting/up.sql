-- Add column only_owner_can_create_team_workspace to workspace_setting_table table
ALTER TABLE workspace_setting_table ADD COLUMN only_owner_can_create_team_workspace INTEGER NOT NULL DEFAULT 0;

