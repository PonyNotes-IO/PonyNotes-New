import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/import.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class NotionImporter extends StatefulWidget {
  const NotionImporter({required this.filePath, super.key});

  final String filePath;

  @override
  State<NotionImporter> createState() => _NotionImporterState();
}

class _NotionImporterState extends State<NotionImporter> {
  late final Future<FlowyResult<void, FlowyError>> _upload;

  @override
  void initState() {
    super.initState();
    _upload = ImportBackendService.importZipFiles(
      [ImportZipPB()..filePath = widget.filePath],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 30, maxHeight: 200),
      child: FutureBuilder(
        future: _upload,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _UploadError(message: LocaleKeys.error_unexpectedError.tr());
          }
          return snapshot.data?.fold(
                (_) => const _UploadSuccess(),
                (error) => _UploadError(
                  message: notionImportErrorMessage(
                    error,
                    languageCode: context.locale.languageCode,
                  ),
                ),
              ) ??
              const _Uploading();
        },
      ),
    );
  }
}

class _UploadSuccess extends StatelessWidget {
  const _UploadSuccess();

  @override
  Widget build(BuildContext context) {
    return FlowyText(
      fontSize: 16,
      LocaleKeys.settings_common_uploadNotionSuccess.tr(),
      maxLines: 10,
    );
  }
}

class _Uploading extends StatelessWidget {
  const _Uploading();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator.adaptive(),
            const VSpace(12),
            FlowyText(
              fontSize: 16,
              LocaleKeys.settings_common_uploadingFile.tr(),
              maxLines: null,
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
String notionImportErrorMessage(
  FlowyError error, {
  required String languageCode,
}) {
  // Older servers can return the workspace quota as a generic error.
  if (error.code == ErrorCode.WorkspaceLimitExceeded ||
      error.msg.startsWith('Workspace limit reached (Limit:')) {
    return languageCode == 'zh'
        ? '导入触发了新建工作区的数量限制。请确认客户端和服务端均支持导入到当前工作区的私有空间。'
        : 'The import hit the workspace limit. Check that both the app '
            'and the server support importing into a private space in the '
            'current workspace.';
  }
  return error.msg;
}

class _UploadError extends StatelessWidget {
  const _UploadError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return FlowyText(message, maxLines: 10);
  }
}
