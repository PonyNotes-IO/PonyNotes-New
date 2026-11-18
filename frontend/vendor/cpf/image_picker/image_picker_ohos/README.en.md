<p align="center">
  <h1 align="center"> <code>image_picker</code> </h1>
</p>


This project is developed based on [image_picker@1.0.4](https://pub.dev/packages/image_picker/versions/1.0.4).

## 1. Installation and Usage

### 1.1 Installation

Navigate to your project directory and add the following dependency to `pubspec.yaml`:

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  image_picker:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/image_picker
      # ref: image_picker-v1.0.4-ohos-1.0.1
      ref: TAG  #   Select a TAG according to the TAG version table below
```

Run the command:

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `image_picker-v1.2.1-ohos-1.0.0` | `image_picker-v1.2.1-ohos-1.0.1` | `br_image_picker-v1.2.1_ohos` |
| 3.35 | `image_picker-v1.2.1-ohos-1.0.0` | `image_picker-v1.2.1-ohos-1.0.1` | `br_image_picker-v1.2.1_ohos` |
| 3.27 | `image_picker-v1.1.2-ohos-1.0.0` | `image_picker-v1.1.2-ohos-1.0.1` | `br_image_picker-v1.1.2_ohos` |
| 3.22 | `image_picker-v1.1.2-ohos-1.0.0` | `image_picker-v1.1.2-ohos-1.0.1` | `br_image_picker-v1.1.2_ohos` |
| 3.7 | `image_picker-v1.0.4-ohos-1.0.0` | `image_picker-v1.0.4-ohos-1.0.1` | `master` |

<!-- tabs:end -->

### 1.2 Usage

For usage examples, see [ohos/example](./example/).

## 2. Constraints

### 2.1 Compatibility

Tested and passed on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

## 3. API

> [!TIP] An **ohos Support** value of **yes** means the property is supported on the ohos platform; **no** means not supported; **partially** means partially supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

| Name                | return          | Description                                                                                                             | Type     | ohos Support |
|---------------------|-------------------------------------------------------------------------------------------------------------------------|----------|-------------------|-------------------|
| pickImage({[ImageSource](#ImageSource ) source,double? maxWidth, double? maxHeight, int? imageQuality, [CameraDevice](#CameraDevice) preferredCameraDevice = CameraDevice.rear,bool requestFullMetadata = true}) | Future<XFile?> | Picks an image.                                                     | function | yes               |
| pickMultiImage({double? maxWidth, double? maxHeight, int? imageQuality, bool requestFullMetadata = true}) | Future<List<XFile>> | Picks multiple images. | function | yes               |
| pickMedia({double? maxWidth, double? maxHeight, int? imageQuality, bool requestFullMetadata = true}) | Future<XFile?> | Returns the [XFile] of the picked image or video.                                                       | function | yes               |
| pickMultipleMedia({double? maxWidth, double? maxHeight, int? imageQuality, bool requestFullMetadata = true}) | Future<List<XFile>> | Returns a [List<XFile>] containing the picked images and/or videos.                    | function | yes               |
| pickVideo({[ImageSource](#ImageSource ) source, [CameraDevice](#CameraDevice ) preferredCameraDevice = CameraDevice.rear, Duration? maxDuration }) | Future<XFile?> | Returns an [XFile] object wrapping the picked video. | function | yes |
| retrieveLostData() | Future<LostDataResponse> | Retrieves the lost [XFile] if [pickImage], [pickMultiImage] or [pickVideo] failed. (Android only) | function | no |
| supportsImageSource([ImageSource](#ImageSource) source) | bool | Determines whether the current device supports the ImageSource mode. | function | no |

## 4. Properties

> [!TIP] An **ohos Support** value of **yes** means the property is supported on the ohos platform; **no** means not supported; **partially** means partially supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

### ImageSource

| Name               | Description        | Type | ohos Support |
| ------------------ | ------------------ | ---- | ------------ |
| ImageSource.camera | Selects all available files. | enum | yes          |
| ImageSource.front  | Opens the user's photo gallery.   | enum | yes          |

### ImageSource

| Name              | Description      | Type | ohos Support |
| ----------------- | ---------------- | ---- | ------------ |
| ImageSource.rear  | Uses the rear camera. | enum | yes          |
| ImageSource.front | Uses the front camera. | enum | yes          |

## 5. Known Issues

None

## 6. License

This project is licensed under [Apache License 2.0](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/image_picker/image_picker/LICENSE), feel free to use and contribute.



> Template version: v0.0.1
