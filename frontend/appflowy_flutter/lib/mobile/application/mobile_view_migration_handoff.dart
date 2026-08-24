import 'package:flutter/foundation.dart';

/// 移动端“旧视图删除 + 新视图替换”的短生命周期交接门闩。
///
/// 白板跨空间迁移会先在目标空间新建视图，再删除源视图。源视图删除通知可能早于
/// 路由替换到达 [MobileViewPage]；只有已登记的预期删除才能跳过通用的强制返首页。
/// 门闩不负责导航，迁移成功、失败或取消后都必须由协调器显式清理。
class MobileViewMigrationHandoff {
  MobileViewMigrationHandoff._();

  static final Map<String, String> _pendingReplacements = {};

  static void begin({
    required String oldViewId,
    required String newViewId,
  }) {
    _pendingReplacements[oldViewId] = newViewId;
  }

  static bool isExpectedRemoval(String viewId) =>
      _pendingReplacements.containsKey(viewId);

  static String? replacementViewId(String oldViewId) =>
      _pendingReplacements[oldViewId];

  static void finish(String oldViewId) {
    _pendingReplacements.remove(oldViewId);
  }

  @visibleForTesting
  static void reset() {
    _pendingReplacements.clear();
  }
}
