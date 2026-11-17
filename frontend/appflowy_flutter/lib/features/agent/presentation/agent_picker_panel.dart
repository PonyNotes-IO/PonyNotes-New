import 'package:flutter/material.dart';
import '../application/agent_definition.dart';

/// Shows the engine's catalog while the caller owns the conversation selection.
class AgentPickerPanel extends StatefulWidget {
  const AgentPickerPanel({
    super.key,
    this.smartMode = true,
    this.autofocus = false,
    this.onModeSelected,
    this.onConfigure,
    this.agents = const [AgentDefinition.quick, AgentDefinition.smartReasoning],
    this.selectedAgent,
    this.onAgentSelected,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final bool smartMode;
  final bool autofocus;
  final ValueChanged<bool>? onModeSelected;
  final VoidCallback? onConfigure;
  final List<AgentDefinition> agents;
  final AgentDefinition? selectedAgent;
  final ValueChanged<AgentDefinition>? onAgentSelected;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<AgentPickerPanel> createState() => _AgentPickerPanelState();
}

class _AgentPickerPanelState extends State<AgentPickerPanel> {
  static const _blue = Color(0xFF4A60B2);
  static const _amber = Color(0xFFD99000);
  final _focus = <String, FocusNode>{};
  late AgentDefinition _selected = widget.selectedAgent ??
      (widget.smartMode
          ? AgentDefinition.smartReasoning
          : AgentDefinition.quick);
  late AgentDefinition _preview = _selected;

  FocusNode _node(AgentDefinition entry) =>
      _focus.putIfAbsent(entry.key, FocusNode.new);

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _foreground =>
      _dark ? const Color(0xFFEAEAEA) : const Color(0xFF262626);
  Color get _secondary =>
      _dark ? const Color(0xFF858585) : const Color(0xFF777777);
  Color get _surface => _dark ? const Color(0xFF262626) : Colors.white;
  Color get _border =>
      _dark ? const Color(0xFF353535) : const Color(0xFFE4E4E4);
  Color get _fill => _dark ? const Color(0xFF343434) : const Color(0xFFF1F1F1);

  TextStyle _text(double size, {Color? color, FontWeight? weight}) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: size,
            height: 1.3,
            letterSpacing: 0,
            color: color ?? _foreground,
            fontWeight: weight ?? FontWeight.w400,
          );

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node(_selected).requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgentPickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedAgent ??
        (widget.smartMode
            ? AgentDefinition.smartReasoning
            : AgentDefinition.quick);
    _selected = widget.agents.where((a) => a.key == selected.key).firstOrNull ??
        selected;
    _preview = widget.agents.where((a) => a.key == _preview.key).firstOrNull ??
        _selected;
    if (widget.autofocus && oldWidget.loading && !widget.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node(_selected).requestFocus();
      });
    }
  }

  void _show(AgentDefinition entry) {
    if (_preview != entry) setState(() => _preview = entry);
  }

  void _select(AgentDefinition entry) {
    if (widget.onAgentSelected != null) {
      widget.onAgentSelected!(entry);
      return;
    }
    if (widget.onModeSelected != null &&
        [AgentDefinition.quick.id, AgentDefinition.smartReasoning.id]
            .contains(entry.id) &&
        entry.sourceTenantId == null) {
      widget.onModeSelected!(entry.smart);
      return;
    }
    setState(() {
      _selected = entry;
      _preview = entry;
    });
  }

  Widget _card(Widget child) => Material(
        color: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: .15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _heading(String label, {double height = 20}) => SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              label,
              style: _text(10, color: _secondary, weight: FontWeight.w500),
            ),
          ),
        ),
      );

  Widget _entry(AgentDefinition entry) => MouseRegion(
        onEnter: (_) => _show(entry),
        child: Semantics(
          selected: _selected.key == entry.key,
          child: SizedBox(
            height: 26,
            child: LayoutBuilder(
              builder: (context, constraints) => MenuItemButton(
                key: ValueKey(
                  'agent-mode-${entry.sourceTenantId == null && entry.id == AgentDefinition.quick.id ? 'quick' : entry.sourceTenantId == null && entry.id == AgentDefinition.smartReasoning.id ? 'smart' : entry.key}',
                ),
                focusNode: _node(entry),
                closeOnActivate: false,
                onFocusChange: (focused) {
                  if (focused) _show(entry);
                },
                onPressed: () => _select(entry),
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    _selected.key == entry.key ? _fill : Colors.transparent,
                  ),
                  foregroundColor: WidgetStatePropertyAll(_foreground),
                  overlayColor: WidgetStatePropertyAll(
                    _foreground.withValues(alpha: .025),
                  ),
                  textStyle: WidgetStatePropertyAll(
                    _text(13, weight: FontWeight.w500),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 2),
                  ),
                  minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
                  maximumSize:
                      const WidgetStatePropertyAll(Size(double.infinity, 26)),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                child: SizedBox(
                  width: constraints.maxWidth - 4,
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: OverflowBox(
                          maxWidth: 32,
                          maxHeight: 32,
                          child:
                              Icon(Icons.stop_rounded, size: 32, color: _blue),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _navigation() => _card(
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.loading) const LinearProgressIndicator(minHeight: 2),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.error!, style: _text(11, color: _secondary)),
                      TextButton(
                        onPressed: widget.onRetry,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              for (final group in const {
                'builtin': '内置智能体',
                'private': '私有自定义智能体',
                'shared': '协作智能体',
              }.entries) ...[
                _heading(group.value),
                for (final entry
                    in widget.agents.where((a) => a.group == group.key))
                  _entry(entry),
                if (!widget.loading &&
                    !widget.agents.any((a) => a.group == group.key))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text('暂无智能体', style: _text(11, color: _secondary)),
                  ),
                const SizedBox(height: 8),
              ],
              Divider(height: 1, color: _border.withValues(alpha: .65)),
              SizedBox(
                height: 28,
                child: MenuItemButton(
                  key: const ValueKey('agent-picker-configure'),
                  onPressed: widget.onConfigure,
                  style: MenuItemButton.styleFrom(
                    foregroundColor: _foreground,
                    disabledForegroundColor: _foreground,
                    textStyle: _text(13),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 15, color: _foreground),
                      const SizedBox(width: 6),
                      const Text('配置智能体'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  String get _description =>
      _preview.description.isEmpty ? '暂无描述' : _preview.description;

  Widget _tag(String label) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _border),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: _text(12)),
        ),
      );

  Widget _capability(String label, String status, {bool warning = false}) =>
      Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: warning
              ? (_dark ? const Color(0xFF312C24) : const Color(0xFFFFF8E9))
              : _fill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: warning ? const Color(0xFFA56C00) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _text(12)),
            const SizedBox(width: 10),
            Text(
              status,
              style: _text(
                10,
                color: warning ? _amber : _secondary,
                weight: warning ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );

  Widget _details() => _card(
        SingleChildScrollView(
          primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 10, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: OverflowBox(
                        maxWidth: 64,
                        maxHeight: 64,
                        child: Icon(Icons.stop_rounded, size: 64, color: _blue),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _preview.name,
                              key: const ValueKey('agent-picker-detail-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(16, weight: FontWeight.w600),
                            ),
                            Row(
                              children: [
                                Icon(
                                  _preview.key == _selected.key
                                      ? Icons.check_circle_outline
                                      : Icons.smart_toy_outlined,
                                  size: 14,
                                  color: _blue,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _preview.key == _selected.key
                                      ? '当前智能体'
                                      : '点击使用',
                                  style: _text(12, color: _secondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  _description,
                  style: _text(13, color: _secondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child:
                    Divider(height: 24, color: _border.withValues(alpha: .6)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _tag(
                      _preview.smart ? '智能推理' : '快速问答',
                    ),
                    _tag(
                      switch (_preview.knowledgeScope) {
                        'all' => '可访问的知识库',
                        'selected' => '指定知识库',
                        _ => '未关联知识库',
                      },
                    ),
                    if (_preview.multiTurn) _tag('多轮对话'),
                    if (_preview.sourceTenantId != null) _tag('使用共享方配置'),
                  ],
                ),
              ),
              Divider(height: 20, color: _border.withValues(alpha: .6)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('能力', style: _text(12, color: _secondary)),
                    const SizedBox(height: 11),
                    _capability('网络搜索', _preview.webSearch ? '已启用' : '未启用'),
                    const SizedBox(height: 10),
                    _capability('图片上传', _preview.imageUpload ? '支持' : '不支持'),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 440;
          final gap = compact ? 8.0 : 13.0;
          final leftWidth =
              compact ? (constraints.maxWidth - gap) * .44 : 236.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: leftWidth,
                height: constraints.maxHeight,
                child: _navigation(),
              ),
              SizedBox(width: gap),
              Expanded(
                child: SizedBox(
                  height: constraints.maxHeight - 4,
                  child: _details(),
                ),
              ),
            ],
          );
        },
      );
}
