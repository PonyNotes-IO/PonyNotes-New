import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/parsers/simple_table_node_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_block_component.dart';
import 'package:appflowy/workspace/application/export/document_exporter.dart';
import 'package:appflowy/workspace/application/export/document_pdf_exporter.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class ExportAction extends StatefulWidget {
  const ExportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<ExportAction> createState() => _ExportActionState();
}

class _ExportActionState extends State<ExportAction> {
  final PopoverController _popoverController = PopoverController();

  @override
  void dispose() {
    _popoverController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      controller: _popoverController,
      direction: PopoverDirection.leftWithTopAligned,
      constraints: const BoxConstraints(
        maxWidth: 200,
        maxHeight: 120,
      ),
      margin: const EdgeInsets.symmetric(
        horizontal: 14.0,
        vertical: 12.0,
      ),
      clickHandler: PopoverClickHandler.gestureDetector,
      offset: const Offset(-10, 0),
      popupBuilder: (_) => _buildExportMenu(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: FlowyIconTextButton(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          leftIconBuilder: (_) => FlowySvg(
            ViewMoreActionType.export.leftIconSvg,
          ),
          iconPadding: 10.0,
          textBuilder: (_) => FlowyText.regular(
            ViewMoreActionType.export.name,
            fontSize: 14.0,
            lineHeight: 1.0,
            figmaLineHeight: 18.0,
          ),
        ),
      ),
    );
  }

  Widget _buildExportMenu(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasTableInDocument(),
      builder: (context, snapshot) {
        final hasTable = snapshot.data ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildExportOption(
              context,
              label: '导出为 Markdown',
              icon: Icons.description,
              onTap: () => _exportAsMarkdown(context),
            ),
            const VSpace(4),
            _buildExportOption(
              context,
              label: '导出为 PDF',
              icon: Icons.picture_as_pdf,
              onTap: () => _exportAsPdf(context),
            ),
            if (hasTable) ...[
              const VSpace(4),
              _buildExportOption(
                context,
                label: '导出CSV文件',
                icon: Icons.table_chart,
                onTap: () => _exportAsCsv(context),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildExportOption(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: onTap,
        leftIcon: Icon(
          icon,
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        iconPadding: 10.0,
        text: FlowyText.regular(
          label,
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  Future<void> _exportAsMarkdown(BuildContext context) async {
    // 关闭弹出菜单
    _popoverController.close();
    
    try {
      final exporter = DocumentExporter(widget.view);
      final result = await exporter.export(DocumentExportType.markdown);

      await result.fold(
        (markdown) async {
          if (markdown.isEmpty) {
            Log.error('导出 Markdown 失败：内容为空');
            if (context.mounted) {
              showToastNotification(message: '导出失败：文档内容为空');
            }
            return;
          }

          final fileName = '${widget.view.nameOrDefault}.md';
          final filePicker = GetIt.instance<FilePickerService>();
          final bytes = Uint8List.fromList(utf8.encode(markdown));
          final savePath = await filePicker.saveFile(
            dialogTitle: '保存 Markdown 文件',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['md'],
            bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
          );

          if (savePath != null) {
            if (!Platform.isAndroid && !Platform.isIOS) {
              await File(savePath).writeAsBytes(bytes);
            }
            Log.info('Markdown 文件已保存到: $savePath');
            if (context.mounted) {
              showToastNotification(message: 'Markdown 文件已保存', type: ToastificationType.success);
            }
          }
        },
        (error) {
          Log.error('导出 Markdown 失败: ${error.msg}');
          if (context.mounted) {
            showToastNotification(message: '导出失败：${error.msg}');
          }
        },
      );
    } catch (e) {
      Log.error('导出 Markdown 异常: $e');
      if (context.mounted) {
        showToastNotification(message: '导出失败：$e');
      }
    }
  }

  Future<void> _exportAsPdf(BuildContext context) async {
    // 关闭弹出菜单
    _popoverController.close();

    final navigator = Navigator.of(context, rootNavigator: true);
    var isLoadingVisible = false;

    void hideLoading() {
      if (isLoadingVisible && navigator.mounted) {
        isLoadingVisible = false;
        navigator.pop();
      }
    }

    try {
      final fileName = '${widget.view.nameOrDefault}.pdf';
      final filePicker = GetIt.instance<FilePickerService>();
      
      // 显示加载指示器
      if (context.mounted) {
        unawaited(
          showDialog<void>(
            context: navigator.context,
            useRootNavigator: false,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          ).whenComplete(() => isLoadingVisible = false),
        );
        isLoadingVisible = true;
      }
      
      // 开始生成 PDF
      final documentService = DocumentService();
      final result = await documentService.openDocument(documentId: widget.view.id);

      await result.fold(
        (documentData) async {
          final document = documentData.toDocument();
          if (document == null) {
            Log.error('导出 PDF 失败：无法获取文档');
            hideLoading();
            if (context.mounted) {
              showToastNotification(message: '导出失败：无法获取文档内容');
            }
            return;
          }

          try {
            final pdfBytes = await DocumentPdfExporter.render(
              document,
              title: widget.view.nameOrDefault,
            );

            // 关闭加载指示器
            hideLoading();

            try {
              final savePath = await filePicker.saveFile(
                dialogTitle: '保存 PDF 文件',
                fileName: fileName,
                type: FileType.custom,
                allowedExtensions: ['pdf'],
                bytes: Platform.isAndroid || Platform.isIOS ? pdfBytes : null,
              );
              if (savePath == null) {
                Log.info('用户取消了 PDF 文件保存');
                return;
              }

              if (!Platform.isAndroid && !Platform.isIOS) {
                await File(savePath).writeAsBytes(pdfBytes);
              }
              Log.info('PDF 文件已保存到: $savePath');

              if (context.mounted) {
                showToastNotification(message: 'PDF 文件已保存', type: ToastificationType.success);
              }
            } catch (e) {
              Log.error('写入 PDF 文件失败: $e');
              if (context.mounted) {
                showToastNotification(message: 'PDF 文件保存失败：$e');
              }
            }
          } catch (e) {
            Log.error('生成 PDF 时出错: $e');
            hideLoading();
            if (context.mounted) {
              showToastNotification(message: 'PDF 生成失败：$e');
            }
          }
        },
        (error) {
          Log.error('导出 PDF 失败: ${error.msg}');
          hideLoading();
          if (context.mounted) {
            showToastNotification(message: '导出失败：${error.msg}');
          }
        },
      );
    } catch (e) {
      Log.error('导出 PDF 异常: $e');
      hideLoading();
      if (context.mounted) {
        showToastNotification(message: '导出失败：$e');
      }
    }
  }

  /// 检查文档中是否包含表格
  Future<bool> _hasTableInDocument() async {
    try {
      final documentService = DocumentService();
      final result = await documentService.openDocument(documentId: widget.view.id);
      return result.fold(
        (documentData) {
          final document = documentData.toDocument();
          if (document == null) return false;
          return _findTableNodes(document.root).isNotEmpty;
        },
        (_) => false,
      );
    } catch (e) {
      Log.error('检查表格时出错: $e');
      return false;
    }
  }

  /// 查找文档中的所有表格节点
  List<Node> _findTableNodes(Node node) {
    final tables = <Node>[];
    if (node.type == SimpleTableBlockKeys.type) {
      tables.add(node);
    }
    for (final child in node.children) {
      tables.addAll(_findTableNodes(child));
    }
    return tables;
  }

  /// 导出表格为 CSV
  Future<void> _exportAsCsv(BuildContext context) async {
    // 关闭弹出菜单
    _popoverController.close();

    try {
      final documentService = DocumentService();
      final result =
          await documentService.openDocument(documentId: widget.view.id);

      await result.fold(
        (documentData) async {
          final document = documentData.toDocument();
          if (document == null) {
            Log.error('导出 CSV 失败：无法获取文档');
            if (context.mounted) {
              showToastNotification(message: '导出失败：无法获取文档内容');
            }
            return;
          }

          // 查找所有表格节点
          final tableNodes = _findTableNodes(document.root);
          if (tableNodes.isEmpty) {
            Log.error('导出 CSV 失败：文档中没有表格');
            if (context.mounted) {
              showToastNotification(message: '导出失败：文档中没有表格');
            }
            return;
          }

          // 如果有多个表格，导出第一个表格
          // 如果有多个表格，可以后续扩展为让用户选择
          final tableNode = tableNodes.first;
          final csvContent = _convertTableToCsv(tableNode);

          if (csvContent.isEmpty) {
            Log.error('导出 CSV 失败：表格内容为空');
            if (context.mounted) {
              showToastNotification(message: '导出失败：表格内容为空');
            }
            return;
          }

          final fileName = '${widget.view.nameOrDefault}_表格.csv';
          final filePicker = GetIt.instance<FilePickerService>();
          final savePath = await filePicker.saveFile(
            dialogTitle: '保存 CSV 文件',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['csv'],
          );

          if (savePath != null) {
            final file = File(savePath);
            // 使用 UTF-8 BOM 以确保 Excel 能正确识别中文
            final bytes = utf8.encode('\uFEFF$csvContent');
            await file.writeAsBytes(bytes);
            Log.info('CSV 文件已保存到: $savePath');
            if (context.mounted) {
              showToastNotification(message: 'CSV 文件已保存', type: ToastificationType.success);
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

  /// 将表格节点转换为 CSV 格式
  String _convertTableToCsv(Node tableNode) {
    try {
      final parser = const SimpleTableNodeParser();
      // 使用 parser 的私有方法提取表格数据
      // 我们需要自己实现提取逻辑
      final tableData = _extractTableData(tableNode);
      if (tableData.isEmpty) {
        return '';
      }

      return _buildCsvContent(tableData);
    } catch (e) {
      Log.error('转换表格为 CSV 时出错: $e');
      return '';
    }
  }

  /// 提取表格数据
  List<List<String>> _extractTableData(Node tableNode) {
    final tableData = <List<String>>[];
    final rows = tableNode.children;

    for (final row in rows) {
      final rowData = _extractRowData(row);
      tableData.add(rowData);
    }

    return tableData;
  }

  /// 提取行数据
  List<String> _extractRowData(Node row) {
    final rowData = <String>[];
    final cells = row.children;

    for (final cell in cells) {
      final content = _extractCellContent(cell);
      rowData.add(content);
    }

    return rowData;
  }

  /// 提取单元格内容
  String _extractCellContent(Node cell) {
    final contentBuffer = StringBuffer();

    for (final child in cell.children) {
      final delta = child.delta;
      if (delta != null) {
        final text = delta.toPlainText();
        contentBuffer.write(text);
      } else {
        // 如果没有 delta，递归获取子节点的文本内容
        final text = _getNodeText(child);
        contentBuffer.write(text);
      }
    }

    return contentBuffer.toString().trim();
  }

  /// 递归获取节点的文本内容
  String _getNodeText(Node node) {
    final buffer = StringBuffer();
    if (node.delta != null) {
      buffer.write(node.delta!.toPlainText());
    }
    for (final child in node.children) {
      buffer.write(_getNodeText(child));
    }
    return buffer.toString();
  }

  /// 构建 CSV 内容
  String _buildCsvContent(List<List<String>> tableData) {
    if (tableData.isEmpty) {
      return '';
    }

    final csvBuffer = StringBuffer();
    for (final row in tableData) {
      final csvRow = row.map((cell) => _escapeCsvField(cell)).join(',');
      csvBuffer.writeln(csvRow);
    }

    return csvBuffer.toString();
  }

  /// 转义 CSV 字段
  String _escapeCsvField(String field) {
    // 如果字段包含逗号、引号或换行符，需要用引号包裹
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      // 转义字段中的引号（用两个引号表示一个引号）
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }

  /// 保存文件（支持 bytes 参数）
  /// 在 macOS/Windows 上，saveFile 返回路径后需要手动写入文件
  Future<String?> _saveFileWithBytes(
    FilePickerService filePicker, {
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      // 在桌面平台上，saveFile 返回路径，需要手动写入
      // 在移动平台上，saveFile 可能支持 bytes 参数自动保存
      final savePath = await filePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      
      if (savePath != null) {
        Log.info('获取到保存路径: $savePath');
        try {
          final file = File(savePath);
          await file.writeAsBytes(bytes);
          Log.info('文件写入成功: $savePath, 大小: ${bytes.length} 字节');
          return savePath;
        } catch (e) {
          Log.error('文件写入失败: $e');
          rethrow;
        }
      } else {
        Log.warn('用户取消了文件保存或保存路径为空');
        return null;
      }
    } catch (e) {
      Log.error('保存文件时发生错误: $e');
      // 尝试使用动态调用（如果实现支持 bytes 参数）
      try {
        final result = await (filePicker as dynamic).saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: bytes,
        );
        Log.info('使用 bytes 参数保存成功: $result');
        return result as String?;
      } catch (e2) {
        Log.error('使用 bytes 参数保存也失败: $e2');
        return null;
      }
    }
  }
}
