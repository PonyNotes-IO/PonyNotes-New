import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/show_flowy_mobile_confirm_dialog.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/shared/af_role_pb_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/invitation/m_invite_member_by_email.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/invitation/m_invite_member_by_link.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';

import 'member_list.dart';

ValueNotifier<int> mobileLeaveWorkspaceNotifier = ValueNotifier(0);

class InviteMembersScreen extends StatelessWidget {
  const InviteMembersScreen({
    super.key,
  });

  static const routeName = '/invite_member';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfilePB?>(
      future: _loadUserProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: SizedBox.shrink(),
          );
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: MobileAppBar(title: '空间成员'),
            body: const _InviteMemberError(),
          );
        }

        final userProfile = snapshot.data!;

        // 把 WorkspaceMemberBloc 提升到 Scaffold 之上，
        // 让 Bottom Sheet 也能 context.read<WorkspaceMemberBloc>()。
        return BlocProvider<WorkspaceMemberBloc>(
          create: (context) => WorkspaceMemberBloc(userProfile: userProfile)
            ..add(const WorkspaceMemberEvent.initial())
            ..add(const WorkspaceMemberEvent.getInviteCode()),
          child: Builder(
            builder: (context) {
              return Scaffold(
                appBar: MobileAppBar(
                  title: '空间成员',
                  actions: [_buildAddMemberButton(context)],
                ),
                body: const _InviteMemberPage(),
                resizeToAvoidBottomInset: false,
              );
            },
          ),
        );
      },
    );
  }

  Future<UserProfilePB?> _loadUserProfile() async {
    final result = await UserBackendService.getCurrentUserProfile();
    return result.fold(
      (s) => s,
      (_) => null,
    );
  }

  Widget _buildAddMemberButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: GestureDetector(
        onTap: () => _showInviteByEmailSheet(context),
        child: FlowySvg(FlowySvgs.add_thin_s),
      ),
    );
  }

  void _showInviteByEmailSheet(BuildContext context) {
    // Bottom Sheet 在新 route 上打开，无法自动继承父 BlocProvider，
    // 所以这里显式 .value 注入同一份 Bloc 实例。
    final bloc = context.read<WorkspaceMemberBloc>();
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: '添加成员',
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return BlocProvider<WorkspaceMemberBloc>.value(
          value: bloc,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppFlowyTheme.of(ctx).spacing.l,
            ),
            child: const MInviteMemberByEmail(),
          ),
        );
      },
    );
  }
}

class _InviteMemberError extends StatelessWidget {
  const _InviteMemberError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowyText.medium(
              LocaleKeys.settings_appearance_members_workspaceMembersError.tr(),
              fontSize: 18.0,
              textAlign: TextAlign.center,
            ),
            const VSpace(8.0),
            FlowyText.regular(
              LocaleKeys
                  .settings_appearance_members_workspaceMembersErrorDescription
                  .tr(),
              fontSize: 17.0,
              maxLines: 10,
              textAlign: TextAlign.center,
              lineHeight: 1.3,
              color: Theme.of(context).hintColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteMemberPage extends StatefulWidget {
  const _InviteMemberPage();

  @override
  State<_InviteMemberPage> createState() => _InviteMemberPageState();
}

class _InviteMemberPageState extends State<_InviteMemberPage> {
  final searchController = TextEditingController();
  String _searchQuery = '';
  bool exceededLimit = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // WorkspaceMemberBloc 已经在外层 InviteMembersScreen 创建并注入，
    // 这里直接消费；BlocConsumer 仍用于弹出邀请成功/失败的 toast。
    return BlocConsumer<WorkspaceMemberBloc, WorkspaceMemberState>(
      listener: _onListener,
      builder: (context, state) {
        // 云同步未启用时显示提示
        if (state.dataSyncRequired) {
          return _buildCloudSyncRequiredView(context);
        }

        // 过滤成员列表
        final filteredMembers = _searchQuery.isEmpty
            ? state.members
            : state.members.where((m) {
                final q = _searchQuery.toLowerCase();
                return m.name.toLowerCase().contains(q) ||
                    m.email.toLowerCase().contains(q);
              }).toList();

        final currentUserProfile = context.read<WorkspaceMemberBloc>().userProfile;

        return SingleChildScrollView(
          child: Column(
            children: [
              VSpace(theme.spacing.xl),
              // 搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _MemberSearchBar(
                  controller: searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              VSpace(8),
              if (state.myRole.isOwner) ...[
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.spacing.xl,
                  ),
                  child: MInviteMemberByLink(),
                ),
              ],
              if (filteredMembers.isNotEmpty) ...[
                VSpace(8),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.spacing.xl,
                  ),
                  child: MobileMemberList(
                    members: filteredMembers,
                    userProfile: currentUserProfile,
                    myRole: state.myRole,
                  ),
                ),
              ] else if (_searchQuery.isNotEmpty) ...[
                // 搜索无结果
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: theme.spacing.xl * 2,
                  ),
                  child: Center(
                    child: FlowyText(
                      '未找到匹配的成员',
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                ),
              ],
              if (state.myRole.isMember) ...[
                const SizedBox(height: 24),
                const _LeaveWorkspaceButton(),
              ],
              const VSpace(48),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCloudSyncRequiredView(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.textColorScheme.secondary,
            ),
            const VSpace(24),
            FlowyText.medium(
              '云同步未启用',
              fontSize: 18.0,
              textAlign: TextAlign.center,
            ),
            const VSpace(12),
            FlowyText.regular(
              '请启用云同步以使用人员管理功能',
              fontSize: 14.0,
              maxLines: 3,
              textAlign: TextAlign.center,
              color: theme.textColorScheme.secondary,
            ),
            const VSpace(24),
            AFOutlinedTextButton.normal(
              text: '启用数据同步',
              onTap: () => _enableCloudSync(context),
            ),
          ],
        ),
      ),
    );
  }

  void _enableCloudSync(BuildContext context) async {
    try {
      context.read<UserWorkspaceBloc>().add(
            UserWorkspaceEvent.updateCloudSyncEnabled(enabled: true),
          );
      showToastNotification(
        message: '已请求启用数据同步，请稍候重试',
      );
    } catch (e) {
      Log.error('Failed to request enable sync: $e');
      showToastNotification(
        type: ToastificationType.error,
        message: '无法启用数据同步，请联系管理员',
      );
    }
  }

  void _onListener(BuildContext context, WorkspaceMemberState state) {
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
              ? LocaleKeys
                  .settings_appearance_members_inviteFailedMemberLimitMobile
                  .tr()
              : LocaleKeys.settings_appearance_members_failedToAddMember.tr();
          setState(() {
            exceededLimit = f.code == ErrorCode.WorkspaceMemberLimitExceeded;
          });
          showToastNotification(
            type: ToastificationType.error,
            message: message,
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
              ? LocaleKeys
                  .settings_appearance_members_inviteFailedMemberLimitMobile
                  .tr()
              : LocaleKeys.settings_appearance_members_failedToInviteMember
                  .tr();
          setState(() {
            exceededLimit = f.code == ErrorCode.WorkspaceMemberLimitExceeded;
          });

          showToastNotification(
            type: ToastificationType.error,
            message: message,
          );
        },
      );
    } else if (actionType == WorkspaceMemberActionType.removeByEmail) {
      result.fold(
        (s) {
          showToastNotification(
            message: LocaleKeys
                .settings_appearance_members_removeFromWorkspaceSuccess
                .tr(),
          );
        },
        (f) {
          showToastNotification(
            type: ToastificationType.error,
            message: LocaleKeys
                .settings_appearance_members_removeFromWorkspaceFailed
                .tr(),
          );
        },
      );
    } else if (actionType == WorkspaceMemberActionType.generateInviteLink) {
      result.fold(
        (s) {
          showToastNotification(
            message: LocaleKeys
                .settings_appearance_members_generatedLinkSuccessfully
                .tr(),
          );

          // copy the invite link to the clipboard
          final inviteLink = state.inviteLink;
          if (inviteLink != null) {
            getIt<ClipboardService>().setPlainText(inviteLink);
            showToastNotification(
              message: LocaleKeys.shareAction_copyLinkSuccess.tr(),
            );
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
        (s) {
          showToastNotification(
            message: LocaleKeys
                .settings_appearance_members_resetLinkSuccessfully
                .tr(),
          );

          // copy the invite link to the clipboard
          final inviteLink = state.inviteLink;
          if (inviteLink != null) {
            getIt<ClipboardService>().setPlainText(inviteLink);
            showToastNotification(
              message: LocaleKeys.shareAction_copyLinkSuccess.tr(),
            );
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

class _MemberSearchBar extends StatelessWidget {
  const _MemberSearchBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10.0)),
      borderSide: BorderSide(color: theme.borderColorScheme.primary),
    );
    final enableBorder = border.copyWith(
      borderSide: BorderSide(color: theme.borderColorScheme.themeThick),
    );
    final hintStyle = theme.textStyle.heading4.standard(
      color: theme.textColorScheme.tertiary,
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return TextField(
          controller: controller,
          onChanged: onChanged,
          style: theme.textStyle.heading4.standard(
            color: theme.textColorScheme.primary,
          ),
          decoration: InputDecoration(
            hintText: '搜索姓名或联系方式',
            hintStyle: hintStyle,
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            border: border,
            enabledBorder: border,
            focusedBorder: enableBorder,
            prefixIconConstraints: BoxConstraints.loose(const Size(38, 40)),
            prefixIcon: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: FlowySvg(
                FlowySvgs.m_home_search_icon_m,
                color: theme.iconColorScheme.secondary,
                size: const Size.square(20),
              ),
            ),
            suffixIconConstraints:
                controller.text.isNotEmpty ? BoxConstraints.loose(const Size(34, 40)) : null,
            suffixIcon: controller.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
                      child: FlowySvg(
                        FlowySvgs.search_clear_m,
                        color: theme.iconColorScheme.tertiary,
                        size: const Size.square(20),
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _LeaveWorkspaceButton extends StatelessWidget {
  const _LeaveWorkspaceButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AFOutlinedTextButton.destructive(
        alignment: Alignment.center,
        text: LocaleKeys.workspace_leaveCurrentWorkspace.tr(),
        onTap: () => _leaveWorkspace(context),
        size: AFButtonSize.l,
      ),
    );
  }

  void _leaveWorkspace(BuildContext context) {
    showFlowyCupertinoConfirmDialog(
      title: LocaleKeys.workspace_leaveCurrentWorkspacePrompt.tr(),
      leftButton: FlowyText(
        LocaleKeys.button_cancel.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF007AFF),
      ),
      rightButton: FlowyText(
        LocaleKeys.button_confirm.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w400,
        color: const Color(0xFFFE0220),
      ),
      onRightButtonPressed: (buttonContext) async {
        // try to use popUntil with a specific route name but failed
        // so use pop twice as a workaround
        Navigator.of(buttonContext).pop();
        Navigator.of(context).pop();
        Navigator.of(context).pop();

        mobileLeaveWorkspaceNotifier.value =
            mobileLeaveWorkspaceNotifier.value + 1;
      },
    );
  }
}
