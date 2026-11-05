# 本地配置 ↔ 云构建（PonyNotes-Builder）对应表

云的唯一真源是 `PonyNotes-Builder/.github/workflows/{windows,android}.yaml`。
下面这些本地文件里的取值已经和 workflow 对齐，构建时不再靠临时脚本打补丁。

## 版本

| 项 | 云（workflow） | 本地配置文件 |
|---|---|---|
| Flutter / Windows | `3.35.1` | 系统 Flutter 3.35.1 |
| Flutter / Android | `3.35.0` | `.fvmrc` = 3.35.0 |
| Rust | `1.91.0` | `frontend/rust-toolchain.toml` = 1.91 |
| cargo-make | `0.37.5` | 本机 0.37.24（仅版本号差） |
| cargo-ndk | `3.3.0` | 未安装（本地走 `copy_android_libs.ps1` 等价路径） |
| NDK（Gradle） | `flutter.ndkVersion` = `27.0.12077973` | `android/app/build.gradle`：`ndkVersion = flutter.ndkVersion` |
| NDK（cargo-ndk / libc++） | r26d = `26.3.11579264` | `rust-lib/.cargo/config.toml` 指向本机 `27.0.12077973`（宿主差异，见下） |
| JDK | Temurin `17` | 本机 Temurin 17.0.19 |
| Gradle wrapper | `8.11.1-all`（services.gradle.org） | 同版本、同官方地址 |

## 构建参数

| 项 | 云 | 本地 |
|---|---|---|
| Windows Rust 任务 | `cargo make --env APP_VERSION=x --profile production-windows-x86 appflowy-core-release` + `code_generation` | 同一 profile / 同一任务（`mobile.toml`、`desktop.toml`、`flutter.toml`） |
| Windows Flutter | `flutter build windows --release --build-name=x` | 同一命令行 |
| Android Rust | `--profile production-android appflowy-core-dev-android-ci`，`cargo ndk … build --release` | `mobile.toml` 的 `sdk-build-android` / `-armv7` / `-ci` 均加 `--release` |
| Android ABI | `abiFilters 'arm64-v8a', 'armeabi-v7a'`（CI 用 python 注入 build.gradle） | `gradle.properties` 的 `androidAbis=arm64-v8a,armeabi-v7a`（build.gradle 读它生成同样 abiFilters） |
| Android 打包排除 | `lib/x86/**`、`lib/x86_64/**` | `app/build.gradle` 的 `packaging.jniLibs.excludes`（按 `androidAbis` 取补集） |
| media_kit ABI | `arm64-v8a` | `gradle.properties` 同值 |
| Android APK | `flutter build apk --target-platform android-arm64,android-arm --build-name x --build-number y --split-debug-info=./debug_info --obfuscate` | `flutter.toml` 的 `flutter-build-android`（含 `--split-debug-info=./debug_info`）同命令行 |
| 代码生成 | `cargo make --profile … code_generation` | 同一任务（Windows 走 `generate.cmd`，Android 走 `generate.sh`） |

## 环境变量（`frontend/appflowy_flutter/.env`）

云在构建前写入，本地文件内容与之一致：

```ini
INTERNAL_BUILD=1
APPFLOWY_CLOUD_URL=https://api.xiaomabiji.com
AUTHENTICATOR_TYPE=3
SENTRY_DSN=
```

## 仍然不同的地方（都是宿主/网络原因，不是配置漂移）

| 差异 | 原因 |
|---|---|
| `rust-lib/.cargo/config.toml` 保留 `[target.*-linux-android]` 段 | 云在 ubuntu 上会删掉它并用 `cargo ndk`；本机 Windows 交叉编译需要这些 NDK clang 路径 |
| `android/build.gradle` 多出阿里云 maven 镜像 | 国内拉依赖必需；指向的构件与 google()/mavenCentral() 相同版本 |
| `windows/CMakeLists.txt` 多 `/FS` 与 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` | 云钉 `windows-2022`（VS 2022）；本机是 VS 2026（MSVC 14.51+） |
| 云里的 sibling 仓库补丁（`AppFlowy-Collab` / `rust-rocksdb` / `langchain-rust` 改成 path） | 那是 CI 为了不重复 clone；本地 `Cargo.toml` / `Cargo.lock` 已锁定同一批 git ref，版本一致 |
| `app/build.gradle` 里手工注册 CargoKit 原生库任务 | 本地修 Flutter Gradle + CargoKit 的插件库缺失问题；云 runner 不走这段 |