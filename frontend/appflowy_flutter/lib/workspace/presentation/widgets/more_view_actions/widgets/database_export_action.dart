import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/settings/share/export_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class DatabaseExportAction extends StatelessWidget {
  const DatabaseExportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyIconTextButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        leftIconBuilder: (_) => FlowySvg(
          ViewMoreActionType.export.leftIconSvg,
        ),
        iconPadding: 10.0,
        textBuilder: (_) => FlowyText.regular(
          '导出CSV文件',
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
        onTap: () => _exportAsCsv(context),
      ),
    );
  }

  Future<void> _exportAsCsv(BuildContext context) async {
    try {
      Log.info('开始导出数据库视图为CSV: ${view.id}');

      final result = await BackendExportService.exportDatabaseAsCSV(view.id);

      await result.fold(
        (exportData) async {
          if (exportData.data.isEmpty) {
            Log.error('导出 CSV 失败：内容为空');
            if (context.mounted) {
              showToastNotification(message: '导出失败：表格内容为空');
            }
            return;
          }

          final fileName = '${view.nameOrDefault}.csv';
          final filePicker = GetIt.instance<FilePickerService>();
          final bytes =
              Uint8List.fromList(utf8.encode('\uFEFF${exportData.data}'));
          final savePath = await filePicker.saveFile(
            dialogTitle: '保存 CSV 文件',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['csv'],
            bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
          );

          if (savePath != null && !Platform.isAndroid && !Platform.isIOS) {
            final file = File(savePath);
            await file.writeAsBytes(bytes);
          }
          if (savePath != null) {
            Log.info('CSV 文件已保存到: $savePath');
            if (context.mounted) {
              showToastNotification(
                message: 'CSV 文件已保存',
                type: ToastificationType.success,
              );
            }
          }
        },
        (error) {
          Log.error('导出 CSV 失败: ${error.msg}');
          if (context.mounted) {
            showToastNotification(message: '导出失败：${error.msg}');
          }
        },
      );
    } catch (e) {
      Log.error('导出 CSV 异常: $e');
      if (context.mounted) {
        showToastNotification(message: '导出失败：$e');
      }
    }
  }
}
