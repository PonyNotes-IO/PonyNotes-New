import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// 插入网页对话框
class InsertWebViewDialog extends StatefulWidget {
  const InsertWebViewDialog({super.key});

  @override
  State<InsertWebViewDialog> createState() => _InsertWebViewDialogState();
}

class _InsertWebViewDialogState extends State<InsertWebViewDialog> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  bool _isInteractive = true;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final url = _urlController.text.trim();
    
    if (url.isEmpty) {
      setState(() {
        _errorMessage = '请输入网页URL';
      });
      return;
    }

    // 简单的URL验证
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() {
        _errorMessage = 'URL必须以http://或https://开头';
      });
      return;
    }

    // 返回结果
    Navigator.of(context).pop(WebViewInsertResult(
      url: url,
      title: _titleController.text.trim().isEmpty 
          ? null 
          : _titleController.text.trim(),
      isInteractive: _isInteractive,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    
    return AlertDialog(
      backgroundColor: theme.surfaceColorScheme.layer01,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      title: Row(
        children: [
          const Icon(Icons.language, size: 24),
          const SizedBox(width: 8),
          Text(
            '插入网页',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // URL输入框
            Text(
              'URL地址 *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://example.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
              onSubmitted: (_) => _validateAndSubmit(),
            ),
            
            const SizedBox(height: 16),
            
            // 标题输入框(可选)
            Text(
              '标题 (可选)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '网页标题',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _validateAndSubmit(),
            ),
            
            const SizedBox(height: 16),
            
            // 交互模式开关
            Row(
              children: [
                Checkbox(
                  value: _isInteractive,
                  onChanged: (value) {
                    setState(() {
                      _isInteractive = value ?? true;
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '允许交互',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.textColorScheme.primary,
                        ),
                      ),
                      Text(
                        '允许在网页中滚动和点击链接',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textColorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '网页内容将自动缓存,支持离线查看。你可以随时刷新缓存以获取最新内容。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _validateAndSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('插入'),
        ),
      ],
    );
  }
}

/// 网页插入结果
class WebViewInsertResult {
  final String url;
  final String? title;
  final bool isInteractive;

  const WebViewInsertResult({
    required this.url,
    this.title,
    this.isInteractive = true,
  });
}

/// 显示插入网页对话框
Future<WebViewInsertResult?> showInsertWebViewDialog(BuildContext context) {
  return showDialog<WebViewInsertResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) => const InsertWebViewDialog(),
  );
}





