import 'package:flutter/foundation.dart';

/// 全窗口显示控制器：
/// - 通过 [isFullWindow] 暴露当前是否处于全窗口模式
/// - 所有需要控制/响应全窗口的地方都应使用此控制器，避免状态不一致
class FullWindowController {
  static final ValueNotifier<bool> isFullWindow = ValueNotifier<bool>(false);

  static void enter() {
    if (!isFullWindow.value) {
      isFullWindow.value = true;
    }
  }

  static void exit() {
    if (isFullWindow.value) {
      isFullWindow.value = false;
    }
  }

  static void toggle() {
    isFullWindow.value = !isFullWindow.value;
  }
}


