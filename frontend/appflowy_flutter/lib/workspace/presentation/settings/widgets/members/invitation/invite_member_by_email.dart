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
    await showDialog(
      context: context,
      builder: (ctx) {
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
                  // 输入框：搜索名称或邮箱/手机号
                  TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      hintText: '搜索名称或者邮箱/手机号',
                    ),
                    autofocus: true,
                    onChanged: (v) {},
                  ),
                  const SizedBox(height: 12),
                  Text('权限级别', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  // Role selector
                  DropdownButton<AFRolePB>(
                    value: _selectedRole,
                    items: const [
                      DropdownMenuItem(value: AFRolePB.Owner, child: Text('工作空间所有者')),
                      DropdownMenuItem(value: AFRolePB.Member, child: Text('成员')),
                      DropdownMenuItem(value: AFRolePB.Guest, child: Text('受限成员')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedRole = v;
                        });
                      }
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
                          final value = _inputController.text.trim();
                          _inviteMemberFromDialog(value, ctx, _selectedRole);
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
      },
    );
  }

  void _inviteMemberFromDialog(String email, BuildContext dialogContext, [AFRolePB? role]) {
    if (!isEmail(email)) {
      showToastNotification(
        type: ToastificationType.error,
        message: LocaleKeys.settings_appearance_members_emailInvalidError.tr(),
      );
      return;
    }

    context
        .read<WorkspaceMemberBloc>()
        .add(WorkspaceMemberEvent.inviteWorkspaceMemberByEmail(email));
    // close the dialog after dispatch
    try {
      Navigator.of(dialogContext).pop();
    } catch (_) {}
  }
}
