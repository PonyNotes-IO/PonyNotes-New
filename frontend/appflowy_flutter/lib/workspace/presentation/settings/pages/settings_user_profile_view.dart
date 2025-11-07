import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_input_field.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

class SettingsUserProfileView extends StatefulWidget {
  const SettingsUserProfileView({
    super.key,
    required this.userProfile,
  });

  final UserProfilePB userProfile;

  @override
  State<SettingsUserProfileView> createState() => _SettingsUserProfileViewState();
}

class _SettingsUserProfileViewState extends State<SettingsUserProfileView> {
  late String _name;
  late String _avatarUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _name = widget.userProfile.name;
    _avatarUrl = widget.userProfile.iconUrl;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(
      title: "我的账户",
      autoSeparate: false,
      children: [
        SettingsCategory(
          title: "个人资料",
          children: [
            const SizedBox(height: 20),
            // 头像部分
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: _isUploading ? null : _uploadAvatar,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.5),
                              width: 2,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: ClipOval(
                            child: _avatarUrl.isNotEmpty
                                ? _buildAvatar(_avatarUrl)
                                : _buildDefaultAvatar(),
                          ),
                        ),
                      ),
                      if (_isUploading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "上传图片",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // 用户名输入
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    "我的名称",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: SettingsInputField(
                    value: _name,
                    placeholder: "我的名称",
                    onSave: (value) {
                      if (value.trim().isEmpty) return;
                      _updateUserName(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar(String url) {
    // 判断是本地路径还是网络 URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultAvatar();
        },
      );
    } else if (File(url).existsSync()) {
      return Image.file(
        File(url),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultAvatar();
        },
      );
    }
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Center(
        child: FlowySvg(
          FlowySvgs.pony_notes_logo_xl,
          size: const Size(100, 100),
          blendMode: null,
        ),
      ),
    );
  }

  Future<void> _uploadAvatar() async {
    if (_isUploading) return;

    // 选择图片文件
    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      type: FileType.image,
    );

    if (result == null || result.files.isEmpty) return;

    final localImagePath = result.files.first.path;
    if (localImagePath == null) return;

    setState(() => _isUploading = true);

    try {
      // 获取当前用户配置，判断是本地模式还是云端模式
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => null,
      );

      if (userProfile == null) {
        Log.error('Failed to get user profile');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取用户信息失败')),
          );
        }
        setState(() => _isUploading = false);
        return;
      }

      final isLocalMode = userProfile.workspaceType == WorkspaceTypePB.LocalW;
      String? uploadedUrl;

      if (isLocalMode) {
        // 本地模式：保存到应用数据目录
        Log.info('Uploading avatar in local mode');
        uploadedUrl = await saveImageToLocalStorage(localImagePath);
      } else {
        // 云端模式：上传到 AppFlowy Cloud Storage
        Log.info('Uploading avatar to cloud storage');
        final (url, errorMsg) = await saveImageToCloudStorage(
          localImagePath,
          userProfile.id.toString(),
        );
        uploadedUrl = url;
        if (errorMsg != null && errorMsg.isNotEmpty) {
          Log.error('Upload avatar error: $errorMsg');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('上传失败: $errorMsg')),
            );
          }
        }
      }

      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        // 调用后端 API 更新用户头像
        final userService = UserBackendService(userId: widget.userProfile.id);
        final updateResult = await userService.updateUserProfile(
          iconUrl: uploadedUrl,
        );
        
        updateResult.fold(
          (success) {
            Log.info('Avatar updated successfully');
            // 更新本地 UI
            if (mounted) {
              setState(() {
                _avatarUrl = uploadedUrl!;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('头像上传成功')),
              );
            }
          },
          (error) {
            Log.error('Failed to update avatar: $error');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('更新头像失败: ${error.msg}')),
              );
            }
          },
        );
      }
    } catch (e) {
      Log.error('Upload avatar exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传异常: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _updateUserName(String newName) async {
    if (newName == _name) return;

    final userService = UserBackendService(userId: widget.userProfile.id);
    final result = await userService.updateUserProfile(name: newName);
    
    result.fold(
      (success) {
        Log.info('User name updated successfully');
        if (mounted) {
          setState(() {
            _name = newName;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('名称更新成功')),
          );
        }
      },
      (error) {
        Log.error('Update user name error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败: ${error.msg}')),
          );
        }
      },
    );
  }
}



