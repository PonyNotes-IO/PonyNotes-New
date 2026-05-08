import 'dart:io';
import 'dart:ui';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/ai/mobile_ai_welcome_page.dart';
import 'package:appflowy/mobile/presentation/notifications/mobile_notifications_screen.dart';
import 'package:appflowy/mobile/presentation/widgets/navigation_bar_button.dart';
import 'package:appflowy/shared/popup_menu/appflowy_popup_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/presentation/notifications/number_red_dot.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'home/mobile_home_page.dart';
import 'search/mobile_search_page.dart';

enum BottomNavigationBarActionType {
  home,
  notificationMultiSelect,
}

final PropertyValueNotifier<ViewLayoutPB?> mobileCreateNewPageNotifier =
    PropertyValueNotifier(null);
final ValueNotifier<BottomNavigationBarActionType> bottomNavigationBarType =
    ValueNotifier(BottomNavigationBarActionType.home);
final ValueNotifier<String?> bottomNavigationBarItemType =
    ValueNotifier(BottomNavigationBarItemType.home.label);

enum BottomNavigationBarItemType {
  home,
  search,
  askAI,
  add,
  notification;

  String get label => name;
  String? get routeName {
    return switch (this) {
      home => MobileHomeScreen.routeName,
      search => MobileSearchScreen.routeName,
      notification => MobileNotificationsScreenV2.routeName,
      add => null,
      askAI => MobileAIWelcomePage.routeName,
    };
  }

  ValueKey get valueKey {
    return ValueKey(label);
  }

  Widget get iconWidget {
    return switch (this) {
      home => const FlowySvg(FlowySvgs.m_home_unselected_m),
      search => const FlowySvg(FlowySvgs.m_home_search_icon_m),
      askAI => const _AskAIcon(),
      add => const FlowySvg(FlowySvgs.m_home_add_m),
      notification => const _NotificationNavigationBarItemIcon(),
    };
  }

  Widget? get activeIcon {
    return switch (this) {
      home => const FlowySvg(FlowySvgs.m_home_selected_m, blendMode: null),
      search =>
        const FlowySvg(FlowySvgs.m_home_search_icon_active_m, blendMode: null),
      askAI => const _AskAIcon(),
      add => const FlowySvg(FlowySvgs.m_home_add_active_m, blendMode: null),
      notification => const _NotificationNavigationBarItemIcon(isActive: true),
    };
  }

  BottomNavigationBarItem get navigationItem {
    return BottomNavigationBarItem(
      key: valueKey,
      label: label,
      icon: iconWidget,
      activeIcon: activeIcon,
    );
  }
}

final _items =
    BottomNavigationBarItemType.values.map((e) => e.navigationItem).toList();

/// Builds the "shell" for the app by building a Scaffold with a
/// BottomNavigationBar, where [child] is placed in the body of the Scaffold.
class MobileBottomNavigationBar extends StatefulWidget {
  /// Constructs an [MobileBottomNavigationBar].
  const MobileBottomNavigationBar({
    required this.navigationShell,
    super.key,
  });

  /// The navigation shell and container for the branch Navigators.
  final StatefulNavigationShell navigationShell;

  @override
  State<MobileBottomNavigationBar> createState() =>
      _MobileBottomNavigationBarState();
}

class _MobileBottomNavigationBarState extends State<MobileBottomNavigationBar> {
  Widget? _bottomNavigationBar;

  @override
  void initState() {
    super.initState();

    bottomNavigationBarType.addListener(_animate);
  }

  @override
  void dispose() {
    bottomNavigationBarType.removeListener(_animate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bottomNavigationBar = switch (bottomNavigationBarType.value) {
      BottomNavigationBarActionType.home =>
        _buildHomePageNavigationBar(context),
      BottomNavigationBarActionType.notificationMultiSelect =>
        _buildNotificationNavigationBar(context),
    };

    return Scaffold(
      body: widget.navigationShell,
      extendBody: true,
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: _transitionBuilder,
        child: _bottomNavigationBar,
      ),
    );
  }

  Widget _buildHomePageNavigationBar(BuildContext context) {
    return _HomePageNavigationBar(
      navigationShell: widget.navigationShell,
    );
  }

  Widget _buildNotificationNavigationBar(BuildContext context) {
    return const _NotificationNavigationBar();
  }

  // widget A going down, widget B going up
  Widget _transitionBuilder(
    Widget child,
    Animation<double> animation,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    );
  }

  void _animate() {
    setState(() {});
  }
}

class _AskAIcon extends StatelessWidget {
  const _AskAIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Image.asset(
        "assets/navigation/icon_ask_ai.png",
        fit: BoxFit.contain,
      ),
    );
  }
}

class _NotificationNavigationBarItemIcon extends StatelessWidget {
  const _NotificationNavigationBarItemIcon({
    this.isActive = false,
  });

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: getIt<ReminderBloc>(),
      child: BlocBuilder<ReminderBloc, ReminderState>(
        builder: (context, state) {
          final hasUnreads = state.reminders.any(
            (reminder) => !reminder.isRead,
          );
          return SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              children: [
                Center(
                  child: isActive
                      ? const FlowySvg(
                          FlowySvgs.m_home_active_notification_m,
                          blendMode: null,
                        )
                      : const FlowySvg(
                          FlowySvgs.m_home_notification_m,
                        ),
                ),
                if (hasUnreads)
                  const Align(
                    alignment: Alignment.topRight,
                    child: NumberedRedDot.mobile(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomePageNavigationBar extends StatelessWidget {
  const _HomePageNavigationBar({
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  bool _isNotificationActive(BuildContext context) {
    return GoRouterState.of(context).uri.path ==
        MobileNotificationsScreenV2.routeName;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 3,
          sigmaY: 3,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: context.border,
            color: context.backgroundColor,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _NavBarItem(
                  icon: BottomNavigationBarItemType.home.iconWidget,
                  activeIcon: BottomNavigationBarItemType.home.activeIcon,
                  isSelected: navigationShell.currentIndex == 0,
                  onTap: () => _onTap(context, 0),
                ),
                _NavBarItem(
                  icon: BottomNavigationBarItemType.search.iconWidget,
                  activeIcon: BottomNavigationBarItemType.search.activeIcon,
                  isSelected: navigationShell.currentIndex == 1,
                  onTap: () => _onTap(context, 1),
                ),
                _NavBarItem(
                  icon: BottomNavigationBarItemType.askAI.iconWidget,
                  activeIcon: BottomNavigationBarItemType.askAI.activeIcon,
                  isSelected: navigationShell.currentIndex == 2,
                  onTap: () => _onTap(context, 2),
                  flex: 2,
                ),
                _NavBarItem(
                  icon: BottomNavigationBarItemType.add.iconWidget,
                  activeIcon: BottomNavigationBarItemType.add.activeIcon,
                  isSelected: false,
                  onTap: () => _onTap(context, 3),
                ),
                _NavBarItem(
                  icon: BottomNavigationBarItemType.notification.iconWidget,
                  activeIcon: BottomNavigationBarItemType.notification.activeIcon,
                  isSelected: _isNotificationActive(context),
                  onTap: () => _onTap(context, 4),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, int bottomBarIndex) {
    closePopupMenu();

    final label = _items[bottomBarIndex].label;
    if (label == BottomNavigationBarItemType.add.label) {
      mobileCreateNewPageNotifier.value = ViewLayoutPB.Document;
      return;
    } else if (label == BottomNavigationBarItemType.askAI.label) {
      // Navigate to AI welcome page via GoRouter (not the navigation shell)
      GoRouter.of(context).go(BottomNavigationBarItemType.askAI.routeName!);
      return;
    } else if (label == BottomNavigationBarItemType.notification.label) {
      // Navigate to notification page via GoRouter (not the navigation shell), like Ask AI
      GoRouter.of(context).go(BottomNavigationBarItemType.notification.routeName!);
      getIt<ReminderBloc>().add(const ReminderEvent.refresh());
      return;
    }
    bottomNavigationBarItemType.value = label;

    // Map bottom bar index to router branch index
    // bottom bar: [home=0, search=1, askAI=2, add=3, notification=4]
    // router: [home=0, search=1, favorite=2]
    final routerIndex = switch (bottomBarIndex) {
      0 => 0,
      1 => 1,
      _ => navigationShell.currentIndex,
    };
    navigationShell.goBranch(
      routerIndex,
      initialLocation: routerIndex == navigationShell.currentIndex,
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.icon,
    this.activeIcon,
    required this.isSelected,
    required this.onTap,
    this.flex = 1,
  });

  final Widget icon;
  final Widget? activeIcon;
  final bool isSelected;
  final VoidCallback onTap;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isSelected
                ? (activeIcon ?? icon)
                : icon,
          ),
        ),
      ),
    );
  }
}

class _NotificationNavigationBar extends StatelessWidget {
  const _NotificationNavigationBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      // todo: use real height here.
      height: 90,
      decoration: BoxDecoration(
        border: context.border,
        color: context.backgroundColor,
      ),
      padding: const EdgeInsets.only(bottom: 20),
      child: ValueListenableBuilder(
        valueListenable: mSelectedNotificationIds,
        builder: (context, value, child) {
          if (value.isEmpty) {
            // not editable
            return IgnorePointer(
              child: Opacity(
                opacity: 0.3,
                child: child,
              ),
            );
          }

          return child!;
        },
        child: Row(
          children: [
            const HSpace(20),
            Expanded(
              child: NavigationBarButton(
                icon: FlowySvgs.m_notification_action_mark_as_read_s,
                text: LocaleKeys.settings_notifications_action_markAsRead.tr(),
                onTap: () => _onMarkAsRead(context),
              ),
            ),
            const HSpace(16),
            Expanded(
              child: NavigationBarButton(
                icon: FlowySvgs.m_notification_action_archive_s,
                text: LocaleKeys.settings_notifications_action_archive.tr(),
                onTap: () => _onArchive(context),
              ),
            ),
            const HSpace(20),
          ],
        ),
      ),
    );
  }

  void _onMarkAsRead(BuildContext context) {
    if (mSelectedNotificationIds.value.isEmpty) {
      return;
    }

    showToastNotification(
      message: LocaleKeys
          .settings_notifications_markAsReadNotifications_allSuccess
          .tr(),
    );

    getIt<ReminderBloc>()
        .add(ReminderEvent.markAsRead(mSelectedNotificationIds.value));

    mSelectedNotificationIds.value = [];
  }

  void _onArchive(BuildContext context) {
    if (mSelectedNotificationIds.value.isEmpty) {
      return;
    }

    showToastNotification(
      message: LocaleKeys.settings_notifications_archiveNotifications_allSuccess
          .tr(),
    );

    getIt<ReminderBloc>()
        .add(ReminderEvent.archive(mSelectedNotificationIds.value));

    mSelectedNotificationIds.value = [];
  }
}

extension on BuildContext {
  Color get backgroundColor {
    return Theme.of(this).isLightMode
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF23262B).withValues(alpha: 0.95);
  }

  Color get borderColor {
    return Theme.of(this).isLightMode
        ? const Color(0x141F2329)
        : const Color(0xFF23262B).withValues(alpha: 0.5);
  }

  Border? get border {
    return Theme.of(this).isLightMode
        ? Border(top: BorderSide(color: borderColor))
        : null;
  }
}
