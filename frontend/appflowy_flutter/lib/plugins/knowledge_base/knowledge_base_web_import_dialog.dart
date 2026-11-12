import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class KnowledgeBaseWebImportDialog extends StatefulWidget {
  const KnowledgeBaseWebImportDialog({
    super.key,
    required this.base,
    required this.service,
  });

  final KnowledgeBase base;
  final KnowledgeBaseService service;

  @override
  State<KnowledgeBaseWebImportDialog> createState() =>
      _KnowledgeBaseWebImportDialogState();
}

class _KnowledgeBaseWebImportDialogState
    extends State<KnowledgeBaseWebImportDialog> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _chunkSize = TextEditingController();
  final _chunkOverlap = TextEditingController();
  String? _confirmedUrl;
  String? _error;
  String _strategy = 'auto';
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _chunkSize.dispose();
    _chunkOverlap.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_confirmedUrl == null) {
        final options = await widget.service.post(
          'web_import_options',
          widget.base.target,
        );
        if (!mounted) return;
        setState(() {
          _chunkSize.text = '${options['chunk_size']}';
          _chunkOverlap.text = '${options['chunk_overlap']}';
          _strategy = options['strategy'] as String;
          _confirmedUrl = _url.text.trim();
        });
      } else {
        await widget.service.post('import_url', {
          ...widget.base.target,
          'url': _confirmedUrl,
          'chunk_size': int.parse(_chunkSize.text),
          'chunk_overlap': int.parse(_chunkOverlap.text),
          'strategy': _strategy,
        });
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = kbError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final parsing = _confirmedUrl != null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(3),
      borderSide: BorderSide(color: theme.borderColorScheme.primary),
    );
    final decoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border,
      enabledBorder: border,
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: theme.surfaceColorScheme.layer01,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        titlePadding: const EdgeInsets.fromLTRB(32, 20, 20, 12),
        contentPadding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
        actionsPadding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
        title: Row(
          children: [
            Expanded(
              child: Text(
                parsing
                    ? kbText(context, '上传文档确认', 'Confirm document upload')
                    : kbText(context, '导入网页', 'Import web page'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: kbText(context, '关闭', 'Close'),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: parsing ? 640 : 436,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!parsing) ...[
                    Text(kbText(context, 'URL地址', 'URL address')),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _url,
                      autofocus: true,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 13),
                      decoration: decoration.copyWith(
                        suffixIconConstraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        hintText: kbText(
                          context,
                          '请输入网页URL，例如：https://example.com',
                          'Enter a web page URL, e.g. https://example.com',
                        ),
                        suffixIcon: IconButton(
                          tooltip: kbText(context, '清空', 'Clear'),
                          onPressed: _busy ? null : _url.clear,
                          icon: const Icon(Icons.close, size: 14),
                        ),
                      ),
                      validator: (value) {
                        final url = value?.trim() ?? '';
                        final uri = Uri.tryParse(url);
                        return uri != null &&
                                (uri.scheme == 'http' ||
                                    uri.scheme == 'https') &&
                                uri.host.isNotEmpty &&
                                uri.userInfo.isEmpty &&
                                url.length <= 2048 &&
                                !RegExp(r'\s').hasMatch(url)
                            ? null
                            : kbText(
                                context,
                                '请输入有效的 HTTP 或 HTTPS 网页地址',
                                'Enter a valid HTTP or HTTPS web page URL',
                              );
                      },
                      onFieldSubmitted: (_) => _confirm(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kbText(
                        context,
                        '支持导入各类网页内容，系统会自动提取和解析网页中的文本内容',
                        'Import web pages and automatically extract and parse their text.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textColorScheme.tertiary,
                      ),
                    ),
                  ] else ...[
                    Text(widget.base.name),
                    const SizedBox(height: 8),
                    SelectableText(_confirmedUrl!),
                    const Divider(height: 32),
                    Text(
                      kbText(context, '文档拆分', 'Document splitting'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _strategy,
                      decoration: decoration.copyWith(
                        labelText:
                            kbText(context, '拆分策略', 'Splitting strategy'),
                      ),
                      items: [
                        for (final (value, zh, en) in const [
                          ('auto', '自动拆分（推荐）', 'Automatic (recommended)'),
                          ('heading', '按标题拆分', 'By heading'),
                          ('heuristic', '智能段落拆分', 'By paragraph'),
                          ('recursive', '递归拆分', 'Recursive'),
                          ('legacy', '传统拆分', 'Legacy'),
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(kbText(context, zh, en)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _strategy = value!),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _chunkSize,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: decoration.copyWith(
                        labelText: kbText(
                          context,
                          '分块大小（字符）',
                          'Chunk size (characters)',
                        ),
                      ),
                      validator: (value) {
                        final size = int.tryParse(value ?? '');
                        return size != null && size >= 100 && size <= 4000
                            ? null
                            : kbText(
                                context,
                                '请输入 100–4000 的整数',
                                'Enter an integer from 100 to 4000',
                              );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _chunkOverlap,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: decoration.copyWith(
                        labelText: kbText(
                          context,
                          '分块重叠（字符）',
                          'Chunk overlap (characters)',
                        ),
                      ),
                      validator: (value) {
                        final overlap = int.tryParse(value ?? '');
                        final size = int.tryParse(_chunkSize.text) ?? 0;
                        return overlap != null &&
                                overlap >= 0 &&
                                overlap <= 500 &&
                                overlap < size
                            ? null
                            : kbText(
                                context,
                                '请输入 0–500 且小于分块大小的整数',
                                'Enter an integer from 0 to 500, smaller than the chunk size',
                              );
                      },
                      onFieldSubmitted: (_) => _confirm(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.textColorScheme.primary,
              backgroundColor: theme.fillColorScheme.contentHover,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(kbText(context, '取消', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF07C05F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            onPressed: _busy ? null : _confirm,
            child: Text(
              _busy
                  ? kbText(context, '处理中…', 'Processing…')
                  : parsing
                      ? kbText(context, '确认上传并解析', 'Upload and parse')
                      : kbText(context, '确认', 'Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}
