# Debug 与 Release 后端配置

| 构建模式 | Cloud API | GoTrue | WebSocket | 网页业务 API 根地址 |
| --- | --- | --- | --- | --- |
| debug | `http://47.94.42.183` | `http://47.94.42.183/gotrue` | `ws://47.94.42.183/ws/v1` | `http://47.94.42.183` |
| release / profile | `https://api.xiaomabiji.com` | `https://api.xiaomabiji.com/gotrue` | `wss://api.xiaomabiji.com/ws/v1` | `https://xiaomabiji.com` |

`frontend/appflowy_flutter/lib/env/env.dart` 使用 Flutter `kDebugMode` 选择环境：debug 使用测试服网关和认证类型 `3`；release/profile 读取 `.env` 生成的正式服配置。
直接读取 `Env` 的设置页、AI 模型列表、文件上传，以及 `cloud_env.dart` 生成的 Dart/Rust SDK 配置都会使用相同环境。文档解析也随构建模式切换。

在 `frontend/appflowy_flutter` 执行：

```powershell
flutter run -d windows
flutter build windows --release
```

如果修改了 Rust、Protobuf 或事件接口，先在 `frontend/` 执行 `cargo make --profile development-windows-x86 appflowy-core-dev` 更新 Rust DLL 和 Dart 接口，再运行 Flutter。单独运行 `flutter run` 不会重建 Rust；旧 DLL/生成文件会导致接口缺失或运行时不一致。

无需为 debug 修改 `.env`。当前正式服配置为：

```dotenv
AUTHENTICATOR_TYPE=3
APPFLOWY_CLOUD_URL=https://api.xiaomabiji.com
BASE_WEB_DOMAIN=https://xiaomabiji.com
```

Windows debug 使用独立单实例锁、窗口类和深链接文件，避免启动时唤起已安装的正式版。
debug 不覆盖系统 `ponynotes://` 协议注册，调试浏览器回调时可向 debug 程序命令行传入 URI。
修改后结束旧 debug 进程再运行，热重载不会重新初始化 Rust SDK 或原生启动器。
启动日志 `cloud setting` 中的 `base_url`、`gotrue_url`、`ws_base_url` 可核对实际环境。
测试服和正式服的账号及令牌互相独立；如果 debug 保留了正式服会话，请先退出后登录测试服。

配置回归检查：

```powershell
flutter test --no-pub test/unit_test/env/cloud_environment_test.dart
flutter test --no-pub --dart-define=dart.vm.product=true test/unit_test/env/cloud_environment_test.dart
flutter test --no-pub --dart-define=dart.vm.profile=true test/unit_test/env/cloud_environment_test.dart
```

后两条用 release/profile 编译常量检查正式服分支，不生成发布包。
