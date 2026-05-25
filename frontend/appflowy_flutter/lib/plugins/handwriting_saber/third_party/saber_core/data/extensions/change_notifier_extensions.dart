import 'package:flutter/material.dart';

/// ChangeNotifier 扩展（从 Saber 项目移植）
extension ChangeNotifierExtensions on ChangeNotifier {
  /// 这是一个 hack，允许我们调用 notifyListeners
  /// 因为 notifyListeners 通常是受保护的
  void notifyListenersPlease() {
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    notifyListeners();
  }
}
