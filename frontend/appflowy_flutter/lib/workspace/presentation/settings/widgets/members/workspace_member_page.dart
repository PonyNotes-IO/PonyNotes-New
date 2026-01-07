import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/shared/af_role_pb_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category_spacer.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/invitation/invite_member_by_email.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/invitation/invite_member_by_link.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';

class WorkspaceMembersPage extends StatelessWidget {
  const WorkspaceMembersPage({
    super.key,
    required this.userProfile,
    required this.workspaceId,
  });

  final UserProfilePB userProfile;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WorkspaceMemberBloc>(
      create: (context) => WorkspaceMemberBloc(userProfile: userProfile)
        ..add(const WorkspaceMemberEvent.initial())
        ..add(const WorkspaceMemberEvent.getInviteCode()),
      child: BlocConsumer<WorkspaceMemberBloc, WorkspaceMemberState>(
        listener: _showResultDialog,
        builder: (context, state) {
          if (state.dataSyncRequired) {
            return SettingsBody(
              title: '人员管理',
              autoSeparate: false,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        FlowyText(
                          '当前云同步未启用。请启用云同步以使用人员管理功能。',
                          fontSize: 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          textAlign: TextAlign.center,
                        ),
                        const VSpace(20),
                        OutlinedRoundedButton(
                          text: '启用数据同步',
                          onTap: () async {
                            try {
                              final uwState = context.read<UserWorkspaceBloc>().state;
                              bool isNonFreeMember = false;
                              final sub = uwState.currentSubscription?.subscription;
                              if (sub != null && (sub.planCode?.isNotEmpty ?? false)) {
                                final planCode = sub.planCode!.toLowerCase();
                                if (planCode != 'free' && planCode != 'freeplan') {
                                  final end = uwState.currentSubscription?.subscription?.endDate;
                                  if (end == null || end.isAfter(DateTime.now())) {
                                    isNonFreeMember = true;
                                  }
                                }
                              } else if (uwState.workspaceSubscriptionInfo != null) {
                                isNonFreeMember =
                                    uwState.workspaceSubscriptionInfo!.plan != WorkspacePlanPB.FreePlan;
                              }

                              if (!isNonFreeMember) {
                                showToastNotification(
                                  type: ToastificationType.error,
                                  message: '云同步为会员专享，请先开通会员后启用。',
                                );
                                return;
                              }

                              context.read<UserWorkspaceBloc>().add(
                                    UserWorkspaceEvent.updateCloudSyncEnabled(
                                      enabled: true,
                                    ),
                                  );
                              showToastNotification(
                                message: '已请求启用数据同步，请稍候重试。',
                              );
                            } catch (e) {
                              Log.error('Failed to request enable sync: $e');
                              showToastNotification(
                                type: ToastificationType.error,
                                message: '无法启用数据同步，请联系管理员。',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return SettingsBody(
            title: '人员管理',
            // Enable it when the backend support admin panel
            // descriptionBuilder: _buildDescription,
            autoSeparate: false,
            children: [
              // Show loading indicator when fetching
              if (state.isLoading) ...[
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ] else ...[
                // Invite section (owners/admins)
              if (state.myRole.canInvite) ...[
                const InviteMemberByLink(),
                const SettingsCategorySpacer(),
                const InviteMemberByEmail(),
                const SettingsCategorySpacer(
                  bottomSpacing: 0,
                ),
              ],

                // Members list or friendly placeholder when empty
              if (state.members.isNotEmpty)
                _MemberList(
                  members: state.members,
                  userProfile: userProfile,
                  myRole: state.myRole,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        FlowyText(
                          '无法加载成员或当前没有成员。',
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        const VSpace(12),
                        Wrap(
                          spacing: 12,
                          children: [
                            OutlinedRoundedButton(
                              text: '重试',
                              onTap: () {
                                context
                                    .read<WorkspaceMemberBloc>()
                                    .add(const WorkspaceMemberEvent.getInviteCode());
                                context
                                    .read<WorkspaceMemberBloc>()
                                    .add(const WorkspaceMemberEvent.getWorkspaceMembers());
                              },
                            ),
                            // "去设置" removed per UX: guide user to enable cloud sync directly.
                            OutlinedRoundedButton(
                              text: '启用数据同步',
                              onTap: () async {
                                try {
                                  // Request enabling cloud sync via UserWorkspaceBloc
                                  context.read<UserWorkspaceBloc>().add(
                                        UserWorkspaceEvent.updateCloudSyncEnabled(
                                          enabled: true,
                                        ),
                                      );
                                  showToastNotification(
                                    message: '已请求启用数据同步，请等待后台生效后重试。',
                                  );
                                } catch (e) {
                                  Log.error('Request to enable cloud sync failed: $e');
                                  showToastNotification(
                                    type: ToastificationType.error,
                                    message: '无法启用数据同步，请在服务器端检查配置或联系管理员。',
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  // Enable it when the backend support admin panel
  // Widget _buildDescription(BuildContext context) {
  //   final theme = AppFlowyTheme.of(context);
  //   return Text.rich(
  //     TextSpan(
  //       children: [
  //         TextSpan(
  //           text:
  //               '${LocaleKeys.settings_appearance_members_memberPageDescription1.tr()} ',
  //           style: theme.textStyle.caption.standard(
  //             color: theme.textColorScheme.secondary,
  //           ),
  //         ),
  //         TextSpan(
  //           text: LocaleKeys.settings_appearance_members_adminPanel.tr(),
  //           style: theme.textStyle.caption.underline(
  //             color: theme.textColorScheme.secondary,
  //           ),
  //           mouseCursor: SystemMouseCursors.click,
  //           recognizer: TapGestureRecognizer()
  //             ..onTap = () async {
  //               final baseUrl = await getAppFlowyCloudUrl();
  //               await afLaunchUrlString(baseUrl);
  //             },
  //         ),
  //         TextSpan(
  //           text:
  //               ' ${LocaleKeys.settings_appearance_members_memberPageDescription2.tr()} ',
  //           style: theme.textStyle.caption.standard(
  //             color: theme.textColorScheme.secondary,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // Widget _showMemberLimitWarning(
  //   BuildContext context,
  //   WorkspaceMemberState state,
  // ) {
  //   // We promise that state.actionResult != null before calling
  //   // this method
  //   final actionResult = state.actionResult!.result;
  //   final actionType = state.actionResult!.actionType;

  //   if (actionType == WorkspaceMemberActionType.inviteByEmail &&
  //       actionResult.isFailure) {
  //     final error = actionResult.getFailure().code;
  //     if (error == ErrorCode.WorkspaceMemberLimitExceeded) {
  //       return Row(
  //         children: [
  //           const FlowySvg(
  //             FlowySvgs.warning_s,
  //             blendMode: BlendMode.dst,
  //             size: Size.square(20),
  //           ),
  //           const HSpace(12),
  //           Expanded(
  //             child: RichText(
  //               text: TextSpan(
  //                 children: [
  //                   if (state.subscriptionInfo?.plan ==
  //                       WorkspacePlanPB.ProPlan) ...[
  //                     TextSpan(
  //                       text: LocaleKeys
  //                           .settings_appearance_members_memberLimitExceededPro
  //                           .tr(),
  //                       style: TextStyle(
  //                         fontSize: 14,
  //                         fontWeight: FontWeight.w400,
  //                         color: AFThemeExtension.of(context).strongText,
  //                       ),
  //                     ),
  //                     WidgetSpan(
  //                       child: MouseRegion(
  //                         cursor: SystemMouseCursors.click,
  //                         child: GestureDetector(
  //                           // Hardcoded support email, in the future we might
  //                           // want to add this to an environment variable
  //                           onTap: () async => afLaunchUrlString(
  //                             'mailto:support@appflowy.io',
  //                           ),
  //                           child: FlowyText(
  //                             LocaleKeys
  //                                 .settings_appearance_members_memberLimitExceededProContact
  //                                 .tr(),
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w400,
  //                             color: Theme.of(context).colorScheme.primary,
  //                           ),
  //                         ),
  //                       ),
  //                     ),
  //                   ] else ...[
  //                     TextSpan(
  //                       text: LocaleKeys
  //                           .settings_appearance_members_memberLimitExceeded
  //                           .tr(),
  //                       style: TextStyle(
  //                         fontSize: 14,
  //                         fontWeight: FontWeight.w400,
  //                         color: AFThemeExtension.of(context).strongText,
  //                       ),
  //                     ),
  //                     WidgetSpan(
  //                       child: MouseRegion(
  //                         cursor: SystemMouseCursors.click,
  //                         child: GestureDetector(
  //                           onTap: () => context
  //                               .read<WorkspaceMemberBloc>()
  //                               .add(const WorkspaceMemberEvent.upgradePlan()),
  //                           child: FlowyText(
  //                             LocaleKeys
  //                                 .settings_appearance_members_memberLimitExceededUpgrade
  //                                 .tr(),
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w400,
  //                             color: Theme.of(context).colorScheme.primary,
  //                           ),
  //                         ),
  //                       ),
  //                     ),
  //                   ],
  //                 ],
  //               ),
  //             ),
  //           ),
  //         ],
  //       );
  //     }
  //   }

  //   return const SizedBox.shrink();
  // }

  void _showResultDialog(BuildContext context, WorkspaceMemberState state) {
    final actionResult = state.actionResult;
    if (actionResult == null) {
      return;
    }

    final actionType = actionResult.actionType;
    final result = actionResult.result;

    // only show the result dialog when the action is WorkspaceMemberActionType.add
    if (actionType == WorkspaceMemberActionType.addByEmail) {
      result.fold(
        (s) {
          showToastNotification(
            message:
                LocaleKeys.settings_appearance_members_addMemberSuccess.tr(),
          );
        },
        (f) {
          Log.error('add workspace member failed: $f');
          final message = f.code == ErrorCode.WorkspaceMemberLimitExceeded
              ? LocaleKeys.settings_appearance_members_memberLimitExceeded.tr()
              : LocaleKeys.settings_appearance_members_failedToAddMember.tr();
          showDialog(
            context: context,
            builder: (context) => NavigatorOkCancelDialog(message: message),
          );
        },
      );
    } else if (actionType == WorkspaceMemberActionType.inviteByEmail) {
      result.fold(
        (s) {
          showToastNotification(
            message:
                LocaleKeys.settings_appearance_members_inviteMemberSuccess.tr(),
          );
        },
        (f) {
          Log.error('invite workspace member failed: $f');
          final message = f.code == ErrorCode.WorkspaceMemberLimitExceeded
              ? LocaleKeys.settings_appearance_members_inviteFailedMemberLimit.tr()
              : LocaleKeys.settings_appearance_members_failedToInviteMember.tr();
          // Show a plain dialog without forcing upgrade action.
          showDialog(
            context: context,
            builder: (context) => NavigatorOkCancelDialog(message: message),
          );
        },
      );
    } else if (actionType == WorkspaceMemberActionType.generateInviteLink) {
      result.fold(
        (s) async {
          showToastNotification(
            message: LocaleKeys
                .settings_appearance_members_generatedLinkSuccessfully
                .tr(),
          );

          // copy the invite link to the clipboard
          final inviteLink = state.inviteLink;
          if (inviteLink != null) {
            await getIt<ClipboardService>().setPlainText(inviteLink);
            Future.delayed(const Duration(milliseconds: 200), () {
              showToastNotification(
                message: LocaleKeys.shareAction_copyLinkSuccess.tr(),
              );
            });
          }
        },
        (f) {
          Log.error('generate invite link failed: $f');
          showToastNotification(
            type: ToastificationType.error,
            message:
                LocaleKeys.settings_appearance_members_generatedLinkFailed.tr(),
          );
        },
      );
    } else if (actionType == WorkspaceMemberActionType.resetInviteLink) {
      result.fold(
        (s) async {
          showToastNotification(
            message: LocaleKeys
                .settings_appearance_members_resetLinkSuccessfully
                .tr(),
          );

          // copy the invite link to the clipboard
          final inviteLink = state.inviteLink;
          if (inviteLink != null) {
            await getIt<ClipboardService>().setPlainText(inviteLink);
            Future.delayed(const Duration(milliseconds: 200), () {
              showToastNotification(
                message: LocaleKeys.shareAction_copyLinkSuccess.tr(),
              );
            });
          }
        },
        (f) {
          Log.error('generate invite link failed: $f');
          showToastNotification(
            type: ToastificationType.error,
            message:
                LocaleKeys.settings_appearance_members_resetLinkFailed.tr(),
          );
        },
      );
    }
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.members,
    required this.myRole,
    required this.userProfile,
  });

  final List<WorkspaceMemberPB> members;
  final AFRolePB myRole;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return SeparatedColumn(
      crossAxisAlignment: CrossAxisAlignment.start,
      separatorBuilder: () => Divider(
        color: theme.borderColorScheme.primary,
      ),
      children: [
        const _MemberListHeader(),
        ...members.map(
          (member) => _MemberItem(
            member: member,
            myRole: myRole,
            userProfile: userProfile,
          ),
        ),
      ],
    );
  }
}

class _MemberListHeader extends StatelessWidget {
  const _MemberListHeader();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            LocaleKeys.settings_appearance_members_user.tr(),
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            LocaleKeys.settings_appearance_members_role.tr(),
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            LocaleKeys.settings_accountPage_email_title.tr(),
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        const HSpace(28.0),
      ],
    );
  }
}

class _MemberItem extends StatelessWidget {
  const _MemberItem({
    required this.member,
    required this.myRole,
    required this.userProfile,
  });

  final WorkspaceMemberPB member;
  final AFRolePB myRole;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Row(
            children: [
              UserAvatar(
                iconUrl: member.avatarUrl,
                name: member.name,
                size: AFAvatarSize.s,
              ),
              HSpace(8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: theme.textStyle.body.enhanced(
                        color: theme.textColorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatJoinedDate(member.joinedAt.toInt()),
                      style: theme.textStyle.caption.standard(
                        color: theme.textColorScheme.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              HSpace(8),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: member.role.isOwner || !myRole.canUpdate
              ? Text(
                  member.role.description,
                  style: theme.textStyle.body.standard(
                    color: theme.textColorScheme.primary,
                  ),
                )
              : _MemberRoleActionList(
                  member: member,
                ),
        ),
        Expanded(
          flex: 3,
          child: FlowyTooltip(
            message: member.email,
            child: Text(
              member.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
        ),
        myRole.canDelete &&
                member.email != userProfile.email // can't delete self
            ? _MemberMoreActionList(member: member)
            : const HSpace(28.0),
      ],
    );
  }

  String _formatJoinedDate(int joinedAt) {
    final date = DateTime.fromMillisecondsSinceEpoch(joinedAt * 1000);
    return 'Joined on ${DateFormat('MMM d, y').format(date)}';
  }
}

enum _MemberMoreAction {
  delete,
}

class _MemberMoreActionList extends StatelessWidget {
  const _MemberMoreActionList({
    required this.member,
  });

  final WorkspaceMemberPB member;

  @override
  Widget build(BuildContext context) {
    return PopoverActionList<_MemberMoreActionWrapper>(
      asBarrier: true,
      direction: PopoverDirection.bottomWithCenterAligned,
      actions: _MemberMoreAction.values
          .map((e) => _MemberMoreActionWrapper(e, member))
          .toList(),
      buildChild: (controller) {
        return FlowyButton(
          useIntrinsicWidth: true,
          text: const FlowySvg(
            FlowySvgs.three_dots_s,
          ),
          onTap: () {
            controller.show();
          },
        );
      },
      onSelected: (action, controller) {
        switch (action.inner) {
          case _MemberMoreAction.delete:
            showCancelAndConfirmDialog(
              context: context,
              title: LocaleKeys.settings_appearance_members_removeMember.tr(),
              description: LocaleKeys
                  .settings_appearance_members_areYouSureToRemoveMember
                  .tr(),
              confirmLabel: LocaleKeys.button_yes.tr(),
              onConfirm: (_) => context.read<WorkspaceMemberBloc>().add(
                    WorkspaceMemberEvent.removeWorkspaceMemberByEmail(
                      action.member.email,
                    ),
                  ),
            );
            break;
        }
        controller.close();
      },
    );
  }
}

class _MemberMoreActionWrapper extends ActionCell {
  _MemberMoreActionWrapper(this.inner, this.member);

  final _MemberMoreAction inner;
  final WorkspaceMemberPB member;

  @override
  String get name {
    switch (inner) {
      case _MemberMoreAction.delete:
        return LocaleKeys.settings_appearance_members_removeFromWorkspace.tr();
    }
  }
}

class _MemberRoleActionList extends StatefulWidget {
  const _MemberRoleActionList({
    required this.member,
  });

  final WorkspaceMemberPB member;

  @override
  State<_MemberRoleActionList> createState() => _MemberRoleActionListState();
}

class _MemberRoleActionListState extends State<_MemberRoleActionList> {
  late AFRolePB _currentRole;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.member.role;
  }

  @override
  void didUpdateWidget(covariant _MemberRoleActionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the member role changed in the parent state, update local state so UI reflects it immediately.
    if (oldWidget.member.role != widget.member.role) {
      setState(() {
        _currentRole = widget.member.role;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return DropdownButton<AFRolePB>(
      value: _currentRole,
      items: [
        DropdownMenuItem(value: AFRolePB.Owner, child: Text('工作空间所有者')),
        DropdownMenuItem(value: AFRolePB.Member, child: Text('成员')),
        DropdownMenuItem(value: AFRolePB.Guest, child: Text('受限成员')),
      ],
      onChanged: (v) {
        if (v == null) return;
        if (v == _currentRole) return;
        // Optimistically update UI
        setState(() {
          _currentRole = v;
        });
        // Dispatch update event
        context.read<WorkspaceMemberBloc>().add(
              WorkspaceMemberEvent.updateWorkspaceMember(
                widget.member.email,
                v,
              ),
            );
      },
      underline: const SizedBox.shrink(),
      elevation: 0,
      dropdownColor: Theme.of(context).cardColor,
      style: theme.textStyle.body.standard(
        color: theme.textColorScheme.primary,
      ),
    );
  }
}
