import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/features/ai_internal/presentation/custom_chat_model_form.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_bindings.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_form.dart';
import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class AiProviderSettingsView extends StatefulWidget {
  const AiProviderSettingsView({
    super.key,
    this.onSaved,
    this.creatorName = '',
    this.workspaceId,
    this.service,
  });
  final ValueChanged<AiProviderConfig>? onSaved;
  final String creatorName;
  final String? workspaceId;
  final KnowledgeModelService? service;
  @override
  State<AiProviderSettingsView> createState() => _AiProviderSettingsViewState();
}

class _AiProviderSettingsViewState extends State<AiProviderSettingsView> {
  KnowledgeModelService? _service;
  List<KnowledgeModel> _models = [];
  KnowledgeModelType? _filter;
  bool _loading = true;
  bool _editing = false;
  bool _binding = false;
  KnowledgeModel? _initial;
  String? _error;
  String? _deleting;
  @override
  void initState() {
    super.initState();
    if (widget.onSaved == null) _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = _service ??
          widget.service ??
          await KnowledgeModelService.current(workspaceId: widget.workspaceId);
      if (!mounted) {
        if (widget.service == null) service.close();
        return;
      }
      _service = service;
      final models = await service.list();
      if (mounted) setState(() => _models = models);
    } catch (e) {
      if (mounted) setState(() => _error = modelError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onSaved != null) {
      return CustomChatModelForm(
        onSaved: widget.onSaved,
        creatorName: widget.creatorName,
      );
    }
    if (_binding) {
      return KnowledgeModelBindings(
        service: _service!,
        models: _models,
        onBack: () => setState(() => _binding = false),
      );
    }
    if (_editing) {
      return KnowledgeModelForm(
        service: _service!,
        initial: _initial,
        initialType: _filter ?? KnowledgeModelType.chat,
        onCancel: () => setState(() => _editing = false),
        onSaved: () {
          setState(() => _editing = false);
          _load();
        },
      );
    }
    final theme = AppFlowyTheme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 480 ? 16 : 36,
        36,
        MediaQuery.sizeOf(context).width < 480 ? 16 : 36,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          SizedBox(height: compact ? 24 : 46),
          KnowledgeModelTypes(
            spread: true,
            selected: _filter,
            models: _models,
            onSelected: (type) => setState(() => _filter = type),
          ),
          if (_loading) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: theme.textColorScheme.error),
            ),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
          if (!_loading && _error == null) ...[
            SizedBox(height: compact ? 28 : 44),
            _title(context, '小马内置模型'),
            const SizedBox(height: 20),
            _cards(context, builtin: true),
            SizedBox(height: compact ? 32 : 56),
            _title(context, '自定义模型'),
            const SizedBox(height: 20),
            _cards(context, builtin: false),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '模型配置',
          style: TextStyle(
            fontSize: 26,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: theme.textColorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '管理不同类型的AI模型，支持 Ollama 本地模型和远程API',
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 700 ? 14 : 18,
            height: 1.5,
            color: theme.textColorScheme.primary.withValues(alpha: .68),
          ),
        ),
      ],
    );
    final add = OutlinedButton.icon(
      onPressed: _loading || _service?.canManage != true ? null : () => _edit(),
      icon: const Icon(Symbols.add, size: 24, weight: 400),
      label: const Text('添加模型'),
      style: OutlinedButton.styleFrom(
        foregroundColor: modelAccent,
        textStyle: DefaultTextStyle.of(context)
            .style
            .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: BorderSide(
          color: theme.textColorScheme.primary.withValues(alpha: .1),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            700 * MediaQuery.textScalerOf(context).scale(14) / 14) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 16),
              add,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 24),
            add,
          ],
        );
      },
    );
  }

  void _edit([KnowledgeModel? model]) => setState(() {
        _initial = model;
        _editing = true;
      });

  Widget _title(BuildContext context, String title) => Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppFlowyTheme.of(context).textColorScheme.primary,
        ),
      );
  KnowledgeModelProvider? _provider(KnowledgeModel model) =>
      _service!.catalog.where((p) => p.id == model.provider).firstOrNull;
  Widget _cards(BuildContext context, {required bool builtin}) {
    final theme = AppFlowyTheme.of(context);
    final visible = _models
        .where(
          (m) => m.builtin == builtin && (_filter == null || m.type == _filter),
        )
        .toList();
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          builtin ? '此分类暂无内置模型' : '此分类暂无自定义模型',
          style: TextStyle(
            fontSize: 13,
            color: theme.textColorScheme.secondary,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final minWidth = 290 * MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns =
            ((c.maxWidth + 14) / (minWidth + 14)).floor().clamp(1, 3);
        final width = (c.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final model in visible)
              SizedBox(
                width: width,
                key: ValueKey('model-card-${model.id}'),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  decoration: modelSurface(context),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (builtin || _service?.canManage != true) {
                          _details(model);
                          return;
                        }
                        _edit(model);
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 22, 12, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: model.label,
                                    child: Text(
                                      model.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: c.maxWidth < 400 ? 16 : 20,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                        color: theme.textColorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!builtin &&
                                    model.data['status'] != null) ...[
                                  const SizedBox(width: 8),
                                  _status(context, model),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 32,
                              child: Row(
                                children: [
                                  Expanded(child: _providerLine(model)),
                                  if (!builtin &&
                                      _service?.canManage == true) ...[
                                    const SizedBox(width: 8),
                                    _action(
                                      '编辑模型',
                                      Symbols.edit,
                                      () => _edit(model),
                                    ),
                                    _action(
                                      '知识库使用设置',
                                      Symbols.link,
                                      () => setState(() => _binding = true),
                                    ),
                                    _action(
                                      '删除模型',
                                      Symbols.delete,
                                      _deleting == null
                                          ? () => _delete(model)
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _action(String label, IconData icon, VoidCallback? onPressed) =>
      IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: 24, weight: 350),
        color: AppFlowyTheme.of(context)
            .textColorScheme
            .primary
            .withValues(alpha: .5),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
      );

  Widget _status(BuildContext context, KnowledgeModel model) {
    final active = model.data['status'] == 'active';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? (dark ? const Color(0xFF70DAB0) : const Color(0xFF35B987))
        : (dark ? const Color(0xFFFF8D90) : const Color(0xFFF45D67));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? .16 : .12),
        borderRadius: BorderRadius.circular(5),
      ),
      // Model status describes configuration readiness, not a live connection probe.
      child: Text(
        active ? '已启用' : '未就绪',
        style: TextStyle(
          color: color,
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _delete(KnowledgeModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text(
          '确定删除“${model.label}”及其保存的密钥？此操作无法撤销。正在使用的模型需先在知识库中解除绑定。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = model.id);
    try {
      await _service!.delete(model.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(modelError(e, deleting: true)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  Widget _providerLine(KnowledgeModel model) {
    final provider = _provider(model);
    return Row(
      children: [
        KnowledgeProviderIcon(provider: provider),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${provider?.id == 'aliyun' ? '阿里云' : provider?.label ?? '小马笔记'} | ${model.type.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: MediaQuery.sizeOf(context).width < 480 ? 14 : 16,
              color: AppFlowyTheme.of(context)
                  .textColorScheme
                  .primary
                  .withValues(alpha: .68),
            ),
          ),
        ),
      ],
    );
  }

  void _details(KnowledgeModel model) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(model.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _providerLine(model),
              const SizedBox(height: 16),
              Text(
                model.builtin ? '由小马知识库提供。可在“知识库使用设置”中选用。' : '此模型由工作区所有者管理。',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _binding = true);
              },
              child: const Text('知识库使用设置'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
}
