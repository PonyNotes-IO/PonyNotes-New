import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
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
            Expanded(child: const SizedBox.shrink()),
          ],
        ),
      ],
    );
  }

  void _inviteMember() {
    // kept for backward compatibility; use dialog flow instead.
  }

  Future<void> _openInviteDialog(BuildContext context) async {
    AFRolePB dialogSelectedRole = _selectedRole;

    await showDialog(
      context: context,
      builder: (ctx) {
        // use StatefulBuilder so the dialog has its own immediate state
        return StatefulBuilder(builder: (dialogCtx, setStateDialog) {
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
                    // 输入框：仅支持通过邮箱或手机号搜索
                    TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: '搜索邮箱或手机号',
                      ),
                      autofocus: true,
                      onChanged: (v) {},
                    ),
                    const SizedBox(height: 12),
                    Text('权限级别', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    // Role selector (use PopupMenuButton inside dialog-local state)
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
                            final value = _inputController.text.trim();
                              // persist selection to outer state for next time
                              setState(() {
                                _selectedRole = dialogSelectedRole;
                              });
                              _inviteMemberFromDialog(value, ctx, dialogSelectedRole);
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

  void _inviteMemberFromDialog(String contact, BuildContext dialogContext, [AFRolePB? role]) {
    final value = contact.trim();

    final isEmailAddr = isEmail(value);
    final isPhone = _isPhoneNumber(value);

    if (!isEmailAddr && !isPhone) {
      showToastNotification(
        type: ToastificationType.error,
        message: '请输入有效的邮箱或手机号',
      );
      return;
    }

    // The backend expects the identifier (email or phone). Use the raw input.
    context
        .read<WorkspaceMemberBloc>()
        .add(WorkspaceMemberEvent.inviteWorkspaceMemberByEmail(value, role ?? AFRolePB.Member));
    // close the dialog after dispatch
    try {
      Navigator.of(dialogContext).pop();
    } catch (_) {}
  }
}
