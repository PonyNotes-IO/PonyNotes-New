import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

extension PasteFromFile on EditorState {
  Future<void> dropFiles(
    List<int> dropPath,
    List<XFile> files,
    String documentId,
    bool isLocalMode, {
    BuildContext? context,
  }) async {
    for (final file in files) {
      String? path;
      String? errorMsg;
      FileUrlType? type;
      if (isLocalMode) {
        path = await saveFileToLocalStorage(file.path);
        type = FileUrlType.local;
      } else {
        final fileSize = File(file.path).lengthSync();
        if (fileSize > kMaxUploadFileSizeBytes) {
          showToastNotification(
            message: '对不起，您最大可上传的单个文件不能超过3GB',
            type: ToastificationType.error,
          );
          continue;
        }

        try {
          final userResult =
              await UserBackendService.getCurrentUserProfile();
          final userProfile =
              userResult.fold((user) => user, (_) => null);
          if (userProfile != null) {
            final hasSpace =
                await hasEnoughCloudStorage(userProfile, fileSize);
            if (!hasSpace) {
              if (context != null && context.mounted) {
                final userProfileForDialog = userProfile;
                await showSimpleAFDialog(
                  context: context,
                  title: '云存储空间不足',
                  content: '您当前可用的云存储空间不足，无法上传文件。请升级会员以获得更多存储空间。',
                  primaryAction: (
                    '升级',
                    (ctx) => MembershipCheckerService().navigateToUpgradePage(
                      ctx,
                      userProfile: userProfileForDialog,
                    ),
                  ),
                  secondaryAction: ('取消', null),
                );
              } else {
                showToastNotification(
                  message: '您当前可用的云存储空间不足，请升级会员以获得更多存储空间。',
                  type: ToastificationType.error,
                );
              }
              continue;
            }
          }
        } catch (e) {
          Log.error('Failed to check cloud storage in dropFiles: $e');
        }

        (path, errorMsg) = await saveFileToCloudStorage(file.path, documentId);
        type = FileUrlType.cloud;
      }

      if (errorMsg != null) {
        showToastNotification(
          message: errorMsg,
          type: ToastificationType.error,
        );
        return;
      }

      if (path == null) {
        continue;
      }

      final t = transaction
        ..insertNode(
          dropPath,
          fileNode(
            url: path,
            type: type,
            name: file.name,
          ),
        );
      await apply(t);
    }
  }
}
