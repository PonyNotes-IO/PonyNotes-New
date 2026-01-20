import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:string_validator/string_validator.dart';

class MInviteMemberByEmail extends StatefulWidget {
  const MInviteMemberByEmail({super.key});

  @override
  State<MInviteMemberByEmail> createState() => _MInviteMemberByEmailState();
}

class _MInviteMemberByEmailState extends State<MInviteMemberByEmail> {
  final _emailController = TextEditingController();

  bool _isInviteButtonEnabled = false;

  @override
  void initState() {
    super.initState();

    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _emailController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AFTextField(
          autoFocus: true,
          controller: _emailController,
          hintText: LocaleKeys.settings_appearance_members_inviteHint.tr(),
          onSubmitted: (value) => _inviteMember(),
        ),
        VSpace(theme.spacing.m),
        _isInviteButtonEnabled
            ? AFFilledTextButton.primary(
                text: 'Send invite',
                alignment: Alignment.center,
                size: AFButtonSize.l,
                textStyle: theme.textStyle.heading4.enhanced(
                  color: theme.textColorScheme.onFill,
                ),
                onTap: _inviteMember,
              )
            : AFFilledTextButton.disabled(
                text: 'Send invite',
                alignment: Alignment.center,
                size: AFButtonSize.l,
                textStyle: theme.textStyle.heading4.enhanced(
                  color: theme.textColorScheme.tertiary,
                ),
              ),
      ],
    );
  }

  void _inviteMember() {
    final identifier = _emailController.text;
    if (!_isValidEmailOrPhone(identifier)) {
      showToastNotification(
        type: ToastificationType.error,
        message: LocaleKeys.settings_appearance_members_emailInvalidError.tr(),
      );
      return;
    }

    context
        .read<WorkspaceMemberBloc>()
        .add(WorkspaceMemberEvent.inviteWorkspaceMemberByEmail(identifier, AFRolePB.Member));
    // clear the email field after inviting
    _emailController.clear();
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

  void _onEmailChanged() {
    setState(() {
      _isInviteButtonEnabled = _emailController.text.isNotEmpty;
    });
  }
}
