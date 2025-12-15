import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:path/path.dart' as p;
import 'package:markdown_widget/markdown_widget.dart';
import 'aliyun_doc_parse_processor.dart' show CancellationToken;
import 'professional_html_parser.dart';

/// 增强的HTML导入对话框，使用阿里云解析
class EnhancedHtmlImportDialog extends StatefulWidget {
  final String parentViewId;
  final VoidCallback? onImportSuccess;

  const EnhancedHtmlImportDialog({
    super.key,
    required this.parentViewId,
    this.onImportSuccess,
  });

  @override
  State<EnhancedHtmlImportDialog> createState() => _EnhancedHtmlImportDialogState();
}

class _EnhancedHtmlImportDialogState extends State<EnhancedHtmlImportDialog> {
  static const int _maxFileSize = 50 * 1024 * 1024; // 50MB，本地解析限制

  File? _selectedFile;
  String? _extractedContent;
  String? _processingError;
  bool _isProcessing = false;
  CancellationToken? _cancellationToken;

  @override
  void dispose() {
    // 清理资源：取消正在进行的任务
    _cancelProcessing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double dialogMaxWidth = 900;
    final double dialogMaxHeight = 700;
    final double dialogWidth = screenSize.width * 0.9 > dialogMaxWidth
        ? dialogMaxWidth
        : screenSize.width * 0.9;
    final double dialogHeight = screenSize.height * 0.9 > dialogMaxHeight
        ? dialogMaxHeight
        : screenSize.height * 0.9;

    return Dialog(
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFileSelector(),
            const SizedBox(height: 16),
            if (_selectedFile != null) ...[
              _buildProcessButton(),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: _buildContentPreview(),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.language, size: 32, color: Colors.blue),
        const SizedBox(width: 12),
        const Text(
          '智能HTML导入',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {
            _cancelProcessing();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _buildFileSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                '选择HTML文件',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _selectFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('选择文件'),
              ),
            ],
          ),
          if (_selectedFile != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(_selectedFile!.path),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<int>(
                          future: _selectedFile!.length(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              final size = snapshot.data!;
                              final sizeStr = _formatFileSize(size);
                              return Text(
                                '文件大小: $sizeStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            setState(() {
                              _selectedFile = null;
                              _extractedContent = null;
                              _processingError = null;
                            });
                          },
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProcessButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isProcessing ? null : _processFile,
        icon: _isProcessing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow),
        label: Text(_isProcessing ? '解析中...' : '开始解析'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildContentPreview() {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('正在解析HTML文件...'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancelProcessing,
              child: const Text('取消'),
            ),
          ],
        ),
      );
    }

    if (_processingError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                const Text(
                  '解析失败',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _processingError!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    }

    if (_extractedContent != null && _extractedContent!.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.preview, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '解析预览',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_extractedContent!.length} 字符',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MarkdownWidget(
                  data: _extractedContent!,
                  shrinkWrap: true,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '请选择HTML文件开始解析',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () {
            _cancelProcessing();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _extractedContent != null && _extractedContent!.isNotEmpty && !_isProcessing
              ? _importDocument
              : null,
          child: const Text('导入'),
        ),
      ],
    );
  }

  /// Cancel current processing task
  void _cancelProcessing() {
    if (_isProcessing && _cancellationToken != null) {
      _cancellationToken!.cancel();
      setState(() {
        _isProcessing = false;
        _processingError = '处理已取消';
      });
      Log.info('HTML处理任务已取消');
    }
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
        withData: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        
        // 检查文件大小（本地解析限制：50MB）
        final fileSize = await file.length();
        if (!_isFileSizeValid(fileSize)) {
          final fileSizeStr = _formatFileSize(fileSize);
          final maxSizeStr = _formatFileSize(_maxFileSize);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('文件大小超过限制（最大$maxSizeStr），当前文件大小：$fileSizeStr。请压缩文件或使用较小的文件。'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
        
        setState(() {
          _selectedFile = file;
          _extractedContent = null;
          _processingError = null;
        });
      }
    } catch (e) {
      Log.error('Failed to select HTML file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  bool _isFileSizeValid(int fileSizeInBytes) {
    return fileSizeInBytes <= _maxFileSize;
  }

  Future<void> _processFile() async {
    if (_selectedFile == null) return;

    // 创建取消令牌
    _cancellationToken = CancellationToken();

    setState(() {
      _isProcessing = true;
      _processingError = null;
      _extractedContent = null; // 重置提取内容
    });

    try {
      String content;
      
      // 本地解析HTML -> Markdown（不经过阿里云）
      content = await _processLocalHtml(_selectedFile!, _cancellationToken);

      // 检查是否已取消
      if (_cancellationToken?.isCancelled ?? false) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _processingError = '处理已取消';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _extractedContent = content;
          _processingError = null;
        });
      }

      Log.info('HTML解析完成，内容长度: ${content.length}');
    } catch (e) {
      Log.error('HTML解析失败: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingError = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      _cancellationToken = null;
    }
  }

  Future<String> _processLocalHtml(File htmlFile, CancellationToken? token) async {
    if (token?.isCancelled ?? false) {
      throw Exception('处理已取消');
    }

    // 读取并解码 HTML 文件
    final bytes = await htmlFile.readAsBytes();
    final htmlString = _decodeHtmlBytes(bytes);

    if (token?.isCancelled ?? false) {
      throw Exception('处理已取消');
    }

    final fileName = p.basename(htmlFile.path);
    // 使用本地解析器转换为 Markdown
    final markdown = ProfessionalHtmlParser.convertHtmlToMarkdown(htmlString, fileName);
    return markdown;
  }

  String _decodeHtmlBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return latin1.decode(bytes);
      } catch (e) {
        Log.warn('HTML 字节解码失败，返回空字符串: $e');
        return '';
      }
    }
  }

  Future<void> _importDocument() async {
    if (_extractedContent == null || _extractedContent!.isEmpty) return;

    try {
      // 将Markdown转换为Document格式
      final document = customMarkdownToDocument(_extractedContent!);
      final documentBytes = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();

      if (documentBytes != null) {
        // 导入到指定视图
        final importResult = await ImportBackendService.importPages(
          widget.parentViewId,
          [
            ImportItemPayloadPB.create()
              ..name = p.basenameWithoutExtension(_selectedFile!.path)
              ..data = documentBytes
              ..viewLayout = ViewLayoutPB.Document
              ..importType = ImportTypePB.Markdown,
          ],
        );

        importResult.fold(
          (views) {
            if (mounted) {
              Navigator.of(context).pop();
              if (widget.onImportSuccess != null) {
                widget.onImportSuccess!();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('HTML文件导入成功'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          (error) {
            Log.error('导入HTML文档失败: $error');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('导入失败: $error'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        );
      } else {
        throw Exception('无法转换Markdown为文档格式');
      }
    } catch (e) {
      Log.error('导入HTML文档失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

