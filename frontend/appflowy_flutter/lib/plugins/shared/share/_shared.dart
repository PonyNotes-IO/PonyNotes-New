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

  shareBloc.add(const ShareEvent.updatePublishStatus());
  try {
    await shareBloc.stream
        .firstWhere((state) => state.viewId == shareBloc.view.id);
  } catch (_) {
    // Keep current state when the refresh stream is interrupted.
  }

  if (!context.mounted) {
    return;
  }

  if (!shareBloc.state.enablePublish) {
    showToastNotification(
      message: '当前笔记未同步到云端，无法生成分享链接',
      description: '请先在设置中连接云服务并开启同步，然后再尝试分享此笔记。',
      type: ToastificationType.warning,
    );
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
  });

  final List<ShareMenuTab> tabs;

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
    final databaseBloc = context.read<DatabaseTabBarBloc?>();
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final shareWithUserBloc = context.read<ShareTabBloc>();
    PageAccessLevelBloc? pageAccessLevelBloc;
    try {
      final bloc = context.read<PageAccessLevelBloc>();
      // 只使用与当前视图 ID 严格匹配的 bloc，避免误用父级（如空间）的 bloc
      if (bloc.view.id == shareBloc.view.id) {
        pageAccessLevelBloc = bloc;
      }
    } catch (_) {
      pageAccessLevelBloc = null;
    }

    await openShareSettingsDialog(
      context: context,
      tabs: tabs,
      shareBloc: shareBloc,
      userWorkspaceBloc: userWorkspaceBloc,
      shareWithUserBloc: shareWithUserBloc,
      databaseBloc: databaseBloc,
      pageAccessLevelBloc: pageAccessLevelBloc,
    );
  }
}
