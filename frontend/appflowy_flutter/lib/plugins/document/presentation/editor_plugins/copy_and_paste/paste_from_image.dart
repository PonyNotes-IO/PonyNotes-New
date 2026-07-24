import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_image_reader.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/default_extensions.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

const _kImageEditorMaxWidth = 800.0;

extension PasteFromImage on EditorState {
  Future<void> dropImages(
    List<int> dropPath,
    List<XFile> files,
    String documentId,
    bool isLocalMode,
  ) async {
    final imageFiles = files.where(
      (file) =>
          file.mimeType?.startsWith('image/') ??
          false || imgExtensionRegex.hasMatch(file.name.toLowerCase()),
    );

    for (final file in imageFiles) {
      String? path;
      String? errorMsg;
      CustomImageType? type;
      double? targetWidth;
      double? targetHeight;

      final dims = await getImageDimensions(file.path);
      if (dims != null) {
        final (origW, origH) = dims;
        if (origW > 0 && origH > 0) {
          final scale = (origW > _kImageEditorMaxWidth)
              ? _kImageEditorMaxWidth / origW
              : 1.0;
          targetWidth = origW * scale;
          targetHeight = origH * scale;
        }
      }

      if (isLocalMode) {
        path = await saveImageToLocalStorage(file.path);
        type = CustomImageType.local;
      } else {
        (path, errorMsg) = await saveImageToCloudStorage(file.path, documentId);
        type = CustomImageType.internal;
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
          customImageNode(
            url: path,
            type: type,
            width: targetWidth,
            height: targetHeight,
          ),
        );
      await apply(t);
    }
  }

  Future<bool> pasteImage(
    String format,
    Uint8List imageBytes,
    String documentId, {
    Selection? selection,
    double? width,
    double? height,
  }) async {
    final context = document.root.context;

    if (context == null) {
      return false;
    }

    final detectedFormat = detectImageFormat(imageBytes);
    if (detectedFormat == null ||
        !defaultImageExtensions.contains(detectedFormat)) {
      Log.info('unsupported format: $format');
      if (PlatformInfo.isMobile) {
        showToastNotification(
          message: LocaleKeys.document_imageBlock_error_invalidImageFormat.tr(),
        );
      }
      return false;
    }
    format = detectedFormat;

    final isLocalMode = context.read<DocumentBloc>().isLocalMode;

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
        'tmp_${uuid()}.$format',
      );
      await File(copyToPath).writeAsBytes(imageBytes);

      double? targetWidth;
      double? targetHeight;
      if (width != null || height != null) {
        targetWidth = width;
        targetHeight = height;
      } else {
        final dims = await getImageDimensions(copyToPath);
        if (dims != null) {
          final (origW, origH) = dims;
          if (origW > 0 && origH > 0) {
            targetWidth = origW;
            targetHeight = origH;
          }
        }
      }

      final String? path;

      CustomImageType type;
      if (isLocalMode) {
        path = await saveImageToLocalStorage(copyToPath);
        type = CustomImageType.local;
      } else {
        final result = await saveImageToCloudStorage(copyToPath, documentId);

        final errorMessage = result.$2;

        if (errorMessage != null && context.mounted) {
          showToastNotification(
            message: errorMessage,
          );
          return false;
        }

        path = result.$1;
        type = CustomImageType.internal;
      }

      if (path != null) {
        await insertImageNode(
          path,
          selection: selection,
          type: type,
          width: targetWidth,
          height: targetHeight,
        );
      }

      return true;
    } catch (e) {
      Log.error('cannot copy image file', e);
      if (context.mounted) {
        showToastNotification(
          message: LocaleKeys.document_imageBlock_error_invalidImage.tr(),
        );
      }
    }

    return false;
  }

  Future<void> insertImageNode(
    String src, {
    Selection? selection,
    required CustomImageType type,
    double? width,
    double? height,
  }) async {
    selection ??= this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = getNodeAtPath(selection.end.path);
    if (node == null) {
      return;
    }
    final transaction = this.transaction;
    // if the current node is empty paragraph, replace it with image node
    if (node.type == ParagraphBlockKeys.type &&
        (node.delta?.isEmpty ?? false)) {
      transaction
        ..insertNode(
          node.path,
          customImageNode(
            url: src,
            type: type,
            width: width,
            height: height,
          ),
        )
        ..deleteNode(node);
    } else {
      transaction.insertNode(
        node.path.next,
        customImageNode(
          url: src,
          type: type,
          width: width,
          height: height,
        ),
      );
    }

    transaction.afterSelection = Selection.collapsed(
      Position(
        path: node.path.next,
      ),
    );

    return apply(transaction);
  }
}
