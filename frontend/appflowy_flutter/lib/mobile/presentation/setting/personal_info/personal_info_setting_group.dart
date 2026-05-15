import 'dart:io' as io;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/password/password_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/user/prelude.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/password/change_password.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/password/setup_password.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/widgets.dart';
import 'personal_info.dart';

class PersonalInfoSettingGroup extends StatelessWidget {
  const PersonalInfoSettingGroup({
    super.key,
    required this.userProfile,
    this.onUserProfileUpdated,
  });

  final UserProfilePB userProfile;
  final VoidCallback? onUserProfileUpdated;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsUserViewBloc>(
          create: (context) => getIt<SettingsUserViewBloc>(
            param1: userProfile,
          )..add(const SettingsUserEvent.initial()),
        ),
        BlocProvider(
          create: (context) => PasswordBloc(userProfile)
            ..add(PasswordEvent.init())
            ..add(PasswordEvent.checkHasPassword()),
        ),
      ],
      child: BlocBuilder<SettingsUserViewBloc, SettingsUserState>(
        builder: (context, state) {
          final profile = state.userProfile;
          final isServerUser = profile.userAuthType == AuthTypePB.Server;

          return Column(
            children: [
              const SizedBox(height: 24),
              // Avatar section
              Builder(
                builder: (ctx) => _AvatarSection(
                  iconUrl: profile.iconUrl,
                  name: profile.name,
                  onAvatarChanged: (url) {
                    ctx.read<SettingsUserViewBloc>().add(
                      SettingsUserEvent.updateUserIcon(iconUrl: url),
                    );
                    // Notify parent to refresh user profile cache
                    onUserProfileUpdated?.call();
                  },
                ),
              ),
              const SizedBox(height: 32),
              // Settings list
              MobileSettingGroup(
                groupTitle: '',
                settingItemList: [
                  // 昵称设置
                  MobileSettingItem(
                    name: '昵称设置',
                    trailing: MobileSettingTrailing(
                      text: profile.name,
                    ),
                    onTap: () {
                      showMobileBottomSheet(
                        context,
                        showHeader: true,
                        title: LocaleKeys.settings_mobile_username.tr(),
                        showCloseButton: true,
                        showDragHandle: true,
                        showDivider: false,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        builder: (_) {
                          return EditUsernameBottomSheet(
                            context,
                            userName: profile.name,
                            onSubmitted: (value) {
                              context
                                  .read<SettingsUserViewBloc>()
                                  .add(SettingsUserEvent.updateUserName(name: value));
                              // Notify parent to refresh user profile cache
                              onUserProfileUpdated?.call();
                            },
                          );
                        },
                      );
                    },
                  ),
                  // 绑定手机
                  if (isServerUser && profile.phone.isNotEmpty)
                    MobileSettingItem(
                      name: '绑定手机',
                      trailing: MobileSettingTrailing(
                        text: _maskPhone(profile.phone),
                      ),
                      onTap: () {
                        _showChangePhoneDialog(context);
                      },
                    )
                  else if (isServerUser)
                    MobileSettingItem(
                      name: '绑定手机',
                      trailing: MobileSettingTrailing(
                        text: '未绑定',
                      ),
                      onTap: () {
                        _showBindPhoneDialog(context);
                      },
                    ),
                  // 绑定邮箱
                  if (isServerUser)
                    MobileSettingItem(
                      name: '绑定邮箱',
                      trailing: MobileSettingTrailing(
                        text: _maskEmail(profile.email),
                      ),
                      onTap: () {
                        _showChangeEmailDialog(context);
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  String _maskEmail(String email) {
    if (email.isEmpty) return '';
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts[0];
    if (local.length <= 3) return email;
    return '${local.substring(0, 3)}***@${parts[1]}';
  }

  void _showChangePhoneDialog(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: '更换手机号',
      showCloseButton: true,
      showDragHandle: true,
      showDivider: false,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      builder: (_) => const _ChangePhoneBottomSheet(),
    );
  }

  void _showBindPhoneDialog(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: '绑定手机号',
      showCloseButton: true,
      showDragHandle: true,
      showDivider: false,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      builder: (_) => _BindPhoneBottomSheet(),
    );
  }

  void _showChangeEmailDialog(BuildContext context) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: '更换邮箱',
      showCloseButton: true,
      showDragHandle: true,
      showDivider: false,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      builder: (_) => _ChangeEmailBottomSheet(
        onEmailChanged: (email) {
          context.read<SettingsUserViewBloc>().add(
            SettingsUserEvent.updateUserEmail(email: email),
          );
        },
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  const _AvatarSection({
    required this.iconUrl,
    required this.name,
    required this.onAvatarChanged,
  });

  final String iconUrl;
  final String name;
  final ValueChanged<String> onAvatarChanged;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Column(
      children: [
        // Avatar with tap to change
        GestureDetector(
          onTap: () => _pickImage(context),
          child: Stack(
            children: [
              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.surfaceColorScheme.secondary,
                ),
                child: ClipOval(
                  child: iconUrl.isNotEmpty
                      ? _buildAvatarImage()
                      : _buildDefaultAvatar(context),
                ),
              ),
              // Camera icon overlay
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF44326B),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Change button
        GestureDetector(
          onTap: () => _pickImage(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EDF7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '更换头像',
              style: theme.textStyle.body.standard(
                color: const Color(0xFF44326B),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarImage() {
    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) {
      return FlowyNetworkImage(
        url: iconUrl,
        width: 80,
        height: 80,
      );
    }
    return Image.file(
      io.File(iconUrl),
      width: 80,
      height: 80,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => AFAvatar(
        name: name,
        size: AFAvatarSize.xl,
      ),
    );
  }

  Widget _buildDefaultAvatar(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: theme.textColorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    final ImagePicker picker = ImagePicker();

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (iconUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('移除头像', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'remove') {
      onAvatarChanged('');
      return;
    }

    try {
      final XFile? image = await picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        // For local mode, save to local storage
        final userProfileResult = await UserBackendService.getCurrentUserProfile();
        final userProfile = userProfileResult.fold(
          (p) => p,
          (_) => null,
        );
        final isLocalMode =
            (userProfile?.workspaceType ?? WorkspaceTypePB.LocalW) ==
                WorkspaceTypePB.LocalW;

        String? savedPath;
        if (isLocalMode) {
          savedPath = await saveImageToLocalStorage(image.path);
        } else {
          // Upload to cloud with empty documentId for user icon
          final result = await saveImageToCloudStorage(image.path, 'user_icon');
          savedPath = result.$1;
        }

        if (savedPath != null && savedPath.isNotEmpty) {
          onAvatarChanged(savedPath);
        }
      }
    } catch (e) {
      Log.error('Failed to pick image: $e');
    }
  }
}

class _ChangePhoneBottomSheet extends StatefulWidget {
  const _ChangePhoneBottomSheet();

  @override
  State<_ChangePhoneBottomSheet> createState() => _ChangePhoneBottomSheetState();
}

class _ChangePhoneBottomSheetState extends State<_ChangePhoneBottomSheet> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSending = false;
  bool _isBinding = false;
  int _countdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            '请输入新的手机号',
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.surfaceColorScheme.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      '+86',
                      style: theme.textStyle.body.standard(),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: theme.textColorScheme.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '请输入手机号',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    hintText: '请输入验证码',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _isSending ? null : _sendCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF44326B)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _countdown > 0 ? '${_countdown}s' : '获取验证码',
                    style: TextStyle(
                      color: _countdown > 0
                          ? theme.textColorScheme.secondary
                          : const Color(0xFF44326B),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AFOutlinedTextButton.normal(
              text: _isBinding ? '绑定中...' : '确认更换',
              onTap: () {
                if (!_isBinding) _bindPhone();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() => _isSending = true);

    final result = await UserBackendService.sendPhoneBindCode(phone);

    result.fold(
      (_) {
        setState(() {
          _isSending = false;
          _countdown = 60;
        });
        _startCountdown();
      },
      (error) {
        setState(() => _isSending = false);
        showToastNotification(message: error.msg);
      },
    );
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        if (_countdown > 0) _countdown--;
      });
      return _countdown > 0;
    });
  }

  Future<void> _bindPhone() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();

    if (phone.isEmpty || code.length != 6) return;

    setState(() => _isBinding = true);

    final result = await UserBackendService.confirmPhoneBind(
      phone: phone,
      token: code,
      merge: false,
    );

    if (!mounted) return;
    setState(() => _isBinding = false);

    result.fold(
      (_) {
        Navigator.pop(context);
        showToastNotification(message: '更换成功');
      },
      (error) {
        showToastNotification(message: error.msg);
      },
    );
  }
}

class _BindPhoneBottomSheet extends StatefulWidget {

  @override
  State<_BindPhoneBottomSheet> createState() => _BindPhoneBottomSheetState();
}

class _BindPhoneBottomSheetState extends State<_BindPhoneBottomSheet> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSending = false;
  bool _isBinding = false;
  int _countdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            '为保障账号安全，请先绑定手机号',
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.surfaceColorScheme.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      '+86',
                      style: theme.textStyle.body.standard(),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: theme.textColorScheme.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '请输入手机号',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    hintText: '请输入验证码',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _isSending ? null : _sendCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF44326B)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _countdown > 0 ? '${_countdown}s' : '获取验证码',
                    style: TextStyle(
                      color: _countdown > 0
                          ? theme.textColorScheme.secondary
                          : const Color(0xFF44326B),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AFOutlinedTextButton.normal(
              text: _isBinding ? '绑定中...' : '绑定手机号',
              onTap: () {
                if (!_isBinding) _bindPhone();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() => _isSending = true);

    final result = await UserBackendService.sendPhoneBindCode(phone);

    result.fold(
      (_) {
        setState(() {
          _isSending = false;
          _countdown = 60;
        });
        _startCountdown();
      },
      (error) {
        setState(() => _isSending = false);
        showToastNotification(message: error.msg);
      },
    );
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        if (_countdown > 0) _countdown--;
      });
      return _countdown > 0;
    });
  }

  Future<void> _bindPhone() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();

    if (phone.isEmpty || code.length != 6) return;

    setState(() => _isBinding = true);

    final result = await UserBackendService.confirmPhoneBind(
      phone: phone,
      token: code,
      merge: false,
    );

    if (!mounted) return;
    setState(() => _isBinding = false);

    result.fold(
      (_) {
        Navigator.pop(context);
        showToastNotification(message: '绑定成功');
      },
      (error) {
        showToastNotification(message: error.msg);
      },
    );
  }
}

class _ChangeEmailBottomSheet extends StatefulWidget {
  const _ChangeEmailBottomSheet({required this.onEmailChanged});

  final void Function(String email) onEmailChanged;

  @override
  State<_ChangeEmailBottomSheet> createState() => _ChangeEmailBottomSheetState();
}

class _ChangeEmailBottomSheetState extends State<_ChangeEmailBottomSheet> {
  final _emailController = TextEditingController();
  bool _isBinding = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            '更换邮箱',
            style: theme.textStyle.heading4.standard(
              color: theme.textColorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: '请输入新邮箱',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AFOutlinedTextButton.normal(
              text: _isBinding ? '修改中...' : '确认修改',
              onTap: () {
                if (!_isBinding) _changeEmail();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      showToastNotification(message: '请输入正确的邮箱地址');
      return;
    }

    setState(() => _isBinding = true);

    widget.onEmailChanged(email);

    if (!mounted) return;
    setState(() => _isBinding = false);
    Navigator.pop(context);
  }
}
