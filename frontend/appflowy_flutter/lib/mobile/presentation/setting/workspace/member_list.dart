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
import 'package:flutter_bloc/flutter_bloc.dart';

const double _memberActionColumnWidth = 36.0;

class MobileMemberList extends StatelessWidget {
  const MobileMemberList({
    super.key,
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
        child: SeparatedColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
          separatorBuilder: () => Divider(
            color: theme.borderColorScheme.primary,
            height: 1,
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
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: _memberActionColumnWidth),
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
  });

  final WorkspaceMemberPB member;
  final AFRolePB myRole;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isSelf = member.uid.toInt() != 0 &&
        member.uid.toInt() == userProfile.id.toInt();
    final canDelete = myRole.canDelete && member.name != userProfile.name;
    final canUpdateRole = myRole.canUpdate && !isSelf;

    return Container(
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
          // 用户名
          Expanded(
            flex: 4,
            child: Text(
              member.name,
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 角色
          Expanded(
            flex: 2,
            child: canUpdateRole
                ? _MemberRoleActionList(member: member)
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _getRoleDisplayName(member.role),
                      style: theme.textStyle.body.standard(
                        color: theme.textColorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          // 常驻操作列（与电脑端保持一致）
          SizedBox(
            width: _memberActionColumnWidth,
            child: canDelete
                ? Align(
                    alignment: Alignment.center,
                    child: _MemberRemoveIconButton(
                      onTap: () => _confirmAndRemove(context),
                    ),
                  )
                : const SizedBox.shrink(),
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

  void _confirmAndRemove(BuildContext context) {
    final workspaceMemberBloc = context.read<WorkspaceMemberBloc>();
    final memberIdentifier = member.uid.toInt() != 0
        ? member.uid.toString()
        : (member.email.isNotEmpty ? member.email : member.name);

    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppFlowyTheme.of(sheetCtx).spacing.l,
                  vertical: AppFlowyTheme.of(sheetCtx).spacing.l,
                ),
                child: Text(
                  '确定要将「${member.name}」移出空间吗？',
                  style: AppFlowyTheme.of(sheetCtx)
                      .textStyle
                      .heading4
                      .standard(
                        color: AppFlowyTheme.of(sheetCtx)
                            .textColorScheme
                            .primary,
                      ),
                ),
              ),
              FlowyOptionTile.text(
                text: '移出空间',
                textColor: Theme.of(sheetCtx).colorScheme.error,
                leftIcon: FlowySvg(
                  FlowySvgs.trash_s,
                  size: const Size.square(18),
                  color: Theme.of(sheetCtx).colorScheme.error,
                ),
                showTopBorder: true,
                showBottomBorder: false,
                onTap: () {
                  workspaceMemberBloc.add(
                    WorkspaceMemberEvent.removeWorkspaceMemberByEmail(
                      memberIdentifier,
                    ),
                  );
                  Navigator.of(sheetCtx).pop();
                },
              ),
              FlowyOptionTile.text(
                text: '取消',
                showTopBorder: false,
                showBottomBorder: false,
                onTap: () => Navigator.of(sheetCtx).pop(),
              ),
              SizedBox(height: AppFlowyTheme.of(sheetCtx).spacing.m),
            ],
          ),
        );
      },
    );
  }
}

class _MemberRemoveIconButton extends StatelessWidget {
  const _MemberRemoveIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Center(
            child: FlowySvg(
              FlowySvgs.trash_s,
              size: const Size.square(18),
              color: theme.iconColorScheme.secondary,
            ),
          ),
        ),
      ),
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
          Flexible(
            child: Text(
              _getRoleDisplayName(member.role),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                  textColor: theme.textColorScheme.primary,
                  showTopBorder: false,
                  showBottomBorder: false,
                  onTap: () {
                    if (!isSelected) {
                      final memberIdentifier = member.uid.toInt() != 0
                          ? member.uid.toString()
                          : (member.email.isNotEmpty
                              ? member.email
                              : member.name);
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