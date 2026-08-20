import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/shared/popup_menu/appflowy_popup_menu.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_panel.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart'
    hide PopupMenuButton, PopupMenuDivider, PopupMenuItem, PopupMenuEntry;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum _MobileSettingsPopupMenuItem {
  settings,
  import,
  trash,
}

class HomePageSettingsPopupMenu extends StatelessWidget {
  const HomePageSettingsPopupMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MobileSettingsPopupMenuItem>(
      offset: const Offset(0, 36),
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(12.0),
        ),
      ),
      shadowColor: const Color(0x68000000),
      elevation: 10,
      color: context.popupMenuBackgroundColor,
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<_MobileSettingsPopupMenuItem>>[
        _buildItem(
          value: _MobileSettingsPopupMenuItem.settings,
          svg: FlowySvgs.m_notification_settings_s,
          text: LocaleKeys.settings_popupMenuItem_settings.tr(),
        ),
        const PopupMenuDivider(height: 0.5),
        _buildItem(
          value: _MobileSettingsPopupMenuItem.import,
          svg: FlowySvgs.icon_import_mobile_lg,
          text: LocaleKeys.moreAction_import.tr(),
        ),
        const PopupMenuDivider(height: 0.5),
        _buildItem(
          value: _MobileSettingsPopupMenuItem.trash,
          svg: FlowySvgs.trash_s,
          text: LocaleKeys.settings_popupMenuItem_trash.tr(),
        ),
      ],
      onSelected: (_MobileSettingsPopupMenuItem value) {
        switch (value) {
          case _MobileSettingsPopupMenuItem.trash:
            _openTrashPage(context);
            break;
          case _MobileSettingsPopupMenuItem.settings:
            _openSettingsPage(context);
            break;
          case _MobileSettingsPopupMenuItem.import:
            _openImportPanel(context);
            break;
        }
      },
      child: const Padding(
        padding: EdgeInsets.all(8.0),
        child: FlowySvg(
          FlowySvgs.m_settings_more_s,
        ),
      ),
    );
  }

  PopupMenuItem<T> _buildItem<T>({
    required T value,
    required FlowySvgData svg,
    required String text,
  }) {
    return PopupMenuItem<T>(
      value: value,
      padding: EdgeInsets.zero,
      child: _PopupButton(
        svg: svg,
        text: text,
      ),
    );
  }

  void _openTrashPage(BuildContext context) {
    context.push(MobileHomeTrashPage.routeName);
  }

  void _openSettingsPage(BuildContext context) {
    UserWorkspaceState? workspaceState;
    try {
      workspaceState = context.read<UserWorkspaceBloc>().state;
    } catch (_) {}
    context.push(
      MobileHomeSettingPage.routeName,
      extra: workspaceState,
    );
  }

  void _openImportPanel(BuildContext context) {
    try {
      final workspaceId =
          context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
      final parentViewId = _importParentViewId(
        context.read<SpaceBloc>().state,
        fallbackParentViewId: workspaceId,
      );
      if (parentViewId != null) {
        showImportPanel(
          parentViewId,
          context,
          (type, name, document, importedViews) {
            if (importedViews != null && importedViews.isNotEmpty) {
              showToastNotification(
                message: '成功导入 ${importedViews.length} 个文件',
              );
            }
          },
          isMobile: true,
        );
      } else {
        showToastNotification(message: '空间正在加载，请稍后再试');
      }
    } catch (e) {
      showToastNotification(message: '打开导入页面时发生错误: $e');
    }
  }

  String? _importParentViewId(
    SpaceState state, {
    String? fallbackParentViewId,
  }) {
    final currentSpace = state.currentSpace;
    if (currentSpace != null && currentSpace.id.isNotEmpty) {
      return currentSpace.id;
    }

    for (final space in state.spaces) {
      if (space.id.isNotEmpty) {
        return space.id;
      }
    }

    // 没有空间时，移动端会显示工作区根目录下的普通页面，因此保持原有
    // 根目录导入行为；加载尚未完成时则不创建不可见页面。
    return state.isInitialized ? fallbackParentViewId : null;
  }
}

class _PopupButton extends StatelessWidget {
  const _PopupButton({
    required this.svg,
    required this.text,
  });

  final FlowySvgData svg;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          FlowySvg(svg, size: const Size.square(20)),
          const HSpace(12),
          FlowyText.regular(
            text,
            fontSize: 16,
          ),
        ],
      ),
    );
  }
}
