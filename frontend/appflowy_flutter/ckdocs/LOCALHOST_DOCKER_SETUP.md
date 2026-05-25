# AppFlowy 本地 Docker 开发环境配置指南

## 问题背景

当使用 `.env` 文件配置 AppFlowy 客户端连接本地 Docker 部署的 AppFlowy-Cloud 服务时，会遇到 URL 端口缺失的问题。

### 问题现象

**错误信息：**
```
error sending request for url (http://localhost/gotrue/magiclink)
```

**预期 URL：**
```
http://localhost:9999/gotrue/magiclink
```

### 问题原因

AppFlowy 的开发模式（`AUTHENTICATOR_TYPE=4`，即 `appflowyCloudDevelop`）需要特殊的端口配置：
- **Base URL**: `http://localhost:8000` - 主 API 服务
- **GoTrue URL**: `http://localhost:9999` - 认证服务（处理登录、注册、魔法链接等）
- **WebSocket URL**: `ws://localhost:8000/ws/v1` - 实时同步服务

但原始代码在使用 `.env` 文件配置时，直接使用了用户提供的 URL（`http://localhost`），没有添加开发模式所需的端口号，导致请求失败。

---

## 代码分析

### 1. 相关代码文件

- **`lib/env/env.dart`**: 环境变量定义和读取
- **`lib/env/cloud_env.dart`**: 云服务配置逻辑
- **`.env`**: 用户配置文件（不在版本控制中）

### 2. 代码执行流程

#### 流程图

```
启动应用
    ↓
读取 .env 文件
    ↓
检查 Env.enableCustomCloud
    ↓
┌───────────────────────────────────┐
│  enableCustomCloud 判断逻辑       │
│  (env.dart 第 11-17 行)          │
└───────────────────────────────────┘
    ↓
    ├─→ true: 用户未配置 .env，使用内置配置
    │         调用 getAppFlowyCloudConfig()
    │         → configurationFromUri() 自动处理端口
    │
    └─→ false: 用户配置了 .env
              直接使用 Env.afCloudUrl
              ⚠️ 原始代码：没有处理开发模式端口
              ✅ 修复后：检测开发模式并调用 configurationFromUri()
```

#### 详细流程说明

**步骤 1：读取 .env 配置**
```dart
// env.dart
@EnviedField(
  obfuscate: false,
  varName: 'APPFLOWY_CLOUD_URL',
  defaultValue: '',
)
static const String afCloudUrl = _Env.afCloudUrl;
```

**步骤 2：判断是否启用自定义云配置**
```dart
// env.dart 第 11-17 行 (原始代码)
static bool get enableCustomCloud {
  return Env.authenticatorType ==
          AuthenticatorType.appflowyCloudSelfHost.value ||
      Env.authenticatorType == AuthenticatorType.appflowyCloud.value ||
      Env.authenticatorType == AuthenticatorType.appflowyCloudDevelop.value &&
          _Env.afCloudUrl.isEmpty;
}
```

**关键点**：这个逻辑判断用户是否需要动态配置云设置。
- 当 `afCloudUrl.isEmpty` 为 `true` 时，返回 `true`（使用内置逻辑）
- 当 `afCloudUrl` 有值时，返回 `false`（使用 .env 配置）

**步骤 3：根据 enableCustomCloud 选择配置方式**

在 `cloud_env.dart` 的 `fromEnv()` 方法中：

```dart
// cloud_env.dart 第 209-245 行
if (Env.enableCustomCloud) {
  // 分支 A: 使用内置配置逻辑
  final appflowyCloudConfig = authenticatorType.isAppFlowyCloudEnabled
      ? await getAppFlowyCloudConfig(authenticatorType)
      : AppFlowyCloudConfiguration.defaultConfig();
  // ...
} else {
  // 分支 B: 使用 .env 文件配置
  final authenticatorType = AuthenticatorType.fromValue(Env.authenticatorType);
  
  // ⚠️ 原始代码问题所在：
  final appflowyCloudConfig = AppFlowyCloudConfiguration(
    base_url: Env.afCloudUrl,  // 直接使用，没有端口号！
    // ...
  );
}
```

### 3. 问题根源详解

#### 原始代码的问题

在 `cloud_env.dart` 第 226-245 行（原始代码）：

```dart
} else {
  // Using the cloud settings from the .env file.
  final authenticatorType = AuthenticatorType.fromValue(Env.authenticatorType);
  
  final appflowyCloudConfig = AppFlowyCloudConfiguration(
    base_url: Env.afCloudUrl,           // ❌ http://localhost (缺少端口)
    ws_base_url: Env.afCloudUrl,        // ❌ http://localhost (缺少端口)
    gotrue_url: Env.afCloudUrl,         // ❌ http://localhost (缺少端口)
    base_web_domain: Env.baseWebDomain,
  );
  
  return AppFlowyCloudSharedEnv(
    authenticatorType: authenticatorType,
    appflowyCloudConfig: appflowyCloudConfig,
  );
}
```

**问题**：
1. 直接使用 `Env.afCloudUrl` 的值（`http://localhost`）
2. 没有检查是否为开发模式（`AUTHENTICATOR_TYPE=4`）
3. 没有调用 `configurationFromUri()` 函数来处理端口配置

#### 为什么分支 A 没问题？

分支 A（`enableCustomCloud = true`）调用了 `getAppFlowyCloudConfig()`：

```dart
// cloud_env.dart 第 161-186 行
Future<AppFlowyCloudConfiguration> getAppFlowyCloudConfig(
  AuthenticatorType authenticatorType,
) async {
  switch (authenticatorType) {
    case AuthenticatorType.appflowyCloudDevelop:
      return configurationFromUri(
        Uri.parse(baseURL),  // 这里会调用 configurationFromUri
        baseURL,
        authenticatorType,
        baseWebDomain,
      );
    // ...
  }
}
```

`configurationFromUri()` 函数会根据 `authenticatorType` 自动添加正确的端口：

```dart
// cloud_env.dart 第 93-141 行
Future<AppFlowyCloudConfiguration> configurationFromUri(
  Uri uri,
  String baseURL,
  AuthenticatorType authenticatorType,
  String baseWebDomain,
) async {
  // ...
  if (authenticatorType == AuthenticatorType.appflowyCloudDevelop) {
    config = AppFlowyCloudConfiguration(
      base_url: '$schema://$host:8000',      // ✅ 自动添加 :8000
      ws_base_url: 'ws://$host:8000/ws/v1',  // ✅ 自动添加 :8000
      gotrue_url: '$schema://$host:9999',    // ✅ 自动添加 :9999
      base_web_domain: baseWebDomain,
    );
  }
  // ...
  return config;
}
```

---

## 解决方案

### 需要修改的文件

只需要修改一个文件：**`lib/env/cloud_env.dart`**

### 修改内容

在 `fromEnv()` 方法的 else 分支中（第 226-245 行），添加对开发模式的检测，并调用 `configurationFromUri()` 来处理端口配置。

#### 修改前（原始代码）

```dart
} else {
  // Using the cloud settings from the .env file.
  final authenticatorType = AuthenticatorType.fromValue(Env.authenticatorType);
  
  final appflowyCloudConfig = AppFlowyCloudConfiguration(
    base_url: Env.afCloudUrl,
    ws_base_url: Env.afCloudUrl,
    gotrue_url: Env.afCloudUrl,
    base_web_domain: Env.baseWebDomain,
  );
  
  return AppFlowyCloudSharedEnv(
    authenticatorType: authenticatorType,
    appflowyCloudConfig: appflowyCloudConfig,
  );
}
```

#### 修改后（修复代码）

```dart
} else {
  // Using the cloud settings from the .env file.
  final authenticatorType = AuthenticatorType.fromValue(Env.authenticatorType);
  
  // For appflowyCloudDevelop type, use configurationFromUri to handle port configuration
  final appflowyCloudConfig = authenticatorType == AuthenticatorType.appflowyCloudDevelop
      ? await configurationFromUri(
          Uri.parse(Env.afCloudUrl),
          Env.afCloudUrl,
          authenticatorType,
          Env.baseWebDomain,
        )
      : AppFlowyCloudConfiguration(
          base_url: Env.afCloudUrl,
          ws_base_url: Env.afCloudUrl,
          gotrue_url: Env.afCloudUrl,
          base_web_domain: Env.baseWebDomain,
        );
  
  // When the cloud type is [AuthenticatorType.appflowyCloudSelfHost] or
  // [AuthenticatorType.appflowyCloudDevelop] in the frontend, it should be
  // converted to [AuthenticatorType.appflowyCloud] to align with the backend representation,
  // where both types are indicated by the value '2'.
  if (authenticatorType.isAppFlowyCloudEnabled) {
    authenticatorType = AuthenticatorType.appflowyCloud;
  }
  
  return AppFlowyCloudSharedEnv(
    authenticatorType: authenticatorType,
    appflowyCloudConfig: appflowyCloudConfig,
  );
}
```

### 修改说明

#### 1. 添加开发模式检测

```dart
authenticatorType == AuthenticatorType.appflowyCloudDevelop
```

检查当前认证类型是否为开发模式（值为 4）。

#### 2. 条件调用 configurationFromUri

```dart
final appflowyCloudConfig = authenticatorType == AuthenticatorType.appflowyCloudDevelop
    ? await configurationFromUri(...)  // 开发模式：使用函数处理端口
    : AppFlowyCloudConfiguration(...)   // 其他模式：直接使用 URL
```

**为什么要这样做？**
- **开发模式**需要特殊的端口配置（8000, 9999）
- **生产模式/自托管模式**通常使用标准端口（80/443），不需要额外处理
- 使用 `configurationFromUri()` 可以复用已有的端口处理逻辑

#### 3. 添加类型转换逻辑

```dart
if (authenticatorType.isAppFlowyCloudEnabled) {
  authenticatorType = AuthenticatorType.appflowyCloud;
}
```

**为什么要转换？**
- 前端区分了多种云类型：`appflowyCloud`（1）、`appflowyCloudSelfHost`（3）、`appflowyCloudDevelop`（4）
- 后端只识别一种云类型（值为 2）
- 需要将前端的多种类型统一转换为后端识别的值

这段逻辑原本只在分支 A 中存在（第 219-221 行），现在补充到分支 B 中，保证逻辑一致性。

---

## 完整配置步骤

### 1. 配置 AppFlowy-Cloud Docker 服务

参考你的 `.ai-rules` 文件，在 AppFlowy-Cloud 目录中：

```bash
cd /Users/kuncao/github.com/my-appflowy/AppFlowy-Cloud

# 启动 Docker 服务
docker compose --file docker-compose-dev.yml up --build -d

# 检查服务状态
docker compose --file docker-compose-dev.yml ps

# 查看日志
docker compose --file docker-compose-dev.yml logs -f
```

### 2. 配置 AppFlowy 客户端

在 `AppFlowy/frontend/appflowy_flutter/` 目录中创建 `.env` 文件：

```bash
cd /Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter
```

创建 `.env` 文件，内容如下：

```env
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost
```

**配置说明：**

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `AUTHENTICATOR_TYPE` | `4` | 使用开发模式（appflowyCloudDevelop） |
| `APPFLOWY_CLOUD_URL` | `http://localhost` | 本地服务地址（**不需要**端口号） |

**为什么不需要端口号？**
- 端口号会由代码自动添加（修复后的 `configurationFromUri()` 函数）
- Base URL: `http://localhost` → `http://localhost:8000`
- GoTrue URL: `http://localhost` → `http://localhost:9999`
- WebSocket URL: `http://localhost` → `ws://localhost:8000/ws/v1`

### 3. 应用代码修改

按照上述"修改内容"部分修改 `lib/env/cloud_env.dart` 文件。

### 4. 重启调试会话

**重要**：必须重新启动调试会话，因为：
1. `.env` 文件是编译时配置，需要重新构建
2. 代码修改需要重新编译才能生效

在 VSCode 中：
1. 停止当前调试会话
2. 重新运行 "AF:Build Dart Only" 调试配置

---

## AuthenticatorType 类型说明

| 类型 | 值 | 用途 | URL 配置 |
|------|-----|------|----------|
| `local` | `0` | 本地模式（不使用云服务） | 无 |
| `appflowyCloud` | `1` | AppFlowy 官方云服务 | `https://api.appflowy.io` |
| `appflowyCloudSelfHost` | `3` | 自托管云服务 | 用户自定义域名，如 `https://your-domain.com` |
| `appflowyCloudDevelop` | `4` | 开发模式（本地 Docker） | `http://localhost`（自动添加端口） |
| `supabase` | `2` | Supabase 服务（已弃用） | - |

### 端口配置对照表

| 模式 | Base URL | GoTrue URL | WebSocket URL |
|------|----------|------------|---------------|
| **开发模式** | `http://localhost:8000` | `http://localhost:9999` | `ws://localhost:8000/ws/v1` |
| **生产模式** | `https://api.appflowy.io` | `https://api.appflowy.io` | `wss://api.appflowy.io/ws/v1` |
| **自托管模式** | `https://your-domain.com` | `https://your-domain.com` | `wss://your-domain.com/ws/v1` |

---

## 设计思路解析

### 为什么需要 enableCustomCloud 判断？

`enableCustomCloud` 的设计目的是区分两种场景：

1. **用户未配置 .env**（`enableCustomCloud = true`）
   - 使用内置的默认配置
   - 根据 `AUTHENTICATOR_TYPE` 自动选择合适的 URL
   - 开发者友好：不需要手动配置就能开发

2. **用户配置了 .env**（`enableCustomCloud = false`）
   - 使用用户提供的自定义 URL
   - 适用于企业自托管场景
   - 灵活性：用户可以完全控制连接地址

### 为什么原始代码会有这个 Bug？

1. **代码假设**：原始代码假设用户配置 `.env` 时会提供完整的 URL（包含端口）
2. **开发模式特殊性**：开发模式的多端口配置（8000, 9999）是后来添加的特性
3. **逻辑不一致**：分支 A 有端口处理逻辑，但分支 B 没有同步

### 修复的核心思想

**统一处理逻辑**：无论是否使用 `.env` 配置，开发模式都应该使用相同的端口处理逻辑（`configurationFromUri()`）。

---

## 验证修改

### 1. 检查配置生效

修改后，应用会生成以下配置：

```dart
AppFlowyCloudConfiguration(
  base_url: 'http://localhost:8000',
  ws_base_url: 'ws://localhost:8000/ws/v1',
  gotrue_url: 'http://localhost:9999',
  base_web_domain: 'appflowy.io',
)
```

### 2. 检查网络请求

在调试日志中（`/Users/kuncao/PonyNotesDatas/PonyNotesDataDoNotRename_api.xiaomabiji.com/`），应该看到：

```
✅ 正确：http://localhost:9999/gotrue/magiclink
❌ 错误：http://localhost/gotrue/magiclink
```

### 3. 测试登录流程

1. 启动 AppFlowy 应用
2. 点击"使用魔法链接登录"
3. 输入邮箱地址
4. 检查是否成功发送魔法链接
5. 在邮箱中点击链接完成登录

---

## 其他注意事项

### 1. .env 文件不在版本控制中

`.env` 文件通常在 `.gitignore` 中，不会提交到 Git 仓库。这是为了：
- 保护敏感信息（如 API 密钥）
- 允许每个开发者使用不同的配置

### 2. 生产构建注意事项

如果要构建生产版本，**不要**在 `.env` 中配置 `AUTHENTICATOR_TYPE=4`，否则会：
- 尝试连接 `localhost:8000`（生产环境不存在）
- 导致所有用户无法登录

生产版本应该：
- 不创建 `.env` 文件（使用默认配置）
- 或配置 `AUTHENTICATOR_TYPE=1`（使用官方云服务）

### 3. 代码生成

`env.dart` 使用 `envied` 包生成 `env.g.dart`，如果修改了 `env.dart` 中的字段定义，需要运行：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**但本次修改不需要重新生成**，因为我们只修改了 `cloud_env.dart`，没有修改 `env.dart` 的字段定义。

---

## 总结

### 问题本质

AppFlowy 客户端在使用 `.env` 文件配置开发模式时，缺少对特殊端口配置的处理，导致请求 URL 缺少端口号。

### 解决方案

在 `cloud_env.dart` 的 `fromEnv()` 方法中，添加对开发模式的检测，并调用 `configurationFromUri()` 函数来自动处理端口配置。

### 修改范围

- **修改文件**：`lib/env/cloud_env.dart`（1 个文件）
- **修改位置**：第 226-245 行（else 分支）
- **修改性质**：逻辑增强（向后兼容）

### 影响范围

- ✅ **开发模式**：修复端口缺失问题
- ✅ **生产模式**：无影响（不经过修改的代码路径）
- ✅ **自托管模式**：无影响（使用 else 分支的直接配置）

### 用户配置

```env
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost
```

简洁明了，端口号由代码自动处理。

---

## 附录：完整代码对比

### 修改前后对比（完整版）

```dart
// ========== 修改前 ==========
} else {
  // Using the cloud settings from the .env file.
  final authenticatorType = AuthenticatorType.fromValue(Env.authenticatorType);
  
  final appflowyCloudConfig = AppFlowyCloudConfiguration(
    base_url: Env.afCloudUrl,
    ws_base_url: Env.afCloudUrl,
    gotrue_url: Env.afCloudUrl,
    base_web_domain: Env.baseWebDomain,
  );
  
  return AppFlowyCloudSharedEnv(
    authenticatorType: authenticatorType,
    appflowyCloudConfig: appflowyCloudConfig,
  );
}

// ========== 修改后 ==========
} else {
  // Using the cloud settings from the .env file.
  final authenticatorType = AuthenticatorType.fromValue(Env.authenticatorType);
  
  // For appflowyCloudDevelop type, use configurationFromUri to handle port configuration
  final appflowyCloudConfig = authenticatorType == AuthenticatorType.appflowyCloudDevelop
      ? await configurationFromUri(
          Uri.parse(Env.afCloudUrl),
          Env.afCloudUrl,
          authenticatorType,
          Env.baseWebDomain,
        )
      : AppFlowyCloudConfiguration(
          base_url: Env.afCloudUrl,
          ws_base_url: Env.afCloudUrl,
          gotrue_url: Env.afCloudUrl,
          base_web_domain: Env.baseWebDomain,
        );
  
  // When the cloud type is [AuthenticatorType.appflowyCloudSelfHost] or
  // [AuthenticatorType.appflowyCloudDevelop] in the frontend, it should be
  // converted to [AuthenticatorType.appflowyCloud] to align with the backend representation,
  // where both types are indicated by the value '2'.
  if (authenticatorType.isAppFlowyCloudEnabled) {
    authenticatorType = AuthenticatorType.appflowyCloud;
  }
  
  return AppFlowyCloudSharedEnv(
    authenticatorType: authenticatorType,
    appflowyCloudConfig: appflowyCloudConfig,
  );
}
```

### 修改点统计

| 类别 | 数量 |
|------|------|
| 新增代码行 | 15 行 |
| 修改代码行 | 1 行 |
| 删除代码行 | 0 行 |
| 新增注释行 | 6 行 |
| 影响的文件 | 1 个 |

---

## 参考资源

- **AppFlowy-Cloud 项目**: `/Users/kuncao/github.com/my-appflowy/AppFlowy-Cloud`
- **Docker Compose 配置**: `docker-compose-dev.yml`
- **调试日志位置**: `/Users/kuncao/PonyNotesDatas/PonyNotesDataDoNotRename_api.xiaomabiji.com/`
- **环境配置指南**: `AppFlowy/frontend/appflowy_flutter/ENV_CONFIG_GUIDE.md`

---

**文档版本**: 1.0  
**创建日期**: 2025-10-04  
**适用版本**: AppFlowy 0.7.x+

