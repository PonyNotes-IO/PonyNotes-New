import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_cubit.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_strings.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KnowledgeGraphPage extends StatelessWidget {
  const KnowledgeGraphPage({super.key});

  @override
  Widget build(BuildContext context) {
    final workspaceId = context.select(
      (UserWorkspaceBloc bloc) => bloc.state.currentWorkspace?.workspaceId,
    );
    if (workspaceId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return BlocProvider(
      key: ValueKey(workspaceId),
      create: (_) => KnowledgeGraphCubit(workspaceId: workspaceId)..start(),
      child: KnowledgeGraphView(
        onOpen: (node) {
          context.read<TabsBloc>().openPlugin(node.view);
        },
      ),
    );
  }
}

class KnowledgeGraphView extends StatefulWidget {
  const KnowledgeGraphView({super.key, required this.onOpen});

  final ValueChanged<GraphNode> onOpen;

  @override
  State<KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<KnowledgeGraphView> {
  final _canvasKey = GlobalKey<KnowledgeGraphCanvasState>();
  final _search = TextEditingController();
  bool _settings = false;
  bool _labels = true;
  bool _hierarchy = true;
  bool _orphans = true;
  KnowledgeGraphData? _source;
  KnowledgeGraphData _visible = const KnowledgeGraphData();

  void _filter() {
    _source = null;
    setState(() {});
  }

  void _reset() {
    _search.clear();
    _hierarchy = _orphans = true;
    _filter();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<KnowledgeGraphCubit, KnowledgeGraphState>(
      builder: (context, state) {
        if (!identical(_source, state.data)) {
          _source = state.data;
          _visible = state.data.filtered(
            query: _search.text,
            hierarchy: _hierarchy,
            orphans: _orphans,
          );
        }
        return Material(
          color: theme.scaffoldBackgroundColor,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.hub_outlined, size: 18, color: theme.hintColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        graphText(context, 'title'),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    _tool(
                      'refresh',
                      Icons.refresh,
                      state.indexing
                          ? null
                          : () => context.read<KnowledgeGraphCubit>().refresh(),
                    ),
                    _tool(
                      'filters',
                      Icons.tune,
                      () => setState(() => _settings = !_settings),
                      selected: _settings,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Overlay the panel on narrow windows, keep the graph spacious otherwise.
                    final wide = constraints.maxWidth >= 760;
                    final graph = Stack(
                      children: [
                        Positioned.fill(child: _body(state)),
                        if (!state.loading && _visible.nodes.isNotEmpty) ...[
                          Positioned(
                            left: 20,
                            bottom: 16,
                            right: 65,
                            child: IgnorePointer(
                              child: Text(
                                '${_visible.nodes.length} ${graphText(context, 'nodes')}  ·  ${_visible.edges.length} ${graphText(context, 'edges')}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Material(
                              color: theme.scaffoldBackgroundColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: theme.dividerColor
                                      .withValues(alpha: 0.15),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _tool(
                                    'zoomIn',
                                    Icons.add,
                                    () => _canvasKey.currentState?.zoom(1.25),
                                  ),
                                  _tool(
                                    'zoomOut',
                                    Icons.remove,
                                    () => _canvasKey.currentState?.zoom(0.8),
                                  ),
                                  _tool(
                                    'fit',
                                    Icons.center_focus_strong_outlined,
                                    () => _canvasKey.currentState?.fit(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (state.indexing ||
                            state.failedDocuments > 0 ||
                            state.error && state.data.nodes.isNotEmpty)
                          Positioned(
                            left: 20,
                            top: 8,
                            right: 20,
                            child: Row(
                              children: [
                                if (state.indexing) ...[
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    graphText(
                                      context,
                                      state.indexing
                                          ? 'indexing'
                                          : state.error
                                              ? 'error'
                                              : 'partial',
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_settings && !wide)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 0,
                            width:
                                constraints.maxWidth.clamp(0, 280).toDouble(),
                            child: _panel(),
                          ),
                      ],
                    );
                    return Row(
                      children: [
                        Expanded(child: graph),
                        if (_settings && wide)
                          SizedBox(width: 280, child: _panel()),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(KnowledgeGraphState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (state.error && state.data.nodes.isEmpty) {
      return _message(
        'error',
        action: 'retry',
        onTap: () => context.read<KnowledgeGraphCubit>().refresh(),
      );
    }
    if (state.data.nodes.isEmpty) return _message('empty', hint: 'emptyHint');
    if (_visible.nodes.isEmpty) {
      return _message('noResults', action: 'reset', onTap: _reset);
    }
    return Tooltip(
      message: graphText(context, 'hint'),
      waitDuration: const Duration(seconds: 3),
      child: KnowledgeGraphCanvas(
        key: _canvasKey,
        data: _visible,
        showLabels: _labels,
        onOpen: widget.onOpen,
      ),
    );
  }

  Widget _message(
    String title, {
    String? hint,
    String? action,
    VoidCallback? onTap,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hub_outlined,
                size: 36,
                color: Theme.of(context).hintColor,
              ),
              const SizedBox(height: 16),
              Text(graphText(context, title), textAlign: TextAlign.center),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  graphText(context, hint),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onTap,
                  child: Text(graphText(context, action)),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _tool(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool selected = false,
  }) =>
      IconButton(
        tooltip: graphText(context, label),
        onPressed: onTap,
        isSelected: selected,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon),
      );

  Widget _panel() {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      shape: Border(
        left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    graphText(context, 'filters'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => setState(() => _settings = false),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => _filter(),
              decoration: InputDecoration(
                hintText: graphText(context, 'search'),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 24),
            _toggle('hierarchy', _hierarchy, (value) {
              _hierarchy = value;
              _filter();
            }),
            _toggle('orphans', _orphans, (value) {
              _orphans = value;
              _filter();
            }),
            _toggle(
              'labels',
              _labels,
              (value) => setState(() => _labels = value),
            ),
            const SizedBox(height: 12),
            Text(
              graphText(context, 'hint'),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _reset,
              child: Text(graphText(context, 'reset')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile.adaptive(
        title: Text(
          graphText(context, label),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
      );
}
