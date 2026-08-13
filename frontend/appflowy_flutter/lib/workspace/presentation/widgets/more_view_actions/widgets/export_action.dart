import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/parsers/simple_table_node_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_block_component.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:appflowy/workspace/application/export/document_exporter.dart';
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
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:appflowy_editor/src/plugins/pdf/html_to_pdf_encoder.dart';
import 'pdf_html_encoder_wrapper.dart';
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

          // 预处理文档中的图片，下载网络图片到本地
          Log.info('开始预处理文档中的图片...');
          final processedDocument = await _preprocessDocumentImages(document);
          Log.info('图片预处理完成');

          // 将文档转换为 Markdown
          // useSimpleImageParser: true 使图片节点输出本地绝对路径而非归档相对路径，
          // 因为 PDF 编码器需要从磁盘直接读取图片文件。
          Log.info('开始将文档转换为 Markdown...');
          final markdown = await customDocumentToMarkdown(
            processedDocument,
            useSimpleImageParser: true,
          );
          Log.info('Markdown 转换完成，长度: ${markdown.length} 字符');

          // 打印 Markdown 内容，检查图片是否被正确包含
          Log.info('Markdown 内容预览:');
          final lines = markdown.split('\n');
          for (int i = 0; i < lines.length && i < 50; i++) {
            if (lines[i].contains('![') || lines[i].contains('http')) {
              Log.info('  第 $i 行: ${lines[i]}');
            }
          }

          if (markdown.isEmpty) {
            Log.error('导出 PDF 失败：Markdown 内容为空');
            hideLoading();
            if (context.mounted) {
              showToastNotification(message: '导出失败：文档内容为空');
            }
            return;
          }

          // 加载支持中文的字体
          Log.info('开始加载中文字体...');
          pw.Font? chineseFont;
          pw.Font? mobileLatinFont;
          List<pw.Font> fontFallbackList = [];
          try {
            // 尝试从系统字体路径加载中文字体
            if (Platform.isMacOS) {
              // macOS 系统字体路径（只使用 TTF 格式，避免 TTC 格式的问题）
              final fontPaths = [
                '/System/Library/Fonts/Supplemental/Arial Unicode.ttf', // Arial Unicode 支持中文
                '/Library/Fonts/Arial Unicode.ttf', // 符号链接到上面的路径
                '/Library/Fonts/Microsoft/SimHei.ttf', // 如果安装了 Microsoft 字体
              ];
              
              for (final fontPath in fontPaths) {
                try {
                  final fontFile = File(fontPath);
                  if (fontFile.existsSync()) {
                    Log.info('尝试加载字体: $fontPath');
                    final fontData = await fontFile.readAsBytes();
                    try {
                      if (fontPath.endsWith('.ttf')) {
                        chineseFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                        Log.info('✅ 成功加载中文字体 (TTF): $fontPath');
                        break;
                      }
                    } catch (e) {
                      Log.warn('⚠️ 加载字体失败 $fontPath: $e');
                      continue;
                    }
                  } else {
                    Log.debug('字体文件不存在: $fontPath');
                  }
                } catch (e) {
                  Log.warn('⚠️ 读取字体文件失败 $fontPath: $e');
                  continue;
                }
              }
            } else if (Platform.isWindows) {
              // Windows 系统字体路径（只使用 TTF 格式）
              final fontPaths = [
                'C:\\Windows\\Fonts\\simhei.ttf', // 黑体
                'C:\\Windows\\Fonts\\msyh.ttf', // 微软雅黑
              ];
              
              for (final fontPath in fontPaths) {
                try {
                  final fontFile = File(fontPath);
                  if (fontFile.existsSync()) {
                    Log.info('尝试加载字体: $fontPath');
                    final fontData = await fontFile.readAsBytes();
                    try {
                      if (fontPath.endsWith('.ttf')) {
                        chineseFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                        Log.info('✅ 成功加载中文字体 (TTF): $fontPath');
                        break;
                      }
                    } catch (e) {
                      Log.warn('⚠️ 加载字体失败 $fontPath: $e');
                      continue;
                    }
                  }
                } catch (e) {
                  Log.warn('⚠️ 读取字体文件失败 $fontPath: $e');
                  continue;
                }
              }
            }
          } catch (e) {
            Log.error('❌ 加载系统字体失败: $e');
          }
          
          // 移动端使用应用内字体，避免依赖 Android/iOS 不同的系统字体格式。
          if (chineseFont == null && (Platform.isAndroid || Platform.isIOS)) {
            try {
              final fontData = await rootBundle.load('assets/fonts/chinese.ttf');
              chineseFont = pw.Font.ttf(fontData);
              final latinFontData = await rootBundle.load(
                'assets/google_fonts/Poppins/Poppins-Regular.ttf',
              );
              mobileLatinFont = pw.Font.ttf(latinFontData);
              Log.info('✅ 成功加载移动端 PDF 字体');
            } catch (e) {
              Log.warn('⚠️ 加载移动端 PDF 字体失败: $e');
            }
          }
          
          // 如果仍然没有字体，记录警告但继续执行
          if (chineseFont == null) {
            Log.error('❌ 无法加载中文字体，PDF 中的中文可能显示为占位符（如 X）');
            Log.error('建议：添加支持中文的 TTF 字体文件到 assets/fonts/ 目录');
            Log.error('或者确保系统中有 Arial Unicode.ttf 字体');
          } else {
            Log.info('✅ 中文字体加载成功，PDF 中文显示应该正常');
            // 将中文字体添加到fontFallback
            fontFallbackList.add(chineseFont);
          }

          // 使用 PdfHTMLEncoder 生成 PDF
          Log.info('开始生成 PDF...');
          
          try {
            // 创建 PdfHTMLEncoderWrapper 实例
            final pdfEncoder = PdfHTMLEncoderWrapper(
              font: mobileLatinFont ?? chineseFont,
              fontFallback: fontFallbackList.isNotEmpty ? fontFallbackList : (chineseFont != null ? [chineseFont] : []),
            );
            
            // 添加文档标题到 Markdown 开头
            final markdownWithTitle = '# ${widget.view.nameOrDefault}\n\n$markdown';
            
            // 使用 PdfHTMLEncoder 转换 Markdown 为 PDF
            Log.info('🔍 开始调用 PdfHTMLEncoder.convert...');
            
            final pdf = await pdfEncoder.convert(markdownWithTitle);
            Log.info('✅ PdfHTMLEncoder.convert 完成');
            
            Log.info('PDF 生成成功');

            Log.info('开始保存 PDF 字节...');
            final pdfBytes = await pdf.save();
            Log.info('PDF 保存完成，大小: ${pdfBytes.length} 字节');

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

  /// 加载图片用于PDF导出
  /// 支持网络URL和本地文件路径
  Future<pw.Widget?> _loadImageForPdf(String imageUrl) async {
    try {
      Uint8List imageBytes;
      
      // 判断是网络URL还是本地路径
      if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        // 网络图片：下载
        Log.info('下载网络图片: $imageUrl');
        try {
          final response = await http.get(Uri.parse(imageUrl));
          if (response.statusCode == 200) {
            imageBytes = response.bodyBytes;
            Log.info('图片下载成功，大小: ${imageBytes.length} 字节');
          } else {
            Log.warn('图片下载失败，状态码: ${response.statusCode}');
            return null;
          }
        } catch (e) {
          Log.warn('下载图片时出错: $e');
          return null;
        }
      } else {
        // 本地图片：读取文件
        Log.info('读取本地图片: $imageUrl');
        try {
          final file = File(imageUrl);
          if (await file.exists()) {
            imageBytes = await file.readAsBytes();
            Log.info('本地图片读取成功，大小: ${imageBytes.length} 字节');
          } else {
            Log.warn('本地图片文件不存在: $imageUrl');
            return null;
          }
        } catch (e) {
          Log.warn('读取本地图片时出错: $e');
          return null;
        }
      }
      
      // 将图片转换为PDF格式
      // 限制图片大小，避免PDF过大
      final maxWidth = 500.0; // PDF页面宽度减去边距后的最大宽度
      final maxHeight = 600.0; // 最大高度
      
      try {
        // 使用 MemoryImage 创建图片widget
        final pdfImage = pw.MemoryImage(imageBytes);
        
        // 创建图片widget，限制大小
        return pw.Center(
          child: pw.Container(
            constraints: pw.BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: pw.Image(
              pdfImage,
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      } catch (e) {
        Log.warn('创建PDF图片widget失败: $e');
        return null;
      }
    } catch (e) {
      Log.error('加载图片失败: $imageUrl, 错误: $e');
      return null;
    }
  }

  /// 预处理文档中的图片，下载网络图片到本地临时目录
  /// 返回处理后的文档副本，其中网络图片URL已替换为本地路径
  Future<Document> _preprocessDocumentImages(Document document) async {
    try {
      Log.info('=== 开始预处理文档图片 ===');
      Log.info('文档根节点子节点数量: ${document.root.children.length}');

      // 创建临时目录用于保存下载的图片
      final tempDir = Directory.systemTemp.createTempSync('ponynotes_pdf_export_');
      Log.info('创建临时目录: ${tempDir.path}');

      // 递归遍历文档节点，下载网络图片
      await _downloadNetworkImagesInNode(document.root, tempDir);

      Log.info('=== 预处理文档图片完成 ===');
      return document;
    } catch (e) {
      Log.error('预处理文档图片失败: $e');
      return document; // 返回原始文档，不阻塞导出流程
    }
  }

  /// 递归遍历节点，下载网络图片
  Future<void> _downloadNetworkImagesInNode(Node node, Directory tempDir) async {
    Log.info('遍历节点: type=${node.type}, id=${node.id}');

    // 处理单图片节点
    if (node.type == CustomImageBlockKeys.type) {
      Log.info('找到单图片节点: ${node.type}');
      await _downloadImageForNode(node, CustomImageBlockKeys.url, tempDir);
    }
    // 处理多图片节点
    else if (node.type == MultiImageBlockKeys.type) {
      Log.info('找到多图片节点: ${node.type}');
      final currentAttributes = node.attributes;
      final images = currentAttributes[MultiImageBlockKeys.images] as List?;
      if (images != null) {
        Log.info('多图片节点包含 ${images.length} 张图片');
        bool updated = false;
        final List<dynamic> newImages = List.from(images);

        for (int i = 0; i < newImages.length; i++) {
          final image = newImages[i] as Map<String, dynamic>?;
          if (image != null) {
            final url = image['url'] as String?;
            final type = image['type'] as int?;
            Log.info('检查图片 $i: url=$url, type=$type');
            if (url != null && type != null) {
              final imageType = CustomImageType.fromIntValue(type);
              if (imageType == CustomImageType.internal || imageType == CustomImageType.external) {
                Log.info('下载网络图片: $url');
                final localPath = await _downloadImage(url, tempDir, 'multi_image_$i');
                if (localPath != null) {
                  // 更新图片URL为本地路径
                  newImages[i] = {...image, 'url': localPath, 'type': CustomImageType.local.toIntValue()};
                  updated = true;
                  Log.info('图片已下载: $url -> $localPath');
                }
              }
            }
          }
        }

        // 使用 updateAttributes 更新节点属性
        if (updated) {
          node.updateAttributes({
            MultiImageBlockKeys.images: newImages,
          });
          Log.info('多图片节点属性已更新');
        }
      }
    }

    // 递归处理子节点
    for (final child in node.children) {
      await _downloadNetworkImagesInNode(child, tempDir);
    }
  }

  /// 下载单个图片节点的网络图片
  Future<void> _downloadImageForNode(Node node, String urlKey, Directory tempDir) async {
    final currentAttributes = node.attributes;
    final url = currentAttributes[urlKey] as String?;
    final type = currentAttributes['image_type'] as int?;

    Log.info('检查图片节点: url=$url, type=$type, urlKey=$urlKey');
    Log.info('节点属性: $currentAttributes');

    if (url == null || type == null) {
      Log.info('跳过图片节点: url或type为空');
      return;
    }

    final imageType = CustomImageType.fromIntValue(type);
    Log.info('图片类型: $imageType');

    // 只处理网络图片（internal 或 external）
    if (imageType == CustomImageType.internal || imageType == CustomImageType.external) {
      Log.info('开始下载网络图片: $url');
      final localPath = await _downloadImage(url, tempDir, 'image');
      if (localPath != null) {
        // 使用 updateAttributes 更新节点属性
        node.updateAttributes({
          urlKey: localPath,
          'image_type': CustomImageType.local.toIntValue(),
        });
        Log.info('已将网络图片下载到本地: $url -> $localPath');
        Log.info('更新后的节点属性: ${node.attributes}');
      }
    } else {
      Log.info('跳过非网络图片: $imageType');
    }
  }

  /// 下载图片并保存到临时目录
  Future<String?> _downloadImage(String url, Directory tempDir, String prefix) async {
    try {
      Log.info('开始下载网络图片: $url');

      // 根据URL生成文件名
      final uri = Uri.parse(url);
      final extension = p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.jpg';
      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final localPath = p.join(tempDir.path, fileName);

      // 下载图片
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        Log.info('图片下载成功: $localPath (${response.bodyBytes.length} 字节)');
        return localPath;
      } else {
        Log.warn('图片下载失败，状态码: ${response.statusCode}, URL: $url');
        return null;
      }
    } catch (e) {
      Log.error('下载图片时出错: $url, 错误: $e');
      return null;
    }
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
