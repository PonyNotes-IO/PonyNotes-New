import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/permission/permission_checker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/default_extensions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

class UploadImageFileWidget extends StatelessWidget {
  const UploadImageFileWidget({
    super.key,
    required this.onPickFiles,
    this.allowedExtensions = defaultImageExtensions,
    this.allowMultipleImages = false,
  });

  final void Function(List<XFile>) onPickFiles;
  final List<String> allowedExtensions;
  final bool allowMultipleImages;

  @override
  Widget build(BuildContext context) {
    Widget child = FlowyButton(
      backgroundColor: Theme.of(context).colorScheme.primary,
      hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
      showDefaultBoxDecorationOnMobile: true,
      radius: PlatformInfo.isMobile ? BorderRadius.circular(8.0) : null,
      text: Container(
        margin: const EdgeInsets.all(4.0),
        alignment: Alignment.center,
        child: FlowyText(
          LocaleKeys.document_imageBlock_upload_placeholder.tr(),
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      onTap: () => _uploadImage(context),
    );

    if (PlatformInfo.isDesktopOrTabletOrWeb) {
      child = FlowyHover(child: child);
    } else {
      child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: child,
      );
    }

    return child;
  }

  Future<void> _uploadImage(BuildContext context) async {
    try {
      // Pad 端和手机端：从相册选择；桌面端：从文件选择。
      if (PlatformInfo.isDesktop) {
        final result = await getIt<FilePickerService>().pickFiles(
          dialogTitle: '',
          type: FileType.custom,
          allowedExtensions: allowedExtensions,
          allowMultiple: allowMultipleImages,
        );
        onPickFiles(result?.files.map((f) => f.xFile).toList() ?? const []);
        return;
      }

      final photoPermission =
          await PermissionChecker.checkPhotoPermission(context);
      if (!photoPermission) {
        Log.error('Has no permission to access the photo library');
        return;
      }
      if (allowMultipleImages) {
        onPickFiles(await ImagePicker().pickMultiImage());
      } else {
        final result =
            await ImagePicker().pickImage(source: ImageSource.gallery);
        onPickFiles(result == null ? const [] : [result]);
      }
    } catch (error, stackTrace) {
      // 原生权限/选择器异常不能冒泡到 Flutter 框架，避免移动端退出进程。
      Log.error('Failed to pick image: $error\n$stackTrace');
      onPickFiles(const []);
    }
  }
}
