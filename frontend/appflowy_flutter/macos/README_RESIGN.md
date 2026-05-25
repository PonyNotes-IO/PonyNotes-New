# macOS 应用重新签名说明

## 问题描述

当应用启动时出现以下错误：
```
Library not loaded: @rpath/HotKey.framework/Versions/A/HotKey
Reason: code signature ... have different Team IDs
```

这是因为 `HotKey.framework` 的代码签名与主应用的 Team ID 不匹配。

## 快速修复

### 1. 构建应用

```bash
cd frontend/appflowy_flutter
flutter build macos --release
```

### 2. 运行重新签名脚本

```bash
./macos/resign_app.sh build/macos/Build/Products/Release/PonyNotes.app
```

### 3. 测试应用

```bash
open build/macos/Build/Products/Release/PonyNotes.app
```

## 脚本说明

`resign_app.sh` 脚本会：

1. **自动检测签名证书**
   - 优先使用 "Developer ID Application" 证书
   - 如果没有，使用 "Apple Development" 证书
   - 如果都没有，使用 ad-hoc 签名（`-`）

2. **重新签名所有组件**
   - 所有 `.framework` 文件
   - 所有 `.app` 插件
   - 所有 `.dylib` 库
   - 所有可执行文件
   - 主应用

3. **验证签名**
   - 验证主应用签名
   - 特别检查 `HotKey.framework`

## 手动签名

如果脚本无法使用，可以手动签名：

```bash
APP_PATH="build/macos/Build/Products/Release/PonyNotes.app"
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"

# 重新签名所有框架
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -exec codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" {} \;

# 重新签名主应用
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"

# 验证
codesign -vvv "$APP_PATH"
```

## 使用 ad-hoc 签名（仅用于测试）

如果只是本地测试，可以使用 ad-hoc 签名：

```bash
APP_PATH="build/macos/Build/Products/Release/PonyNotes.app"
codesign --force --deep --sign - "$APP_PATH"
```

注意：ad-hoc 签名的应用无法通过 Gatekeeper 验证，需要手动允许运行。

## 常见问题

### Q: 脚本提示找不到签名证书

A: 确保在 Xcode 中已登录 Apple ID，并且有有效的开发者证书。

### Q: 签名后仍然无法运行

A: 检查是否有其他框架也需要重新签名：
```bash
codesign -vvv build/macos/Build/Products/Release/PonyNotes.app
```

### Q: 如何查看可用的签名证书

A: 运行：
```bash
security find-identity -v -p codesigning
```

