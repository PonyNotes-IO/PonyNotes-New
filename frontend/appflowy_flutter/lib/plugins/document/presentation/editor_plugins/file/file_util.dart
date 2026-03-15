import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/error.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';

/// 单文件最大上传限制：3GB
const int kMaxUploadFileSizeBytes = 3 * 1024 * 1024 * 1024;

/// 检查云存储空间是否足够
///
/// 返回 true 表示有足够空间，返回 false 表示空间不足。
/// 获取订阅信息失败时默认允许上传（放行到服务端检查）。
Future<bool> hasEnoughCloudStorage(
  UserProfilePB userProfile,
  int fileSizeInBytes,
) async {
  try {
    final subscriptionService = SubscriptionService();
    final subscription = await subscriptionService.getCurrentSubscription(
      userProfile: userProfile,
      caller: 'file_util.hasEnoughCloudStorage',
    );

    final storageUsedGb = subscription?.usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = subscription?.usage?.storageTotalGb ?? 0.0;

    // 无法获取订阅信息时，允许上传（由服务端决策）
    if (storageTotalGb <= 0) return true;

    final fileSizeGb = fileSizeInBytes / (1024 * 1024 * 1024);
    return (storageUsedGb + fileSizeGb) <= storageTotalGb;
  } catch (e) {
    Log.error('Failed to check cloud storage quota: $e');
    return true; // 检查失败时默认允许上传
  }
}

Future<String?> saveFileToLocalStorage(String localFilePath) async {
  final path = await getIt<ApplicationDataStorage>().getPath();
  final filePath = p.join(path, 'files');

  try {
    // create the directory if not exists
    final directory = Directory(filePath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final copyToPath = p.join(
      filePath,
      '${uuid()}${p.extension(localFilePath)}',
    );
    await File(localFilePath).copy(
      copyToPath,
    );
    return copyToPath;
  } catch (e) {
    Log.error('cannot save file', e);
    return null;
  }
}

Future<(String? path, String? errorMessage)> saveFileToCloudStorage(
  String localFilePath,
  String documentId, [
  bool isImage = false,
]) async {
  final documentService = DocumentService();
  Log.debug("Uploading file from local path: $localFilePath");
  final result = await documentService.uploadFile(
    localFilePath: localFilePath,
    documentId: documentId,
  );

  return result.fold(
    (s) async {
      if (isImage) {
        await CustomImageCacheManager().putFile(
          s.url,
          File(localFilePath).readAsBytesSync(),
        );
      }

      return (s.url, null);
    },
    (err) {
      // 检查单文件大小限制错误
      if (err.isSingleFileLimitExceeded) {
        final message = LocaleKeys.sideBar_singleFileSizeLimitExceeded.tr();
        return (null, message);
      }
      // 检查存储空间限制错误
      final message = Platform.isIOS
          ? LocaleKeys.sideBar_storageLimitDialogTitleIOS.tr()
          : LocaleKeys.sideBar_storageLimitDialogTitle.tr();
      if (err.isStorageLimitExceeded) {
        return (null, message);
      }
      return (null, err.msg);
    },
  );
}

/// Downloads a MediaFilePB
///
/// On Mobile the file is fetched first using HTTP, and then saved using FilePicker.
/// On Desktop the files location is picked first using FilePicker, and then the file is saved.
///
Future<void> downloadMediaFile(
  BuildContext context,
  MediaFilePB file, {
  VoidCallback? onDownloadBegin,
  VoidCallback? onDownloadEnd,
  UserProfilePB? userProfile,
}) async {
  if ([
    FileUploadTypePB.NetworkFile,
    FileUploadTypePB.LocalFile,
  ].contains(file.uploadType)) {
    /// When the file is a network file or a local file, we can directly open the file.
    await afLaunchUrlString(file.url);
  } else {
    if (userProfile == null) {
      showToastNotification(
        message: LocaleKeys.grid_media_downloadFailedToken.tr(),
      );
      return;
    }

    final uri = Uri.parse(file.url);
    // token 已经是 access_token 字符串，不需要解析
    final token = userProfile.token;

    if (UniversalPlatform.isMobile) {
      onDownloadBegin?.call();

      final response =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final tempFile = File(uri.pathSegments.last);
        final result = await FilePicker().saveFile(
          fileName: p.basename(tempFile.path),
          bytes: response.bodyBytes,
        );

        if (result != null && context.mounted) {
          showToastNotification(
            type: ToastificationType.error,
            message: LocaleKeys.grid_media_downloadSuccess.tr(),
          );
        }
      } else if (context.mounted) {
        showToastNotification(
          type: ToastificationType.error,
          message: LocaleKeys.document_plugins_image_imageDownloadFailed.tr(),
        );
      }

      onDownloadEnd?.call();
    } else {
      final savePath = await FilePicker().saveFile(fileName: file.name);
      if (savePath == null) {
        return;
      }

      onDownloadBegin?.call();

      final response =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final imgFile = File(savePath);
        await imgFile.writeAsBytes(response.bodyBytes);

        if (context.mounted) {
          showToastNotification(
            message: LocaleKeys.grid_media_downloadSuccess.tr(),
          );
        }
      } else if (context.mounted) {
        showToastNotification(
          type: ToastificationType.error,
          message: LocaleKeys.document_plugins_image_imageDownloadFailed.tr(),
        );
      }

      onDownloadEnd?.call();
    }
  }
}

Future<void> insertLocalFile(
  BuildContext context,
  XFile file, {
  required String documentId,
  UserProfilePB? userProfile,
  void Function(String, bool)? onUploadSuccess,
}) async {
  if (file.path.isEmpty) return;

  final fileType = file.fileType.toMediaFileTypePB();

  // Check upload type
  final isLocalMode = (userProfile?.workspaceType ?? WorkspaceTypePB.LocalW) ==
      WorkspaceTypePB.LocalW;

  String? path;
  String? errorMsg;
  if (isLocalMode) {
    path = await saveFileToLocalStorage(file.path);
  } else {
    // 检查1：单文件大小不能超过 3GB（客户端立即拒绝，无需请求服务端）
    final fileSize = File(file.path).lengthSync();
    if (fileSize > kMaxUploadFileSizeBytes) {
      showSnackBarMessage(context, '对不起，您最大可上传的单个文件不能超过3GB');
      return;
    }

    // 检查2：已用空间 + 本次文件大小 不能超过订阅计划允许的最大云存储空间
    if (userProfile != null) {
      final hasEnoughSpace =
          await hasEnoughCloudStorage(userProfile, fileSize);
      if (!hasEnoughSpace) {
        if (context.mounted) {
          await showSimpleAFDialog(
            context: context,
            title: '云存储空间不足',
            content: '您当前可用的云存储空间不足，无法上传文件。请升级会员以获得更多存储空间。',
            primaryAction: (
              '升级',
              (ctx) => MembershipCheckerService().navigateToUpgradePage(
                ctx,
                userProfile: userProfile,
              ),
            ),
            secondaryAction: ('取消', null),
          );
        }
        return;
      }
    }

    (path, errorMsg) = await saveFileToCloudStorage(
      file.path,
      documentId,
      fileType == MediaFileTypePB.Image,
    );
  }

  if (errorMsg != null) {
    return showSnackBarMessage(context, errorMsg);
  }

  if (path == null) {
    return;
  }

  onUploadSuccess?.call(path, isLocalMode);
}

/// [onUploadSuccess] Callback to be called when the upload is successful.
///
/// The callback is called for each file that is successfully uploaded.
/// In case of an error, the error message will be shown on a per-file basis.
///
Future<void> insertLocalFiles(
  BuildContext context,
  List<XFile> files, {
  required String documentId,
  UserProfilePB? userProfile,
  void Function(
    XFile file,
    String path,
    bool isLocalMode,
  )? onUploadSuccess,
}) async {
  if (files.every((f) => f.path.isEmpty)) return;

  // Check upload type
  final isLocalMode = (userProfile?.workspaceType ?? WorkspaceTypePB.LocalW) ==
      WorkspaceTypePB.LocalW;

  for (final file in files) {
    final fileType = file.fileType.toMediaFileTypePB();

    String? path;
    String? errorMsg;

    if (isLocalMode) {
      path = await saveFileToLocalStorage(file.path);
    } else {
      // 检查1：单文件大小不能超过 3GB（客户端立即拒绝）
      final fileSize = File(file.path).lengthSync();
      if (fileSize > kMaxUploadFileSizeBytes) {
        if (context.mounted) {
          showSnackBarMessage(context, '对不起，您最大可上传的单个文件不能超过3GB');
        }
        continue;
      }

      // 检查2：已用空间 + 本次文件大小 不能超过订阅计划允许的最大云存储空间
      if (userProfile != null) {
        final hasEnoughSpace =
            await hasEnoughCloudStorage(userProfile, fileSize);
        if (!hasEnoughSpace) {
          if (context.mounted) {
            await showSimpleAFDialog(
              context: context,
              title: '云存储空间不足',
              content: '您当前可用的云存储空间不足，无法上传文件。请升级会员以获得更多存储空间。',
              primaryAction: (
                '升级',
                (ctx) => MembershipCheckerService().navigateToUpgradePage(
                  ctx,
                  userProfile: userProfile,
                ),
              ),
              secondaryAction: ('取消', null),
            );
          }
          continue;
        }
      }

      (path, errorMsg) = await saveFileToCloudStorage(
        file.path,
        documentId,
        fileType == MediaFileTypePB.Image,
      );
    }

    if (errorMsg != null) {
      showSnackBarMessage(context, errorMsg);
      continue;
    }

    if (path == null) {
      continue;
    }
    onUploadSuccess?.call(file, path, isLocalMode);
  }
}
