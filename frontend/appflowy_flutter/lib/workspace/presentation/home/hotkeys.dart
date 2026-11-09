import 'dart:async';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_window_size_manager.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/sidebar/rename_view/rename_view_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_service.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/shortcut_registry.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<HotKeyItem> _registeredItems = [];
  Future<void> _registration = Future.value();

  late final Map<String, KeyDownHandler> handlers = {
    'app.sidebar': (_) => colappsedMenus(context),
    'app.theme': (_) =>
        context.read<AppearanceSettingsCubit>().toggleThemeMode(),
    'app.closeTab': (_) =>
        context.read<TabsBloc>().add(const TabsEvent.closeCurrentTab()),
    'app.previousTab': (_) => _selectTab(context, -1),
    'app.nextTab': (_) => _selectTab(context, 1),
    'app.rename': (_) =>
        getIt<RenameViewBloc>().add(const RenameViewEvent.open()),
    'app.zoomIn': (_) => _scaleWithStep(0.1),
    'app.zoomOut': (_) => _scaleWithStep(-0.1),
    'app.resetZoom': (_) => _scale(1),
    'app.nextSpace': (_) => switchToTheNextSpace.value++,
    'app.newPage': (_) => createNewPageNotifier.value++,
    'app.settings': openSettingsHotKey(context).keyDownHandler!,
  };

  @override
  void initState() {
    super.initState();
    shortcutChanges.addListener(_refreshHotKeys);
    _registration = _loadHotKeys();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    shortcutChanges.removeListener(_refreshHotKeys);
    unawaited(_registration.then((_) => _unregisterHotKeys()));
    super.dispose();
  }

  Future<void> _registerHotKeys() async {
    if (_isRegistered || !mounted) {
      return;
    }
    _isRegistered = true;
    for (final entry in handlers.entries) {
      final id = entry.key;
      for (final binding in shortcutFor(id).keybindings) {
        final code =
            KeyCodeParser.fromLogicalKey(LogicalKeyboardKey(binding.keyCode));
        if (code == null) continue;
        final configured = HotKeyItem(
          hotKey: HotKey(
            code,
            scope: HotKeyScope.inapp,
            modifiers: [
              if (binding.isControlPressed) KeyModifier.control,
              if (binding.isMetaPressed) KeyModifier.meta,
              if (binding.isAltPressed) KeyModifier.alt,
              if (binding.isShiftPressed) KeyModifier.shift,
            ],
          ),
          keyDownHandler: (key) {
            if (!isRecordingShortcut) entry.value(key);
          },
        );
        await configured.register();
        _registeredItems.add(configured);
      }
    }
  }

  Future<void> _unregisterHotKeys() async {
    if (!_isRegistered) {
      return;
    }
    _isRegistered = false;
    await Future.wait(_registeredItems.map((item) => item.unregister()));
    _registeredItems.clear();
  }

  Future<void> _loadHotKeys() async {
    try {
      final service = SettingsShortcutService();
      await service.updateCommandShortcuts(
        allShortcutEvents,
        await service.getCustomizeShortcuts(),
      );
    } catch (error) {
      Log.error('Could not load shortcuts: $error');
    }
    await _registerHotKeys();
  }

  void _refreshHotKeys() {
    _registration = _registration.then((_) async {
      await _unregisterHotKeys();
      await _registerHotKeys();
    });
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
