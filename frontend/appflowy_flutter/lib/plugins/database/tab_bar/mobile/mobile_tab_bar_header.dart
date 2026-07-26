import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/view/database_field_list.dart';
import 'package:appflowy/mobile/presentation/database/view/database_filter_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/view/database_sort_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/view/database_view_list.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/database/grid/application/filter/filter_editor_bloc.dart';
import 'package:appflowy/plugins/database/grid/application/sort/sort_editor_bloc.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MobileTabBarHeader extends StatelessWidget {
  const MobileTabBarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final afTheme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 4.0,
        right: 16.0,
        top: 14.0,
        bottom: 8.0,
      ),
      child: Row(
        children: [
          _buildBackButton(context, afTheme),
          const HSpace(8),
          const Flexible(
            child: _DatabaseViewSelectorButton(),
          ),
          const HSpace(8),
          _buildTrailingActions(context),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, AppFlowyThemeData afTheme) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () {
          EditorNotification.exitEditing().post();
          if (Navigator.canPop(context)) {
            Navigator.maybePop(context);
          } else {
            context.read<TabsBloc>().add(
                  TabsEvent.openPlugin(
                    plugin: makePlugin(pluginType: PluginType.homepage),
                  ),
                );
          }
        },
        icon: FlowySvg(
          FlowySvgs.mobile_return_s,
          size: const Size(7, 12),
          color: afTheme.iconColorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTrailingActions(BuildContext context) {
    return BlocBuilder<DatabaseTabBarBloc, DatabaseTabBarState>(
      builder: (context, state) {
        final currentView = state.tabBars.firstWhereIndexedOrNull(
          (index, tabBar) => index == state.selectedIndex,
        );

        if (currentView == null) {
          return const SizedBox.shrink();
        }

        final databaseController =
            state.tabBarControllerByViewId[currentView.viewId]?.controller;
        final viewInfoBloc = context.read<ViewInfoBloc>();

        return Row(
          children: [
            ViewFavoriteButton(
              key: ValueKey('favorite_button_${currentView.viewId}'),
              view: currentView.view,
            ),
            const SizedBox(width: 10),
            ShareButton(
              key: ValueKey('share_button_${currentView.viewId}'),
              view: currentView.view,
            ),
            const SizedBox(width: 4),
            MoreViewActions(
              view: currentView.view,
              viewInfoBloc: viewInfoBloc,
              customActions: databaseController == null
                  ? const []
                  : _buildDatabaseControlActions(
                      context,
                      databaseController,
                      currentView.layout,
                    ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildDatabaseControlActions(
    BuildContext context,
    DatabaseController databaseController,
    ViewLayoutPB layout,
  ) {
    return [
      if (layout == ViewLayoutPB.Grid)
        _DatabaseToolbarAction(
          icon: FlowySvgs.sort_ascending_s,
          label: LocaleKeys.grid_settings_sort.tr(),
          onTap: () => _showSortPanel(context, databaseController),
        ),
      if (layout == ViewLayoutPB.Grid ||
          layout == ViewLayoutPB.Board ||
          layout == ViewLayoutPB.Calendar)
        _DatabaseToolbarAction(
          icon: FlowySvgs.filter_s,
          label: LocaleKeys.grid_settings_filter.tr(),
          onTap: () => _showFilterPanel(context, databaseController),
        ),
      _DatabaseToolbarAction(
        icon: FlowySvgs.m_field_hide_s,
        label: LocaleKeys.grid_settings_properties.tr(),
        onTap: () => _showFieldList(context, databaseController),
      ),
    ];
  }
}

class _DatabaseViewSelectorButton extends StatelessWidget {
  const _DatabaseViewSelectorButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DatabaseTabBarBloc, DatabaseTabBarState>(
      builder: (context, state) {
        final tabBar = state.tabBars.firstWhereIndexedOrNull(
          (index, tabBar) => index == state.selectedIndex,
        );

        if (tabBar == null) {
          return const SizedBox.shrink();
        }

        return TextButton(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.fromLTRB(12, 8, 8, 8),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(48, 0)),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).brightness == Brightness.light
                  ? const Color(0x0F212729)
                  : const Color(0x0FFFFFFF),
            ),
            overlayColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.secondary,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildViewIconButton(context, tabBar.view),
              const HSpace(6),
              Flexible(
                child: FlowyText.medium(
                  tabBar.view.nameOrDefault,
                  fontSize: 14,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const HSpace(8),
              const FlowySvg(
                FlowySvgs.arrow_tight_s,
                size: Size.square(10),
              ),
            ],
          ),
          onPressed: () {
            showTransitionMobileBottomSheet(
              context,
              showDivider: false,
              builder: (_) {
                return MultiBlocProvider(
                  providers: [
                    BlocProvider<ViewBloc>.value(
                      value: context.read<ViewBloc>(),
                    ),
                    BlocProvider<DatabaseTabBarBloc>.value(
                      value: context.read<DatabaseTabBarBloc>(),
                    ),
                  ],
                  child: const MobileDatabaseViewList(),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildViewIconButton(BuildContext context, ViewPB view) {
    final iconData = view.icon.toEmojiIconData();
    if (iconData.isEmpty || iconData.type != FlowyIconType.icon) {
      return SizedBox.square(
        dimension: 16.0,
        child: view.defaultIcon(),
      );
    }
    return RawEmojiIconWidget(
      emoji: iconData,
      emojiSize: 16,
    );
  }
}

class _DatabaseToolbarAction extends StatelessWidget {
  const _DatabaseToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final FlowySvgData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FlowyButton(
      text: FlowyText.medium(label),
      leftIcon: FlowySvg(icon, size: const Size.square(20)),
      onTap: onTap,
    );
  }
}

void _showFieldList(
  BuildContext context,
  DatabaseController databaseController,
) {
  showTransitionMobileBottomSheet(
    context,
    showHeader: true,
    showBackButton: true,
    title: LocaleKeys.grid_settings_properties.tr(),
    builder: (_) {
      return BlocProvider.value(
        value: context.read<ViewBloc>(),
        child: MobileDatabaseFieldList(
          databaseController: databaseController,
          canCreate: false,
        ),
      );
    },
  );
}

void _showSortPanel(
  BuildContext context,
  DatabaseController databaseController,
) {
  showMobileBottomSheet(
    context,
    showDragHandle: true,
    showDivider: false,
    useSafeArea: false,
    backgroundColor: AFThemeExtension.of(context).background,
    builder: (_) {
      return MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => SortEditorBloc(
              viewId: databaseController.viewId,
              fieldController: databaseController.fieldController,
            ),
          ),
          BlocProvider.value(value: context.read<ViewBloc>()),
        ],
        child: const MobileSortEditor(),
      );
    },
  );
}

void _showFilterPanel(
  BuildContext context,
  DatabaseController databaseController,
) {
  showMobileBottomSheet(
    context,
    showDragHandle: true,
    showDivider: false,
    useSafeArea: false,
    backgroundColor: AFThemeExtension.of(context).background,
    builder: (_) {
      return MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => FilterEditorBloc(
              viewId: databaseController.viewId,
              fieldController: databaseController.fieldController,
            ),
          ),
          BlocProvider.value(value: context.read<ViewBloc>()),
        ],
        child: const MobileFilterEditor(),
      );
    },
  );
}