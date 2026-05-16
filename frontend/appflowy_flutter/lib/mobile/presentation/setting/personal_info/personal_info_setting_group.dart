import 'dart:io' as io;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/personal_info/edit_username_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/setting/personal_info/email_bind_page.dart';
import 'package:appflowy/mobile/presentation/setting/personal_info/phone_bind_page.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/password/password_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/user/prelude.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/widgets.dart';

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
                        context.push(MobilePhoneBindPage.routeName);
                      },
                    )
                  else if (isServerUser)
                    MobileSettingItem(
                      name: '绑定手机',
                      trailing: MobileSettingTrailing(
                        text: '未绑定',
                      ),
                      onTap: () {
                        context.push(MobilePhoneBindPage.routeName);
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
                        context.push(MobileEmailBindPage.routeName);
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
        // Avatar with change button overlay
        GestureDetector(
          onTap: () => _pickImage(context),
          child: SizedBox(
            width: 80,
            height: 112,
            child: Stack(
              alignment: Alignment.topCenter,
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
                // Change button
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3800),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '更换',
                      style: theme.textStyle.body.standard(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
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
