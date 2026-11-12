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

enum _Section {
  tags('文档标签', 'Document tags', Icons.sell_outlined),
  parser('解析引擎', 'Parser engine', Icons.find_in_page_outlined),
  chunks('分块设置', 'Chunk settings', Icons.content_copy_outlined),
  images('图像处理', 'Image processing', Icons.image_outlined),
  audio('音频处理', 'Audio processing', Icons.volume_up_outlined),
  summary('文档摘要', 'Document summary', Icons.description_outlined),
  questions('AI 问题生成', 'AI question generation', Icons.chat_bubble_outline);

  const _Section(this.zh, this.en, this.icon);
  final String zh;
  final String en;
  final IconData icon;
  String label(BuildContext context) => kbText(context, zh, en);
}

class _KnowledgeBaseWebImportDialogState
    extends State<KnowledgeBaseWebImportDialog> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _numbers = <String, TextEditingController>{
    for (final name in [
      'chunk_size',
      'chunk_overlap',
      'parent_chunk_size',
      'child_chunk_size',
      'question_count',
    ])
      name: TextEditingController(),
  };
  final _tags = <String>{};
  Map<String, dynamic> _options = {};
  Map<String, dynamic> _process = {};
  _Section _section = _Section.tags;
  String? _confirmedUrl;
  String? _error;
  bool _busy = false;
  Map<String, dynamic> get _chunk => group('chunking_config');
  Map<String, dynamic> group(String name) =>
      _process[name] as Map<String, dynamic>;
  List<Map<String, dynamic>> items(String name) =>
      (_options[name] as List).cast<Map<String, dynamic>>();
  String text(String zh, String en) => kbText(context, zh, en);

  @override
  void dispose() {
    _url.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_confirmedUrl != null && !_validateNumbers()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_confirmedUrl == null) {
        final options =
            await widget.service.post('web_import_options', widget.base.target);
        if (!mounted) return;
        if (options['version'] != 2) {
          throw const KnowledgeBaseException(404, action: 'web_import_options');
        }
        setState(() {
          _options = options;
          _process = options['process_config'] as Map<String, dynamic>;
          for (final entry in _numbers.entries) {
            entry.value.text =
                '${entry.key == 'question_count' ? group('question_generation_config')[entry.key] : _chunk[entry.key]}';
          }
          _tags.clear();
          _section = _Section.tags;
          _confirmedUrl = _url.text.trim();
        });
      } else {
        for (final entry in _numbers.entries) {
          final target = entry.key == 'question_count'
              ? group('question_generation_config')
              : _chunk;
          target[entry.key] = int.parse(entry.value.text);
        }
        await widget.service.post('import_url', {
          ...widget.base.target,
          'url': _confirmedUrl,
          'tag_ids': _tags.toList(),
          'process_config': _process,
        });
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = kbError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validateNumbers() {
    for (final (name, min, max) in [
      ('chunk_size', 100, 4000),
      ('chunk_overlap', 0, 500),
      ('parent_chunk_size', 100, 20000),
      ('child_chunk_size', 100, 4000),
      ('question_count', 1, 10),
    ]) {
      final value = int.tryParse(_numbers[name]!.text);
      if (value == null || value < min || value > max) {
        setState(() {
          _section =
              name == 'question_count' ? _Section.questions : _Section.chunks;
          _error = text(
            '请检查${_section.label(context)}：请输入 $min–$max 的整数。',
            'Check ${_section.label(context)}: enter an integer from $min to $max.',
          );
        });
        return false;
      }
    }
    if (int.parse(_numbers['chunk_overlap']!.text) >=
            int.parse(_numbers['chunk_size']!.text) ||
        int.parse(_numbers['child_chunk_size']!.text) >
            int.parse(_numbers['parent_chunk_size']!.text)) {
      setState(() {
        _section = _Section.chunks;
        _error = text(
          '重叠必须小于分块大小，子块不能大于父块。',
          'Overlap must be smaller than the chunk; children cannot exceed the parent.',
        );
      });
      return false;
    }
    for (final name in ['vlm_config', 'asr_config']) {
      if (group(name)['enabled'] == true && group(name)['model_id'] == '') {
        setState(() {
          _section = name == 'vlm_config' ? _Section.images : _Section.audio;
          _error = text(
            '请选择${_section.label(context)}模型。',
            'Select a model for ${_section.label(context)}.',
          );
        });
        return false;
      }
    }
    return true;
  }

  InputDecoration decoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      );
  Widget number(String name, String zh, String en) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: TextFormField(
          key: ValueKey(name),
          controller: _numbers[name],
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: decoration(text(zh, en)),
        ),
      );
  Widget instructions(
    String name,
    String field,
    String zh,
    String en, {
    int maxLength = 1000,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(
          key: ValueKey('$name-$field'),
          initialValue: group(name)[field] as String,
          enabled: !_busy,
          maxLength: maxLength,
          minLines: 1,
          maxLines: 3,
          decoration: decoration(text(zh, en)),
          onChanged: (value) => group(name)[field] = value,
        ),
      );
  Widget toggle(
    String zh,
    String en,
    bool value,
    ValueChanged<bool>? changed,
  ) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(text(zh, en)),
        value: value,
        onChanged: _busy ? null : changed,
      );
  Widget model(String name, String kind) {
    final models = items('models').where((m) => m['type'] == kind).toList();
    if (models.isEmpty) {
      return Text(
        text(
          '当前没有可用模型，请联系管理员配置后使用。',
          'No model is available. Ask your administrator to configure one.',
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('$name-model'),
      isExpanded: true,
      initialValue: group(name)['model_id'] == ''
          ? null
          : group(name)['model_id'] as String,
      decoration: decoration(text('模型', 'Model')),
      items: [
        for (final m in models)
          DropdownMenuItem(
            value: m['id'] as String,
            child: Text(m['name'] as String, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy
          ? null
          : (value) => setState(() => group(name)['model_id'] = value),
    );
  }

  String status(_Section section) => switch (section) {
        _Section.tags => _tags.isEmpty
            ? text('未设置', 'None')
            : text('已选 ${_tags.length} 个', '${_tags.length} selected'),
        _Section.parser =>
          (_process['parser_engine_rules'] as List).first['engine'] == ''
              ? text('默认', 'Default')
              : (_process['parser_engine_rules'] as List).first['engine']
                  as String,
        _Section.chunks =>
          '${_numbers['chunk_size']!.text} · ${_chunk['enable_parent_child'] == true ? text('父子分块', 'Parent-child') : text('普通分块', 'Standard')}',
        _Section.images => group('vlm_config')['enabled'] == true
            ? text('已开启', 'On')
            : text('未开启', 'Off'),
        _Section.audio => group('asr_config')['enabled'] == true
            ? text('已开启', 'On')
            : text('未开启', 'Off'),
        _Section.summary => _process['summary_enabled'] == true
            ? text('已开启', 'On')
            : text('未开启', 'Off'),
        _Section.questions =>
          group('question_generation_config')['enabled'] == true
              ? text(
                  '${_numbers['question_count']!.text} 个',
                  '${_numbers['question_count']!.text} questions',
                )
              : text('未开启', 'Off'),
      };

  List<Widget> sectionFields() {
    switch (_section) {
      case _Section.tags:
        return [
          Text(
            text(
              '为本次导入的网页选择标签，可多选。',
              'Choose tags for this web page (optional).',
            ),
          ),
          const SizedBox(height: 16),
          if (items('tags').isEmpty)
            Text(text('此知识库暂无标签。', 'This knowledge base has no tags.')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in items('tags'))
                FilterChip(
                  label: Text(tag['name'] as String),
                  selected: _tags.contains(tag['id']),
                  onSelected: _busy
                      ? null
                      : (selected) => setState(() {
                            if (selected) {
                              _tags.add(tag['id'] as String);
                            } else {
                              _tags.remove(tag['id']);
                            }
                          }),
                ),
            ],
          ),
        ];
      case _Section.parser:
        return [
          Text(text('选择本次网页使用的解析引擎。', 'Choose the parser for this web page.')),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: (_process['parser_engine_rules'] as List)
                .first['engine'] as String,
            isExpanded: true,
            decoration: decoration(text('网页解析引擎', 'Web page parser')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(text('默认引擎', 'Default parser')),
              ),
              for (final engine in items('engines'))
                DropdownMenuItem(
                  value: engine['id'] as String,
                  child: Text(engine['name'] as String),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(
                      () => (_process['parser_engine_rules'] as List)
                          .first['engine'] = value,
                    ),
          ),
        ];
      case _Section.chunks:
        return [
          DropdownButtonFormField<String>(
            initialValue: _chunk['strategy'] as String,
            decoration: decoration(text('拆分策略', 'Splitting strategy')),
            items: [
              for (final (value, zh, en) in const [
                ('auto', '自动拆分（推荐）', 'Automatic (recommended)'),
                ('heading', '按标题拆分', 'By heading'),
                ('heuristic', '智能段落拆分', 'By paragraph'),
                ('recursive', '递归拆分', 'Recursive'),
                ('legacy', '传统拆分', 'Legacy'),
              ])
                DropdownMenuItem(value: value, child: Text(text(zh, en))),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _chunk['strategy'] = value),
          ),
          const SizedBox(height: 20),
          number('chunk_size', '分块大小（字符）', 'Chunk size (characters)'),
          number('chunk_overlap', '分块重叠（字符）', 'Chunk overlap (characters)'),
          toggle(
            '父子分块',
            'Parent-child chunks',
            _chunk['enable_parent_child'] == true,
            (value) => setState(() => _chunk['enable_parent_child'] = value),
          ),
          if (_chunk['enable_parent_child'] == true) ...[
            number('parent_chunk_size', '父块大小（字符）', 'Parent size (characters)'),
            number('child_chunk_size', '子块大小（字符）', 'Child size (characters)'),
          ],
        ];
      case _Section.images:
      case _Section.audio:
        final image = _section == _Section.images;
        final name = image ? 'vlm_config' : 'asr_config';
        final kind = image ? 'VLLM' : 'ASR';
        final available = items('models').any((m) => m['type'] == kind);
        return [
          Text(
            image
                ? text(
                    '识别网页中的图片内容并生成描述。',
                    'Read images in the web page and generate descriptions.',
                  )
                : text(
                    '对支持的音频来源进行语音识别；普通网页正文不需要开启。',
                    'Transcribe supported audio sources. Plain web text does not require this.',
                  ),
          ),
          toggle(
            image ? '启用图像处理' : '启用音频处理',
            image ? 'Enable image processing' : 'Enable audio processing',
            group(name)['enabled'] == true,
            available
                ? (value) => setState(() {
                      group(name)['enabled'] = value;
                      if (image) _process['enable_multimodel'] = value;
                    })
                : null,
          ),
          if (!available || group(name)['enabled'] == true) model(name, kind),
          if (group(name)['enabled'] == true) ...[
            instructions(
              name,
              image ? 'description_language' : 'language',
              '语言（可选，如 zh、en）',
              'Language (optional, e.g. zh, en)',
              maxLength: 32,
            ),
            if (image)
              instructions(
                name,
                'custom_instructions',
                '图像处理要求（可选）',
                'Image instructions (optional)',
              ),
          ],
        ];
      case _Section.summary:
        return [
          Text(text('解析后生成文档摘要。', 'Generate a summary after parsing.')),
          toggle(
            '生成文档摘要',
            'Generate document summary',
            _process['summary_enabled'] == true,
            _options['summary_available'] == true
                ? (value) => setState(() => _process['summary_enabled'] = value)
                : null,
          ),
          if (_options['summary_available'] != true)
            Text(
              text(
                '当前知识库未配置摘要模型。',
                'No summary model is configured for this knowledge base.',
              ),
            ),
        ];
      case _Section.questions:
        final config = group('question_generation_config');
        return [
          Text(
            text(
              '为每个分块生成检索问题，改善问答召回。',
              'Generate questions for each chunk to improve retrieval.',
            ),
          ),
          toggle(
            '生成 AI 问题',
            'Generate AI questions',
            config['enabled'] == true,
            _options['summary_available'] == true
                ? (value) => setState(() => config['enabled'] = value)
                : null,
          ),
          if (_options['summary_available'] != true)
            Text(
              text(
                '当前知识库未配置问答生成模型。',
                'No question generation model is configured.',
              ),
            ),
          if (config['enabled'] == true) ...[
            number(
              'question_count',
              '每个分块的问题数（1–10）',
              'Questions per chunk (1–10)',
            ),
            instructions(
              'question_generation_config',
              'custom_instructions',
              '问题生成要求（可选）',
              'Question instructions (optional)',
            ),
          ],
        ];
    }
  }

  Widget parsingContent() => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          final color = AppFlowyTheme.of(context).textColorScheme.tertiary;
          final editor = SingleChildScrollView(
            key: ValueKey(_section),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _section.label(context),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                ...sectionFields(),
              ],
            ),
          );
          if (!wide) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<_Section>(
                    key: ValueKey('section-${_section.name}'),
                    initialValue: _section,
                    decoration: decoration(text('解析配置', 'Parsing settings')),
                    items: [
                      for (final section in _Section.values)
                        DropdownMenuItem(
                          value: section,
                          child: Text(section.label(context)),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _section = value!),
                  ),
                ),
                Expanded(child: editor),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 172,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text('上传位置', 'Destination'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.base.name),
                      const Divider(height: 24),
                      const Icon(Icons.link, size: 18),
                      const SizedBox(height: 8),
                      SelectableText(
                        _confirmedUrl!,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 172,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        text('解析配置', 'Parsing settings'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final section in _Section.values)
                      ListTile(
                        dense: true,
                        selected: _section == section,
                        leading: Icon(section.icon, size: 18),
                        title: Text(
                          section.label(context),
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          status(section),
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                        onTap: _busy
                            ? null
                            : () => setState(() => _section = section),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: editor),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final parsing = _confirmedUrl != null;
    final theme = AppFlowyTheme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: theme.surfaceColorScheme.layer01,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        insetPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            Expanded(
              child: Text(
                text(
                  parsing ? '上传文档确认' : '导入网页',
                  parsing ? 'Confirm document upload' : 'Import web page',
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: text('关闭', 'Close'),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        content: SizedBox(
          width: parsing ? 920 : 436,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parsing) ...[
                  Text(
                    text(
                      '请确认本次解析设置，修改仅用于本次导入。',
                      'Review parsing settings for this import. Changes apply to this import only.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height - 265)
                        .clamp(180, 520),
                    child: parsingContent(),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _url,
                    autofocus: true,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: decoration(
                      text('URL 地址', 'URL address'),
                    ).copyWith(
                      hintText: 'https://example.com',
                      suffixIcon: IconButton(
                        tooltip: text('清空', 'Clear'),
                        onPressed: _busy ? null : _url.clear,
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                    validator: (value) {
                      final url = value?.trim() ?? '';
                      final uri = Uri.tryParse(url);
                      return uri != null &&
                              (uri.scheme == 'http' || uri.scheme == 'https') &&
                              uri.host.isNotEmpty &&
                              uri.userInfo.isEmpty &&
                              url.length <= 2048 &&
                              !RegExp(r'\s').hasMatch(url)
                          ? null
                          : text(
                              '请输入有效的 HTTP 或 HTTPS 网页地址',
                              'Enter a valid HTTP or HTTPS web page URL',
                            );
                    },
                    onFieldSubmitted: (_) => _confirm(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    text(
                      '下一步设置本次网页的解析方式。',
                      'Configure parsing for this web page in the next step.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textColorScheme.tertiary,
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (parsing)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _confirmedUrl = null;
                        _error = null;
                      }),
              child: Text(text('上一步', 'Back')),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(text('取消', 'Cancel')),
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
                  ? text('处理中…', 'Processing…')
                  : parsing
                      ? text('确认上传并解析', 'Upload and parse')
                      : text('下一步：解析配置', 'Next: parsing settings'),
            ),
          ),
        ],
      ),
    );
  }
}
