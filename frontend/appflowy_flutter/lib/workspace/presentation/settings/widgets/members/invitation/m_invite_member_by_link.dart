import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MInviteMemberByLink extends StatefulWidget {
  const MInviteMemberByLink({super.key});

  @override
  State<MInviteMemberByLink> createState() => _MInviteMemberByLinkState();
}

class _MInviteMemberByLinkState extends State<MInviteMemberByLink> {
  bool _linkEnabled = true;

  Future<void> _onGenerateInviteLink(BuildContext context) async {
    final inviteLink = context.read<WorkspaceMemberBloc>().state.inviteLink;
    if (inviteLink != null) {
      await showConfirmDialog(
        context: context,
        style: ConfirmPopupStyle.cancelAndOk,
        title: LocaleKeys.settings_appearance_members_resetInviteLink.tr(),
        description: LocaleKeys
            .settings_appearance_members_resetInviteLinkDescription
            .tr(),
        confirmLabel: LocaleKeys.settings_appearance_members_reset.tr(),
        onConfirm: (_) {
          context.read<WorkspaceMemberBloc>().add(
                const WorkspaceMemberEvent.generateInviteLink(),
              );
        },
        confirmButtonBuilder: (dialogContext) => AFFilledTextButton.destructive(
          size: AFButtonSize.l,
          text: LocaleKeys.settings_appearance_members_reset.tr(),
          onTap: () {
            context.read<WorkspaceMemberBloc>().add(
                  const WorkspaceMemberEvent.generateInviteLink(),
                );

            Navigator.of(dialogContext).pop();
          },
        ),
      );
    } else {
      context.read<WorkspaceMemberBloc>().add(
            const WorkspaceMemberEvent.generateInviteLink(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: EdgeInsets.all(theme.spacing.m),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.settings_appearance_members_inviteLinkToAddMember.tr(),
                  style: theme.textStyle.heading4.enhanced(
                    color: theme.textColorScheme.primary,
                  ),
                ),
                VSpace(theme.spacing.s),
                if (_linkEnabled)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '只有拥有邀请成员权限的人员才能查看此内容。你也可以 ',
                          style: theme.textStyle.caption.standard(
                            color: theme.textColorScheme.primary,
                          ),
                        ),
                        TextSpan(
                          text: '创建新链接',
                          style: theme.textStyle.caption.standard(
                            color: theme.textColorScheme.action,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _onGenerateInviteLink(context),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '只有拥有邀请成员权限的人员才能查看此内容。',
                    style: theme.textStyle.caption.standard(
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Switch(
                value: _linkEnabled,
                onChanged: (value) {
                  setState(() {
                    _linkEnabled = value;
                  });
                },
                activeColor: theme.textColorScheme.primary,
              ),
              if (_linkEnabled) ...[
                VSpace(theme.spacing.s),
                _CopyLinkButton(),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CopyLinkButton extends StatelessWidget {
  const _CopyLinkButton();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFOutlinedTextButton.normal(
      text: LocaleKeys.button_copyLink.tr(),
      textStyle: theme.textStyle.body.standard(
        color: theme.textColorScheme.primary,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.l,
        vertical: theme.spacing.s,
      ),
      onTap: () {
        final link = context.read<WorkspaceMemberBloc>().state.inviteLink;
        if (link != null) {
          getIt<ClipboardService>().setData(
            ClipboardServiceData(
              plainText: link,
            ),
          );

          showToastNotification(
            message: LocaleKeys.shareAction_copyLinkSuccess.tr(),
          );
        } else {
          showToastNotification(
            message: LocaleKeys.settings_appearance_members_noInviteLink.tr(),
            type: ToastificationType.error,
          );
        }
      },
    );
  }
}
