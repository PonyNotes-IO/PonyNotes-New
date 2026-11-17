import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_form_controls.dart';
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
    this.models = const [],
  });
  final KnowledgeModelService service;
  final KnowledgeModel? initial;
  final KnowledgeModelType initialType;
  final List<KnowledgeModel> models;
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
  bool _reasoning = true;
  // Temperature is not part of the WeKnora model parameter allowlist yet, so the
  // slider stays local and is intentionally left out of the save payload.
  double _temperature = 1.3;
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
    _context.text = modelThousands(params['context_window'] ?? 128000);
    _maxTokens.text = modelThousands(params['max_output_tokens'] ?? 8192);
    _dimension.text = modelThousands(
      (params['embedding_parameters'] as Map?)?['dimension'],
    );
    _truncate.text = modelThousands(
      (params['embedding_parameters'] as Map?)?['truncate_prompt_tokens'] ??
          8192,
    );
    _dimensionOverride = (params['embedding_parameters']
            as Map?)?['supports_dimension_override'] ==
        true;
    // Thinking support is the default; only an explicit false is preserved.
    _reasoning = (params['spec'] as Map?)?['reasoning'] as bool? ?? true;
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
    final n = modelNumber(value);
    return n == null || n < 1 || n > max ? '请输入 1-$max 的整数' : null;
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
          'context_window': modelNumber(_context.text)!,
          'max_output_tokens': modelNumber(_maxTokens.text)!,
          'supports_vision': _type == KnowledgeModelType.vision,
          'spec': {
            'api': _protocol == 'ollama'
                ? 'ollama'
                : _protocol == 'provider'
                    ? _provider?.data['api'] ?? 'openai-completions'
                    : 'openai-completions',
            'reasoning': _reasoning,
            'context_window': modelNumber(_context.text)!,
            'max_output_tokens': modelNumber(_maxTokens.text)!,
          },
        },
        if (_type == KnowledgeModelType.embedding)
          'embedding_parameters': {
            'dimension': modelNumber(_dimension.text)!,
            'truncate_prompt_tokens': modelNumber(_truncate.text)!,
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
    return Theme(
      data: modelControlsTheme(context),
      child: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
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
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
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
                    const Text(
                      '模型类型',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    KnowledgeModelTypes(
                      spread: true,
                      models: widget.models,
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
                    const SizedBox(height: 18),
                    if (_loading) const LinearProgressIndicator(),
                    if (!_loading) ...[
                      modelField(
                        context,
                        '服务商',
                        ModelSelect(
                          key: const ValueKey('model-provider'),
                          value: _providerId,
                          selectedChild: _provider == null
                              ? const Text('自定义（OpenAI 兼容接口）')
                              : _providerRow(_provider!),
                          entries: [
                            for (final provider in _providerChoices)
                              DropdownMenuEntry(
                                value: provider.id,
                                label: provider.label,
                                labelWidget: _providerRow(provider, menu: true),
                              ),
                          ],
                          onChanged: _fixedEmbedding || _saving
                              ? null
                              : (value) => _changeProvider(value!),
                        ),
                        hint: '选择已接入的供应商，或使用自定义配置',
                      ),
                      if (_type != KnowledgeModelType.rerank &&
                          _type != KnowledgeModelType.speech)
                        modelField(
                          context,
                          '接口协议',
                          ModelSelect(
                            key: const ValueKey('model-protocol'),
                            value: _protocol,
                            entries: [
                              if (_providerId != 'generic')
                                const DropdownMenuEntry(
                                  value: 'provider',
                                  label: '厂商原生协议',
                                ),
                              const DropdownMenuEntry(
                                value: 'openai',
                                label: 'OpenAI 兼容协议',
                              ),
                              const DropdownMenuEntry(
                                value: 'ollama',
                                label: 'Ollama 本地服务',
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
                          hint: '决定请求格式和错误校验方式：Ollama、vllm 通常选择 OpenAI 兼容协议',
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
                            hint: '例如：http://api.openai.com/v1',
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
                        hint: '格式：http://域名/路径，需包含完整的请求路径',
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
                            hint: widget.initial == null
                                ? '输入 API Key'
                                : '留空保留已保存的密钥',
                            suffix: IconButton(
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
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
                        hint: _protocol == 'ollama' || _providerId == 'generic'
                            ? '格式：以 sk- 开头的字符串，本地模型无 Key 时可填写 ollama-local'
                            : '输入服务商提供的访问凭据',
                      ),
                      if ((_provider?.models(_type) ?? []).isNotEmpty)
                        modelField(
                          context,
                          '厂商模型',
                          ModelSelect(
                            key: const ValueKey('model-preset'),
                            value: _provider!
                                    .models(_type)
                                    .any((m) => m['id'] == _name.text)
                                ? _name.text
                                : null,
                            hint: '选择预设，或在下方填写模型名称',
                            entries: [
                              for (final model in _provider!.models(_type))
                                DropdownMenuEntry(
                                  value: model['id'] as String,
                                  label: model['name'] as String? ??
                                      model['id'] as String,
                                ),
                            ],
                            onChanged: _fixedEmbedding || _saving
                                ? null
                                : (id) => setState(() {
                                      _name.text = id!;
                                      final model = _provider!
                                          .models(_type)
                                          .firstWhere((m) => m['id'] == id);
                                      if ((model['dimension'] as num? ?? 0) >
                                          0) {
                                        _dimension.text =
                                            modelThousands(model['dimension']);
                                      }
                                      if ((model['context_window'] as num? ??
                                              0) >
                                          0) {
                                        _context.text = modelThousands(
                                          model['context_window'],
                                        );
                                      }
                                      if ((model['max_output_tokens'] as num? ??
                                              0) >
                                          0) {
                                        _maxTokens.text = modelThousands(
                                          model['max_output_tokens'],
                                        );
                                      }
                                      _reasoning = model['reasoning'] != false;
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
                              modelInputDecoration(context, hint: '输入你的模型名称'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '请输入模型名称'
                                  : null,
                        ),
                      ),
                      for (final field in _fields) _extraField(field),
                      if (_chat) ...[
                        _numbers([
                          ModelTokenControl(
                            id: 'model-context',
                            label: '上下文长度',
                            controller: _context,
                            hint: '正整数，范围 1-2,000,000',
                            validator: _positive,
                          ),
                          ModelTokenControl(
                            id: 'model-output',
                            label: 'MAX tokens',
                            controller: _maxTokens,
                            hint: '正整数，不能超过上下文长度',
                            validator: (v) {
                              final error = _positive(v);
                              if (error != null) return error;
                              return modelNumber(v)! >
                                      (modelNumber(_context.text) ?? 0)
                                  ? '不能超过上下文长度'
                                  : null;
                            },
                          ),
                          ModelSliderControl(
                            id: 'model-temperature',
                            label: '温度',
                            valueLabel:
                                '${_temperature.toStringAsFixed(1)} 温度',
                            value: _temperature,
                            min: 0,
                            max: 2,
                            divisions: 20,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _temperature = v),
                            hint: '0~2 的小数，越低越稳定',
                          ),
                        ]),
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
                  ],
                ),
              ),
            ),
            Padding(
              padding: modelPagePadding(context).copyWith(top: 8, bottom: 20),
              child: _actions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() => Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 24,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _saving ? null : widget.onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(86, 32),
                tapTargetSize: MediaQuery.sizeOf(context).width >= 480
                    ? MaterialTapTargetSize.shrinkWrap
                    : MaterialTapTargetSize.padded,
              ),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(86, 32),
                tapTargetSize: MediaQuery.sizeOf(context).width >= 480
                    ? MaterialTapTargetSize.shrinkWrap
                    : MaterialTapTargetSize.padded,
              ),
              onPressed:
                  _saving || _loading || (_providers.isEmpty && _error != null)
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
      );

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
        : provider.id == 'generic'
            ? '任意 OpenAI 兼容接口（vLLM、SGLang、Xinference、Ollama 等）'
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
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  height: 1.4,
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
                    fontSize: 11,
                    color: theme.textColorScheme.primary.withValues(alpha: .48),
                  ),
                ),
              ],
            ],
          ),
        ),
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
    return 'API Key';
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
          inputFormatters: const [ModelThousandsFormatter()],
          decoration: modelInputDecoration(context),
          validator: validator ?? (v) => _positive(v, max: max),
        ),
      );
  // 168px is the narrowest card that still fits a five-character label next to
  // the 86px grouped value box, so the default 1280px window keeps three cards
  // side by side instead of using the slightly wider 12px padding layout.
  Widget _numbers(List<Widget> children) => LayoutBuilder(
        builder: (context, c) => c.maxWidth <
                (children.length * 168 + (children.length - 1) * 10) *
                    MediaQuery.textScalerOf(context).scale(12) /
                    12
            ? Column(children: children)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
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
        ModelSelect(
          key: ValueKey('model-extra-${field['key']}'),
          value: options.any((o) => o['value'] == controller.text)
              ? controller.text
              : null,
          entries: [
            for (final o in options)
              DropdownMenuEntry(
                value: o['value'] as String,
                label: o['label'] as String? ?? o['value'] as String,
              ),
          ],
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
