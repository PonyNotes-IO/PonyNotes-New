import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:string_validator/string_validator.dart';

class MInviteMemberByEmail extends StatefulWidget {
  const MInviteMemberByEmail({super.key});

  @override
  State<MInviteMemberByEmail> createState() => _MInviteMemberByEmailState();
}

class _MInviteMemberByEmailState extends State<MInviteMemberByEmail> {
  final _inputController = TextEditingController();
  AFRolePB _selectedRole = AFRolePB.Member;

  final RustShareWithUserRepositoryImpl _repo = RustShareWithUserRepositoryImpl();

  List<SharedUser> _searchResults = [];
  final List<SharedUser> _selectedUsers = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final memberBloc = context.read<WorkspaceMemberBloc>();
    final currentUser = memberBloc.userProfile;
    final existingMembers = memberBloc.state.members;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 搜索框 + 搜索按钮
        Row(
          children: [
            Expanded(
              child: AFTextField(
                controller: _inputController,
                hintText: '搜索邮箱或手机号',
                onSubmitted: (_) => _performSearch(currentUser, existingMembers),
              ),
            ),
            HSpace(theme.spacing.s),
            AFOutlinedTextButton.normal(
              text: '搜索',
              textStyle: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
              onTap: () {
                if (_isSearching) return;
                _performSearch(currentUser, existingMembers);
              },
            ),
          ],
        ),
        VSpace(theme.spacing.m),

        // 已选用户 chips
        if (_selectedUsers.isNotEmpty) ...[
          _SelectedUsersChips(
            selectedUsers: _selectedUsers,
            onRemove: (user) {
              setState(() {
                _selectedUsers.removeWhere((s) => _identifierOf(s) == _identifierOf(user));
              });
            },
          ),
          VSpace(theme.spacing.s),
        ],

        // 搜索结果
        _SearchResultsView(
          isSearching: _isSearching,
          hasSearched: _hasSearched,
          searchResults: _searchResults,
          selectedUsers: _selectedUsers,
          onToggle: _toggleSelectUser,
        ),
        VSpace(theme.spacing.m),

        // 权限选择
        Text(
          '权限级别',
          style: theme.textStyle.body.standard(
            color: theme.textColorScheme.primary,
          ),
        ),
        VSpace(theme.spacing.s),
        _MobileRoleSegmented(
          selectedRole: _selectedRole,
          onChanged: (role) => setState(() => _selectedRole = role),
        ),
        VSpace(theme.spacing.l),

        // 操作按钮
        Row(
          children: [
            Expanded(
              child: AFOutlinedTextButton.normal(
                text: '取消',
                size: AFButtonSize.l,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            HSpace(theme.spacing.s),
            Expanded(
              child: AFFilledTextButton.primary(
                text: '邀请',
                size: AFButtonSize.l,
                onTap: () => _onInvitePressed(memberBloc),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 搜索逻辑（与桌面端保持一致：手机号多格式重试）
  // ---------------------------------------------------------------------------

  Future<void> _performSearch(currentUser, existingMembers) async {
    final q = _inputController.text.trim();
    if (q.isEmpty) {
      showToastNotification(
        type: ToastificationType.error,
        message: '请输入邮箱或手机号',
      );
      return;
    }
    if (!_isValidEmailOrPhone(q)) {
      showToastNotification(
        type: ToastificationType.error,
        message: '请输入有效的邮箱地址或手机号',
      );
      return;
    }

    final normalized = q.replaceAll(
      RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F\u00A0]'),
      '',
    );

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    FlowyResult<SharedUsers, FlowyError> res = await _repo.searchUsers(
      query: normalized,
    );
    List<SharedUser> users = [];
    String? searchError;
    res.fold(
      (u) => users = u,
      (e) {
        searchError = e.msg;
        users = [];
      },
    );

    if (users.isEmpty) {
      final digitsOnly = normalized.replaceAll(RegExp(r'\D'), '');
      final looksLikePhone = digitsOnly.isNotEmpty &&
          digitsOnly.length >= 6 &&
          digitsOnly.length <= 15;
      if (looksLikePhone) {
        final variants = <String>{};
        variants.add(digitsOnly);
        variants.add(digitsOnly.replaceFirst(RegExp(r'^0+'), ''));
        if (!digitsOnly.startsWith('86') && digitsOnly.length == 11) {
          variants.add('86$digitsOnly');
          variants.add('+86$digitsOnly');
        }
        if (!digitsOnly.startsWith('+')) {
          variants.add('+$digitsOnly');
        }
        for (final v in variants) {
          if (v.trim().isEmpty) continue;
          Log.info('InviteSearch: retrying with variant: $v');
          final r2 = await _repo.searchUsers(query: v);
          r2.fold((u2) {
            if (u2.isNotEmpty) users = u2;
          }, (_) {});
          if (users.isNotEmpty) break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _searchResults = users.where((user) {
        if (_isCurrentLoginUser(user, currentUser)) return false;
        if (_isAlreadyWorkspaceMember(user, existingMembers)) return false;
        if (_isAlreadySelected(user)) return false;
        return true;
      }).toList();
      _isSearching = false;
    });

    if (users.isEmpty && searchError != null) {
      Log.error('InviteSearch: $searchError');
      if (!mounted) return;
      showToastNotification(
        type: ToastificationType.error,
        message: '搜索失败，请检查网络后重试',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 多选切换
  // ---------------------------------------------------------------------------

  void _toggleSelectUser(SharedUser user) {
    final identifier = _identifierOf(user);
    setState(() {
      final idx = _selectedUsers
          .indexWhere((s) => _identifierOf(s) == identifier);
      if (idx >= 0) {
        _selectedUsers.removeAt(idx);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 提交邀请
  // ---------------------------------------------------------------------------

  void _onInvitePressed(WorkspaceMemberBloc bloc) {
    if (_selectedUsers.isEmpty) {
      showToastNotification(
        type: ToastificationType.error,
        message: '请先搜索并选择要邀请的用户',
      );
      return;
    }

    for (final user in _selectedUsers) {
      final identifier = user.email.isNotEmpty
          ? user.email
          : (user.phone?.isNotEmpty == true ? user.phone! : user.name);
      if (!_isValidEmailOrPhone(identifier)) {
        showToastNotification(
          type: ToastificationType.error,
          message: '用户 ${user.name} 的邮箱或手机号格式无效，无法邀请',
        );
        continue;
      }
      bloc.add(
        WorkspaceMemberEvent.inviteWorkspaceMemberByEmail(
          identifier,
          _selectedRole,
        ),
      );
    }

    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // 工具方法
  // ---------------------------------------------------------------------------

  static String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F\u00A0]'), '')
        .trim()
        .toLowerCase();
  }

  static String _identifierOf(SharedUser user) {
    return user.name.isNotEmpty
        ? '${user.email}|${user.name}'
        : user.email;
  }

  bool _isCurrentLoginUser(SharedUser user, currentUser) {
    if (currentUser == null) return false;
    final userEmail = _normalize(user.email);
    final userName = _normalize(user.name);
    final currentEmail = _normalize(currentUser.email);
    final currentName = _normalize(currentUser.name);
    return (userEmail.isNotEmpty && userEmail == currentEmail) ||
        (userName.isNotEmpty && userName == currentName);
  }

  bool _isAlreadyWorkspaceMember(SharedUser user, existingMembers) {
    final userEmail = _normalize(user.email);
    final userName = _normalize(user.name);
    for (final member in existingMembers) {
      final memberEmail = _normalize(member.email);
      final memberName = _normalize(member.name);
      if ((userEmail.isNotEmpty && userEmail == memberEmail) ||
          (userName.isNotEmpty && userName == memberName)) {
        return true;
      }
    }
    return false;
  }

  bool _isAlreadySelected(SharedUser user) {
    final identifier = _identifierOf(user);
    return _selectedUsers.any((s) => _identifierOf(s) == identifier);
  }

  bool _isValidEmailOrPhone(String input) {
    if (input.isEmpty) return false;
    if (input.contains('@')) return isEmail(input);
    String cleaned = input.trim();
    if (cleaned.startsWith('+')) cleaned = cleaned.substring(1);
    if (cleaned.isNotEmpty && RegExp(r'^\d+$').hasMatch(cleaned)) {
      final len = cleaned.length;
      return len >= 6 && len <= 15;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// 已选用户 chips
// ---------------------------------------------------------------------------

class _SelectedUsersChips extends StatelessWidget {
  const _SelectedUsersChips({
    required this.selectedUsers,
    required this.onRemove,
  });

  final List<SharedUser> selectedUsers;
  final void Function(SharedUser user) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Wrap(
      spacing: theme.spacing.s,
      runSpacing: theme.spacing.s,
      children: selectedUsers.map((u) {
        final label = u.name.isNotEmpty ? u.name : u.email;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.s,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceContainerColorScheme.layer01,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.borderColorScheme.primary,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
              HSpace(4),
              GestureDetector(
                onTap: () => onRemove(u),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: theme.iconColorScheme.tertiary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// 搜索结果列表
// ---------------------------------------------------------------------------

class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.isSearching,
    required this.hasSearched,
    required this.searchResults,
    required this.selectedUsers,
    required this.onToggle,
  });

  final bool isSearching;
  final bool hasSearched;
  final List<SharedUser> searchResults;
  final List<SharedUser> selectedUsers;
  final void Function(SharedUser user) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (isSearching) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (searchResults.isEmpty && hasSearched) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
        child: Center(
          child: Text(
            '未找到用户',
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
      );
    }
    if (searchResults.isEmpty) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: searchResults.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: theme.borderColorScheme.primary),
        itemBuilder: (context, idx) {
          final user = searchResults[idx];
          final already = selectedUsers.any(
            (u) =>
                (u.email.isNotEmpty && u.email == user.email) ||
                (u.name.isNotEmpty && u.name == user.name),
          );
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: theme.surfaceContainerColorScheme.layer01,
              child: Text(
                user.name.isNotEmpty
                    ? user.name[0].toUpperCase()
                    : (user.email.isNotEmpty ? user.email[0].toUpperCase() : '?'),
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.primary,
                ),
              ),
            ),
            title: Text(
              user.name.isNotEmpty ? user.name : user.email,
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
            subtitle: user.email.isNotEmpty && user.name.isNotEmpty
                ? Text(
                    user.email,
                    style: theme.textStyle.caption.standard(
                      color: theme.textColorScheme.secondary,
                    ),
                  )
                : null,
            trailing: Icon(
              already ? Icons.check_box : Icons.check_box_outline_blank,
              color: already
                  ? theme.textColorScheme.primary
                  : theme.iconColorScheme.tertiary,
            ),
            onTap: () => onToggle(user),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 角色 Segmented 选择器（移动端专用，比 PopoverActionList 更适合底部 sheet）
// ---------------------------------------------------------------------------

class _MobileRoleSegmented extends StatelessWidget {
  const _MobileRoleSegmented({
    required this.selectedRole,
    required this.onChanged,
  });

  final AFRolePB selectedRole;
  final ValueChanged<AFRolePB> onChanged;

  static const _options = [
    (AFRolePB.Owner, '所有者'),
    (AFRolePB.Member, '成员'),
    (AFRolePB.Guest, '受限成员'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Wrap(
      spacing: theme.spacing.s,
      runSpacing: theme.spacing.s,
      children: _options.map((opt) {
        final (role, label) = opt;
        final selected = role == selectedRole;
        return _RoleChip(
          label: label,
          selected: selected,
          onTap: () => onChanged(role),
        );
      }).toList(),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          // 选中态使用语义色 action 蓝（深浅模式下对比度都足够），
          // 避免使用 textColorScheme.primary 在深色模式下接近白色导致看不清。
          color: selected
              ? theme.textColorScheme.action
              : theme.surfaceContainerColorScheme.layer01,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.textColorScheme.action
                : theme.borderColorScheme.primary,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textStyle.body.standard(
            color: selected
                ? theme.textColorScheme.onFill
                : theme.textColorScheme.primary,
          ),
        ),
      ),
    );
  }
}
