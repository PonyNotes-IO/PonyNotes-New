import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

class FlowyTab extends StatefulWidget {
  const FlowyTab({
    super.key,
    required this.pageManager,
    required this.isCurrent,
    required this.onTap,
    required this.isAllPinned,
    this.width,
  });

  final PageManager pageManager;
  final bool isCurrent;
  final VoidCallback onTap;

  /// Signifies whether all tabs are pinned
  ///
  final bool isAllPinned;
  final double? width;

  @override
  State<FlowyTab> createState() => _FlowyTabState();
}

class _FlowyTabState extends State<FlowyTab> {
  static const Color _lightModeTabColor = Color(0xFFF9F9F9);
  static const Color _darkModeTabColor = Color(0xFF2C2C2C);
  static const Color _darkModeTabForegroundColor = Color(0xFFF9F9F9);

  final controller = PopoverController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabBackgroundColor = theme.brightness == Brightness.dark
        ? _darkModeTabColor
        : _lightModeTabColor;
    final tabHoverColor = theme.brightness == Brightness.dark
        ? _darkModeTabColor
        : widget.isCurrent
            ? tabBackgroundColor
            : null;

    return SizedBox(
      width: widget.pageManager.isPinned ? 54 : widget.width,
      child: _wrapInTooltip(
        widget.pageManager.plugin.widgetBuilder.viewName,
        child: FlowyHover(
          resetHoverOnRebuild: false,
          style: HoverStyle(
            borderRadius: BorderRadius.zero,
            backgroundColor: tabBackgroundColor,
            hoverColor: tabHoverColor,
          ),
          builder: (context, isHovering) => AppFlowyPopover(
            controller: controller,
            offset: const Offset(4, 4),
            triggerActions: PopoverTriggerFlags.secondaryClick,
            showAtCursor: true,
            popupBuilder: (_) => BlocProvider.value(
              value: context.read<TabsBloc>(),
              child: TabMenu(
                controller: controller,
                pageId: widget.pageManager.plugin.id,
                isPinned: widget.pageManager.isPinned,
                isAllPinned: widget.isAllPinned,
              ),
            ),
            child: ChangeNotifierProvider.value(
              value: widget.pageManager.notifier,
              child: Consumer<PageNotifier>(
                builder: (context, value, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  // We use a Listener to avoid gesture detector onPanStart debounce
                  child: Listener(
                    onPointerDown: (event) {
                      if (event.buttons == kPrimaryButton) {
                        widget.onTap();
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Stop move window detector
                      onPanStart: (_) {},
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: widget.width ?? HomeSizes.tabBarWidth,
                          minWidth: widget.pageManager.isPinned ? 54 : 0,
                        ),
                        height: HomeSizes.tabBarHeight,
                        child: _wrapReadableDarkModeContent(
                          context,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: widget.pageManager.notifier.tabBarWidget(
                                  widget.pageManager.plugin.id,
                                  widget.pageManager.isPinned,
                                ),
                              ),
                              if (!widget.pageManager.isPinned) ...[
                                Visibility(
                                  visible: isHovering || PlatformInfo.isTablet,
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: FlowyIconButton(
                                      onPressed: () => _closeTab(context),
                                      icon: const FlowySvg(
                                        FlowySvgs.close_s,
                                        size: Size.square(22),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _closeTab(BuildContext context) => context
      .read<TabsBloc>()
      .add(TabsEvent.closeTab(widget.pageManager.plugin.id));

  Widget _wrapReadableDarkModeContent(
    BuildContext context, {
    required Widget child,
  }) {
    final theme = Theme.of(context);
    if (theme.brightness != Brightness.dark) {
      return child;
    }

    // Keep the requested dark tab strip readable in dark mode.
    // Dark mode uses #2C2C2C tabs with light text/icons.
    // 深色模式选项卡使用 #2C2C2C，并切换为浅色文字和图标。
    return Theme(
      data: theme.copyWith(
        iconTheme: theme.iconTheme.copyWith(
          color: _darkModeTabForegroundColor,
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: _darkModeTabForegroundColor,
          displayColor: _darkModeTabForegroundColor,
        ),
        colorScheme: theme.colorScheme.copyWith(
          onSurface: _darkModeTabForegroundColor,
          onSurfaceVariant: _darkModeTabForegroundColor.withValues(alpha: 0.72),
        ),
      ),
      child: child,
    );
  }

  Widget _wrapInTooltip(String? viewName, {required Widget child}) {
    if (viewName != null) {
      return FlowyTooltip(
        message: viewName,
        child: child,
      );
    }

    return child;
  }
}

@visibleForTesting
class TabMenu extends StatelessWidget {
  const TabMenu({
    super.key,
    required this.controller,
    required this.pageId,
    required this.isPinned,
    required this.isAllPinned,
  });

  final PopoverController controller;
  final String pageId;
  final bool isPinned;
  final bool isAllPinned;

  @override
  Widget build(BuildContext context) {
    return SeparatedColumn(
      separatorBuilder: () => const VSpace(4),
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: isPinned ? 0.5 : 1,
          child: _wrapInTooltip(
            shouldWrap: isPinned,
            message: LocaleKeys.tabMenu_closeDisabledHint.tr(),
            child: FlowyButton(
              text: FlowyText.regular(LocaleKeys.tabMenu_close.tr()),
              onTap: () => _closeTab(context),
              disable: isPinned,
            ),
          ),
        ),
        Opacity(
          opacity: isAllPinned ? 0.5 : 1,
          child: _wrapInTooltip(
            shouldWrap: true,
            message: isAllPinned
                ? LocaleKeys.tabMenu_closeOthersDisabledHint.tr()
                : LocaleKeys.tabMenu_closeOthersHint.tr(),
            child: FlowyButton(
              text: FlowyText.regular(
                LocaleKeys.tabMenu_closeOthers.tr(),
              ),
              onTap: () => _closeOtherTabs(context),
              disable: isAllPinned,
            ),
          ),
        ),
        const Divider(height: 0.5),
        FlowyButton(
          text: FlowyText.regular(
            isPinned
                ? LocaleKeys.tabMenu_unpinTab.tr()
                : LocaleKeys.tabMenu_pinTab.tr(),
          ),
          onTap: () => _togglePin(context),
        ),
      ],
    );
  }

  Widget _wrapInTooltip({
    required bool shouldWrap,
    String? message,
    required Widget child,
  }) {
    if (shouldWrap) {
      return FlowyTooltip(
        message: message,
        child: child,
      );
    }

    return child;
  }

  void _closeTab(BuildContext context) {
    context.read<TabsBloc>().add(TabsEvent.closeTab(pageId));
    controller.close();
  }

  void _closeOtherTabs(BuildContext context) {
    context.read<TabsBloc>().add(TabsEvent.closeOtherTabs(pageId));
    controller.close();
  }

  void _togglePin(BuildContext context) {
    context.read<TabsBloc>().add(TabsEvent.togglePin(pageId));
    controller.close();
  }
}
