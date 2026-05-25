<h1 align="center" style="margin:0"> AppFlowy_Flutter</h1>
<div align="center">
  <img src="https://img.shields.io/badge/Flutter-v3.13.19-blue"/>
  <img src="https://img.shields.io/badge/Rust-v1.70-orange"/>
</div>

> Documentation for Contributors

This Repository contains the codebase for the frontend of the application, currently we use Flutter as our frontend framework.

### Platforms Supported Using Flutter 💻

- Linux
- macOS
- Windows
  > We are actively working on support for Android & iOS!

_Additionally, we are working on a Web version built with Tauri!_

### Am I Eligible to Contribute?

Yes! You are eligible to contribute, check out the ways in which you can [contribute to AppFlowy](https://docs.appflowy.io/docs/documentation/software-contributions/contributing-to-appflowy). Some of the ways in which you can contribute are:

- Non-Coding Contributions
  - Documentation
  - Feature Requests and Feedbacks
  - Report Bugs
  - Improve Translations
- Coding Contributions

To contribute to `AppFlowy_Flutter` codebase specifically (coding contribution) we suggest you to have basic knowledge of Flutter. In case you are new to Flutter, we suggest you learn the basics, and then contribute afterwards. To get started with Flutter read [here](https://flutter.dev/docs/get-started/codelab).

### What OS should I use for development?

We support all OS for Development i.e. Linux, MacOS and Windows. However, most of us promote macOS and Linux over Windows. We have detailed [docs](https://docs.appflowy.io/docs/documentation/appflowy/from-source/environment-setup) on how to setup `AppFlowy_Flutter` on your local system respectively per operating system.

### Getting Started ❇

We have detailed documentation on how to [get started](https://docs.appflowy.io/docs/documentation/software-contributions/contributing-to-appflowy) with the project, and make your first contribution. However, we do have some specific picks for you:

- [Code Architecture](https://appflowy.gitbook.io/docs/essential-documentation/contribute-to-appflowy/architecture/frontend/frontend/codemap)
- [Styleguide & Conventions](https://docs.appflowy.io/docs/documentation/software-contributions/conventions/naming-conventions)
- [Making Your First PR](https://docs.appflowy.io/docs/documentation/software-contributions/submitting-code/submitting-your-first-pull-request)
- [All AppFlowy Documentation](https://docs.appflowy.io/docs/documentation/appflowy) - Contribution guide, build and run, debugging, testing, localization, etc.

### Need Help?

- New to GitHub? Follow [these](https://docs.appflowy.io/docs/documentation/software-contributions/submitting-code/setting-up-your-repositories) steps to get started
- Stuck Somewhere? Join our [Discord](https://discord.gg/9Q2xaN37tV), we're there to help you!
- Find out more about the [community initiatives](https://docs.appflowy.io/docs/appflowy/community).

---

## 百度网盘集成配置 🗂️

本项目已集成百度网盘功能，允许用户从百度网盘导入文件到本地文件库。

### ⚠️ 重要提示

在使用百度网盘功能前，您必须：

1. **在百度开放平台创建应用** 并配置**授权回调地址** (redirect_uri)
2. **在本地创建配置文件** 填入 API 密钥

如果跳过第1步，点击"授权登录"时会出现 **"无法访问此页面"** 错误！

**详细配置说明请查看：[BAIDU_CLOUD_SETUP.md](./BAIDU_CLOUD_SETUP.md)**

---

### 快速配置步骤

#### 1. 在百度开放平台配置应用

访问 [百度网盘开放平台](https://pan.baidu.com/union/console/application)（如无法访问，请尝试 https://openapi.baidu.com/console/index），创建应用并添加授权回调地址：

```
http://localhost:8080/auth/callback
```

**这一步是必须的！** redirect_uri 必须提前在百度平台配置，否则 OAuth 授权会失败。

#### 2. 获取 API 密钥

在应用详情页获取：
- **API Key** (App Key)
- **Secret Key**

#### 3. 创建本地配置文件

在 `appflowy_flutter` 目录下：

```bash
cp baidu_cloud_config_example.env .env.baidu
```

#### 4. 编辑配置文件

打开 `.env.baidu`，填入真实的 API 密钥：

```env
# 百度网盘开放平台配置
BAIDU_CLOUD_APP_KEY=你的_API_Key
BAIDU_CLOUD_SECRET_KEY=你的_Secret_Key
BAIDU_CLOUD_REDIRECT_URI=http://localhost:8080/auth/callback
```

**重要：** `BAIDU_CLOUD_REDIRECT_URI` 必须与百度平台配置的完全一致！

#### 5. 重启应用

配置完成后，重启应用以加载新配置。

### 安全说明

- `.env.baidu` 文件会被git忽略，确保API密钥安全
- 永远不要将API密钥硬编码在代码中
- 定期轮换API密钥
- 在生产环境中使用更安全的密钥管理服务

### 使用方法

```dart
// 1. 初始化配置
await BaiduCloudConfigService.instance.loadConfig();

// 2. 用户授权
final service = BaiduCloudService();
final authUrl = service.getAuthorizationUrl();
// 打开浏览器进行授权

// 3. 导入文件
final files = await service.getFileList('/');
await fileLibraryService.importFromBaiduCloud();
```

### 故障排除

**配置无效错误**
- 检查 `.env.baidu` 文件是否存在
- 确认API密钥格式正确
- 验证回调地址配置

**授权失败**
- 检查App Key和Secret Key是否正确
- 确认回调地址与应用配置一致
- 验证网络连接

### 相关文件

- `baidu_cloud_config_example.env` - 配置模板
- `lib/plugins/file_library/services/baidu_cloud_config_service.dart` - 配置服务
- `lib/plugins/file_library/services/baidu_cloud_service.dart` - 百度网盘API服务
- `lib/plugins/file_library/services/baidu_cloud_models.dart` - 数据模型