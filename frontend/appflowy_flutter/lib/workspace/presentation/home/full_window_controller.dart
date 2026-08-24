import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy_backend/log.dart';

/// 全窗口显示控制器：
/// - 通过 [isFullWindow] 暴露当前是否处于全窗口模式
/// - 所有需要控制/响应全窗口的地方都应使用此控制器，避免状态不一致
///
/// 该控制器用于管理应用内的全屏模式（非系统级全屏），主要影响：
/// - 侧边栏的显示/隐藏
/// - 顶部工具栏的显示/隐藏
/// - 编辑面板的显示/隐藏
/// - 整体布局的重新排列
class FullWindowController {
  static final ValueNotifier<bool> isFullWindow = ValueNotifier<bool>(false);

  static void enter() {
    try {
      if (!isFullWindow.value) {
        isFullWindow.value = true;
        Log.info('[FullWindowController] entered full window mode');
      }
    } catch (error, stackTrace) {
      Log.error(
        '[FullWindowController] failed to enter full window: $error',
        error,
        stackTrace,
      );
    }
  }

  static void exit() {
    try {
      if (isFullWindow.value) {
        isFullWindow.value = false;
        Log.info('[FullWindowController] exited full window mode');
      }
    } catch (error, stackTrace) {
      Log.error(
        '[FullWindowController] failed to exit full window: $error',
        error,
        stackTrace,
      );
    }
  }

  static void exitAndExpandMenu(BuildContext context) {
    exit();
    _expandMenuIfHidden(context);
  }

  static void toggle() {
    try {
      isFullWindow.value = !isFullWindow.value;
      Log.info(
        '[FullWindowController] toggled full window mode: ${isFullWindow.value}',
      );
    } catch (error, stackTrace) {
      Log.error(
        '[FullWindowController] failed to toggle full window: $error',
        error,
        stackTrace,
      );
    }
  }

  static void toggleAndExpandMenu(BuildContext context) {
    if (isFullWindow.value) {
      exit();
      _expandMenuIfHidden(context);
      return;
    }

    _expandMenuIfHidden(context);
    enter();
  }

  static void collapseMenuAndEnterFullWindow(BuildContext context) {
    try {
      context.read<HomeSettingBloc>().add(
            const HomeSettingEvent.changeMenuStatus(MenuStatus.hidden),
          );
    } catch (_) {
      // Some callers may not have a HomeSettingBloc in scope.
    }

    enter();
  }

  static bool _expandMenuIfHidden(BuildContext context) {
    try {
      final bloc = context.read<HomeSettingBloc>();
      if (bloc.state.menuStatus == MenuStatus.hidden) {
        bloc.add(
          const HomeSettingEvent.changeMenuStatus(MenuStatus.expanded),
        );
        return true;
      }
    } catch (_) {
      // Some full-window controls can be built outside the home settings scope.
    }
    return false;
  }
}
