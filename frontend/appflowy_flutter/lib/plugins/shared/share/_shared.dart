import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy/plugins/shared/share/share_settings_dialog.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/flowy_svgs.g.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../workspace/presentation/widgets/dialogs.dart';

Future<void> openShareSettingsDialog({
  required BuildContext context,
  required List<ShareMenuTab> tabs,
  required ShareBloc shareBloc,
  required UserWorkspaceBloc userWorkspaceBloc,
  required ShareTabBloc shareWithUserBloc,
  DatabaseTabBarBloc? databaseBloc,
  PageAccessLevelBloc? pageAccessLevelBloc,
}) async {
  if (pageAccessLevelBloc != null &&
      !pageAccessLevelBloc.state.isLoadingLockStatus &&
      pageAccessLevelBloc.state.isReadOnly) {
    showToastNotification(
      message: '该文档为只读内容，不能再次共享或发布',
      type: ToastificationType.warning,
    );
    return;
  }

  if (tabs.isEmpty) {
    final isGuestMode =
        userWorkspaceBloc.state.currentWorkspace?.workspaceType ==
            WorkspaceTypePB.LocalW;
    showToastNotification(
      message:
          isGuestMode ? '快速开始，无法分享和发布。如需分享和发布，请登录/注册' : '该文档为只读内容，不能再次共享或发布',
      type: ToastificationType.warning,
    );
    return;
  }

  // Non-blocking refresh: the share dialog must open immediately after click.
  // 非阻塞刷新：点击分享后必须立即打开弹窗，避免状态流卡住导致“点了没反应”。
  shareBloc.add(const ShareEvent.updatePublishStatus());

  if (!context.mounted) {
    return;
  }

  shareWithUserBloc.add(ShareTabEvent.loadSharedUsers());

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (dialogContext) {
      return MultiBlocProvider(
        providers: [
          if (databaseBloc != null) BlocProvider.value(value: databaseBloc),
          BlocProvider.value(value: shareBloc),
          BlocProvider.value(value: userWorkspaceBloc),
          BlocProvider.value(value: shareWithUserBloc),
          if (pageAccessLevelBloc != null)
            BlocProvider.value(value: pageAccessLevelBloc),
        ],
        child: ShareSettingsDialog(
          tabs: tabs,
          viewName: shareBloc.state.viewName,
        ),
      );
    },
  );
}

class ShareMenuButton extends StatelessWidget {
  const ShareMenuButton({
    super.key,
    required this.tabs,
    this.pageAccessLevelBloc,
    this.readPageAccessLevelFromContext = true,
  });

  final List<ShareMenuTab> tabs;
  final PageAccessLevelBloc? pageAccessLevelBloc;
  final bool readPageAccessLevelFromContext;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: FlowySvg(
        FlowySvgs.icon_share_m,
        size: const Size.square(18),
        color: Theme.of(context).colorScheme.onSurface,
      ),
      tooltip: LocaleKeys.shareAction_buttonText.tr(),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(
        minWidth: 36,
        minHeight: 36,
      ),
      onPressed: () => _openShareSettings(context),
    );
  }

  Future<void> _openShareSettings(BuildContext context) async {
    final shareBloc = context.read<ShareBloc>();
    DatabaseTabBarBloc? databaseBloc;
    try {
      databaseBloc = context.read<DatabaseTabBarBloc>();
    } catch (_) {
      databaseBloc = null;
    }
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final shareWithUserBloc = context.read<ShareTabBloc>();
    PageAccessLevelBloc? effectivePageAccessLevelBloc = pageAccessLevelBloc;
    if (effectivePageAccessLevelBloc == null &&
        readPageAccessLevelFromContext) {
      try {
        effectivePageAccessLevelBloc = context.read<PageAccessLevelBloc>();
      } catch (_) {
        effectivePageAccessLevelBloc = null;
      }
    }

    await openShareSettingsDialog(
      context: context,
      tabs: tabs,
      shareBloc: shareBloc,
      userWorkspaceBloc: userWorkspaceBloc,
      shareWithUserBloc: shareWithUserBloc,
      databaseBloc: databaseBloc,
      pageAccessLevelBloc: effectivePageAccessLevelBloc,
    );
  }
}
