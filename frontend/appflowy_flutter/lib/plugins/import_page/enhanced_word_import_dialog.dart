import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:file_picker/file_picker.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:path/path.dart' as p;
import 'package:markdown_widget/markdown_widget.dart';
import 'processor/aliyun_doc_parse_processor.dart';

/// 增强的Word导入对话框，提供实时预览和解析状态
class EnhancedWordImportDialog extends StatefulWidget {
  final String parentViewId;
  final VoidCallback? onImportSuccess;

  const EnhancedWordImportDialog({
    super.key,
    required this.parentViewId,
    this.onImportSuccess,
  });

  @override
  State<EnhancedWordImportDialog> createState() => _EnhancedWordImportDialogState();
}

class _EnhancedWordImportDialogState extends State<EnhancedWordImportDialog> {
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
        const Icon(Icons.description, size: 32, color: Colors.blue),
        const SizedBox(width: 12),
        const Text(
          '智能Word导入',
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
      child: _selectedFile == null
          ? Row(
              children: [
                const Icon(Icons.insert_drive_file, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _selectFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择Word文件 (.docx, .doc)'),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                const Icon(Icons.description, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFile!.path.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: _selectFile,
                  child: const Text('更换文件'),
                ),
              ],
            ),
    );
  }

  Widget _buildProcessButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _selectedFile != null && !_isProcessing ? _processFile : null,
        icon: _isProcessing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: Text(_isProcessing ? '解析中...' : '开始解析'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildContentPreview() {
    if (_processingError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          border: Border.all(color: Colors.red[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    '解析失败',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_processingError!),
            ],
          ),
        ),
      );
    }

    if (_extractedContent == null || _extractedContent!.isEmpty) {
      String message = '选择文件并点击"开始解析"来预览提取的内容';
      if (_isProcessing) {
        message = '正在解析中，请稍候...';
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isProcessing ? Icons.hourglass_empty : Icons.preview,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.preview, size: 20),
            const SizedBox(width: 8),
            const Text(
              '解析结果预览',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_extractedContent != null && _extractedContent!.isNotEmpty)
              Text(
                '${_extractedContent!.length} 字符',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: MarkdownWidget(
                data: _extractedContent!,
                shrinkWrap: true,
                selectable: true,
              ),
            ),
          ),
        ),
      ],
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
      Log.info('Word处理任务已取消');
    }
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx', 'doc'],
        withData: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        
        // 检查文件大小（使用阿里云API限制：20MB）
        final fileSize = await file.length();
        if (!AliyunDocParseProcessor.isFileSizeValid(fileSize)) {
          final fileSizeStr = _formatFileSize(fileSize);
          final maxSizeStr = _formatFileSize(AliyunDocParseProcessor.maxFileSize);
          showToastNotification(
            message: '文件大小超过限制（最大$maxSizeStr），当前文件大小：$fileSizeStr。请压缩文件或使用较小的文件。',
            type: ToastificationType.error,
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
      Log.error('Failed to select Word file: $e');
      showToastNotification(
        message: '选择文件失败: $e',
        type: ToastificationType.error,
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

  Future<void> _processFile() async {
    if (_selectedFile == null) return;

    // 创建新的取消令牌
    _cancellationToken = CancellationToken();
    
    setState(() {
      _isProcessing = true;
      _processingError = null;
      _extractedContent = null; // 重置提取内容
    });

    try {
      String content;
      
      // 使用阿里云API处理Word文件
      content = await AliyunDocParseProcessor.processWordFile(
        _selectedFile!,
        cancellationToken: _cancellationToken,
      );

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

      // 验证内容不为空
      if (content.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _processingError = '提取的内容为空，请检查Word文件是否包含文本内容';
          });
        }
        return;
      }

      // 更新UI
      if (mounted) {
        setState(() {
          _extractedContent = content;
          _isProcessing = false;
        });
      }
    } catch (e) {
      Log.error('Word处理失败: $e');
      if (mounted) {
        // 检查是否已取消
        if (_cancellationToken?.isCancelled ?? false) {
          setState(() {
            _isProcessing = false;
            _processingError = '处理已取消';
          });
        } else {
          _processingError = 'Word处理失败: $e';
          _isProcessing = false;
        }
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
              showToastNotification(
                message: 'Word文件导入成功',
                type: ToastificationType.success,
              );
            }
          },
          (error) {
            if (mounted) {
              showToastNotification(
                message: '导入失败: $error',
                type: ToastificationType.error,
              );
            }
          },
        );
      }
    } catch (e) {
      Log.error('Failed to import Word document: $e');
      if (mounted) {
        showToastNotification(
          message: '导入失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }
}

