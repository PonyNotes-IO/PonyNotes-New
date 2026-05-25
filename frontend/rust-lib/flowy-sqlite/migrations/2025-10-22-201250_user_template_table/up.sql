-- Create user template table
CREATE TABLE user_template_table (
    id TEXT PRIMARY KEY NOT NULL,
    user_id BIGINT NOT NULL,
    template_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    author TEXT NOT NULL,
    preview_url TEXT NOT NULL,
    featured BOOLEAN NOT NULL DEFAULT 0,
    tags TEXT NOT NULL DEFAULT '[]',
    download_url TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

-- Create indexes for better query performance
CREATE INDEX idx_user_template_user_id ON user_template_table(user_id);
CREATE INDEX idx_user_template_template_id ON user_template_table(template_id);
CREATE INDEX idx_user_template_category ON user_template_table(category);
CREATE INDEX idx_user_template_featured ON user_template_table(featured);
CREATE INDEX idx_user_template_created_at ON user_template_table(created_at);
