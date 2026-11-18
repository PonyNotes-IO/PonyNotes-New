<p align="center">
  <h1 align="center"> <code>image_picker</code> </h1>
</p>


本项目基于 [image_picker@1.0.4](https://pub.dev/packages/image_picker/versions/1.0.4) 开发。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  image_picker:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/image_picker
      # ref: image_picker-v1.0.4-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `image_picker-v1.2.1-ohos-1.0.0` | `image_picker-v1.2.1-ohos-1.0.1` | `br_image_picker-v1.2.1_ohos` |
| 3.35 | `image_picker-v1.2.1-ohos-1.0.0` | `image_picker-v1.2.1-ohos-1.0.1` | `br_image_picker-v1.2.1_ohos` |
| 3.27 | `image_picker-v1.1.2-ohos-1.0.0` | `image_picker-v1.1.2-ohos-1.0.1` | `br_image_picker-v1.1.2_ohos` |
| 3.22 | `image_picker-v1.1.2-ohos-1.0.0` | `image_picker-v1.1.2-ohos-1.0.1` | `br_image_picker-v1.1.2_ohos` |
| 3.7 | `image_picker-v1.0.4-ohos-1.0.0` | `image_picker-v1.0.4-ohos-1.0.1` | `master` |

<!-- tabs:end -->

### 1.2 使用案例

使用案例详见 [ohos/example](./example/)

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

## 3. API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name                | return          | Description                                                                                                             | Type     | ohos Support |
|---------------------|-------------------------------------------------------------------------------------------------------------------------|----------|-------------------|-------------------|
| pickImage({[ImageSource](#ImageSource ) source,double? maxWidth, double? maxHeight, int? imageQuality, [CameraDevice](#CameraDevice) preferredCameraDevice = CameraDevice.rear,bool requestFullMetadata = true}) | Future<XFile?> | 选择图片                                                     | function | yes               |
| pickMultiImage({double? maxWidth, double? maxHeight, int? imageQuality, bool requestFullMetadata = true}) | Future<List<XFile>> | 选择多张图片 | function | yes               |
| pickMedia({double? maxWidth, double? maxHeight, int? imageQuality, bool requestFullMetadata = true}) | Future<XFile?> | 返回拾取的图像或视频的[XFile]。                                                       | function | yes               |
| pickMultipleMedia({double? maxWidth, double? maxHeight, int? imageQuality, bool requestFullMetadata = true}) | Future<List<XFile>> | 返回一个[List<XFile>]，其中包含拾取的图像和/或视频。                    | function | yes               |
| pickVideo({[ImageSource](#ImageSource ) source，[CameraDevice](#CameraDevice ) preferredCameraDevice = CameraDevice.rear, Duration? maxDuration }) | Future<XFile?> | 返回一个[XFile]对象，用于包装拾取的视频。 | function | yes |
| retrieveLostData() | Future<LostDataResponse> | [pickImage]、[pickMultiImage]或[pickVideo]失败时，检索丢失的[XFile]。（仅限安卓系统） | function | no |
| supportsImageSource([ImageSource](#ImageSource) source) | bool | 判断当前设备是否支持ImageSource模式 | function | no |

## 4. 属性

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

### ImageSource

| Name               | Description        | Type | ohos Support |
| ------------------ | ------------------ | ---- | ------------ |
| ImageSource.camera | 选择所有可用的文件 | enum | yes          |
| ImageSource.front  | 打开用户的照片库   | enum | yes          |

### ImageSource

| Name              | Description      | Type | ohos Support |
| ----------------- | ---------------- | ---- | ------------ |
| ImageSource.rear  | 使用后置摄像头。 | enum | yes          |
| ImageSource.front | 使用前置摄像头。 | enum | yes          |

## 5. 遗留问题

无

## 6. 开源协议

本项目基于 [Apache License 2.0](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/image_picker/image_picker/LICENSE) ，请自由地享受和参与开源。



> 模板版本: v0.0.1