import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/error.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

const _kImageUploadReadyTimeout = Duration(seconds: 90);

/// 读取本地图片文件的像素尺寸（宽×高）。
/// 若读取失败或文件不存在，返回 null。
Future<(double width, double height)?> getImageDimensions(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return (frame.image.width.toDouble(), frame.image.height.toDouble());
  } catch (e) {
    Log.debug('getImageDimensions failed for $path: $e');
    return null;
  }
}

Future<String?> saveImageToLocalStorage(String localImagePath) async {
  final path = await getIt<ApplicationDataStorage>().getPath();
  final imagePath = p.join(
    path,
    'images',
  );
  try {
    // create the directory if not exists
    final directory = Directory(imagePath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final copyToPath = p.join(
      imagePath,
      '${uuid()}${p.extension(localImagePath)}',
    );
    await File(localImagePath).copy(
      copyToPath,
    );
    return copyToPath;
  } catch (e) {
    Log.error('cannot save image file', e);
    return null;
  }
}

Future<(String? path, String? errorMessage)> saveImageToCloudStorage(
  String localImagePath,
  String documentId,
) async {
  final documentService = DocumentService();
  Log.debug("Uploading image local path: $localImagePath");
  final result = await documentService.uploadFile(
    localFilePath: localImagePath,
    documentId: documentId,
  );
  return result.fold(
    (s) async {
      await CustomImageCacheManager().putFile(
        s.url,
        File(localImagePath).readAsBytesSync(),
      );
      final uploadError = await _waitForImageUploadReady(s.url);
      if (uploadError != null) {
        await CustomImageCacheManager().removeFile(s.url);
        return (null, uploadError);
      }
      return (s.url, null);
    },
    (err) {
      if (err.isSingleFileLimitExceeded) {
        final message = LocaleKeys.sideBar_singleFileSizeLimitExceeded.tr();
        return (null, message);
      }
      if (err.isStorageLimitExceeded) {
        final message = Platform.isIOS
            ? LocaleKeys.sideBar_storageLimitDialogTitleIOS.tr()
            : LocaleKeys.sideBar_storageLimitDialogTitle.tr();
        return (null, message);
      }
      return (null, err.msg);
    },
  );
}

Future<String?> _waitForImageUploadReady(String url) async {
  final fileStorageService = getIt<FileStorageService>();
  final notifier = fileStorageService.onFileProgress(fileUrl: url);
  final completer = Completer<String?>();

  void resolve(String? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void listener() {
    final progress = notifier.value;
    if (progress.error != null && progress.error!.isNotEmpty) {
      Log.error(
        '[ImageUpload] upload progress failed before image became visible: url=$url, error=${progress.error}',
      );
      resolve(progress.error);
      return;
    }

    if (progress.progress >= 1.0) {
      Log.debug('[ImageUpload] upload completed, image can be inserted: $url');
      resolve(null);
    }
  }

  notifier.addListener(listener);

  try {
    final initialState = await fileStorageService.getFileState(url);
    initialState.fold(
      (state) {
        if (state.isFinish) {
          resolve(null);
        }
      },
      (err) {
        Log.error(
          '[ImageUpload] unable to query initial file state: url=$url, error=${err.msg}',
        );
      },
    );

    return await completer.future.timeout(
      _kImageUploadReadyTimeout,
      onTimeout: () {
        Log.error(
          '[ImageUpload] timed out waiting for upload completion: url=$url, timeout=${_kImageUploadReadyTimeout.inSeconds}s',
        );
        return LocaleKeys.button_uploadFailed.tr();
      },
    );
  } finally {
    notifier.removeListener(listener);
    notifier.dispose();
  }
}

Future<List<ImageBlockData>> extractAndUploadImages(
  BuildContext context,
  List<String?> urls,
  bool isLocalMode,
) async {
  final List<ImageBlockData> images = [];

  String? lastErrorMsg;
  for (final url in urls) {
    if (url == null || url.isEmpty) {
      continue;
    }

    String? path;
    String? errorMsg;
    CustomImageType imageType = CustomImageType.local;

    if (isLocalMode) {
      path = await saveImageToLocalStorage(url);
    } else {
      (path, errorMsg) = await saveImageToCloudStorage(
        url,
        context.read<DocumentBloc>().documentId,
      );
      imageType = CustomImageType.internal;
    }

    if (path != null && errorMsg == null) {
      images.add(ImageBlockData(url: path, type: imageType));
    } else {
      lastErrorMsg = errorMsg;
    }
  }

  if (context.mounted && lastErrorMsg != null) {
    showToastNotification(message: lastErrorMsg, type: ToastificationType.error);
  }

  return images;
}

@visibleForTesting
int deleteImageTestCounter = 0;

Future<void> deleteImageFromLocalStorage(String localImagePath) async {
  try {
    await File(localImagePath)
        .delete()
        .whenComplete(() => deleteImageTestCounter++);
  } catch (e) {
    Log.error('cannot delete image file', e);
  }
}
