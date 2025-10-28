# 模板数据库迁移系统

## 概述

模板数据库使用 Diesel ORM 的迁移系统来管理数据库结构的版本控制和演进，与 `flowy-sqlite` 的迁移系统保持一致。

## 目录结构

```
flowy-template/
├── migrations/                           # 迁移文件目录
│   └── 2025-10-22-200316_user_template_table/
│       ├── up.sql                       # 升级迁移
│       └── down.sql                     # 降级迁移
├── src/
│   ├── schema.rs                        # 自动生成的表结构定义
│   └── migration.rs                     # 迁移管理代码
├── diesel.toml                          # Diesel 配置文件
└── scripts/
    └── migrate.sh                       # 迁移管理脚本
```

## 迁移文件格式

### 命名规则
迁移文件夹命名格式：`YYYY-MM-DD-HHMMSS_描述性名称`

例如：`2025-10-22-200316_user_template_table`

### 文件内容
- **`up.sql`**: 向前迁移（升级数据库结构）
- **`down.sql`**: 向后迁移（回滚数据库结构）

## 使用方法

### 1. 自动迁移（推荐）

在应用启动时，模板服务会自动运行所有待执行的迁移：

```rust
// 在 TemplateService::initialize() 中
pub async fn initialize(&self) -> FlowyResult<()> {
    let mut conn = self.pool.get()?;
    crate::migration::run_migrations(&mut conn)?;
    Ok(())
}
```

### 2. 手动迁移

使用提供的迁移脚本：

```bash
# 运行所有待执行的迁移
./scripts/migrate.sh run

# 查看迁移状态
./scripts/migrate.sh status

# 生成新的迁移文件
./scripts/migrate.sh generate add_new_field

# 回滚最后一个迁移
./scripts/migrate.sh redo

# 重置数据库（删除所有数据）
./scripts/migrate.sh reset
```

### 3. 使用 Diesel CLI

```bash
# 安装 diesel-cli
cargo install diesel_cli --no-default-features --features sqlite

# 设置数据库URL
export DATABASE_URL="sqlite://./template.db"

# 运行迁移
diesel migration run

# 查看迁移状态
diesel migration list

# 生成新迁移
diesel migration generate add_new_table

# 回滚迁移
diesel migration redo
```

## 迁移管理 API

### 运行迁移
```rust
use flowy_template::migration;

// 运行所有待执行的迁移
migration::run_migrations(&mut conn)?;
```

### 检查迁移状态
```rust
// 检查是否有待执行的迁移
let has_pending = migration::has_pending_migrations(&mut conn)?;

// 获取详细的迁移状态
let status = migration::get_migration_status(&mut conn)?;
println!("待执行迁移数量: {}", status.pending_count);
```

## 当前迁移

### 2025-10-22-200316_user_template_table

**创建用户模板表**

```sql
-- up.sql
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

-- 创建索引
CREATE INDEX idx_user_template_user_id ON user_template_table(user_id);
CREATE INDEX idx_user_template_template_id ON user_template_table(template_id);
CREATE INDEX idx_user_template_category ON user_template_table(category);
CREATE INDEX idx_user_template_featured ON user_template_table(featured);
CREATE INDEX idx_user_template_created_at ON user_template_table(created_at);
```

```sql
-- down.sql
DROP INDEX IF EXISTS idx_user_template_created_at;
DROP INDEX IF EXISTS idx_user_template_featured;
DROP INDEX IF EXISTS idx_user_template_category;
DROP INDEX IF EXISTS idx_user_template_template_id;
DROP INDEX IF EXISTS idx_user_template_user_id;
DROP TABLE user_template_table;
```

## 添加新迁移

### 1. 生成迁移文件
```bash
./scripts/migrate.sh generate add_template_version_field
```

### 2. 编辑迁移文件
编辑生成的 `up.sql` 和 `down.sql` 文件：

```sql
-- migrations/YYYY-MM-DD-HHMMSS_add_template_version_field/up.sql
ALTER TABLE user_template_table ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
```

```sql
-- migrations/YYYY-MM-DD-HHMMSS_add_template_version_field/down.sql
ALTER TABLE user_template_table DROP COLUMN version;
```

### 3. 更新 schema.rs
运行迁移后，Diesel 会自动更新 `src/schema.rs` 文件。

### 4. 更新 Rust 代码
更新相关的结构体和代码以支持新字段。

## 最佳实践

### 1. 迁移设计原则
- **向前兼容**: 新迁移不应破坏现有功能
- **可回滚**: 每个 `up.sql` 都应有对应的 `down.sql`
- **原子性**: 每个迁移应该是原子的，要么全部成功，要么全部失败
- **测试**: 在开发环境中充分测试迁移

### 2. 字段变更
- **添加字段**: 使用 `ALTER TABLE ADD COLUMN`，提供默认值
- **删除字段**: 先确保不再使用，然后删除
- **修改字段**: 通常需要创建新字段，迁移数据，删除旧字段

### 3. 索引管理
- 在 `up.sql` 中创建索引
- 在 `down.sql` 中删除索引
- 考虑索引对性能的影响

### 4. 数据迁移
- 对于复杂的数据迁移，考虑分步进行
- 备份重要数据
- 在测试环境中验证迁移

## 故障排除

### 常见问题

1. **迁移失败**
   ```bash
   # 查看详细错误信息
   diesel migration run --verbose
   ```

2. **迁移状态不一致**
   ```bash
   # 重置迁移状态
   diesel migration redo
   ```

3. **数据库锁定**
   ```bash
   # 检查是否有其他进程在使用数据库
   lsof template.db
   ```

### 调试技巧

1. **查看迁移历史**
   ```sql
   SELECT * FROM __diesel_schema_migrations;
   ```

2. **手动执行 SQL**
   ```bash
   sqlite3 template.db < migration_file.sql
   ```

3. **备份和恢复**
   ```bash
   # 备份
   cp template.db template.db.backup
   
   # 恢复
   cp template.db.backup template.db
   ```

## 与 flowy-sqlite 的集成

模板数据库迁移系统与 `flowy-sqlite` 的迁移系统完全兼容：

- 使用相同的 Diesel 迁移框架
- 遵循相同的命名和结构约定
- 支持相同的迁移管理命令
- 可以独立运行或集成到主数据库

这确保了模板功能可以独立开发和部署，同时保持与主系统的一致性。
