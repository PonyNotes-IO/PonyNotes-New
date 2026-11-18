/// 鸿蒙原生能力统一桥接。
///
/// 设计目标：
/// 1. **零侵入复用 pub.dev 原版插件**：在 ArkTS 侧 ([OhosNativeBridgePlugin]) 注册
///    各三方库原本使用的 MethodChannel / EventChannel（如
///    `dev.fluttercommunity.plus/package_info`、`miguelruivo.flutter.plugins.filepicker` 等），
///    使业务层对这些插件的调用在鸿蒙上无需改动即可工作。
/// 2. **统一通道**：额外暴露 `ponynotes/ohos_native`，供业务直接调用鸿蒙专属能力
///    （例如获取可写目录、隐私授权状态等），避免散落新通道。
///
/// 非鸿蒙平台本插件不注册任何原生实现，调用 [channel] 会抛 MissingPluginException，
/// 业务应通过 [OhosNativeBridge.isOhos] 守卫。
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// 统一原生通道名。
const String kOhosNativeChannel = 'ponynotes/ohos_native';

/// 鸿蒙原生桥接的 Dart 门面。
class OhosNativeBridge {
  OhosNativeBridge._();

  static final OhosNativeBridge instance = OhosNativeBridge._();

  final MethodChannel channel = const MethodChannel(kOhosNativeChannel);

  /// 是否运行在鸿蒙系统。
  ///
  /// 用 `operatingSystem` 字符串判断，而非 fork 私有的 `Platform.isOhos` getter：
  /// 后者在标准 Dart SDK 的 `dart:io` 中不存在，Android 构建上动态调用会抛
  /// `NoSuchMethodError`（即使 try/catch 也有性能与稳定性隐患）。
  /// `operatingSystem` 是所有 SDK 共有的标准 API（vm:platform-const，编译期常量）。
  static bool get isOhos => Platform.operatingSystem == 'ohos';

  /// 在鸿蒙上注册仍使用旧版 `static platform` 模式的插件的 MethodChannel 实现。
  ///
  /// 部分三方库（如 file_picker 10.x）不会在鸿蒙自动注册平台实现，
  /// 需在应用启动时显式赋值，否则调用会抛 "platform hasn't been registered"。
  /// 已使用 platform_interface 默认 MethodChannel 的库（plus 系列、secure_storage、
  /// app_links、local_notifications）无需此步。
  ///
  /// 仅鸿蒙生效；其他平台直接返回。
  static Future<void> registerOhosPlatformOverrides() async {
    if (!isOhos) return;
    // file_picker：把平台实现切到通用 MethodChannel 实现。
    // 通过字符串查找避免在非鸿蒙环境硬依赖 file_picker 的内部类。
    try {
      final dynamic filePickerLib = _lookupFilePickerPlatform();
      if (filePickerLib != null) {
        // ignore: avoid_dynamic_calls
        filePickerLib(FilePickerIOInstance());
      }
    } catch (_) {
      // file_picker 未被依赖时忽略。
    }
  }

  static dynamic _lookupFilePickerPlatform() {
    // 使用 dart:mirrors 不可用，这里通过延迟导入不可行；
    // 改为在业务层（main.dart）直接调用 FilePicker.platform = FilePickerIO()。
    // 此方法保留为空实现，真正的注册在 main.dart 中完成。
    return null;
  }

  /// 鸿蒙应用文件目录（等价 FlowySDK.getFilesDir）。
  Future<String?> getFilesDir() =>
      channel.invokeMethod<String>('getFilesDir');

  /// 鸿蒙应用缓存目录。
  Future<String?> getCacheDir() =>
      channel.invokeMethod<String>('getCacheDir');

  /// 鸿蒙临时目录。
  Future<String?> getTemporaryDir() =>
      channel.invokeMethod<String>('getTemporaryDir');

  /// 获取设备信息（os / architecture / model / brand 等）。
  Future<Map<String, dynamic>?> getDeviceInfo() async {
    final map = await channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
    return map?.cast<String, dynamic>();
  }

  /// 统一 toast。
  Future<void> showToast(String message) =>
      channel.invokeMethod<void>('showToast', {'message': message});
}

/// 占位类型，避免在非 file_picker 环境下引用失败。
class FilePickerIOInstance {}
