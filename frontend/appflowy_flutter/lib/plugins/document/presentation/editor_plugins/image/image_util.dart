import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:ui';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
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
  String documentId, {
  bool waitForUpload = true,
}) async {
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
      if (!waitForUpload) {
        return (s.url, null);
      }

      // 断网时**一秒都不等**：图片已落本地缓存（上方 putFile）并进入 Rust 侧上传
      // 队列，联网后自动续传。此处原本会一直等到 _kImageUploadReadyTimeout（90 秒）
      // 才放弃，用户表现为「插图卡很久」—— 而这段等待在离线时注定是白等的。
      //
      // 本地优先是硬要求：私有空间的图片存取不应依赖网络，插入必须是瞬时的，
      // 同步留给空闲时的上传队列。
      if (await _isOffline()) {
        Log.info(
          '[ImageUpload] 当前离线，跳过等待直接插入本地缓存并留在上传队列: ${s.url}',
        );
        return (s.url, null);
      }

      final progress = await _waitForImageUploadReady(s.url);
      if (progress?.error case final error?) {
        await CustomImageCacheManager().removeFile(s.url);
        return (null, uploadFailureMessage(progress!.errorCode, error));
      }
      return (s.url, null);
    },
    (err) => (null, uploadFailureMessage(err.code.value, err.msg)),
  );
}

/// 判断「等待上传完成」阶段的错误是否属于**可稍后续传**的情况（断网 / 等待超时）。
///
/// 当前是否离线。探测失败一律按「在线」处理 —— 宁可多等，也不误判成离线而
/// 跳过必要的等待。
Future<bool> _isOffline() async {
  try {
    final result = await Connectivity()
        .checkConnectivity()
        .timeout(const Duration(seconds: 2));
    return result == ConnectivityResult.none;
  } catch (_) {
    return false;
  }
}

Future<FileProgress?> _waitForImageUploadReady(String url) async {
  final notifier = getIt<FileStorageService>().onFileProgress(fileUrl: url);
  final completer = Completer<FileProgress?>();
  void listener() {
    final progress = notifier.value;
    if ((progress.error != null ||
            progress.isReady ||
            progress.isWaitingForNetwork) &&
        !completer.isCompleted) {
      completer.complete(progress);
    }
  }

  notifier.addListener(listener);
  listener();
  try {
    // A timeout leaves the locally cached image queued for background sync.
    return await completer.future
        .timeout(_kImageUploadReadyTimeout, onTimeout: () => null);
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
  final validUrls = urls.whereType<String>().where((url) => url.isNotEmpty);
  if (validUrls.isEmpty) {
    return [];
  }

  // A queued cloud upload persists its source file before it waits for the
  // network. Submit every selected image first and insert its cached URL as
  // soon as it is durable locally, rather than serializing the collection on
  // the per-image upload timeout.
  final documentId = context.read<DocumentBloc>().documentId;
  final results = await Future.wait(
    validUrls.map(
      (url) => _extractAndUploadImage(
        url: url,
        documentId: documentId,
        isLocalMode: isLocalMode,
      ),
    ),
  );

  final images = <ImageBlockData>[];
  String? lastErrorMsg;
  for (final result in results) {
    if (result.image != null) {
      images.add(result.image!);
    } else if (result.errorMessage != null) {
      lastErrorMsg = result.errorMessage;
    }
  }

  if (context.mounted && lastErrorMsg != null) {
    showToastNotification(
      message: lastErrorMsg,
      type: ToastificationType.error,
    );
  }

  return images;
}

Future<({ImageBlockData? image, String? errorMessage})> _extractAndUploadImage({
  required String url,
  required String documentId,
  required bool isLocalMode,
}) async {
  if (isLocalMode) {
    final path = await saveImageToLocalStorage(url);
    return (
      image: path == null
          ? null
          : ImageBlockData(url: path, type: CustomImageType.local),
      errorMessage: null,
    );
  }

  final (path, errorMessage) = await saveImageToCloudStorage(
    url,
    documentId,
    waitForUpload: false,
  );
  return (
    image: path == null
        ? null
        : ImageBlockData(url: path, type: CustomImageType.internal),
    errorMessage: errorMessage,
  );
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
