import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pdf_text_extraction_service.dart';
import '../../../../../util/log_utils.dart';

/// PDF文本选择对话框
/// 用于显示PDF页面提取的文本，允许用户选择和复制
class PdfTextSelectionDialog extends StatefulWidget {
  const PdfTextSelectionDialog({
    super.key,
    required this.pdfFilePath,
    required this.pageIndex,
  });

  final String pdfFilePath;
  final int pageIndex; // PDF页面索引（从0开始）

  static Future<void> show({
    required BuildContext context,
    required String pdfFilePath,
    required int pageIndex,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => PdfTextSelectionDialog(
        pdfFilePath: pdfFilePath,
        pageIndex: pageIndex,
      ),
    );
  }

  @override
  State<PdfTextSelectionDialog> createState() => _PdfTextSelectionDialogState();
}

class _PdfTextSelectionDialogState extends State<PdfTextSelectionDialog> {
  String _extractedText = '';
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _extractText();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _extractText() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final text = await PdfTextExtractionService.extractPageTextFromFile(
        widget.pdfFilePath,
        widget.pageIndex,
      );

      setState(() {
        _extractedText = text;
        _textController.text = text;
        _isLoading = false;
      });
    } catch (e) {
      LogUtils.error('提取PDF文本失败: $e');
      setState(() {
        _errorMessage = '提取文本失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _copyToClipboard() async {
    final selection = _textController.selection;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? _textController.text.substring(selection.start, selection.end)
        : '';
    final textToCopy = selectedText.isNotEmpty ? selectedText : _extractedText;

    if (textToCopy.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可复制的文本')),
        );
      }
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: textToCopy));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制 ${textToCopy.length} 个字符到剪贴板'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      LogUtils.error('复制到剪贴板失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  Future<void> _copyAllToClipboard() async {
    if (_extractedText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可复制的文本')),
        );
      }
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: _extractedText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制全部文本（${_extractedText.length} 个字符）到剪贴板'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      LogUtils.error('复制到剪贴板失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Row(
              children: [
                const Text(
                  'PDF文本提取',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '页面 ${widget.pageIndex + 1}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 16),
            // 工具栏
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _copyAllToClipboard,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制全部'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _copyToClipboard,
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('复制选中'),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _extractText,
                  tooltip: '重新提取',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 文本内容区域
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在提取文本...'),
                          ],
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _extractText,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          )
                        : _extractedText.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.text_fields,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '该页面没有可提取的文本',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : TextField(
                                controller: _textController,
                                maxLines: null,
                                expands: true,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(12),
                                  hintText: '提取的文本将显示在这里...',
                                ),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                                textAlignVertical: TextAlignVertical.top,
                              ),
              ),
            ),
            const SizedBox(height: 16),
            // 底部信息
            if (!_isLoading && _extractedText.isNotEmpty)
              Text(
                '文本长度: ${_extractedText.length} 个字符',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

