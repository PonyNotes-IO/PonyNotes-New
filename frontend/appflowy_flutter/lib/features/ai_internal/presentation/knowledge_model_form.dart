import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class KnowledgeModelForm extends StatefulWidget {
  const KnowledgeModelForm({
    super.key,
    required this.service,
    required this.onSaved,
    required this.onCancel,
    this.initial,
    this.initialType = KnowledgeModelType.chat,
  });
  final KnowledgeModelService service;
  final KnowledgeModel? initial;
  final KnowledgeModelType initialType;
  final VoidCallback onSaved;
  final VoidCallback onCancel;
  @override
  State<KnowledgeModelForm> createState() => _KnowledgeModelFormState();
}

class _KnowledgeModelFormState extends State<KnowledgeModelForm> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _displayName = TextEditingController();
  final _context = TextEditingController();
  final _maxTokens = TextEditingController();
  final _dimension = TextEditingController();
  final _truncate = TextEditingController();
  final Map<String, TextEditingController> _extras = {};
  late KnowledgeModelType _type;
  String _providerId = 'generic';
  String _protocol = 'openai';
  List<KnowledgeModelProvider> _providers = [];
  bool _loading = true;
  bool _saving = false;
  bool _obscureKey = true;
  bool _dimensionOverride = false;
  bool _reasoning = false;
  String? _error;
  int _generation = 0;
  KnowledgeModelProvider? get _provider =>
      _providers.where((p) => p.id == _providerId).firstOrNull;
  bool get _chat =>
      _type == KnowledgeModelType.chat || _type == KnowledgeModelType.vision;
  bool get _fixedEmbedding =>
      widget.initial?.type == KnowledgeModelType.embedding;

  @override
  void initState() {
    super.initState();
    final model = widget.initial;
    final params = model?.parameters ?? {};
    _type = model?.type ?? widget.initialType;
    _url.text = params['base_url'] as String? ?? '';
    _name.text = model?.name ?? '';
    _displayName.text = model?.data['display_name'] as String? ?? '';
    _providerId = model?.provider ?? 'generic';
    _protocol = model?.data['source'] == 'local'
        ? 'ollama'
        : _providerId == 'generic' ||
                (params['spec'] as Map?)?['api'] == 'openai-completions'
            ? 'openai'
            : 'provider';
    _context.text = '${params['context_window'] ?? 128000}';
    _maxTokens.text = '${params['max_output_tokens'] ?? 8192}';
    _dimension.text =
        '${(params['embedding_parameters'] as Map?)?['dimension'] ?? ''}';
    _truncate.text =
        '${(params['embedding_parameters'] as Map?)?['truncate_prompt_tokens'] ?? 8192}';
    _dimensionOverride = (params['embedding_parameters']
            as Map?)?['supports_dimension_override'] ==
        true;
    _reasoning = (params['spec'] as Map?)?['reasoning'] == true;
    _loadProviders();
  }

  @override
  void dispose() {
    for (final c in [
      _url,
      _name,
      _key,
      _displayName,
      _context,
      _maxTokens,
      _dimension,
      _truncate,
      ..._extras.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProviders() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final providers = await widget.service.providers(_type);
      if (!mounted || generation != _generation) return;
      setState(() {
        _providers = providers;
        if (!providers.any((p) => p.id == _providerId)) _providerId = 'generic';
        _loading = false;
        _prepareExtras();
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = modelError(e);
        });
      }
    }
  }

  String _localized(Map<String, dynamic> value, String field) =>
      (value['${field}s'] as Map?)?['zh-CN'] as String? ??
      value[field] as String? ??
      '';
  List<Map<String, dynamic>> get _fields =>
      (_provider?.fields ?? []).where((field) {
        final types = field['model_types'] as List? ?? [];
        return types.isEmpty || types.contains(_type.apiValue);
      }).toList();
  void _prepareExtras() {
    for (final field in _fields) {
      _extras.putIfAbsent(
        field['key'] as String,
        () => TextEditingController(text: field['default'] as String? ?? ''),
      );
    }
  }

  void _changeProvider(String id) {
    setState(() {
      _providerId = id;
      _protocol = id == 'generic' ? 'openai' : 'provider';
      _key.clear();
      _name.clear();
      for (final controller in _extras.values) {
        controller.clear();
      }
      _url.text = _provider?.url(_type) ?? '';
      _prepareExtras();
    });
  }

  String? _positive(String? value, {int max = 2000000}) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > max ? '请输入 1–$max 的整数' : null;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final params = <String, dynamic>{
        'base_url': _url.text.trim(),
        'provider': _providerId,
        if (_key.text.trim().isNotEmpty) 'api_key': _key.text.trim(),
        if (_chat) ...{
          'interface_type': _protocol == 'ollama' ? 'ollama' : 'openai',
          'context_window': int.parse(_context.text),
          'max_output_tokens': int.parse(_maxTokens.text),
          'supports_vision': _type == KnowledgeModelType.vision,
          'spec': {
            'api': _protocol == 'ollama'
                ? 'ollama'
                : _protocol == 'provider'
                    ? _provider?.data['api'] ?? 'openai-completions'
                    : 'openai-completions',
            'reasoning': _reasoning,
            'context_window': int.parse(_context.text),
            'max_output_tokens': int.parse(_maxTokens.text),
          },
        },
        if (_type == KnowledgeModelType.embedding)
          'embedding_parameters': {
            'dimension': int.parse(_dimension.text),
            'truncate_prompt_tokens': int.parse(_truncate.text),
            'supports_dimension_override': _dimensionOverride,
          },
        if (_fields.isNotEmpty)
          'extra_config': {
            for (final field in _fields)
              if (_extras[field['key']]!.text.isNotEmpty)
                field['key']: _extras[field['key']]!.text,
          },
      };
      await widget.service.save(
        {
          'name': _name.text.trim(),
          'display_name': _displayName.text.trim(),
          'type': _type.apiValue,
          'source': _protocol == 'ollama' ? 'local' : 'remote',
          'parameters': params,
        },
        id: widget.initial?.id,
      );
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = modelError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: theme.backgroundColorScheme.primary,
        focusColor: theme.textColorScheme.primary.withValues(alpha: .035),
        highlightColor: theme.textColorScheme.primary.withValues(alpha: .035),
        colorScheme:
            Theme.of(context).colorScheme.copyWith(primary: modelAccent),
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: modelPagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '返回模型列表',
                    onPressed: _saving ? null : widget.onCancel,
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: modelHeading(
                      context,
                      widget.initial == null ? '添加模型' : '编辑模型',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('模型类型'),
              const SizedBox(height: 8),
              KnowledgeModelTypes(
                selected: _type,
                allowAll: false,
                enabled: widget.initial == null && !_saving,
                onSelected: (type) {
                  setState(() {
                    _type = type!;
                    _providerId = 'generic';
                    _protocol = 'openai';
                    _key.clear();
                    _url.clear();
                    _name.clear();
                  });
                  _loadProviders();
                },
              ),
              const SizedBox(height: 22),
              if (_loading) const LinearProgressIndicator(),
              if (!_loading) ...[
                modelField(
                  context,
                  '服务商',
                  DropdownButtonFormField<String>(
                    initialValue: _providerId,
                    isExpanded: true,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    menuMaxHeight: 400,
                    decoration: modelInputDecoration(context),
                    itemHeight: 68,
                    selectedItemBuilder: (context) => [
                      for (final provider in _providerChoices)
                        _providerRow(provider),
                    ],
                    items: [
                      for (final provider in _providerChoices)
                        DropdownMenuItem(
                          value: provider.id,
                          child: _providerRow(provider, menu: true),
                        ),
                    ],
                    onChanged: _fixedEmbedding || _saving
                        ? null
                        : (value) => _changeProvider(value!),
                  ),
                  hint: '选择厂商预设，或使用自定义服务地址',
                ),
                if (_type != KnowledgeModelType.rerank &&
                    _type != KnowledgeModelType.speech)
                  modelField(
                    context,
                    '接口协议',
                    DropdownButtonFormField<String>(
                      initialValue: _protocol,
                      isExpanded: true,
                      decoration: modelInputDecoration(context),
                      items: [
                        if (_providerId != 'generic')
                          const DropdownMenuItem(
                            value: 'provider',
                            child: Text('厂商原生协议'),
                          ),
                        const DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI 兼容协议'),
                        ),
                        const DropdownMenuItem(
                          value: 'ollama',
                          child: Text('Ollama 本地服务'),
                        ),
                      ],
                      onChanged: _fixedEmbedding || _saving
                          ? null
                          : (v) => setState(() {
                                _protocol = v!;
                                if (v == 'ollama' && _url.text.isEmpty) {
                                  _url.text = 'http://localhost:11434';
                                }
                              }),
                    ),
                  ),
                modelField(
                  context,
                  '接口地址',
                  TextFormField(
                    key: const ValueKey('model-url'),
                    controller: _url,
                    readOnly: _fixedEmbedding,
                    decoration: modelInputDecoration(
                      context,
                      hint: 'https://api.example.com/v1',
                    ),
                    validator: (value) {
                      final uri = Uri.tryParse(value?.trim() ?? '');
                      return uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty
                          ? '请输入有效的 HTTP 或 HTTPS 地址'
                          : null;
                    },
                  ),
                  hint: '地址须能被 WeKnora 服务端访问；localhost 指服务端本机。',
                ),
                modelField(
                  context,
                  _credentialLabel,
                  TextFormField(
                    key: const ValueKey('model-key'),
                    controller: _key,
                    obscureText: _obscureKey,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: modelInputDecoration(
                      context,
                      hint:
                          widget.initial == null ? '输入 API Key' : '留空保留已保存的密钥',
                      suffix: IconButton(
                        tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                    validator: (value) => widget.initial == null &&
                            _protocol != 'ollama' &&
                            _providerId != 'generic' &&
                            (value?.trim().isEmpty ?? true)
                        ? '请输入访问凭据'
                        : null,
                  ),
                ),
                if ((_provider?.models(_type) ?? []).isNotEmpty)
                  modelField(
                    context,
                    '厂商模型',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      hint: const Text('选择预设，或在下方填写模型名称'),
                      decoration: modelInputDecoration(context),
                      items: [
                        for (final model in _provider!.models(_type))
                          DropdownMenuItem(
                            value: model['id'] as String,
                            child: Text(
                              model['name'] as String? ?? model['id'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _fixedEmbedding || _saving
                          ? null
                          : (id) => setState(() {
                                _name.text = id!;
                                final model = _provider!
                                    .models(_type)
                                    .firstWhere((m) => m['id'] == id);
                                if ((model['dimension'] as num? ?? 0) > 0) {
                                  _dimension.text = '${model['dimension']}';
                                }
                                if ((model['context_window'] as num? ?? 0) >
                                    0) {
                                  _context.text = '${model['context_window']}';
                                }
                                if ((model['max_output_tokens'] as num? ?? 0) >
                                    0) {
                                  _maxTokens.text =
                                      '${model['max_output_tokens']}';
                                }
                                _reasoning = model['reasoning'] == true;
                              }),
                    ),
                  ),
                modelField(
                  context,
                  '模型名称',
                  TextFormField(
                    key: const ValueKey('model-name'),
                    controller: _name,
                    readOnly: _fixedEmbedding,
                    decoration:
                        modelInputDecoration(context, hint: '输入真实模型 ID'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入模型名称'
                        : null,
                  ),
                ),
                modelField(
                  context,
                  '显示名称（可选）',
                  TextFormField(
                    controller: _displayName,
                    decoration: modelInputDecoration(context, hint: '便于区分的名称'),
                  ),
                ),
                for (final field in _fields) _extraField(field),
                if (_chat) ...[
                  _numbers([
                    _number('上下文长度', _context),
                    _number(
                      'MAX tokens',
                      _maxTokens,
                      validator: (v) {
                        final error = _positive(v);
                        if (error != null) return error;
                        return int.parse(v!) >
                                (int.tryParse(_context.text) ?? 0)
                            ? '不能超过上下文长度'
                            : null;
                      },
                    ),
                  ]),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('支持推理 / 思考程度'),
                    value: _reasoning,
                    onChanged: (v) => setState(() => _reasoning = v),
                  ),
                ],
                if (_type == KnowledgeModelType.embedding) ...[
                  _numbers([
                    _number('向量维度', _dimension, max: 65536),
                    _number('最大输入 tokens', _truncate),
                  ]),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('支持指定输出维度'),
                    value: _dimensionOverride,
                    onChanged: _fixedEmbedding
                        ? null
                        : (v) => setState(() => _dimensionOverride = v),
                  ),
                ],
                if (_type == KnowledgeModelType.rerank)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('保存后，在“知识库使用设置”中选用此 ReRank 模型并设置返回数量。'),
                  ),
                if (_type == KnowledgeModelType.speech)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('用于知识库音频内容的语音转写（ASR）。'),
                  ),
                if (_fixedEmbedding)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('向量模型定义保持固定。需更换模型或维度时，请添加新模型并用于新知识库。'),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : widget.onCancel,
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: modelAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _saving ||
                            _loading ||
                            (_providers.isEmpty && _error != null)
                        ? null
                        : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                  if (_error != null && _providers.isEmpty)
                    TextButton(
                      onPressed: _loadProviders,
                      child: const Text('重试'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<KnowledgeModelProvider> get _providerChoices => [
        if (!_providers.any((p) => p.id == 'generic'))
          KnowledgeModelProvider(
            {'value': 'generic', 'label': '自定义（OpenAI 兼容接口）'},
          ),
        ..._providers,
      ];
  Widget _providerRow(KnowledgeModelProvider provider, {bool menu = false}) {
    final selected = provider.id == _providerId;
    final theme = AppFlowyTheme.of(context);
    final examples =
        provider.models(_type).take(3).map((m) => m['id']).join('、');
    final description = examples.isNotEmpty
        ? examples
        : _localized(provider.data, 'description');
    return Row(
      children: [
        KnowledgeProviderIcon(provider: provider),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.id == 'generic' ? '自定义（OpenAI 兼容接口）' : provider.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: menu && selected
                      ? modelAccent
                      : theme.textColorScheme.primary,
                ),
              ),
              if (menu && description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorScheme.primary.withValues(alpha: .48),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (menu && selected) ...[
          const SizedBox(width: 10),
          const Icon(Icons.check, size: 18, color: modelAccent),
        ],
      ],
    );
  }

  String get _credentialLabel {
    for (final label in _provider?.data['credentialLabels'] as List? ?? []) {
      final types = label['model_types'] as List? ?? [];
      if (types.isEmpty || types.contains(_type.apiValue)) {
        return _localized(Map<String, dynamic>.from(label as Map), 'label');
      }
    }
    return _providerId == 'generic' ? 'API Key（可选）' : 'API Key';
  }

  Widget _number(
    String label,
    TextEditingController controller, {
    int max = 2000000,
    String? Function(String?)? validator,
  }) =>
      modelField(
        context,
        label,
        TextFormField(
          controller: controller,
          readOnly: _fixedEmbedding,
          keyboardType: TextInputType.number,
          decoration: modelInputDecoration(context),
          validator: validator ?? (v) => _positive(v, max: max),
        ),
      );
  Widget _numbers(List<Widget> children) => LayoutBuilder(
        builder: (context, c) => c.maxWidth < 480
            ? Column(children: children)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: children[i]),
                  ],
                ],
              ),
      );
  Widget _extraField(Map<String, dynamic> field) {
    final controller = _extras[field['key']]!;
    final label = _localized(field, 'label');
    if (field['type'] == 'boolean') {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: controller.text == 'true',
        onChanged: (v) => setState(() => controller.text = '$v'),
      );
    }
    if (field['type'] == 'select') {
      final options = field['options'] as List? ?? [];
      return modelField(
        context,
        label,
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: options.any((o) => o['value'] == controller.text)
              ? controller.text
              : null,
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o['value'] as String,
                child: Text(o['label'] as String? ?? o['value'] as String),
              ),
          ],
          decoration: modelInputDecoration(context),
          onChanged: (v) => controller.text = v ?? '',
        ),
      );
    }
    return modelField(
      context,
      label,
      TextFormField(
        controller: controller,
        obscureText: field['secret'] == true || field['type'] == 'password',
        keyboardType: field['type'] == 'number'
            ? TextInputType.number
            : TextInputType.text,
        decoration: modelInputDecoration(
          context,
          hint: _localized(field, 'placeholder'),
        ),
        validator: (v) => field['required'] == true &&
                widget.initial == null &&
                (v?.trim().isEmpty ?? true)
            ? '请输入$label'
            : null,
      ),
    );
  }
}
