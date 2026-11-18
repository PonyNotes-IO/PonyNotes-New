import 'dart:math' as math;

import 'package:appflowy/features/agent/application/agent_internal_service.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/ai_internal/application/knowledge_model_service.dart';
import 'package:appflowy/features/ai_internal/presentation/custom_chat_model_form.dart';
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
    this.internalService,
  });
  final ValueChanged<AiProviderConfig>? onSaved;
  final String creatorName;
  final String? workspaceId;
  final KnowledgeModelService? service;
  final AgentInternalService? internalService;
  @override
  State<AiProviderSettingsView> createState() => _AiProviderSettingsViewState();
}

class _AiProviderSettingsViewState extends State<AiProviderSettingsView> {
  KnowledgeModelService? _service;
  List<KnowledgeModel> _models = [];
  List<AiProviderConfig> _internalModels = [];
  bool _loadingInternal = true;
  String? _internalError;
  KnowledgeModelType? _filter;
  bool _loading = true;
  bool _editing = false;
  KnowledgeModel? _initial;
  String? _error;
  String? _deleting;
  @override
  void initState() {
    super.initState();
    if (widget.onSaved == null) {
      _load();
      _loadInternal();
    }
  }

  Future<void> _loadInternal() async {
    setState(() {
      _loadingInternal = true;
      _internalError = null;
    });
    try {
      final models =
          await (widget.internalService ?? AgentInternalService()).models();
      if (mounted) setState(() => _internalModels = models);
    } catch (e) {
      if (mounted) {
        setState(() => _internalError = '$e'.replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingInternal = false);
    }
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
      if (mounted) {
        setState(() {
          _models = models;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = modelError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: modelControlsTheme(context),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            height: 1.4,
            color: AppFlowyTheme.of(context).textColorScheme.primary,
          ),
          child: Builder(builder: _build),
        ),
      );

  Widget _build(BuildContext context) {
    if (widget.onSaved != null) {
      return CustomChatModelForm(
        onSaved: widget.onSaved,
        creatorName: widget.creatorName,
      );
    }
    if (_editing) {
      return KnowledgeModelForm(
        models: _models,
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 480 ? 16 : 28,
        22,
        MediaQuery.sizeOf(context).width < 480 ? 16 : 28,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 24),
          KnowledgeModelTypes(
            spread: true,
            selected: _filter,
            models: _displayModels,
            onSelected: (type) => setState(() => _filter = type),
          ),
          const SizedBox(height: 28),
          _title(context, '小马内置模型'),
          const SizedBox(height: 12),
          if (_loadingInternal) const LinearProgressIndicator(),
          if (_internalError != null) ...[
            Text(
              _internalError!,
              style: TextStyle(color: theme.textColorScheme.error),
            ),
            TextButton(onPressed: _loadInternal, child: const Text('重试内置模型')),
          ],
          _cards(context, builtin: true),
          const SizedBox(height: 36),
          _title(context, '自定义模型'),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: theme.textColorScheme.error)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
          _cards(context, builtin: false),
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
            fontSize: 24,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: theme.textColorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '管理不同类型的AI模型，支持 Ollama 本地模型和远程API',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: theme.textColorScheme.primary.withValues(alpha: .68),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            420 * MediaQuery.textScalerOf(context).scale(14) / 14) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 12),
              _addButton(context),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            _addButton(context),
          ],
        );
      },
    );
  }

  Widget _addButton(BuildContext context) => OutlinedButton.icon(
        onPressed: _loading ||
                (_service?.canManage != true && _service?.canManageChat != true)
            ? null
            : () => _edit(),
        icon: const Icon(Symbols.add, size: 16, weight: 400),
        label: const Text('添加模型'),
        style: OutlinedButton.styleFrom(
          foregroundColor: modelAccent,
          textStyle: DefaultTextStyle.of(context)
              .style
              .copyWith(fontSize: 12, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 32),
          side: BorderSide(
            color: AppFlowyTheme.of(context)
                .textColorScheme
                .primary
                .withValues(alpha: .1),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  void _edit([KnowledgeModel? model]) => setState(() {
        _initial = model;
        _editing = true;
      });

  Widget _title(BuildContext context, String title) => Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppFlowyTheme.of(context).textColorScheme.primary,
        ),
      );
  // Display-only entries: Agent aliases never enter forms or UUID model bindings.
  List<KnowledgeModel> get _displayModels => [
        for (final model in _internalModels)
          KnowledgeModel({
            'id': 'agent:${model.modelName}',
            'name': model.modelName,
            'display_name': model.label,
            'type': KnowledgeModelType.chat.apiValue,
            'is_builtin': true,
            'can_edit': false,
            'parameters': {
              'provider': switch (model.providerName) {
                '火山引擎' => 'volcengine',
                '阿里云 DashScope' => 'aliyun',
                'DeepSeek' => 'deepseek',
                _ => 'generic',
              },
            },
          }),
        ..._models.where(
          (model) =>
              model.builtin || model.canEdit || model.id.startsWith('custom:'),
        ),
      ];

  AiProviderConfig? _agentModel(KnowledgeModel model) => _internalModels
      .where((m) => model.id == 'agent:${m.modelName}')
      .firstOrNull;

  KnowledgeModelProvider? _provider(KnowledgeModel model) =>
      _service?.catalog.where((p) => p.id == model.provider).firstOrNull;

  Widget _cards(BuildContext context, {required bool builtin}) {
    final theme = AppFlowyTheme.of(context);
    final visible = _displayModels
        .where(
          (m) => m.builtin == builtin && (_filter == null || m.type == _filter),
        )
        .toList();
    if (visible.isEmpty) {
      if (_loading ||
          (builtin && _loadingInternal) ||
          (builtin ? _internalError != null : _error != null)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          builtin ? '此分类暂无内置模型' : '此分类暂无自定义模型',
          style: TextStyle(
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final minWidth = 240 * MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns =
            ((c.maxWidth + 12) / (minWidth + 12)).floor().clamp(1, 3);
        final width =
            ((c.maxWidth - (columns - 1) * 12) / columns).clamp(0.0, 306.0);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final model in visible)
              SizedBox(
                width: width,
                key: ValueKey(
                  _agentModel(model) != null
                      ? 'agent-model-card-${model.name}'
                      : 'model-card-${model.id}',
                ),
                child: _modelCard(context, model, builtin: builtin),
              ),
          ],
        );
      },
    );
  }

  Widget _modelCard(
    BuildContext context,
    KnowledgeModel model, {
    required bool builtin,
  }) {
    final theme = AppFlowyTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final canEdit = model.canEdit &&
        (model.id.startsWith('custom:')
            ? _service?.canManageChat == true
            : _service?.canManage == true);
    final title = Text(
      model.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: theme.textColorScheme.primary,
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: builtin
                    ? title
                    : Tooltip(message: model.label, child: title),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(child: _providerLine(model)),
                if (!builtin) ...[
                  const SizedBox(width: 4),
                  _action(
                    '编辑模型',
                    Symbols.edit,
                    canEdit ? () => _edit(model) : null,
                  ),
                  // shortcut: sharing has no defined behavior yet; keep this slot inert until specified.
                  GestureDetector(
                    key: ValueKey('model-share-placeholder-${model.id}'),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () {},
                    child: Semantics(
                      label: '分享',
                      enabled: false,
                      child: SizedBox.square(
                        dimension: 24,
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: Icon(
                            Symbols.link,
                            size: 16,
                            weight: 350,
                            color: theme.textColorScheme.primary
                                .withValues(alpha: .5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _action(
                    '删除模型',
                    Symbols.delete,
                    canEdit && _deleting == null ? () => _delete(model) : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      decoration: BoxDecoration(
        color: dark ? theme.backgroundColorScheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark
              ? theme.textColorScheme.primary.withValues(alpha: .12)
              : const Color(0xFFE9E9E9),
          width: .5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .16 : .05),
            offset: const Offset(0, 2),
            blurRadius: 10,
          ),
        ],
      ),
      child: builtin
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  content,
                  if (model.data['status'] != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _status(context, model),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback? onPressed) =>
      IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: 16, weight: 350),
        color: AppFlowyTheme.of(context)
            .textColorScheme
            .primary
            .withValues(alpha: .5),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          tapTargetSize: MediaQuery.sizeOf(context).width >= 480
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
        ),
      );

  Widget _status(BuildContext context, KnowledgeModel model) {
    final active = model.data['status'] == 'active';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? (dark ? const Color(0xFF70DAB0) : const Color(0xFF35B987))
        : (dark ? const Color(0xFFFF8D90) : const Color(0xFFF45D67));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
          model.id.startsWith('custom:')
              ? '确定删除“${model.label}”？删除后，你和工作区成员将无法继续使用此模型。'
              : '确定删除“${model.label}”及其保存的密钥？此操作无法撤销。正在使用的模型需先在知识库中解除绑定。',
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
    final agent = _agentModel(model);
    final label = agent != null && agent.providerName.isNotEmpty
        ? agent.providerName
        : provider?.id == 'aliyun'
            ? '阿里云'
            : provider?.label ??
                (model.id.startsWith('custom:') ? '自定义接口' : '小马笔记');
    return Row(
      children: [
        KnowledgeProviderIcon(provider: provider, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$label | ${model.type.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
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
}
