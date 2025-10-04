# AppFlowy 环境配置指南 (env.g.dart)

## 📖 文件说明

### `env.g.dart` 是什么？

`env.g.dart` 是一个 **自动生成的文件**，由 Flutter 的代码生成工具 `build_runner` 根据以下内容生成：
- **模板文件**: `lib/env/env.dart` (定义了需要哪些环境变量)
- **配置文件**: `.env` 文件 (提供实际的环境变量值)

### 工作原理

```
┌─────────────┐      ┌──────────────────┐      ┌─────────────┐
│   .env      │ ──>  │  build_runner    │ ──>  │  env.g.dart │
│ (配置源文件) │      │ (envied_generator)│      │ (生成的代码) │
└─────────────┘      └──────────────────┘      └─────────────┘
       ↑                                               ↑
       │                                               │
   你要修改的                                     不要直接修改！
```

## 🚫 为什么修改后会恢复？

**因为 `env.g.dart` 是自动生成的！**

每次运行以下操作时，它都会被重新生成：
- ✅ VSCode 调试 (Debug)
- ✅ `flutter run`
- ✅ `flutter build`
- ✅ `dart run build_runner build`
- ✅ `cargo make appflowy-linux` (等构建命令)

**重要**: `.gitignore` 中已经配置忽略 `.env` 和 `*.g.dart` 文件，所以它们不会被提交到 Git。

## ✅ 正确的修改方法

### 步骤 1: 创建 .env 文件

在 `/Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter/` 目录下创建 `.env` 文件：

```bash
cd /Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter/
touch .env
```

### 步骤 2: 配置本地开发环境

编辑 `.env` 文件，添加以下内容：

```env
# 本地开发环境配置
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost
```

**环境变量说明：**

| 变量名 | 值 | 说明 |
|-------|---|------|
| `AUTHENTICATOR_TYPE` | `0` | 本地模式 (Local) |
| | `1` | Supabase 云服务 |
| | `2` | AppFlowy Cloud (官方云，默认) |
| | `3` | AppFlowy Cloud 自托管 |
| | `4` | AppFlowy Cloud 开发模式 (推荐本地开发) |
| `APPFLOWY_CLOUD_URL` | `http://localhost` | AppFlowy-Cloud 后端地址 |
| | `http://localhost:8000` | 指定端口 |
| | `http://api.xiaomabiji.com` | 你的自定义域名 |

**其他可选变量：**

```env
# 完整配置示例
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost:8000
INTERNAL_BUILD=true
SENTRY_DSN=
BASE_WEB_DOMAIN=https://appflowy.com
```

### 步骤 3: 重新生成代码

有两种方式：

#### 方式 1: 使用 VSCode 任务 (推荐)

1. 按 `Cmd+Shift+P` (macOS) 或 `Ctrl+Shift+P` (Windows/Linux)
2. 输入: `Tasks: Run Task`
3. 选择: `AF: Generate Env File`

#### 方式 2: 使用命令行

```bash
cd /Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter

# 方法 A: 清理并重新生成
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs

# 方法 B: 使用 Makefile (如果在 appflowy_flutter 目录下有 Makefile)
make freeze_build

# 方法 C: 监听模式 (开发时使用，文件改动自动重新生成)
dart run build_runner watch
```

### 步骤 4: 验证生成结果

检查 `lib/env/env.g.dart` 文件，确认内容已更新：

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'env.dart';

final class _Env {
  static const int authenticatorType = 4;  // ✅ 应该是 4
  static const String afCloudUrl = 'http://localhost';  // ✅ 应该是你配置的地址
  // ... 其他配置
}
```

## 📝 完整的本地开发流程

### 1. 第一次设置

```bash
# 1. 进入 Flutter 项目目录
cd /Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter

# 2. 创建 .env 文件
cat > .env << 'EOF'
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost
EOF

# 3. 生成环境配置代码
dart run build_runner build --delete-conflicting-outputs

# 4. 启动调试
# 现在可以在 VSCode 中按 F5 启动调试
```

### 2. 使用已有的 dev.env (推荐)

你已经有了 `dev.env` 文件，可以直接复制：

```bash
cd /Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter

# 复制 dev.env 作为 .env
cp dev.env .env

# 查看内容
cat .env
# 输出:
# APPFLOWY_CLOUD_URL=http://localhost
# AUTHENTICATOR_TYPE=4

# 重新生成代码
dart run build_runner build --delete-conflicting-outputs
```

## 🔍 深入理解

### envied 包的工作原理

1. **`envied` 包**: 运行时读取环境变量的库
2. **`envied_generator` 包**: 代码生成器，在构建时生成 `*.g.dart` 文件
3. **`build_runner` 包**: Flutter/Dart 的代码生成工具链

### env.dart 中的注解说明

```dart
@Envied(path: '.env')  // ← 指定配置文件路径
abstract class Env {
  @EnviedField(
    obfuscate: false,           // ← 不混淆 (true 会加密)
    varName: 'AUTHENTICATOR_TYPE',  // ← .env 中的变量名
    defaultValue: 2,            // ← 如果 .env 中没有，使用默认值
  )
  static const int authenticatorType = _Env.authenticatorType;
}
```

### 为什么要这样设计？

**优点：**
1. ✅ **安全**: `.env` 文件不会提交到 Git，保护敏感信息
2. ✅ **灵活**: 每个开发者可以有自己的配置
3. ✅ **类型安全**: 生成的代码是强类型的
4. ✅ **编译时优化**: 配置在编译时确定，运行时性能更好

## 🎯 常见场景配置

### 场景 1: 连接本地 AppFlowy-Cloud

```env
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost
```

### 场景 2: 连接本地 AppFlowy-Cloud (自定义端口)

```env
AUTHENTICATOR_TYPE=4
APPFLOWY_CLOUD_URL=http://localhost:8000
```

### 场景 3: 连接远程自托管服务器

```env
AUTHENTICATOR_TYPE=3
APPFLOWY_CLOUD_URL=https://api.xiaomabiji.com
```

### 场景 4: 本地离线模式 (不需要云服务)

```env
AUTHENTICATOR_TYPE=0
APPFLOWY_CLOUD_URL=
```

### 场景 5: 官方云服务

不需要 `.env` 文件，或者创建一个空的：

```env
AUTHENTICATOR_TYPE=2
APPFLOWY_CLOUD_URL=
```

## ⚠️ 注意事项

1. **不要直接修改 `env.g.dart`**
   - 这个文件会被自动覆盖
   - 所有修改都应该在 `.env` 文件中进行

2. **不要提交 `.env` 文件到 Git**
   - 已经在 `.gitignore` 中配置
   - 每个开发者应该有自己的 `.env`

3. **如果没有 `.env` 文件**
   - 会使用 `env.dart` 中定义的 `defaultValue`
   - 默认是官方云模式 (`AUTHENTICATOR_TYPE=2`)

4. **修改 .env 后记得重新生成**
   - 运行 `dart run build_runner build -d`
   - 或者重新启动调试

5. **不同环境使用不同的 .env 文件**
   - `.env` - 默认/开发环境
   - `.env.production` - 生产环境
   - 通过修改 `env.dart` 中的 `@Envied(path: '.env')` 切换

## 🛠️ 故障排查

### 问题 1: 修改 .env 后没有生效

**解决方法：**
```bash
# 1. 清理缓存
dart run build_runner clean

# 2. 删除旧的生成文件
rm lib/env/env.g.dart

# 3. 重新生成
dart run build_runner build --delete-conflicting-outputs

# 4. 重启调试
```

### 问题 2: 找不到 .env 文件

**解决方法：**
```bash
# 确认当前目录
pwd
# 应该输出: /Users/kuncao/github.com/my-appflowy/AppFlowy/frontend/appflowy_flutter

# 检查文件是否存在
ls -la | grep env

# 如果不存在，创建它
touch .env
echo "AUTHENTICATOR_TYPE=4" >> .env
echo "APPFLOWY_CLOUD_URL=http://localhost" >> .env
```

### 问题 3: build_runner 报错

**解决方法：**
```bash
# 1. 更新依赖
flutter pub get

# 2. 清理并重新生成
flutter clean
flutter pub get
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

## 📚 相关文件

| 文件路径 | 作用 | 是否可编辑 |
|---------|------|----------|
| `lib/env/env.dart` | 定义环境变量模板 | ✅ 可以 (需要重新生成) |
| `lib/env/env.g.dart` | 自动生成的配置代码 | ❌ 不要修改 |
| `.env` | 环境变量配置文件 | ✅ **应该修改** |
| `dev.env` | 开发环境配置示例 | ✅ 可以复制使用 |
| `.gitignore` | 包含 `.env` 和 `*.g.dart` | ℹ️ 已配置 |
| `pubspec.yaml` | 包含 `envied` 依赖 | ℹ️ 参考 |

## 🔗 参考资源

- [envied 包文档](https://pub.dev/packages/envied)
- [build_runner 文档](https://pub.dev/packages/build_runner)
- AppFlowy 源码中的 `env.dart`

---

**总结**: 以后只需要修改 `.env` 文件，然后运行 `dart run build_runner build -d`，就能正确配置本地开发环境了！

