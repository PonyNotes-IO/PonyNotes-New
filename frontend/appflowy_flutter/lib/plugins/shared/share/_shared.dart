import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
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

class ShareMenuButton extends StatelessWidget {
  const ShareMenuButton({
    super.key,
    required this.tabs,
  });

  final List<ShareMenuTab> tabs;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: FlowySvg(FlowySvgs.icon_share_m,
        size: const Size.square(18),
        color:Theme.of(context).colorScheme.onSurface,
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
    final enableCloudShare =
        context.read<ShareBloc?>()?.state.enablePublish ?? false;

    // 当前工作区未连接云服务或不支持发布，同步状态未知，阻止分享
    if (!enableCloudShare) {
      showToastNotification(
        message: '当前笔记未同步到云端，无法生成分享链接',
        description: '请先在设置中连接云服务并开启同步，然后再尝试分享此笔记。',
        type: ToastificationType.warning,
      );
      return;
    }
    final shareBloc = context.read<ShareBloc>();
    final databaseBloc = context.read<DatabaseTabBarBloc?>();
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final shareWithUserBloc = context.read<ShareTabBloc>();
    PageAccessLevelBloc? pageAccessLevelBloc;
    try {
      pageAccessLevelBloc = context.read<PageAccessLevelBloc>();
    } catch (_) {
      pageAccessLevelBloc = null;
    }

    shareBloc.add(const ShareEvent.updatePublishStatus());
    shareWithUserBloc.add(ShareTabEvent.loadSharedUsers());

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (dialogContext) {
        return MultiBlocProvider(
          providers: [
            if (databaseBloc != null)
              BlocProvider.value(value: databaseBloc),
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
}
