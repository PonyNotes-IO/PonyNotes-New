import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/buttons/primary_button.dart';
import 'package:flowy_infra_ui/widget/dialog/styled_dialogs.dart';
import 'package:flutter/material.dart';

import '../../application/handwriting_asset_sync.dart';

class PdfUploadDialog extends StatefulWidget {
  const PdfUploadDialog({super.key, required this.upload});

  final Future<void> Function(ValueChanged<HandwritingUploadProgress>) upload;

  static Future<void> show({
    required BuildContext context,
    required Future<void> Function(ValueChanged<HandwritingUploadProgress>)
        upload,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PdfUploadDialog(upload: upload),
      );

  @override
  State<PdfUploadDialog> createState() => _PdfUploadDialogState();
}

class _PdfUploadDialogState extends State<PdfUploadDialog> {
  HandwritingUploadProgress _progress = const HandwritingUploadProgress();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _upload());
  }

  Future<void> _upload() async {
    if (!mounted) return;
    setState(() {
      _failed = false;
      _progress = const HandwritingUploadProgress();
    });
    try {
      await widget.upload((progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      Log.warn('[HandwritingAssets] PDF upload dialog: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _progress.fraction;
    final status = _progress.isSaving
        ? LocaleKeys.handwritingStorage_savingPdfReference.tr()
        : fraction == null
            ? LocaleKeys.handwritingStorage_preparingPdfUpload.tr()
            : fraction == 1
                ? LocaleKeys.handwritingStorage_confirmingPdfUpload.tr()
                : LocaleKeys.fileDropzone_uploading.tr();

    return PopScope(
      canPop: false,
      child: StyledDialog(
        maxWidth: 420,
        shrinkWrap: false,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _failed
                    ? LocaleKeys.fileDropzone_uploadFailed.tr()
                    : LocaleKeys.handwritingStorage_uploadingPdf.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Text(LocaleKeys.settings_common_uploadingFile.tr()),
              const SizedBox(height: 20),
              if (_failed) ...[
                Text(LocaleKeys.handwritingStorage_pdfUploadRetry.tr()),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: PrimaryTextButton(
                    LocaleKeys.button_retry.tr(),
                    onPressed: _upload,
                  ),
                ),
              ] else ...[
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 12),
                Text(status),
                if (fraction != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    LocaleKeys.handwritingStorage_pdfUploadProgress.tr(
                      namedArgs: {
                        'percent': '${(fraction * 100).floor()}',
                        'sent': (_progress.sentBytes / (1024 * 1024))
                            .toStringAsFixed(2),
                        'total': (_progress.totalBytes / (1024 * 1024))
                            .toStringAsFixed(2),
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
