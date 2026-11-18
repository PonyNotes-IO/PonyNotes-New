import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:flutter/material.dart';

class KnowledgeModelBindings extends StatefulWidget {
  const KnowledgeModelBindings({
    super.key,
    required this.service,
    required this.models,
    required this.onBack,
  });
  final KnowledgeModelService service;
  final List<KnowledgeModel> models;
  final VoidCallback onBack;
  @override
  State<KnowledgeModelBindings> createState() => _KnowledgeModelBindingsState();
}

class _KnowledgeModelBindingsState extends State<KnowledgeModelBindings> {
  List<KnowledgeBase> _bases = [];
  String? _baseId;
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _embeddingLocked = false;
  String? _error;
  final _topK = TextEditingController(text: '10');
  final _form = GlobalKey<FormState>();
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _loadBases();
  }

  @override
  void dispose() {
    _topK.dispose();
    super.dispose();
  }

  Future<void> _loadBases() async {
    try {
      final bases = await widget.service.bases();
      if (!mounted) return;
      setState(() {
        _bases = bases;
        _loading = false;
      });
      if (bases.isNotEmpty) await _select(bases.first.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = modelError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(String id) async {
    final generation = ++_generation;
    setState(() {
      _baseId = id;
      _settings = null;
      _error = null;
      _loading = true;
    });
    try {
      final settings = await widget.service.settings(id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _settings = settings.values;
        _embeddingLocked = settings.embeddingLocked;
        _topK.text = '${settings.values['rerank_top_k'] ?? 10}';
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = modelError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.bind(
        _baseId!,
        {..._settings!, 'rerank_top_k': int.parse(_topK.text)},
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('知识库模型绑定已保存')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) setState(() => _error = modelError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: modelPagePadding(context),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '返回模型列表',
                    onPressed: _saving ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(child: modelHeading(context, '知识库使用设置')),
                ],
              ),
              const SizedBox(height: 16),
              const Text('为知识库选择实际使用的模型。已有文档时保留当前向量模型；其他解析配置用于之后的入库任务。'),
              const SizedBox(height: 24),
              if (_bases.isNotEmpty)
                modelField(
                  context,
                  '知识库',
                  DropdownButtonFormField<String>(
                    initialValue: _baseId,
                    isExpanded: true,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    menuMaxHeight: 320,
                    decoration: modelInputDecoration(context),
                    items: [
                      for (final base in _bases)
                        DropdownMenuItem(
                          value: base.id,
                          child:
                              Text(base.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _saving ? null : (id) => _select(id!),
                  ),
                ),
              if (_loading)
                const LinearProgressIndicator()
              else if (_bases.isEmpty && _error == null)
                const Text('暂无可管理且已就绪的知识库。'),
              if (_settings != null) ...[
                for (final entry in const {
                  'embedding_model_id': KnowledgeModelType.embedding,
                  'summary_model_id': KnowledgeModelType.chat,
                  'rerank_model_id': KnowledgeModelType.rerank,
                  'vlm_model_id': KnowledgeModelType.vision,
                  'asr_model_id': KnowledgeModelType.speech,
                }.entries)
                  _selector(entry.key, entry.value),
                modelField(
                  context,
                  'ReRank 返回数量',
                  TextFormField(
                    controller: _topK,
                    keyboardType: TextInputType.number,
                    decoration: modelInputDecoration(context),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 200
                          ? '请输入 1–200 的整数'
                          : null;
                    },
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : widget.onBack,
                    child: const Text('返回'),
                  ),
                  if (_settings != null)
                    FilledButton(
                      onPressed: _loading || _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存使用设置'),
                    ),
                  if (_error != null)
                    TextButton(
                      onPressed: () =>
                          _baseId == null ? _loadBases() : _select(_baseId!),
                      child: const Text('重试'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
  Widget _selector(String field, KnowledgeModelType type) {
    final options = widget.models
        .where((model) => model.type == type && !model.id.startsWith('custom:'))
        .toList();
    final selected = _settings![field] as String? ?? '';
    return modelField(
      context,
      type.label,
      DropdownButtonFormField<String>(
        key: ValueKey('binding-$field'),
        initialValue: selected,
        isExpanded: true,
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        menuMaxHeight: 320,
        decoration: modelInputDecoration(context),
        items: [
          if (type != KnowledgeModelType.embedding || selected.isEmpty)
            const DropdownMenuItem(value: '', child: Text('不使用')),
          if (selected.isNotEmpty && !options.any((m) => m.id == selected))
            DropdownMenuItem(
              value: selected,
              child: const Text('当前配置（模型暂不可用）'),
            ),
          for (final model in options)
            DropdownMenuItem(
              value: model.id,
              child: Text(model.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _saving ||
                (type == KnowledgeModelType.embedding && _embeddingLocked)
            ? null
            : (id) => setState(() => _settings![field] = id),
      ),
      hint: type == KnowledgeModelType.embedding && _embeddingLocked
          ? '知识库已有文档，保留当前向量模型。'
          : null,
    );
  }
}
