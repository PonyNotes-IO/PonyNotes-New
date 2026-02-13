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
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';

class WorkspaceMembersPage extends StatefulWidget {
  const WorkspaceMembersPage({
    super.key,
    required this.userProfile,
    required this.workspaceId,
  });

  final UserProfilePB userProfile;
  final String workspaceId;

  @override
  State<WorkspaceMembersPage> createState() => _WorkspaceMembersPageState();
}

class _WorkspaceMembersPageState extends State<WorkspaceMembersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WorkspaceMemberBloc>(
      create: (context) => WorkspaceMemberBloc(userProfile: widget.userProfile)
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
                              final uwState =
                                  context.read<UserWorkspaceBloc>().state;
                              bool isNonFreeMember = false;
                              final sub =
                                  uwState.currentSubscription?.subscription;
                              if (sub != null &&
                                  (sub.planCode?.isNotEmpty ?? false)) {
                                final planCode = sub.planCode!.toLowerCase();
                                if (planCode != 'free' &&
                                    planCode != 'freeplan' &&
                                    planCode != 'fmb') {
                                  final end = uwState.currentSubscription
                                      ?.subscription?.endDate;
                                  if (end == null ||
                                      end.isAfter(DateTime.now())) {
                                    isNonFreeMember = true;
                                  }
                                }
                              } else if (uwState.workspaceSubscriptionInfo !=
                                  null) {
                                isNonFreeMember =
                                    uwState.workspaceSubscriptionInfo!.plan !=
                                        WorkspacePlanPB.FreePlan;
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
                  // Invite link above; place the "添加成员" button and the search box on the same row.
                  const InviteMemberByLink(),
                  const SettingsCategorySpacer(),
                  Row(
                    children: [
                      // "添加成员" button (renders from InviteMemberByEmail widget)
                      const InviteMemberByEmail(),
                      const Spacer(),
                      SizedBox(
                        width: 320,
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(hoverColor: Colors.transparent),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: '搜索姓名或联系方式',
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      splashRadius: 20,
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor:
                                  Theme.of(context).cardColor.withOpacity(0.03),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 12),
                            ),
                            onChanged: (v) {
                              setState(() {
                                _searchQuery = v.trim().toLowerCase();
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SettingsCategorySpacer(bottomSpacing: 0),
                ],

                // Members list or friendly placeholder when empty
                if (state.members.isNotEmpty)
                  _MemberList(
                    members: (_searchQuery.isEmpty)
                        ? state.members
                        : state.members.where((m) {
                            final q = _searchQuery;
                            final name = m.name.toLowerCase();
                            final email = m.email.toLowerCase();
                            return name.contains(q) || email.contains(q);
                          }).toList(),
                    userProfile: widget.userProfile,
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
                                context.read<WorkspaceMemberBloc>().add(
                                    const WorkspaceMemberEvent.getInviteCode());
                                context.read<WorkspaceMemberBloc>().add(
                                    const WorkspaceMemberEvent
                                        .getWorkspaceMembers());
                              },
                            ),
                            // "去设置" removed per UX: guide user to enable cloud sync directly.
                            OutlinedRoundedButton(
                              text: '启用数据同步',
                              onTap: () async {
                                try {
                                  // Request enabling cloud sync via UserWorkspaceBloc
                                  context.read<UserWorkspaceBloc>().add(
                                        UserWorkspaceEvent
                                            .updateCloudSyncEnabled(
                                          enabled: true,
                                        ),
                                      );
                                  showToastNotification(
                                    message: '已请求启用数据同步，请等待后台生效后重试。',
                                  );
                                } catch (e) {
                                  Log.error(
                                      'Request to enable cloud sync failed: $e');
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
              ? LocaleKeys.settings_appearance_members_inviteFailedMemberLimit
                  .tr()
              : LocaleKeys.settings_appearance_members_failedToInviteMember
                  .tr();
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
          flex: 3,
          child: Text(
            '团队协作区',
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
        // Expanded(
        //   flex: 2,
        //   child: Text(
        //     '群组',
        //     style: theme.textStyle.body.standard(
        //       color: theme.textColorScheme.secondary,
        //     ),
        //   ),
        // ),
        // email column removed per design
        Expanded(flex: 1, child: SizedBox(width: 24.0)),
      ],
    );
  }
}

class _MemberItem extends StatefulWidget {
  const _MemberItem({
    required this.member,
    required this.myRole,
    required this.userProfile,
  });

  final WorkspaceMemberPB member;
  final AFRolePB myRole;
  final UserProfilePB userProfile;

  @override
  State<_MemberItem> createState() => _MemberItemState();
}

class _MemberItemState extends State<_MemberItem> {
  String? _contact;

  @override
  void initState() {
    super.initState();
    // 优先使用 email；email 为空时直接显示空（避免 N+1 API 查询）
    _contact = widget.member.email.isNotEmpty ? widget.member.email : '';
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final myRole = widget.myRole;
    final userProfile = widget.userProfile;
    final theme = AppFlowyTheme.of(context);
    final currentWorkspace =
        context.watch<UserWorkspaceBloc>().state.currentWorkspace;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                      _contact ?? '',
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
        // 团队协作区 列
        Expanded(
          flex: 3,
          child: Text(
            currentWorkspace?.name ?? '—',
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 2,
          child:member.role.isOwner || !myRole.canUpdate
              ? FlowyText.regular(
            member.role.description,
            color: theme.textColorScheme.primary,
            fontSize: 14,
          )
              : _MemberRoleActionList(
            member: member,
          ),
        ),
        // 群组 列（placeholder，目前 backend 未提供 group 字段）
        // Expanded(
        //   flex: 2,
        //   child: Text(
        //     '—',
        //     style: theme.textStyle.body.standard(
        //       color: theme.textColorScheme.primary,
        //     ),
        //     maxLines: 1,
        //     overflow: TextOverflow.ellipsis,
        //   ),
        // ),
        // email column removed per design; keep member.email available for internal logic (e.g., delete check)
        Expanded(
          flex: 1,
          child: myRole.isOwner &&
                  member.name != userProfile.name // can't delete self
              ? _MemberMoreActionList(member: member)
              : SizedBox(width: 24.0),
        )
      ],
    );
  }
}

enum _MemberMoreAction {
  delete,
}

class _MemberMoreActionList extends StatefulWidget {
  const _MemberMoreActionList({
    required this.member,
  });

  final WorkspaceMemberPB member;

  @override
  State<_MemberMoreActionList> createState() => _MemberMoreActionListState();
}

class _MemberMoreActionListState extends State<_MemberMoreActionList> {
  late final String _memberIdentifier;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    // 优先使用 email，否则用 name 做标识（避免 N+1 API 查询）
    _memberIdentifier = member.email.isNotEmpty ? member.email : member.name;
  }

  @override
  Widget build(BuildContext context) {
    return PopoverActionList<_MemberMoreActionWrapper>(
      asBarrier: true,
      direction: PopoverDirection.bottomWithCenterAligned,
      actions: _MemberMoreAction.values
          .map((e) => _MemberMoreActionWrapper(e, widget.member))
          .toList(),
      buildChild: (controller) {
        return FlowyButton(
          useIntrinsicWidth: true,
          text: FlowyText.regular(
            LocaleKeys.settings_appearance_members_removeMember.tr(),
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
          ),
          onTap: () {
            controller.show();
          },
        );
      },
      onSelected: (action, controller) {
        switch (action.inner) {
          case _MemberMoreAction.delete:
            final identifier = _memberIdentifier;

            Log.info('准备删除成员: name=${widget.member.name}, identifier=$identifier, email=${widget.member.email}');

            showCancelAndDeleteDialog(
              context: context,
              title: LocaleKeys.settings_appearance_members_removeMember.tr(),
              description: LocaleKeys
                  .settings_appearance_members_areYouSureToRemoveMember
                  .tr(),
              confirmLabel: LocaleKeys.button_delete.tr(),
              onDelete: () {
                Log.info('确认删除成员: identifier=$identifier');
                // 使用 BlocBuilder 确保在 widget active 时才发送事件
                if (!context.mounted) {
                  Log.error('删除失败: context 已卸载');
                  return;
                }
                context.read<WorkspaceMemberBloc>().add(
                      WorkspaceMemberEvent.removeWorkspaceMemberByEmail(identifier),
                    );
              },
              closeOnAction: true
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

class _RoleActionWrapper extends ActionCell {
  _RoleActionWrapper(this.role, this.member);

  final AFRolePB role;
  final WorkspaceMemberPB member;

  @override
  String get name {
    switch (role) {
      case AFRolePB.Owner:
        return '工作空间所有者';
      case AFRolePB.Member:
        return '成员';
      case AFRolePB.Guest:
        return '受限成员';
    }
    return "";
  }
}

class _MemberRoleActionList extends StatelessWidget {
  const _MemberRoleActionList({
    required this.member,
  });

  final WorkspaceMemberPB member;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    
    // 定义角色选项
    final roleOptions = [
      _RoleActionWrapper(AFRolePB.Owner, member),
      _RoleActionWrapper(AFRolePB.Member, member),
      _RoleActionWrapper(AFRolePB.Guest, member),
    ];

    return PopoverActionList<_RoleActionWrapper>(
      asBarrier: true,
      direction: PopoverDirection.bottomWithCenterAligned,
      actions: roleOptions,
      buildChild: (controller) {
        return FlowyButton(
          useIntrinsicWidth:true,
          onTap: () {
            controller.show();
          },
          text: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlowyText.regular(
                _getRoleDisplayName(member.role),
                color: theme.textColorScheme.primary,
                fontSize: 14,
              ),
              FlowySvg(FlowySvgs.arrow_down_s,)
            ],
          ),
        );
      },
      onSelected: (action, controller) {
        if (action.role == member.role) {
          controller.close();
          return;
        }
        
        // Dispatch update event
        context.read<WorkspaceMemberBloc>().add(
              WorkspaceMemberEvent.updateWorkspaceMember(
                member.name,
                action.role,
              ),
            );
        controller.close();
      },
    );
  }

  String _getRoleDisplayName(AFRolePB role) {
    switch (role) {
      case AFRolePB.Owner:
        return '工作空间所有者';
      case AFRolePB.Member:
        return '成员';
      case AFRolePB.Guest:
        return '受限成员';
    }
    return "";
  }

}
