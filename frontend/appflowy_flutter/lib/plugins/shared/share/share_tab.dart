import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
// removed SecondaryTextButton to avoid dependency issues
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'constants.dart';

class ShareTab extends StatelessWidget {
  const ShareTab({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        VSpace(18),
        _ShareTabHeader(),
        VSpace(2),
        _ShareTabDescription(),
        VSpace(14),
        _ShareTabContent(),
      ],
    );
  }
}

class _ShareTabHeader extends StatelessWidget {
  const _ShareTabHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const FlowySvg(FlowySvgs.share_tab_icon_s),
        const HSpace(6),
        FlowyText.medium(
          LocaleKeys.shareAction_shareTabTitle.tr(),
          figmaLineHeight: 18.0,
        ),
      ],
    );
  }
}

class _ShareTabDescription extends StatelessWidget {
  const _ShareTabDescription();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: FlowyText.regular(
        LocaleKeys.shareAction_shareTabDescription.tr(),
        fontSize: 13.0,
        figmaLineHeight: 18.0,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}

class _ShareTabContent extends StatefulWidget {
  const _ShareTabContent();

  @override
  State<_ShareTabContent> createState() => _ShareTabContentState();
}

class _ShareTabContentState extends State<_ShareTabContent> {
  bool _loading = true;
  bool _isPublic = false;
  ViewPB? _viewPB;

  @override
  void initState() {
    super.initState();
    _loadVisibility();
  }

  Future<void> _loadVisibility() async {
    final state = context.read<ShareBloc>().state;
    if (state.viewId.isEmpty) {
      setState(() {
        _loading = false;
        _isPublic = false;
      });
      return;
    }

    final result = await ViewBackendService.getView(state.viewId);
    result.fold((view) {
      _viewPB = view;
      // 无法直接获取可见性，这里仅结束加载；实际状态由本地切换维护
      setState(() {
        _loading = false;
      });
    }, (err) {
      setState(() {
        _isPublic = false;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ShareBloc, ShareState>(
      listener: (context, state) {
        // whenever share state changes (e.g., viewId), reload visibility
        _loadVisibility();
      },
      child: BlocBuilder<ShareBloc, ShareState>(
        builder: (context, state) {
        if (_loading) {
          return const SizedBox(
            height: 36,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final shareUrl = ShareConstants.buildShareUrl(
          workspaceId: state.workspaceId,
          viewId: state.viewId,
        );

        if (!_isPublic) {
          return Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            child: PrimaryRoundedButton(
              margin: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 0),
              text: '共享',
              useIntrinsicWidth: false,
              figmaLineHeight: 18.0,
              onTap: () async {
                await _setVisibility(true);
              },
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: FlowyTextField(
                  text: shareUrl,
                  readOnly: true,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const HSpace(8.0),
            PrimaryRoundedButton(
              margin: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 14.0),
              text: LocaleKeys.button_copyLink.tr(),
              figmaLineHeight: 18.0,
              leftIcon: FlowySvg(
                FlowySvgs.share_tab_copy_s,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              onTap: () => _copy(context, shareUrl),
            ),
            const HSpace(8.0),
            TextButton(
              onPressed: () async {
                await _setVisibility(false);
              },
              child: const Text('取消共享'),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<void> _setVisibility(bool public) async {
    if (_viewPB == null) {
      await _loadVisibility();
      if (_viewPB == null) return;
    }
    setState(() => _loading = true);
    // 恢复为：显式切换工作区可见性，匹配“我的空间展示”预期
    final result = await ViewBackendService.updateViewsVisibility([_viewPB!], public);
    result.fold((_) {
      setState(() {
        _isPublic = public;
        _loading = false;
      });
    }, (err) {
      setState(() => _loading = false);
      showToastNotification(message: err.msg.isEmpty ? '操作失败' : err.msg);
    });
  }

  void _copy(BuildContext context, String url) {
    getIt<ClipboardService>().setData(
      ClipboardServiceData(plainText: url),
    );

    showToastNotification(
      message: LocaleKeys.message_copy_success.tr(),
    );
  }
}
