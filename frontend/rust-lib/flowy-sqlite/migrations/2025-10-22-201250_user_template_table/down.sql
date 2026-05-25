-- This file should undo anything in `up.sql`
DROP INDEX IF EXISTS idx_user_template_created_at;
DROP INDEX IF EXISTS idx_user_template_featured;
DROP INDEX IF EXISTS idx_user_template_category;
DROP INDEX IF EXISTS idx_user_template_template_id;
DROP INDEX IF EXISTS idx_user_template_user_id;
DROP TABLE user_template_table;
