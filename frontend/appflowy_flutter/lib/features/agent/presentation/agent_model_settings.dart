import 'dart:async';

import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import '../application/agent_credits.dart';
import '../application/agent_model_preferences.dart';
import '../application/agent_internal_service.dart';

Future<AiProviderConfig?> showAgentModelSettings(BuildContext context) =>
    showDialog<AiProviderConfig>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '关闭模型设置',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: AiProviderSettingsView(
                  onSaved: (config) => Navigator.pop(context, config),
                ),
              ),
            ],
          ),
        ),
      ),
    );

class AgentModelSettingsButton extends StatefulWidget {
  const AgentModelSettingsButton({
    super.key,
    this.enabled = true,
    this.onChanged,
    this.currentConfig,
    this.currentThinking,
    this.internalService,
  });
  final bool enabled;
  final AiProviderConfig? currentConfig;
  final String? currentThinking;
  final AgentInternalService? internalService;
  final Future<void> Function(AiProviderConfig config, String thinking)?
      onChanged;

  @override
  State<AgentModelSettingsButton> createState() =>
      _AgentModelSettingsButtonState();
}

class _AgentModelSettingsButtonState extends State<AgentModelSettingsButton> {
  final storage = const AiProviderConfigStorage();
  AiProviderConfig active = const AiProviderConfig();
  List<AiProviderConfig> profiles = [];
  List<AiProviderConfig> internalModels = [];
  String? internalError;
  bool loadingInternal = true;
  late final internal = widget.internalService ?? AgentInternalService();
  String thinking = 'off';
  bool updating = false;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AgentModelSettingsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentConfig != null) active = widget.currentConfig!;
    if (widget.currentThinking != null) thinking = widget.currentThinking!;
  }

  Future<void> _load({AiProviderConfig? selected}) async {
    final generation = ++loadGeneration;
    try {
      var config = selected ?? widget.currentConfig ?? await storage.load();
      final saved = await storage.loadProfiles();
      final level =
          widget.currentThinking ?? await AgentModelPreferences.loadThinking();
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        active = config;
        profiles = saved;
        thinking = level;
      });
      List<AiProviderConfig> managed = [];
      String? failure;
      try {
        managed = await internal.models();
        config = selected ??
            widget.currentConfig ??
            await internal.preferred(available: managed);
      } catch (e) {
        failure = '$e'.replaceFirst('Bad state: ', '');
      }
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        active = config;
        internalModels = managed;
        internalError = failure;
        loadingInternal = false;
      });
      // A gateway key can serve several models; offer each one under the same endpoint and key.
      final seen = {for (final p in saved) '${p.baseUrl}|${p.modelName}'};
      for (final endpoint in {
        for (final p in saved) '${p.baseUrl}|${p.apiKey}': p,
      }.values.toList()) {
        for (final model in await fetchGatewayModels(endpoint)) {
          if (seen.add('${endpoint.baseUrl}|$model')) {
            saved.add(endpoint.copyWith(modelName: model));
          }
        }
      }
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        active = config;
        profiles = saved;
        internalModels = managed;
        internalError = failure;
        loadingInternal = false;
        thinking = level;
      });
    } catch (e) {
      if (mounted) setState(() => loadingInternal = false);
      _error(e);
    }
  }

  void _error(Object error) {
    if (mounted) {
      showToastNotification(message: '$error', type: ToastificationType.error);
    }
  }

  Future<void> _select(AiProviderConfig config, String level) async {
    if (updating) return;
    ++loadGeneration;
    final previous = active;
    final previousThinking = thinking;
    setState(() => updating = true);
    try {
      await internal.select(config);
      await AgentModelPreferences.saveThinking(level);
      await widget.onChanged?.call(config, level);
      if (mounted) {
        setState(() {
          active = config;
          thinking = level;
        });
        unawaited(_load(selected: config));
      }
    } catch (e) {
      try {
        await internal.select(previous);
        await AgentModelPreferences.saveThinking(previousThinking);
        await _load(selected: previous);
        _error(e);
      } catch (restoreError) {
        _error('模型切换失败：$e；配置恢复失败，请重新选择模型：$restoreError');
      }
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Future<void> _custom() async {
    final config = await showAgentModelSettings(context);
    if (mounted && config != null && config.isComplete) {
      await _select(config, thinking);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PopupMenuButton<AiProviderConfig>(
            enabled: widget.enabled &&
                !updating &&
                (!loadingInternal || profiles.isNotEmpty),
            tooltip: '选择模型',
            color: AppFlowyTheme.of(context).surfaceColorScheme.layer01,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
            onOpened: _load,
            onSelected: (config) =>
                config.isComplete ? _select(config, thinking) : _custom(),
            itemBuilder: (_) => [
              PopupMenuItem<AiProviderConfig>(
                enabled: false,
                height: 36,
                child: Text(
                  '内部模型',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (loadingInternal ||
                  internalError != null ||
                  internalModels.isEmpty)
                PopupMenuItem<AiProviderConfig>(
                  enabled: false,
                  child: Text(
                    loadingInternal ? '正在加载内部模型…' : internalError ?? '暂无可用内部模型',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              for (final config in internalModels)
                PopupMenuItem(
                  value: config,
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_outlined, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          config.modelName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (active.isInternal &&
                          config.modelName == active.modelName)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              if (profiles.isNotEmpty)
                PopupMenuItem<AiProviderConfig>(
                  enabled: false,
                  height: 36,
                  child: Text(
                    '自定义模型',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              for (var i = 0; i < profiles.length; i++)
                PopupMenuItem(
                  value: profiles[i],
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_outlined, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              profiles[i].modelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              Uri.tryParse(profiles[i].baseUrl)?.host ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!active.isInternal &&
                          profiles[i].modelName == active.modelName &&
                          profiles[i].baseUrl == active.baseUrl)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
              if (profiles.isNotEmpty) const PopupMenuDivider(),
              const PopupMenuItem(
                value: AiProviderConfig(),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18),
                    SizedBox(width: 12),
                    Text('配置自定义模型'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      active.isComplete
                          ? active.modelName
                          : loadingInternal
                              ? '加载模型…'
                              : '选择模型',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          ),
          if (active.supportsReasoning)
            MenuAnchor(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(
                  AppFlowyTheme.of(context).surfaceColorScheme.layer01,
                ),
                elevation: const WidgetStatePropertyAll(6),
                side: WidgetStatePropertyAll(
                  BorderSide(color: Theme.of(context).dividerColor),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              menuChildren: [
                SizedBox(
                  width: 280,
                  child: _ThinkingControl(
                    model: active.modelName,
                    value: thinking,
                    onSelected: (level) => _select(active, level),
                  ),
                ),
              ],
              builder: (context, controller, child) => TextButton(
                onPressed: widget.enabled && !updating
                    ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                    : null,
                child: Text(
                  '思考 · ${AgentModelPreferences.labels[AgentModelPreferences.levels.indexOf(thinking)]}',
                ),
              ),
            ),
        ],
      );
}

class _ThinkingControl extends StatefulWidget {
  const _ThinkingControl({
    required this.model,
    required this.value,
    required this.onSelected,
  });
  final String model;
  final String value;
  final ValueChanged<String> onSelected;
  @override
  State<_ThinkingControl> createState() => _ThinkingControlState();
}

class _ThinkingControlState extends State<_ThinkingControl> {
  late double value =
      AgentModelPreferences.levels.indexOf(widget.value).toDouble();
  @override
  void didUpdateWidget(covariant _ThinkingControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      value = AgentModelPreferences.levels.indexOf(widget.value).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '思考程度 · ${AgentModelPreferences.labels[value.round()]}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '重置思考程度',
                  icon: const Icon(Icons.restart_alt, size: 20),
                  onPressed: () {
                    setState(() => value = 0);
                    widget.onSelected('off');
                  },
                ),
              ],
            ),
            Slider(
              value: value,
              max: 4,
              divisions: 4,
              label: AgentModelPreferences.labels[value.round()],
              onChanged: (v) => setState(() => value = v),
              onChangeEnd: (v) =>
                  widget.onSelected(AgentModelPreferences.levels[v.round()]),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('关闭'), Text('高')],
            ),
          ],
        ),
      );
}
