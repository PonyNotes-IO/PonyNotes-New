-- Add column only_owner_can_create_team_workspace to workspace_setting table
ALTER TABLE workspace_setting ADD COLUMN only_owner_can_create_team_workspace INTEGER NOT NULL DEFAULT 0;


