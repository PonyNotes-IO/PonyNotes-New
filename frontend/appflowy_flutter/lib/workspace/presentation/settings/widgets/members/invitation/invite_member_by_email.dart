import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:string_validator/string_validator.dart';

class InviteMemberByEmail extends StatefulWidget {
  const InviteMemberByEmail({super.key});

  @override
  State<InviteMemberByEmail> createState() => _InviteMemberByEmailState();
}

class _InviteMemberByEmailState extends State<InviteMemberByEmail> {
  final _inputController = TextEditingController();
  AFRolePB _selectedRole = AFRolePB.Member;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Removed the prompt text as requested.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AFFilledTextButton.primary(
              text: '添加成员',
              onTap: () => _openInviteDialog(context),
            ),
            HSpace(theme.spacing.l),
            const SizedBox.shrink(),
          ],
        ),
      ],
    );
  }

  Future<void> _openInviteDialog(BuildContext context) async {
    AFRolePB dialogSelectedRole = _selectedRole;
    final memberBloc = context.read<WorkspaceMemberBloc>();
    final currentUser = memberBloc.userProfile;
    final existingMembers = memberBloc.state.members;

    await showDialog(
      context: context,
      builder: (ctx) {
        // use StatefulBuilder so the dialog has its own immediate state
        final repo = RustShareWithUserRepositoryImpl();
        List<SharedUser> searchResults = [];
        List<SharedUser> selectedUsers = [];
        bool isSearching = false;
        bool hasSearched = false;

        return StatefulBuilder(builder: (dialogCtx, setStateDialog) {
          String normalizeIdentifier(String value) {
            return value
                .replaceAll(
                    RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F\u00A0]'), '')
                .trim()
                .toLowerCase();
          }

          bool isCurrentLoginUser(SharedUser user) {
            final userName = normalizeIdentifier(user.name);
            final userEmail = normalizeIdentifier(user.email);
            final currentName = normalizeIdentifier(currentUser.name);
            final currentEmail = normalizeIdentifier(currentUser.email);
            return (userName.isNotEmpty && userName == currentName) ||
                (userEmail.isNotEmpty && userEmail == currentEmail);
          }

          bool isAlreadyWorkspaceMember(SharedUser user) {
            final userName = normalizeIdentifier(user.name);
            final userEmail = normalizeIdentifier(user.email);
            return existingMembers.any((member) {
              final memberName = normalizeIdentifier(member.name);
              final memberEmail = normalizeIdentifier(member.email);
              return (userName.isNotEmpty && userName == memberName) ||
                  (userEmail.isNotEmpty && userEmail == memberEmail);
            });
          }

          bool isAlreadySelected(SharedUser user) {
            final userName = normalizeIdentifier(user.name);
            final userEmail = normalizeIdentifier(user.email);
            return selectedUsers.any((selected) {
              final selectedName = normalizeIdentifier(selected.name);
              final selectedEmail = normalizeIdentifier(selected.email);
              return (userName.isNotEmpty && userName == selectedName) ||
                  (userEmail.isNotEmpty && userEmail == selectedEmail);
            });
          }

          Future<void> performSearch(String q) async {
            // Normalize common invisible characters copied from DB, then trim
            final normalized = q
                .replaceAll(
                    RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F\u00A0]'), '')
                .trim();
            hasSearched = true;
            if (normalized.isEmpty) {
              setStateDialog(() {
                searchResults = [];
              });
              return;
            }

            setStateDialog(() {
              isSearching = true;
            });

            // Attempt initial search with normalized value
            FlowyResult<SharedUsers, FlowyError> res =
                await repo.searchUsers(query: normalized);
            List<SharedUser> users = [];
            res.fold((u) => users = u, (e) => users = []);

            // If no result and the query looks like a phone number, try variants
            if (users.isEmpty) {
              final digitsOnly = normalized.replaceAll(RegExp(r'\D'), '');
              final looksLikePhone = digitsOnly.isNotEmpty &&
                  digitsOnly.length >= 6 &&
                  digitsOnly.length <= 15;

              if (looksLikePhone) {
                final variants = <String>{};
                variants.add(digitsOnly);
                // strip leading zeros
                variants.add(digitsOnly.replaceFirst(RegExp(r'^0+'), ''));
                // try with +86 and without
                if (!digitsOnly.startsWith('86') && digitsOnly.length == 11) {
                  variants.add('86$digitsOnly');
                  variants.add('+86$digitsOnly');
                }
                // try with plus
                if (!digitsOnly.startsWith('+')) {
                  variants.add('+$digitsOnly');
                }

                for (final v in variants) {
                  if (v.trim().isEmpty) continue;
                  Log.info('InviteSearch: retrying search with variant: $v');
                  final r2 = await repo.searchUsers(query: v);
                  r2.fold((u2) {
                    if (u2.isNotEmpty) {
                      users = u2;
                    }
                  }, (_) {});
                  if (users.isNotEmpty) break;
                }
              }
            }

            setStateDialog(() {
              searchResults = users.where((user) {
                if (isCurrentLoginUser(user)) {
                  return false;
                }
                if (isAlreadyWorkspaceMember(user)) {
                  return false;
                }
                if (isAlreadySelected(user)) {
                  return false;
                }
                return true;
              }).toList();
              isSearching = false;
            });

            if (users.isEmpty) {
              // no results; do not spam toast, just leave empty state visible
              Log.info('InviteSearch: no users found for query "$normalized"');
            }
          }

          void toggleSelectUser(SharedUser user) {
            // 使用 email 作为唯一标识符，如果 email 为空则使用 name
            final identifier = user.name;
            final exists =
                selectedUsers.indexWhere((u) => (u.name) == identifier) >= 0;
            setStateDialog(() {
              if (exists) {
                selectedUsers.removeWhere((u) => (u.name) == identifier);
              } else {
                selectedUsers.add(user);
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: SizedBox(
              width: 520,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '添加成员',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    // 输入框：支持邮箱或手机号搜索 + 搜索按钮
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            decoration: const InputDecoration(
                              hintText: '搜索邮箱或手机号',
                            ),
                            autofocus: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '搜索',
                          icon: isSearching
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : const Icon(Icons.search),
                          onPressed: () async {
                            final q = _inputController.text.trim();
                            await performSearch(q);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Selected users chips
                    if (selectedUsers.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: selectedUsers.map((u) {
                          return Chip(
                            label: Text(u.name.isNotEmpty ? u.name : u.email),
                            onDeleted: () {
                              setStateDialog(() {
                                selectedUsers
                                    .removeWhere((s) => s.name == u.name);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Search results list
                    if (searchResults.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final user = searchResults[idx];
                            final already =
                                selectedUsers.any((u) => u.name == user.name);
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(user.name.isNotEmpty
                                    ? user.name[0].toUpperCase()
                                    : '?'),
                              ),
                              title: Text(user.name.isNotEmpty
                                  ? user.name
                                  : user.email),
                              subtitle: Text(user.name),
                              trailing: Icon(already
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank),
                              onTap: () {
                                toggleSelectUser(user);
                              },
                            );
                          },
                        ),
                      )
                    else if (isSearching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (hasSearched && searchResults.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Center(
                          child: Text(
                            '未找到用户',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    const SizedBox(height: 12),
                    Text('权限级别', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    // Role selector
                    _InviteRoleActionList(
                        selectedRole: dialogSelectedRole,
                        onRoleChanged: (role) {
                          setStateDialog(() {
                            dialogSelectedRole = role;
                          });
                        },
                      ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text('取消'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            // persist selection to outer state for next time
                            setState(() {
                              _selectedRole = dialogSelectedRole;
                            });

                            // If user manually typed an identifier and didn't select from results,
                            // include that input as a single invite target.
                            final typed = _inputController.text.trim();
                            if (typed.isNotEmpty &&
                                selectedUsers.every((u) =>
                                    u.name != typed &&
                                    u.email != typed &&
                                    u.phone != typed) &&
                                _isValidEmailOrPhone(typed)) {
                              selectedUsers.add(SharedUser(
                                  email: typed,
                                  name: typed,
                                  role: ShareRole.guest,
                                  accessLevel: ShareAccessLevel.readOnly));
                            }

                            // Dispatch invite events for all selected users
                            for (final u in selectedUsers) {
                              // 优先使用邮箱，其次手机号，最后用户名作为邀请标识符
                              final identifier = u.email.isNotEmpty
                                  ? u.email
                                  : (u.phone?.isNotEmpty == true
                                      ? u.phone!
                                      : u.name);
                              if (!_isValidEmailOrPhone(identifier)) {
                                showToastNotification(
                                  type: ToastificationType.error,
                                  message: '用户 ${u.name} 的邮箱或手机号格式无效，无法邀请',
                                );
                                continue;
                              }
                              context.read<WorkspaceMemberBloc>().add(
                                    WorkspaceMemberEvent
                                        .inviteWorkspaceMemberByEmail(
                                      identifier,
                                      dialogSelectedRole,
                                    ),
                                  );
                            }

                            // close dialog
                            try {
                              Navigator.of(ctx).pop();
                            } catch (_) {}
                          },
                          child: Text('邀请'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  /// 验证邮箱或手机号格式
  /// 支持：
  /// - 邮箱：包含@符号的标准邮箱格式
  /// - 手机号：纯数字或以+开头的数字（至少6位，最多15位）
  bool _isValidEmailOrPhone(String input) {
    if (input.isEmpty) return false;

    // 检查是否是邮箱（包含@符号）
    if (input.contains('@')) {
      return isEmail(input);
    }

    // 检查是否是手机号（纯数字或以+开头）
    String cleaned = input.trim();
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.isNotEmpty && RegExp(r'^\d+$').hasMatch(cleaned)) {
      final len = cleaned.length;
      // 手机号长度一般在6-15位之间（与后端验证逻辑一致）
      return len >= 6 && len <= 15;
    }

    return false;
  }
}

class _InviteRoleActionList extends StatelessWidget {
  const _InviteRoleActionList({
    required this.selectedRole,
    required this.onRoleChanged,
  });

  final AFRolePB selectedRole;
  final void Function(AFRolePB) onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // 定义角色选项
    final roleOptions = [
      _InviteRoleActionWrapper(AFRolePB.Owner),
      _InviteRoleActionWrapper(AFRolePB.Member),
      _InviteRoleActionWrapper(AFRolePB.Guest),
    ];

    return PopoverActionList<_InviteRoleActionWrapper>(
      asBarrier: true,
      direction: PopoverDirection.bottomWithLeftAligned,
      actions: roleOptions,
      buildChild: (controller) {
        return GestureDetector(
          onTap: () {
            controller.show();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8,horizontal: 12),
            decoration: BoxDecoration(
                color: AppFlowyTheme.of(context).borderColorScheme.primary,
                borderRadius: BorderRadius.circular(6),
                border:Border.all(color: AppFlowyTheme.of(context).surfaceContainerColorScheme.layer01,width: 1)
            ),
            child: Row(
              children: [
                FlowyText.regular(
                  _getRoleDisplayName(selectedRole),
                  color: theme.textColorScheme.primary,
                  fontSize: 14,
                ),
                Spacer(),
                FlowySvg(
                  FlowySvgs.arrow_right_m,
                )
              ],
            ),
          ),
        );
      },
      onSelected: (action, controller) {
        if (action.role == selectedRole) {
          controller.close();
          return;
        }

        onRoleChanged(action.role);
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

class _InviteRoleActionWrapper extends ActionCell {
  _InviteRoleActionWrapper(this.role);

  final AFRolePB role;

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
