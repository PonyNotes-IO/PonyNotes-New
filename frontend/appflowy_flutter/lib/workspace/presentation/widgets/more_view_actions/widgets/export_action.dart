import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:appflowy_editor/src/plugins/pdf/html_to_pdf_encoder.dart';
import 'pdf_html_encoder_wrapper.dart';

class ExportAction extends StatelessWidget {
  const ExportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
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
    try {
      final exporter = DocumentExporter(view);
      final result = await exporter.export(DocumentExportType.markdown);

      result.fold(
        (markdown) async {
          if (markdown.isEmpty) {
            Log.error('导出 Markdown 失败：内容为空');
            if (context.mounted) {
              _showError(context, '导出失败：文档内容为空');
            }
            return;
          }

          final fileName = '${view.nameOrDefault}.md';
          final filePicker = GetIt.instance<FilePickerService>();
          final savePath = await filePicker.saveFile(
            dialogTitle: '保存 Markdown 文件',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['md'],
          );

          if (savePath != null) {
            final file = File(savePath);
            await file.writeAsString(markdown, encoding: utf8);
            Log.info('Markdown 文件已保存到: $savePath');
            if (context.mounted) {
              _showSuccess(context, 'Markdown 文件已保存');
            }
          }
        },
        (error) {
          Log.error('导出 Markdown 失败: ${error.msg}');
          if (context.mounted) {
            _showError(context, '导出失败：${error.msg}');
          }
        },
      );
    } catch (e) {
      Log.error('导出 Markdown 异常: $e');
      if (context.mounted) {
        _showError(context, '导出失败：$e');
      }
    }
  }

  Future<void> _exportAsPdf(BuildContext context) async {
    try {
      final documentService = DocumentService();
      final result = await documentService.openDocument(documentId: view.id);

      await result.fold(
        (documentData) async {
          final document = documentData.toDocument();
          if (document == null) {
            Log.error('导出 PDF 失败：无法获取文档');
            if (context.mounted) {
              _showError(context, '导出失败：无法获取文档内容');
            }
            return;
          }

          // 将文档转换为 Markdown
          Log.info('开始将文档转换为 Markdown...');
          final markdown = await customDocumentToMarkdown(document);
          Log.info('Markdown 转换完成，长度: ${markdown.length} 字符');
          
          // 调试：检查Markdown中是否包含代码块
          if (markdown.contains('```')) {
            Log.info('✅ Markdown中包含代码块标记');
            final codeBlockMatches = RegExp(r'```[\s\S]*?```').allMatches(markdown);
            Log.info('找到 ${codeBlockMatches.length} 个代码块');
            for (final match in codeBlockMatches) {
              final codeBlock = match.group(0) ?? '';
              final preview = codeBlock.length > 100 
                  ? '${codeBlock.substring(0, 100)}...' 
                  : codeBlock;
              Log.info('代码块预览: $preview');
            }
          } else {
            Log.warn('⚠️ Markdown中未找到代码块标记');
          }
          
          if (markdown.isEmpty) {
            Log.error('导出 PDF 失败：Markdown 内容为空');
            if (context.mounted) {
              _showError(context, '导出失败：文档内容为空');
            }
            return;
          }

          // 加载支持中文的字体
          Log.info('开始加载中文字体和Emoji字体...');
          pw.Font? chineseFont;
          pw.Font? emojiFont;
          List<pw.Font> fontFallbackList = [];
          try {
            // 尝试从系统字体路径加载中文字体
            if (Platform.isMacOS) {
              // macOS 系统字体路径（优先使用 TTF 格式，因为 pdf 包对 TTC 支持可能有问题）
              final fontPaths = [
                '/System/Library/Fonts/Supplemental/Arial Unicode.ttf', // Arial Unicode 支持中文
                '/Library/Fonts/Arial Unicode.ttf', // 符号链接到上面的路径
                '/Library/Fonts/Microsoft/SimHei.ttf', // 如果安装了 Microsoft 字体
                '/System/Library/Fonts/Supplemental/Songti.ttc', // 宋体 TTC（尝试）
                '/System/Library/Fonts/STHeiti Medium.ttc', // 黑体 TTC（尝试）
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
                      } else if (fontPath.endsWith('.ttc')) {
                        // TTC 格式：pdf 包可能不支持，但尝试加载
                        // 注意：TTC 是字体集合，可能需要特殊处理
                        try {
                          chineseFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                          Log.info('✅ 成功加载中文字体 (TTC): $fontPath');
                          break;
                        } catch (e) {
                          Log.warn('⚠️ TTC 格式加载失败，尝试下一个字体: $e');
                          continue;
                        }
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
              // Windows 系统字体路径
              final fontPaths = [
                'C:\\Windows\\Fonts\\simhei.ttf', // 黑体
                'C:\\Windows\\Fonts\\msyh.ttf', // 微软雅黑
                'C:\\Windows\\Fonts\\simsun.ttc', // 宋体 TTC
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
                      } else if (fontPath.endsWith('.ttc')) {
                        try {
                          chineseFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                          Log.info('✅ 成功加载中文字体 (TTC): $fontPath');
                          break;
                        } catch (e) {
                          Log.warn('⚠️ TTC 格式加载失败: $e');
                          continue;
                        }
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
          
          // 如果系统字体加载失败，尝试使用 Flutter 资源
          if (chineseFont == null) {
            try {
              // 尝试从 assets 加载字体（如果项目中有中文字体资源）
              final fontData = await rootBundle.load('assets/fonts/chinese.ttf');
              chineseFont = pw.Font.ttf(fontData);
              Log.info('✅ 成功从 assets 加载中文字体');
            } catch (e) {
              Log.warn('⚠️ 从 assets 加载字体失败: $e');
            }
          }
          
          // 如果仍然没有字体，记录警告并提示用户
          if (chineseFont == null) {
            Log.error('❌ 无法加载中文字体，PDF 中的中文可能显示为占位符（如 X）');
            Log.error('建议：添加支持中文的 TTF 字体文件到 assets/fonts/ 目录');
            Log.error('或者确保系统中有 Arial Unicode.ttf 字体');
            // 显示错误提示给用户
            if (context.mounted) {
              _showError(
                context,
                '警告：无法加载中文字体，PDF 中的中文可能显示异常。请检查系统字体或联系技术支持。',
              );
            }
          } else {
            Log.info('✅ 中文字体加载成功，PDF 中文显示应该正常');
            // 将中文字体添加到fontFallback
            fontFallbackList.add(chineseFont);
          }
          
          // 尝试加载Emoji字体（macOS）
          if (Platform.isMacOS) {
            try {
              final emojiFontPaths = [
                '/System/Library/Fonts/Apple Color Emoji.ttc',
                '/System/Library/Fonts/Supplemental/Apple Color Emoji.ttc',
              ];
              
              for (final emojiPath in emojiFontPaths) {
                final emojiFile = File(emojiPath);
                if (await emojiFile.exists()) {
                  try {
                    final fontData = await emojiFile.readAsBytes();
                    // .ttc文件可能包含多个字体，尝试加载第一个
                    emojiFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                    fontFallbackList.add(emojiFont);
                    Log.info('✅ 成功加载Emoji字体: $emojiPath');
                    break;
                  } catch (e) {
                    Log.warn('⚠️ 加载Emoji字体失败 ($emojiPath): $e');
                  }
                }
              }
            } catch (e) {
              Log.warn('⚠️ 尝试加载Emoji字体时出错: $e');
            }
          }
          
          if (emojiFont == null) {
            Log.warn('⚠️ 无法加载Emoji字体，代码块中的emoji可能显示为方框');
            Log.warn('建议：确保系统中有 Apple Color Emoji 字体');
          } else {
            Log.info('✅ Emoji字体加载成功，代码块中的emoji应该正常显示');
          }

          // 使用 PdfHTMLEncoder 生成 PDF（支持完整的 Markdown 语法）
          // PdfHTMLEncoder 会自动处理图片、代码块、标题等所有 Markdown 语法
          Log.info('开始生成 PDF...');
          
          try {
            // 创建 PdfHTMLEncoderWrapper 实例（确保代码块被正确处理）
            // 使用包含emoji字体的fontFallback，确保代码块中的emoji能正常显示
            final pdfEncoder = PdfHTMLEncoderWrapper(
              font: chineseFont,
              fontFallback: fontFallbackList.isNotEmpty ? fontFallbackList : (chineseFont != null ? [chineseFont] : []),
            );
            
            // 添加文档标题到 Markdown 开头
            final markdownWithTitle = '# ${view.nameOrDefault}\n\n$markdown';
            
            // 调试：检查Markdown中代码块格式
            if (markdownWithTitle.contains('```')) {
              Log.info('🔍 检查Markdown代码块格式...');
              final codeBlockPattern = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
              final matches = codeBlockPattern.allMatches(markdownWithTitle);
              Log.info('  找到 ${matches.length} 个代码块（带语言标识）');
              
              // 检查没有语言标识的代码块
              final simpleCodeBlockPattern = RegExp(r'```\n([\s\S]*?)```');
              final simpleMatches = simpleCodeBlockPattern.allMatches(markdownWithTitle);
              Log.info('  找到 ${simpleMatches.length} 个代码块（无语言标识）');
              
              // 检查第一个代码块的内容
              if (simpleMatches.isNotEmpty) {
                final firstMatch = simpleMatches.first;
                final codeContent = firstMatch.group(1) ?? '';
                final preview = codeContent.length > 100 
                    ? '${codeContent.substring(0, 100)}...' 
                    : codeContent;
                Log.info('  第一个代码块内容预览: $preview');
                Log.info('  代码块内容长度: ${codeContent.length}');
              }
            }
            
            // 使用 PdfHTMLEncoder 转换 Markdown 为 PDF
            Log.info('🔍 开始调用 PdfHTMLEncoder.convert...');
            
            // 直接测试 Markdown 到 HTML 的转换，检查代码块是否被正确转换
            try {
              final testHtml = md.markdownToHtml(
                markdownWithTitle,
                extensionSet: md.ExtensionSet.gitHubFlavored,
              );
              Log.info('🔍 直接测试HTML转换: 长度=${testHtml.length}');
              final hasPre = testHtml.contains('<pre') || testHtml.contains('</pre>');
              final hasCode = testHtml.contains('<code') || testHtml.contains('</code>');
              Log.info('🔍 HTML转换结果: 包含pre标签=$hasPre, 包含code标签=$hasCode');
              
              if (hasPre) {
                final preMatches = RegExp(r'<pre[^>]*>[\s\S]*?</pre>', multiLine: true).allMatches(testHtml);
                Log.info('🔍 找到 ${preMatches.length} 个pre标签');
                if (preMatches.isNotEmpty) {
                  final firstPre = preMatches.first.group(0) ?? '';
                  final preview = firstPre.length > 500 ? '${firstPre.substring(0, 500)}...' : firstPre;
                  Log.info('🔍 第一个pre标签预览: $preview');
                }
              } else {
                Log.error('❌ HTML转换后没有pre标签！');
                // 输出HTML的前2000个字符用于调试
                final htmlPreview = testHtml.length > 2000 ? '${testHtml.substring(0, 2000)}...' : testHtml;
                Log.error('❌ HTML预览: $htmlPreview');
              }
            } catch (e) {
              Log.error('❌ 测试HTML转换失败: $e');
            }
            
            final pdf = await pdfEncoder.convert(markdownWithTitle);
            Log.info('✅ PdfHTMLEncoder.convert 完成');
            
            Log.info('PDF 生成成功');

            Log.info('开始保存 PDF 字节...');
            final pdfBytes = await pdf.save();
            Log.info('PDF 保存完成，大小: ${pdfBytes.length} 字节');
            Log.info('PDF 生成成功，大小: ${pdfBytes.length} 字节');
            
            final fileName = '${view.nameOrDefault}.pdf';
            final filePicker = GetIt.instance<FilePickerService>();
            
            // 对于 PDF，我们需要先获取保存路径，然后写入文件
            // 注意：FilePickerService 的 saveFile 在某些平台上可能需要 bytes 参数
            // 这里我们使用反射或者直接调用实现类的方法
            final savePath = await _saveFileWithBytes(
              filePicker,
              dialogTitle: '保存 PDF 文件',
              fileName: fileName,
              bytes: Uint8List.fromList(pdfBytes),
            );

            if (savePath != null) {
              Log.info('PDF 文件已保存到: $savePath');
              // 验证文件是否真的保存成功
              final file = File(savePath);
              if (await file.exists()) {
                final fileSize = await file.length();
                Log.info('PDF 文件验证成功，文件大小: $fileSize 字节');
                if (context.mounted) {
                  _showSuccess(context, 'PDF 文件已保存');
                }
              } else {
                Log.error('PDF 文件保存失败：文件不存在');
                if (context.mounted) {
                  _showError(context, 'PDF 文件保存失败：文件不存在');
                }
              }
            } else {
              Log.error('PDF 文件保存失败：用户取消了保存或保存路径为空');
              // 不显示错误，因为用户可能只是取消了保存
            }
          } catch (e) {
            Log.error('生成 PDF 时出错: $e');
            if (context.mounted) {
              _showError(context, 'PDF 生成失败：$e');
            }
          }
        },
        (error) {
          Log.error('导出 PDF 失败: ${error.msg}');
          if (context.mounted) {
            _showError(context, '导出失败：${error.msg}');
          }
        },
      );
    } catch (e) {
      Log.error('导出 PDF 异常: $e');
      if (context.mounted) {
        _showError(context, '导出失败：$e');
      }
    }
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 检查文档中是否包含表格
  Future<bool> _hasTableInDocument() async {
    try {
      final documentService = DocumentService();
      final result = await documentService.openDocument(documentId: view.id);
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
    try {
      final documentService = DocumentService();
      final result = await documentService.openDocument(documentId: view.id);

      await result.fold(
        (documentData) async {
          final document = documentData.toDocument();
          if (document == null) {
            Log.error('导出 CSV 失败：无法获取文档');
            if (context.mounted) {
              _showError(context, '导出失败：无法获取文档内容');
            }
            return;
          }

          // 查找所有表格节点
          final tableNodes = _findTableNodes(document.root);
          if (tableNodes.isEmpty) {
            Log.error('导出 CSV 失败：文档中没有表格');
            if (context.mounted) {
              _showError(context, '导出失败：文档中没有表格');
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
              _showError(context, '导出失败：表格内容为空');
            }
            return;
          }

          final fileName = '${view.nameOrDefault}_表格.csv';
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
              _showSuccess(context, 'CSV 文件已保存');
            }
          }
        },
        (error) {
          Log.error('导出 CSV 失败: ${error.msg}');
          if (context.mounted) {
            _showError(context, '导出失败：${error.msg}');
          }
        },
      );
    } catch (e) {
      Log.error('导出 CSV 异常: $e');
      if (context.mounted) {
        _showError(context, '导出失败：$e');
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

