import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_input_field.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
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
  late String _originalName;
  late String _originalAvatarUrl;
  bool _isUploading = false;
  bool _isSaving = false;
  String? _pendingAvatarPath;

  @override
  void initState() {
    super.initState();
    _name = widget.userProfile.name;
    _avatarUrl = widget.userProfile.iconUrl;
    _originalName = widget.userProfile.name;
    _originalAvatarUrl = widget.userProfile.iconUrl;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(
      title: "个人资料",
      autoSeparate: false,
      children: [
        const SizedBox(height: 20),
        // 我的名称
        _buildEditField(
          context,
          label: "我的名称",
          child: SettingsInputField(
            value: _name,
            placeholder: "请输入您的名称",
            onSave: (value) {
              if (value.trim().isEmpty) return;
              setState(() {
                _name = value;
              });
            },
          ),
        ),
        const SizedBox(height: 24),
        // 我的头像
        _buildEditField(
          context,
          label: "我的头像",
          child: _buildAvatarUploadSection(),
        ),
        const SizedBox(height: 32),
        // 保存按钮
        _buildSaveButton(),
      ],
    );
  }

  // 构建编辑字段 - 同一行显示标签和内容
  Widget _buildEditField(BuildContext context, {required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: FlowyText(
            label,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  // 构建头像上传区域
  Widget _buildAvatarUploadSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 可点击的头像
        GestureDetector(
          onTap: _isUploading ? null : _selectAvatar,
          child: Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipOval(
                  child: _avatarUrl.isNotEmpty
                      ? _buildAvatar(_avatarUrl)
                      : _buildDefaultAvatar(),
                ),
              ),
              // 上传状态指示器
              if (_isUploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black54,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
      color: Colors.grey[100],
      child: Center(
        child: FlowySvg(
          FlowySvgs.pony_notes_logo_xl,
          size: const Size(40, 40),
          blendMode: null,
        ),
      ),
    );
  }

  // 构建保存按钮
  Widget _buildSaveButton() {
    final hasChanges = _hasChanges();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton(
          onPressed: (hasChanges && !_isSaving) ? _saveChanges : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  "保存",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
        ),
      ],
    );
  }

  // 检查是否有变化
  bool _hasChanges() {
    return _name != _originalName || 
           _avatarUrl != _originalAvatarUrl || 
           _pendingAvatarPath != null;
  }

  // 选择头像
  Future<void> _selectAvatar() async {
    if (_isUploading) return;

    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      type: FileType.image,
    );

    if (result == null || result.files.isEmpty) return;

    final localImagePath = result.files.first.path;
    if (localImagePath == null) return;

    setState(() {
      _pendingAvatarPath = localImagePath;
      // 临时显示选中的图片
      _avatarUrl = localImagePath;
    });
  }

  // 保存所有变化
  Future<void> _saveChanges() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final userService = UserBackendService(userId: widget.userProfile.id);
      
      // 1. 如果有待上传的头像，先上传头像
      String? finalAvatarUrl = _avatarUrl;
      if (_pendingAvatarPath != null) {
        finalAvatarUrl = await _uploadAvatarFile(_pendingAvatarPath!);
        if (finalAvatarUrl == null) {
          // 头像上传失败，停止保存
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('头像上传失败')),
            );
          }
          return;
        }
      }

      // 2. 更新用户资料（名称和头像URL）
      final updateResult = await userService.updateUserProfile(
        name: _name,
        iconUrl: finalAvatarUrl,
      );

      updateResult.fold(
        (success) {
          Log.info('User profile updated successfully');
          if (mounted) {
            // 更新原始值
            setState(() {
              _originalName = _name;
              _originalAvatarUrl = finalAvatarUrl!;
              _avatarUrl = finalAvatarUrl;
              _pendingAvatarPath = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('保存成功')),
            );
          }
        },
        (error) {
          Log.error('Failed to update user profile: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('保存失败: ${error.msg}')),
            );
          }
        },
      );
    } catch (e) {
      Log.error('Save changes exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存异常: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // 上传头像文件
  Future<String?> _uploadAvatarFile(String localImagePath) async {
    try {
      // 获取当前用户配置，判断是本地模式还是云端模式
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => null,
      );

      if (userProfile == null) {
        Log.error('Failed to get user profile');
        return null;
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
        }
      }

      return uploadedUrl;
    } catch (e) {
      Log.error('Upload avatar file exception: $e');
      return null;
    }
  }

}



