import 'dart:async';

import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../application/agent_credits.dart';
import '../application/agent_model_preferences.dart';
import '../application/agent_internal_service.dart';
import 'agent_model_details.dart';

Future<AiProviderConfig?> showAgentModelSettings(BuildContext context) {
  final creatorName =
      context.read<UserWorkspaceBloc?>()?.state.userProfile.name ?? '';
  return showDialog<AiProviderConfig>(
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
                creatorName: creatorName,
                onSaved: (config) => Navigator.pop(context, config),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

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
  String thinking = AgentModelPreferences.defaultLevel;
  bool updating = false;
  int loadGeneration = 0;
  final modelMenuHeaderKey = GlobalKey();

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
      var config = selected ?? widget.currentConfig ?? const AiProviderConfig();
      final saved = await storage.loadProfiles();
      final level =
          widget.currentThinking ?? await AgentModelPreferences.loadThinking();
      if (!mounted || generation != loadGeneration) return;
      if (loadingInternal) {
        setState(() {
          active = config;
          profiles = saved;
          thinking = level;
        });
      }
      List<AiProviderConfig> managed = [];
      String? failure;
      try {
        managed = await internal.models();
        config = selected ??
            widget.currentConfig ??
            await internal.preferred(available: managed);
      } catch (e) {
        failure = '$e'.replaceFirst('Bad state: ', '');
        if (selected == null && widget.currentConfig == null) {
          try {
            config = await internal.preferred(available: managed);
          } catch (_) {
            // Keep the model unselected if account identification failed.
          }
        }
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

  Widget _heading(String label, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: AppFlowyTheme.of(context)
                    .textColorScheme
                    .primary
                    .withValues(alpha: .45),
              ),
        ),
      );

  Widget _modelItem(AiProviderConfig config) {
    final color = AppFlowyTheme.of(context).textColorScheme.primary;
    final selected = config.isInternal == active.isInternal &&
        config.modelName == active.modelName &&
        (config.isInternal || config.baseUrl == active.baseUrl);
    final name = config.modelName.toLowerCase();
    final brand = name.contains('deepseek')
        ? 'deepseek'
        : name.contains('glm') || name.contains('zhipu')
            ? 'zai'
            : null;
    final item = Semantics(
      selected: selected,
      child: MenuItemButton(
        onPressed: widget.enabled && !updating
            ? () => _select(config, thinking)
            : null,
        style: MenuItemButton.styleFrom(
          backgroundColor: selected ? color.withValues(alpha: .08) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        leadingIcon: brand == null
            ? Icon(Icons.auto_awesome_outlined, size: 14, color: color)
            : FlowySvg(
                FlowySvgData('assets/images/setting/model_$brand.svg'),
                size: const Size.square(14),
                color: color,
              ),
        trailingIcon: selected
            ? Icon(Icons.check, size: 14, color: color)
            : const SizedBox(width: 14),
        overflowAxis: Axis.vertical,
        child: Text(
          config.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return config.isInternal
        ? Tooltip(message: config.label, child: item)
        : AgentModelDetails(
            key: ValueKey('${config.baseUrl}|${config.modelName}'),
            config: config,
            menuHeaderKey: modelMenuHeaderKey,
            child: item,
          );
  }

  int get _thinkingIndex {
    final index = AgentModelPreferences.levels.indexOf(thinking);
    return index < 0
        ? AgentModelPreferences.levels
            .indexOf(AgentModelPreferences.defaultLevel)
        : index;
  }

  Widget _thinkingItem(int index) {
    const descriptions = [
      '直接回答',
      '简单问答',
      '轻量分析',
      '日常任务，均衡思考',
      '深入分析',
      '复杂问题，多步推理',
      '高难度任务，充分思考',
    ];
    final theme = AppFlowyTheme.of(context);
    final foreground = theme.textColorScheme.primary;
    final accent = theme.fillColorScheme.themeThick;
    final level = AgentModelPreferences.levels[index];
    final selected = index == _thinkingIndex;
    return Semantics(
      selected: selected,
      child: MenuItemButton(
        key: ValueKey('agent-thinking-$level'),
        autofocus: selected,
        onPressed:
            widget.enabled && !updating ? () => _select(active, level) : null,
        style: MenuItemButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: selected ? accent.withValues(alpha: .10) : null,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        trailingIcon: selected
            ? Icon(Icons.check, size: 16, color: accent)
            : const SizedBox(width: 16),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                AgentModelPreferences.labels[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                descriptions[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: foreground.withValues(alpha: .65),
                ),
              ),
            ),
            if (level == AgentModelPreferences.defaultLevel)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '默认',
                  style: TextStyle(
                    fontSize: 10,
                    color: foreground.withValues(alpha: .65),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final foreground = theme.textColorScheme.primary;
    final textStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12);
    final thinkingWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 300.0);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MenuButtonTheme(
          data: MenuButtonThemeData(
            style: MenuItemButton.styleFrom(
              foregroundColor: foreground,
              iconColor: foreground,
              textStyle: textStyle,
              minimumSize: const Size(0, 26),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: MenuAnchor(
            crossAxisUnconstrained: false,
            style: MenuStyle(
              backgroundColor:
                  WidgetStatePropertyAll(theme.surfaceColorScheme.layer01),
              surfaceTintColor:
                  const WidgetStatePropertyAll(Colors.transparent),
              elevation: const WidgetStatePropertyAll(8),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
              minimumSize: const WidgetStatePropertyAll(Size(224, 0)),
              maximumSize:
                  const WidgetStatePropertyAll(Size(224, double.infinity)),
              side: WidgetStatePropertyAll(
                BorderSide(color: foreground.withValues(alpha: .12)),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              alignment: AlignmentDirectional.bottomEnd,
            ),
            alignmentOffset: const Offset(-224, 8),
            onOpen: _load,
            menuChildren: [
              _heading('平台模型', key: modelMenuHeaderKey),
              if (loadingInternal ||
                  internalError != null ||
                  internalModels.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    loadingInternal ? '正在加载平台模型…' : internalError ?? '暂无可用平台模型',
                    style: textStyle?.copyWith(
                      color: foreground.withValues(alpha: .55),
                    ),
                  ),
                ),
              ...internalModels.map(_modelItem),
              if (profiles.isNotEmpty) ...[
                const SizedBox(height: 4),
                _heading('自定义模型'),
                ...profiles.map(_modelItem),
              ],
              Divider(height: 9, color: foreground.withValues(alpha: .08)),
              MenuItemButton(
                onPressed: widget.enabled && !updating ? _custom : null,
                leadingIcon: const Icon(Icons.edit_outlined, size: 14),
                child: const Text('配置自定义模型'),
              ),
            ],
            builder: (context, controller, child) => Tooltip(
              message: '选择模型',
              child: TextButton(
                onPressed: widget.enabled && !updating
                    ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  textStyle: textStyle,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          active.isComplete
                              ? active.label
                              : loadingInternal
                                  ? '加载模型…'
                                  : '选择模型',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      controller.isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (active.supportsReasoning)
          MenuAnchor(
            crossAxisUnconstrained: false,
            alignmentOffset: Offset(-thinkingWidth, 8),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(
                theme.surfaceColorScheme.layer01,
              ),
              surfaceTintColor:
                  const WidgetStatePropertyAll(Colors.transparent),
              elevation: const WidgetStatePropertyAll(8),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
              minimumSize: WidgetStatePropertyAll(Size(thinkingWidth, 0)),
              maximumSize:
                  WidgetStatePropertyAll(Size(thinkingWidth, double.infinity)),
              side: WidgetStatePropertyAll(
                BorderSide(color: foreground.withValues(alpha: .12)),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              alignment: AlignmentDirectional.bottomEnd,
            ),
            menuChildren: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '思考强度',
                      style: textStyle?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '按任务难度选择思考深度',
                      style: textStyle?.copyWith(
                        fontSize: 11,
                        color: foreground.withValues(alpha: .65),
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < AgentModelPreferences.levels.length; i++)
                _thinkingItem(i),
              Divider(height: 13, color: foreground.withValues(alpha: .08)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '思考越深入，通常耗时越长',
                  style: textStyle?.copyWith(
                    fontSize: 11,
                    color: foreground.withValues(alpha: .65),
                  ),
                ),
              ),
            ],
            builder: (context, controller, child) => Tooltip(
              message: '思考强度',
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  textStyle: textStyle,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: widget.enabled && !updating
                    ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '思考 · ${AgentModelPreferences.labels[_thinkingIndex]}',
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      controller.isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
