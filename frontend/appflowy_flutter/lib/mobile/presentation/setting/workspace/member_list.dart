import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/shared/af_role_pb_extension.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class MobileMemberList extends StatelessWidget {
  const MobileMemberList({
    super.key,
    required this.members,
    required this.myRole,
    required this.userProfile,
    required this.workspaceName,
  });

  final List<WorkspaceMemberPB> members;
  final AFRolePB myRole;
  final UserProfilePB userProfile;
  final String? workspaceName;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.m,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: SlidableAutoCloseBehavior(
          child: SeparatedColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            separatorBuilder: () => Divider(
              color: theme.borderColorScheme.primary,
              height: 1,
            ),
            children: [
              // 表头
              _MemberListHeader(),
              ...members.map(
                (member) => _MemberItem(
                  member: member,
                  myRole: myRole,
                  userProfile: userProfile,
                  workspaceName: workspaceName,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberListHeader extends StatelessWidget {
  const _MemberListHeader();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.m,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
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
              '团队协作区',
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              LocaleKeys.settings_appearance_members_role.tr(),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.secondary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberItem extends StatelessWidget {
  const _MemberItem({
    required this.member,
    required this.myRole,
    required this.userProfile,
    required this.workspaceName,
  });

  final WorkspaceMemberPB member;
  final AFRolePB myRole;
  final UserProfilePB userProfile;
  final String? workspaceName;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isSelf = member.uid.toInt() != 0 && member.uid.toInt() == userProfile.id.toInt();
    final canDelete = myRole.canDelete && member.name != userProfile.name;
    final canUpdateRole = myRole.canUpdate && !isSelf;

    Widget child = Container(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.m,
      ),
      child: Row(
        children: [
          // 用户头像
          UserAvatar(
            iconUrl: member.avatarUrl,
            name: member.name,
            size: AFAvatarSize.s,
          ),
          HSpace(8),
          // 用户名和邮箱
          Expanded(
            flex: 3,
            child: Text(
              member.name,
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 团队协作区
          Expanded(
            flex: 2,
            child: Text(
              workspaceName ?? '—',
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          // 角色
          Expanded(
            flex: 2,
            child: canUpdateRole
                ? _MemberRoleActionList(member: member)
                : Text(
                    _getRoleDisplayName(member.role),
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.primary,
                    ),
                    textAlign: TextAlign.end,
                  ),
          ),
        ],
      ),
    );

    if (canDelete) {
      child = Slidable(
        key: ValueKey(member.name),
        endActionPane: ActionPane(
          extentRatio: 1 / 6.0,
          motion: const ScrollMotion(),
          children: [
            CustomSlidableAction(
              backgroundColor: const Color(0xE5515563),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
              onPressed: (context) {
                HapticFeedback.mediumImpact();
                _showDeleteMenu(context);
              },
              padding: EdgeInsets.zero,
              child: const FlowySvg(
                FlowySvgs.three_dots_s,
                size: Size.square(24),
                color: Colors.white,
              ),
            ),
          ],
        ),
        child: child,
      );
    }

    return child;
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

  void _showDeleteMenu(BuildContext context) {
    final workspaceMemberBloc = context.read<WorkspaceMemberBloc>();
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return FlowyOptionTile.text(
          text: LocaleKeys.settings_appearance_members_removeFromWorkspace.tr(),
          height: 52.0,
          textColor: Theme.of(context).colorScheme.error,
          leftIcon: FlowySvg(
            FlowySvgs.trash_s,
            size: const Size.square(18),
            color: Theme.of(context).colorScheme.error,
          ),
          showTopBorder: false,
          showBottomBorder: false,
          onTap: () {
            final memberIdentifier = member.uid.toInt() != 0
                ? member.uid.toString()
                : (member.email.isNotEmpty ? member.email : member.name);
            workspaceMemberBloc.add(
              WorkspaceMemberEvent.removeWorkspaceMemberByEmail(memberIdentifier),
            );
            Navigator.of(context).pop();
          },
        );
      },
    );
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

    return GestureDetector(
      onTap: () => _showRoleSelector(context, theme),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _getRoleDisplayName(member.role),
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          HSpace(4),
          FlowySvg(
            FlowySvgs.arrow_down_s,
            size: const Size.square(16),
            color: theme.textColorScheme.secondary,
          ),
        ],
      ),
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

  void _showRoleSelector(BuildContext context, AppFlowyThemeData theme) {
    final workspaceMemberBloc = context.read<WorkspaceMemberBloc>();
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(theme.spacing.l),
                child: Text(
                  '选择角色',
                  style: theme.textStyle.heading4.enhanced(
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              ...AFRolePB.values.map((role) {
                final isSelected = role == member.role;
                return FlowyOptionTile.text(
                  text: _getRoleDisplayName(role) + (isSelected ? ' ✓' : ''),
                  height: 52.0,
                  textColor: isSelected
                      ? theme.textColorScheme.primary
                      : theme.textColorScheme.primary,
                  showTopBorder: false,
                  showBottomBorder: false,
                  onTap: () {
                    if (!isSelected) {
                      final memberIdentifier = member.uid.toInt() != 0
                          ? member.uid.toString()
                          : (member.email.isNotEmpty ? member.email : member.name);
                      workspaceMemberBloc.add(
                        WorkspaceMemberEvent.updateWorkspaceMember(
                          memberIdentifier,
                          role,
                        ),
                      );
                    }
                    Navigator.of(ctx).pop();
                  },
                );
              }),
              SizedBox(height: theme.spacing.m),
            ],
          ),
        );
      },
    );
  }
}
