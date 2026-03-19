import 'dart:io';
import 'dart:ui';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/dispatch/error.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

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
    showSnackBarMessage(context, lastErrorMsg);
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
