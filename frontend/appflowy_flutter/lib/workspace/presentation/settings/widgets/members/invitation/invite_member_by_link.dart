import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InviteMemberByLink extends StatefulWidget {
  const InviteMemberByLink({super.key});

  @override
  State<InviteMemberByLink> createState() => _InviteMemberByLinkState();
}

class _InviteMemberByLinkState extends State<InviteMemberByLink> {
  bool _linkEnabled = true;
  late final TapGestureRecognizer _generateRecog;

  @override
  void initState() {
    super.initState();
    _generateRecog = TapGestureRecognizer()..onTap = _onClickCreateLink;
  }

  @override
  void dispose() {
    _generateRecog.dispose();
    super.dispose();
  }
 
  Future<void> _onGenerateInviteLink() async {
    final state = context.read<WorkspaceMemberBloc>().state;
    final subscriptionInfo = state.subscriptionInfo;
    final inviteLink = state.inviteLink;

    // Allow generating invite links for all plans — no upgrade restriction.

    if (inviteLink != null) {
      await showConfirmDialog(
        context: context,
        style: ConfirmPopupStyle.cancelAndOk,
        title: LocaleKeys.settings_appearance_members_resetInviteLink.tr(),
        description:
            LocaleKeys.settings_appearance_members_resetInviteLinkDescription.tr(),
        confirmLabel: LocaleKeys.settings_appearance_members_reset.tr(),
        onConfirm: (_) {
          context.read<WorkspaceMemberBloc>().add(
                const WorkspaceMemberEvent.generateInviteLink(),
              );
        },
        confirmButtonBuilder: (_) => AFFilledTextButton.destructive(
          text: LocaleKeys.settings_appearance_members_reset.tr(),
          onTap: () {
            context.read<WorkspaceMemberBloc>().add(
                  const WorkspaceMemberEvent.generateInviteLink(),
                );

            Navigator.of(context).pop();
          },
        ),
      );
    } else {
      context.read<WorkspaceMemberBloc>().add(
            const WorkspaceMemberEvent.generateInviteLink(),
          );
    }
  }

  Future<void> _performGenerateInviteLink() async {
    final state = context.read<WorkspaceMemberBloc>().state;
    final subscriptionInfo = state.subscriptionInfo;
    final inviteLink = state.inviteLink;

    // No per-plan member limit enforced here — always allow generating a link.

    // dispatch generate event (this will create or reset link on server)
    context.read<WorkspaceMemberBloc>().add(const WorkspaceMemberEvent.generateInviteLink());
  }

  Future<void> _onClickCreateLink() async {
    // Show iOS style confirm first
    await showSimpleConfirmDialog(
      context: context,
      message: '确定要为工作空间所有成员重置邀请链接？旧链接将无法再使用。',
      confirmText: '重置',
      cancelText: '取消',
      confirmTextColor: Theme.of(context).colorScheme.error,
      onConfirm: () {
        _performGenerateInviteLink();
      },
    );
  }
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '通过邀请链接来新增成员',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              if (_linkEnabled)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                            '只有拥有邀请成员权限的人员才能查看此内容。你也可以 ',
                        style: AppFlowyTheme.of(context)
                            .textStyle
                            .caption
                            .standard(
                              color: AppFlowyTheme.of(context).textColorScheme.primary,
                            ),
                      ),
                      TextSpan(
                        text: '创建新链接',
                        style: AppFlowyTheme.of(context)
                            .textStyle
                            .caption
                            .standard(
                              color: AppFlowyTheme.of(context).textColorScheme.action,
                            ),
                        recognizer: _generateRecog,
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '只有拥有邀请成员权限的人员才能查看此内容。',
                  style: AppFlowyTheme.of(context).textStyle.caption.standard(
                    color: AppFlowyTheme.of(context).textColorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_linkEnabled) ...[
              _CopyLinkButton(),
              const SizedBox(width: 12),
            ],
            Toggle(
              value: _linkEnabled,
              onChanged: (v) {
                setState(() {
                  _linkEnabled = v;
                });
                // persistence can be added later
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Text(
      LocaleKeys.settings_appearance_members_inviteLinkToAddMember.tr(),
      style: theme.textStyle.body.enhanced(
        color: theme.textColorScheme.primary,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: LocaleKeys.settings_appearance_members_clickToCopyLink.tr(),
            style: theme.textStyle.caption.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          TextSpan(
            text: ' ${LocaleKeys.settings_appearance_members_or.tr()} ',
            style: theme.textStyle.caption.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          TextSpan(
            text: LocaleKeys.settings_appearance_members_generateANewLink.tr(),
            style: theme.textStyle.caption.standard(
              color: theme.textColorScheme.action,
            ),
            mouseCursor: SystemMouseCursors.click,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _onGenerateInviteLink(context),
          ),
        ],
      ),
    );
  }

  Future<void> _onGenerateInviteLink(BuildContext context) async {
    final state = context.read<WorkspaceMemberBloc>().state;
    final subscriptionInfo = state.subscriptionInfo;
    final inviteLink = state.inviteLink;

    // check the current workspace member count, if it exceed the limit, show a upgrade dialog.
    // prevent hard code here, because the member count may exceed the limit after the invite link is generated.
    if (inviteLink == null && subscriptionInfo != null) {
      int memberLimit = 0;
      String upgradeToPlan = '';
      
      switch (subscriptionInfo.plan) {
        case WorkspacePlanPB.FreePlan:
          // Free plan for local use, no cloud member limit
          break;
        case WorkspacePlanPB.StudentPlan:
          memberLimit = 2;
          upgradeToPlan = '标准版';
          break;
        case WorkspacePlanPB.StandardPlan:
          memberLimit = 5;
          upgradeToPlan = '团队版';
          break;
        case WorkspacePlanPB.TeamPlan:
          memberLimit = 10;
          break;
      }
      
      if (memberLimit > 0 && state.members.length >= memberLimit) {
        await showConfirmDialog(
          context: context,
          title:
              LocaleKeys.settings_appearance_members_inviteFailedDialogTitle.tr(),
          description: upgradeToPlan.isNotEmpty
              ? '已达到当前计划的成员数量上限（$memberLimit人），请升级到$upgradeToPlan解锁更多成员'
              : LocaleKeys.settings_appearance_members_inviteFailedMemberLimit.tr(),
          confirmLabel: LocaleKeys.upgradePlanModal_actionButton.tr(),
          onConfirm: (_) => context
              .read<WorkspaceMemberBloc>()
              .add(const WorkspaceMemberEvent.upgradePlan()),
        );
        return;
      }
    }

    if (inviteLink != null) {
      // show a dialog to confirm if the user wants to copy the link to the clipboard
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
        confirmButtonBuilder: (_) => AFFilledTextButton.destructive(
          text: LocaleKeys.settings_appearance_members_reset.tr(),
          onTap: () {
            context.read<WorkspaceMemberBloc>().add(
                  const WorkspaceMemberEvent.generateInviteLink(),
                );

            Navigator.of(context).pop();
          },
        ),
      );
    } else {
      context.read<WorkspaceMemberBloc>().add(
            const WorkspaceMemberEvent.generateInviteLink(),
          );
    }
  }
}

class _CopyLinkButton extends StatefulWidget {
  const _CopyLinkButton();

  @override
  State<_CopyLinkButton> createState() => _CopyLinkButtonState();
}

class _CopyLinkButtonState extends State<_CopyLinkButton> {
  ToastificationItem? toastificationItem;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFOutlinedTextButton.normal(
      text: LocaleKeys.settings_appearance_members_copyLink.tr(),
      textStyle: theme.textStyle.body.standard(
        color: theme.textColorScheme.primary,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.l,
        vertical: theme.spacing.s,
      ),
      onTap: () async {
        final state = context.read<WorkspaceMemberBloc>().state;
        final subscriptionInfo = state.subscriptionInfo;
        // check the current workspace member count, if it exceed the limit, show a upgrade dialog.
        // prevent hard code here, because the member count may exceed the limit after the invite link is generated.
        // Allow copying invite link for all plans — no upgrade restriction.

        final link = state.inviteLink;
        if (link != null) {
          await getIt<ClipboardService>().setData(
            ClipboardServiceData(
              plainText: link,
            ),
          );

          if (toastificationItem != null) {
            toastification.dismiss(toastificationItem!);
          }

          toastificationItem = showToastNotification(
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
