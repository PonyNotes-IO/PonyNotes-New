import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:flutter/material.dart';

/// 日历未保存离开守卫：侧边栏点击主页/问AI等时，若当前在日历且存在未保存的编辑或新建，先弹窗确认再跳转。
class CalendarUnsavedGuard {
  CalendarUnsavedGuard._();
  static final CalendarUnsavedGuard instance = CalendarUnsavedGuard._();

  bool _hasUnsaved = false;
  VoidCallback? _performLeave;

  bool get hasUnsaved => _hasUnsaved;

  /// 日历页调用：更新是否有未保存状态及「执行离开」的回调
  void register({required bool hasUnsaved, VoidCallback? performLeave}) {
    _hasUnsaved = hasUnsaved;
    _performLeave = performLeave;
  }

  /// 侧边栏等处在跳转前调用：若当前是日历且有未保存，则弹窗确认；确认离开或无需确认时执行 [onLeave]
  void maybeConfirmLeave(BuildContext context, VoidCallback onLeave) {
    maybeConfirmLeaveAsync(context).then((canLeave) {
      if (canLeave) onLeave();
    });
  }

  /// 异步版本：返回 true 表示可以离开，false 表示取消
  Future<bool> maybeConfirmLeaveAsync(BuildContext context) async {
    try {
      final tabsBloc = getIt<TabsBloc>();
      final currentPluginType = tabsBloc.state.currentPageManager.plugin.pluginType;
      if (currentPluginType != PluginType.calendar) {
        return true;
      }
    } catch (_) {
      return true;
    }

    if (!_hasUnsaved) {
      return true;
    }

    // 弹窗确认，返回 Future<bool>
    final result = await showSimpleConfirmDialogAsync(
      context: context,
      message: '当前设置还没有被保存，确认要离开吗？',
      confirmText: '离开',
    );

    if (result == true) {
      _performLeave?.call();
      return true;
    }
    return false;
  }
}
