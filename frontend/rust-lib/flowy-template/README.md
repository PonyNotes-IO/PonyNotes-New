# Flowy Template Cloud Sync

这个模块实现了AppFlowy模板的云同步功能，允许用户将本地模板同步到云端，并在不同设备间共享。

## 功能特性

### 1. 本地数据库存储
- 使用SQLite数据库存储用户模板
- 支持模板的增删改查操作
- 自动创建数据库表结构

### 2. 云同步服务
- 支持将本地模板同步到AppFlowy Cloud
- 支持从云端下载模板到本地
- 双向同步，处理冲突解决
- 增量同步，只同步变更内容

### 3. 同步状态管理
- 跟踪最后同步时间
- 检测待同步的更改
- 显示同步进度状态

## 架构设计

### 核心组件

1. **TemplateManager** - 模板管理器
   - 提供统一的模板操作接口
   - 支持本地和云端两种模式
   - 自动处理同步逻辑

2. **TemplateService** - 本地数据库服务
   - 管理SQLite数据库操作
   - 处理模板的CRUD操作
   - 数据库迁移和初始化

3. **TemplateSyncManager** - 同步管理器
   - 处理本地和云端数据转换
   - 管理同步状态和时间戳
   - 实现冲突解决策略

4. **TemplateCloudService** - 云服务接口
   - 定义云端API接口
   - 支持AppFlowy Cloud实现
   - 可扩展支持其他云服务

### 数据流

```
Flutter UI -> TemplateManager -> TemplateService (本地) + TemplateSyncManager (云端)
                                    ↓
                              SQLite Database    HTTP API (AppFlowy Cloud)
```

## 使用方法

### 1. 初始化模板管理器

```rust
// 仅本地模式
let manager = TemplateManager::new(pool);

// 启用云同步模式
let manager = TemplateManager::with_cloud_sync(pool, user_id, workspace_id);
```

### 2. 基本操作

```rust
// 获取我的模板
let templates = manager.get_my_templates().await?;

// 添加模板到我的模板
manager.add_to_my_templates(template).await?;

// 从我的模板移除
manager.remove_from_my_templates(&template_id).await?;
```

### 3. 云同步操作

```rust
// 同步到云端
manager.sync_to_cloud().await?;

// 从云端同步
manager.sync_from_cloud().await?;

// 双向同步
manager.bidirectional_sync().await?;

// 获取同步状态
let status = manager.get_sync_status().await?;
```

## 数据库模式

### user_template_table

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 主键，UUID |
| user_id | BIGINT | 用户ID |
| template_id | TEXT | 模板ID |
| title | TEXT | 模板标题 |
| description | TEXT | 模板描述 |
| category | TEXT | 模板分类 |
| author | TEXT | 作者 |
| preview_url | TEXT | 预览图URL |
| featured | BOOLEAN | 是否推荐 |
| tags | TEXT | 标签（JSON格式） |
| download_url | TEXT | 下载URL |
| created_at | BIGINT | 创建时间戳 |
| updated_at | BIGINT | 更新时间戳 |

## 云服务API

### 同步模板
```
POST /api/templates/sync
{
  "user_id": 123,
  "workspace_id": "uuid",
  "templates": [...],
  "last_sync_timestamp": 1234567890
}
```

### 获取用户模板
```
GET /api/templates/user/{user_id}?workspace_id={uuid}&since={timestamp}
```

### 添加模板
```
POST /api/templates
{
  "user_id": 123,
  "workspace_id": "uuid",
  "template": {...}
}
```

### 删除模板
```
DELETE /api/templates/{template_id}?user_id={user_id}&workspace_id={uuid}
```

## 配置选项

### 环境变量

```bash
# AppFlowy Cloud API端点
APPTEMPLATE_CLOUD_API_URL=https://api.appflowy.io

# 同步间隔（秒）
APPTEMPLATE_SYNC_INTERVAL=300

# 最大重试次数
APPTEMPLATE_MAX_RETRIES=3
```

### 用户设置

- 启用/禁用云同步
- 自动同步间隔
- 冲突解决策略
- 数据加密选项

## 错误处理

### 常见错误类型

1. **网络错误** - 网络连接失败，自动重试
2. **认证错误** - 用户未登录或token过期
3. **数据冲突** - 本地和云端数据不一致
4. **存储错误** - 本地数据库操作失败

### 错误恢复策略

1. 自动重试机制
2. 降级到本地模式
3. 用户手动干预
4. 数据备份和恢复

## 性能优化

### 1. 增量同步
- 只同步变更的模板
- 使用时间戳标记
- 批量操作减少网络请求

### 2. 缓存策略
- 本地缓存减少数据库查询
- 智能预加载
- 过期数据清理

### 3. 并发控制
- 避免重复同步
- 队列管理同步任务
- 资源锁定机制

## 安全考虑

### 1. 数据加密
- 传输层加密（HTTPS）
- 可选的数据加密
- 安全的密钥管理

### 2. 访问控制
- 用户身份验证
- 权限验证
- 数据隔离

### 3. 隐私保护
- 最小化数据收集
- 用户数据控制
- 合规性支持

## 扩展性

### 1. 多云支持
- 抽象云服务接口
- 插件化架构
- 配置驱动

### 2. 自定义同步策略
- 可配置的同步规则
- 自定义冲突解决
- 业务逻辑扩展

### 3. 监控和日志
- 详细的同步日志
- 性能指标收集
- 错误追踪和报告

## 开发指南

### 1. 添加新的云服务

```rust
impl TemplateCloudService for MyCloudService {
    // 实现所有必需的方法
}
```

### 2. 自定义同步策略

```rust
impl TemplateSyncManager {
    pub fn with_custom_strategy(&self, strategy: SyncStrategy) -> Self {
        // 实现自定义同步逻辑
    }
}
```

### 3. 添加新的模板字段

1. 更新数据库模式
2. 修改实体结构
3. 更新同步逻辑
4. 处理数据迁移

## 测试

### 单元测试
```bash
cargo test --package flowy-template
```

### 集成测试
```bash
cargo test --package flowy-template --test integration
```

### 性能测试
```bash
cargo bench --package flowy-template
```

## 贡献指南

1. Fork 项目
2. 创建功能分支
3. 编写测试
4. 提交代码
5. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](../../LICENSE) 文件。
