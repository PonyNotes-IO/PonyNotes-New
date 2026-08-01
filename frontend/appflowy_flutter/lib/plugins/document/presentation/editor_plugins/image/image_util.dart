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

      final uploadError = await _waitForImageUploadReady(s.url);
      if (uploadError != null) {
        // 【离线上传支持 2026-07-19】断网/等待超时时，不再判定为失败。
        //
        // 原实现：只要云端上传未在超时内完成，就 removeFile 删掉本地缓存并返回错误，
        // 导致图片块**根本不会插入**，用户断网时完全无法插图（实测报错：
        // `error sending request for url (.../create_upload)`）。
        //
        // 但此时数据其实是安全的：
        // - 上方已把本地字节以云端 url 为键写入 CustomImageCacheManager，可离线显示；
        // - Rust 侧已将文件复制到 temp_storage、记录写入 SQLite 并进入上传队列；
        // - 网络错误不会删除该队列记录（handle_upload_error 仅在单文件超限时删除），
        //   联网后由 uploader 自动续传。
        // 因此"未上传完成"只应表现为「待同步」状态，而非丢弃用户的图片。
        //
        // 仅对「网络不可用/等待超时」放行；配额超限等业务错误仍在下方 (err) 分支拦截。
        if (_isPendingUploadError(uploadError)) {
          Log.info(
            '[ImageUpload] upload not finished (offline/timeout), insert with local cache and keep it queued: ${s.url}',
          );
          return (s.url, null);
        }
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

/// 判断「等待上传完成」阶段的错误是否属于**可稍后续传**的情况（断网 / 等待超时）。
///
/// 【离线上传支持 2026-07-19】这类情况不应判定为上传失败：文件已落本地缓存与
/// 上传队列，联网后会自动续传，UI 只需呈现「待同步」。
///
/// 与 Rust 侧 `FlowyError::is_network_unavailable()` 的判定口径保持一致——
/// client-api 底层 reqwest 的发送失败常被折叠为 Internal，只能按消息特征识别。
bool _isPendingUploadError(String error) {
  final e = error.toLowerCase();
  return e.contains('error sending request') ||
      e.contains('connection refused') ||
      e.contains('connection reset') ||
      e.contains('dns error') ||
      e.contains('timed out') ||
      e.contains('network is unreachable') ||
      e.contains('no route to host') ||
      e.contains('failed to lookup address') ||
      // 等待超时：`_waitForImageUploadReady` 超时会返回该文案。
      error == LocaleKeys.button_uploadFailed.tr();
}

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
