import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
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
          Future<void> performSearch(String q) async {
            // Normalize common invisible characters copied from DB, then trim
            final normalized = q.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F\u00A0]'), '').trim();
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
            FlowyResult<SharedUsers, FlowyError> res = await repo.searchUsers(query: normalized);
            List<SharedUser> users = [];
            res.fold((u) => users = u, (e) => users = []);

            // If no result and the query looks like a phone number, try variants
            if (users.isEmpty) {
              final digitsOnly = normalized.replaceAll(RegExp(r'\D'), '');
              final looksLikePhone = digitsOnly.isNotEmpty && digitsOnly.length >= 6 && digitsOnly.length <= 15;

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
              searchResults = users;
              isSearching = false;
            });

            if (users.isEmpty) {
              // no results; do not spam toast, just leave empty state visible
              Log.info('InviteSearch: no users found for query "$normalized"');
            }
          }

          void toggleSelectUser(SharedUser user) {
            final exists = selectedUsers.indexWhere((u) => u.email == user.email) >= 0;
            setStateDialog(() {
              if (exists) {
                selectedUsers.removeWhere((u) => u.email == user.email);
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
                          icon: isSearching ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.search),
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
                                selectedUsers.removeWhere((s) => s.email == u.email);
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
                            final already = selectedUsers.any((u) => u.email == user.email);
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
                              ),
                              title: Text(user.name.isNotEmpty ? user.name : user.email),
                              subtitle: Text(user.email),
                              trailing: Icon(already ? Icons.check_box : Icons.check_box_outline_blank),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: PopupMenuButton<AFRolePB>(
                        padding: EdgeInsets.zero,
                        color: Theme.of(context).cardColor,
                        onSelected: (v) {
                          setStateDialog(() {
                            dialogSelectedRole = v;
                          });
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: AFRolePB.Owner, child: Text('工作空间所有者')),
                          const PopupMenuItem(value: AFRolePB.Member, child: Text('成员')),
                          const PopupMenuItem(value: AFRolePB.Guest, child: Text('受限成员')),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dialogSelectedRole == AFRolePB.Owner
                                  ? '工作空间所有者'
                                  : dialogSelectedRole == AFRolePB.Guest
                                      ? '受限成员'
                                      : '成员',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
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
                            if (typed.isNotEmpty && selectedUsers.every((u) => u.email != typed)) {
                              selectedUsers.add(SharedUser(email: typed, name: typed, role: ShareRole.guest, accessLevel: ShareAccessLevel.readOnly));
                            }

                            // Dispatch invite events for all selected users
                            for (final u in selectedUsers) {
                              final identifier = u.email;
                              // Validate email format before inviting
                              if (!isEmail(identifier)) {
                                showToastNotification(
                                  type: ToastificationType.error,
                                  message: '用户 ${u.name} 的邮箱格式无效，无法邀请',
                                );
                                continue;
                              }
                              context.read<WorkspaceMemberBloc>().add(
                                    WorkspaceMemberEvent.inviteWorkspaceMemberByEmail(
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

  bool _isPhoneNumber(String input) {
    // Normalize: remove non-digit characters
    final digits = input.replaceAll(RegExp(r'\\D'), '');
    // Basic length check for phone numbers (allow 6-15 digits)
    return digits.length >= 6 && digits.length <= 15;
  }

}
