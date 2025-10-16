# CocoaPods 环境配置修复说明

## 问题描述
在 VSCode/Cursor 中调试 Flutter macOS 应用时，出现 "CocoaPods not installed or not in valid state" 错误。

## 根本原因
VSCode/Cursor 从 macOS GUI 启动时，继承的是 `launchd` 的环境变量，而不是 shell（bash/zsh）的环境变量。即使在 `.bash_profile` 或 `.zshrc` 中配置了正确的 PATH，GUI 应用程序也无法访问这些配置。

## 解决方案

### 1. 项目级配置
已在以下文件中配置了正确的 PATH：
- `.vscode/settings.json` - 添加了 `dart.env` 配置
- `.vscode/launch.json` - 在调试配置中添加了 PATH 环境变量

### 2. 全局配置
在 Cursor 的全局设置中添加了 `dart.env` 配置：
- 文件位置：`~/Library/Application Support/Cursor/User/settings.json`
- 配置内容：
```json
"dart.env": {
  "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}
```

### 3. 系统级配置
创建了 LaunchAgent 以确保系统重启后 PATH 仍然有效：
- 文件位置：`~/Library/LaunchAgents/environment.plist`
- 这个 plist 文件会在系统启动时自动设置 launchd 的 PATH 环境变量

## 使用说明

### 首次配置后
1. **完全退出** Cursor（使用 `Cmd+Q`，不是重新加载窗口）
2. 重新打开 Cursor
3. 启动调试模式

### 如果问题仍然存在
1. 验证 CocoaPods 是否已安装：
   ```bash
   pod --version
   ```

2. 验证 launchd PATH 是否正确：
   ```bash
   launchctl getenv PATH
   ```
   应该输出：`/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`

3. 如果 launchctl PATH 为空，手动设置：
   ```bash
   launchctl setenv PATH "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
   ```

4. 重新加载 LaunchAgent：
   ```bash
   launchctl unload ~/Library/LaunchAgents/environment.plist
   launchctl load ~/Library/LaunchAgents/environment.plist
   ```

## 技术细节

### CocoaPods 安装位置
- 可执行文件：`/usr/local/bin/pod`
- 版本：1.16.2
- 通过 Homebrew 安装：`/usr/local/Cellar/cocoapods/1.16.2_1/bin/pod`

### Ruby 环境
- Ruby 版本：2.6.10
- Ruby 路径：`/usr/bin/ruby`
- Gems 安装目录：`/Library/Ruby/Gems/2.6.0`
- Gems 可执行文件目录：`/usr/local/bin`

## 注意事项
1. 此配置不会影响其他开发者的构建环境
2. 所有配置都是本地的，不会提交到版本控制系统
3. LaunchAgent 会在系统启动时自动运行，无需手动干预
4. 如果更换了 CocoaPods 的安装位置，需要相应更新 PATH 配置

## 验证配置是否成功
在 Cursor 的集成终端中运行：
```bash
echo $PATH
which pod
pod --version
```

应该能够看到：
- PATH 包含 `/usr/local/bin`
- `which pod` 输出 `/usr/local/bin/pod`
- `pod --version` 输出 `1.16.2`


