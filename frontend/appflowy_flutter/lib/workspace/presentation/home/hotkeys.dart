import 'dart:async';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/sidebar/rename_view/rename_view_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';
import 'package:scaled_app/scaled_app.dart';

typedef KeyDownHandler = void Function(HotKey hotKey);

ValueNotifier<int> switchToTheNextSpace = ValueNotifier(0);
ValueNotifier<int> createNewPageNotifier = ValueNotifier(0);
ValueNotifier<ViewPB?> switchToSpaceNotifier = ValueNotifier(null);

/// 用于同步 SpaceHub 选中视图的布局信息，让侧边栏分割线可以正确判断是否禁用
/// 当 SpaceHub 中选中白板视图时，侧边栏分割线也需要禁用
ValueNotifier<ViewLayoutPB?> spaceHubSelectedViewLayoutNotifier =
    ValueNotifier(null);

@visibleForTesting
final zoomInKeyCodes = [KeyCode.equal, KeyCode.numpadAdd, KeyCode.add];
@visibleForTesting
final zoomOutKeyCodes = [KeyCode.minus, KeyCode.numpadSubtract];
@visibleForTesting
final resetZoomKeyCodes = [KeyCode.digit0, KeyCode.numpad0];

// Use a global value to store the zoom level and update it in the hotkeys.
@visibleForTesting
double appflowyScaleFactor = 1.0;

/// Helper class that utilizes the global [HotKeyManager] to easily
/// add a [HotKey] with different handlers.
///
/// Makes registration of a [HotKey] simple and easy to read, and makes
/// sure the [KeyDownHandler], and other handlers, are grouped with the
/// relevant [HotKey].
///
class HotKeyItem {
  HotKeyItem({
    required this.hotKey,
    this.keyDownHandler,
  });

  final HotKey hotKey;
  final KeyDownHandler? keyDownHandler;

  Future<void> register() =>
      hotKeyManager.register(hotKey, keyDownHandler: keyDownHandler);

  Future<void> unregister() => hotKeyManager.unregister(hotKey);
}

class HomeHotKeys extends StatefulWidget {
  const HomeHotKeys({
    super.key,
    required this.userProfile,
    required this.child,
  });

  final UserProfilePB userProfile;
  final Widget child;

  @override
  State<HomeHotKeys> createState() => _HomeHotKeysState();
}

class _HomeHotKeysState extends State<HomeHotKeys> {
  final windowSizeManager = WindowSizeManager();
  var _isRegistered = false;

  late final items = [
    // Collapse sidebar menu (using slash)
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.backslash,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) => colappsedMenus(context),
    ),

    // Collapse sidebar menu (using .)
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.period,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) => colappsedMenus(context),
    ),

    // Toggle theme mode light/dark. Ctrl/Cmd+Shift+L belongs to the document
    // editor's left-align command, so use Alt to avoid both handlers firing.
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.keyL,
        modifiers: [
          Platform.isMacOS ? KeyModifier.meta : KeyModifier.control,
          KeyModifier.shift,
          KeyModifier.alt,
        ],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) =>
          context.read<AppearanceSettingsCubit>().toggleThemeMode(),
    ),

    // Close current tab
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.keyW,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) =>
          context.read<TabsBloc>().add(const TabsEvent.closeCurrentTab()),
    ),

    // Go to previous tab
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.pageUp,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) => _selectTab(context, -1),
    ),

    // Go to next tab
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.pageDown,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) => _selectTab(context, 1),
    ),

    // Rename current view
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.f2,
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) =>
          getIt<RenameViewBloc>().add(const RenameViewEvent.open()),
    ),

    // Scale up/down the app
    // In some keyboards, the system returns equal as + keycode, while others may return add as + keycode, so add them both as zoom in key.
    ...zoomInKeyCodes.map(
      (keycode) => HotKeyItem(
        hotKey: HotKey(
          keycode,
          modifiers: [
            Platform.isMacOS ? KeyModifier.meta : KeyModifier.control,
          ],
          scope: HotKeyScope.inapp,
        ),
        keyDownHandler: (_) => _scaleWithStep(0.1),
      ),
    ),

    ...zoomOutKeyCodes.map(
      (keycode) => HotKeyItem(
        hotKey: HotKey(
          keycode,
          modifiers: [
            Platform.isMacOS ? KeyModifier.meta : KeyModifier.control,
          ],
          scope: HotKeyScope.inapp,
        ),
        keyDownHandler: (_) => _scaleWithStep(-0.1),
      ),
    ),

    // Reset app scaling
    ...resetZoomKeyCodes.map(
      (keycode) => HotKeyItem(
        hotKey: HotKey(
          keycode,
          modifiers: [
            Platform.isMacOS ? KeyModifier.meta : KeyModifier.control,
          ],
          scope: HotKeyScope.inapp,
        ),
        keyDownHandler: (_) => _scale(1),
      ),
    ),

    // Switch to the next space
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.keyO,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) => switchToTheNextSpace.value++,
    ),

    // Create a new page
    HotKeyItem(
      hotKey: HotKey(
        KeyCode.keyN,
        modifiers: [Platform.isMacOS ? KeyModifier.meta : KeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      keyDownHandler: (_) => createNewPageNotifier.value++,
    ),

    // Open settings dialog
    openSettingsHotKey(context),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_registerHotKeys());
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    unawaited(_unregisterHotKeys());
    super.dispose();
  }

  Future<void> _registerHotKeys() async {
    if (_isRegistered) {
      return;
    }
    _isRegistered = true;
    await Future.wait(items.map((item) => item.register()));
  }

  Future<void> _unregisterHotKeys() async {
    if (!_isRegistered) {
      return;
    }
    _isRegistered = false;
    await Future.wait(items.map((item) => item.unregister()));
  }

  void _selectTab(BuildContext context, int change) {
    final bloc = context.read<TabsBloc>();
    bloc.add(TabsEvent.selectTab(bloc.state.currentIndex + change));
  }

  Future<void> _scaleWithStep(double step) async {
    final currentScaleFactor = await windowSizeManager.getScaleFactor();

    double textScale = (currentScaleFactor + step).clamp(
      WindowSizeManager.minScaleFactor,
      WindowSizeManager.maxScaleFactor,
    );

    // only keep 2 decimal places
    textScale = double.parse(textScale.toStringAsFixed(2));

    Log.info('scale the app from $currentScaleFactor to $textScale');

    await _scale(textScale);
  }

  Future<void> _scale(double scaleFactor) async {
    if (FlowyRunner.currentMode == IntegrationMode.integrationTest) {
      // The integration test will fail if we check the scale factor in the test.
      // #0      ScaledWidgetsFlutterBinding.Eval ()
      // #1      ScaledWidgetsFlutterBinding.instance (package:scaled_app/scaled_app.dart:66:62)
      appflowyScaleFactor = double.parse(scaleFactor.toStringAsFixed(2));
    } else {
      // 白板平台视图偏移修复后改用标准 WidgetsFlutterBinding，ScaledWidgetsFlutterBinding 不再初始化。
      // 这里安全屏蔽：缩放暂不生效，但不抛 null 异常。
      try {
        ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => scaleFactor;
      } catch (_) {
        Log.info('App 全局缩放暂停用（白板偏移修复改用标准 WidgetsFlutterBinding）');
        return;
      }
    }

    await windowSizeManager.setScaleFactor(scaleFactor);
  }

  void colappsedMenus(BuildContext context) {
    final bloc = context.read<HomeSettingBloc>();
    final isNotificationPanelCollapsed =
        bloc.state.isNotificationPanelCollapsed;
    if (!isNotificationPanelCollapsed) {
      bloc.add(const HomeSettingEvent.collapseNotificationPanel());
    } else {
      bloc.collapseMenu();
    }
  }
}
