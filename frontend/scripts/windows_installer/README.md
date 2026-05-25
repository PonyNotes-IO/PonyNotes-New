# Windows 安装包构建指南

## 前置要求

1. **Flutter SDK** - 用于构建 Windows 应用
2. **Rust 工具链** - 用于构建后端核心库
3. **Inno Setup 6** - 用于创建安装包
   - 下载地址: https://jrsoftware.org/isdl.php
   - 安装后确保 `iscc.exe` 在系统 PATH 中

## 构建步骤

### 1. 构建 Flutter Release 版本

```powershell
cd appflowy_flutter
flutter clean
flutter pub get
flutter build windows --release
```

### 2. 构建 Rust 核心库 Release 版本

```powershell
cd rust-lib
cargo build --release
```

### 3. 一键打包（推荐）

双击运行 `build_installer.cmd` 脚本，或在终端执行：

```powershell
cd scripts\windows_installer
build_installer.cmd
```

## 手动打包（可选）

如果需要手动控制打包过程：

```powershell
# 1. 准备安装目录
mkdir installer_output\AppFlowy
mkdir installer_output\AppFlowy\data

# 2. 复制 Flutter 构建产物
xcopy appflowy_flutter\build\windows\x64\runner\Release\* installer_output\AppFlowy\ /E /H

# 3. 复制 Rust DLL 依赖
xcopy rust-lib\target\release\deps\*.dll installer_output\AppFlowy\ /Y

# 4. 复制到 scripts\windows_installer
xcopy installer_output\AppFlowy scripts\windows_installer\AppFlowy\ /E /H

# 5. 执行编译
cd scripts\windows_installer
iscc inno_setup_config.iss
```

## 输出文件

安装包生成位置: `scripts\windows_installer\Output/setup.exe`

## 注意事项

- 默认安装到 `C:\Users\<用户名>\AppData\Local\Programs\AppFlowy`
- 桌面快捷方式: `AppFlowy.lnk`
- 开始菜单: `AppFlowy` 组
- 支持自定义协议: `appflowy://`

## 版本更新

修改 `inno_setup_config.iss` 中的版本号：

```iss
#define AppVersion "0.9.9"
```

