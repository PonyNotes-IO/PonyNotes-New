import 'dart:math' as math;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_cubit.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_extraction.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_strings.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/shared/settings/show_settings.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KnowledgeGraphPage extends StatelessWidget {
  const KnowledgeGraphPage({super.key, this.focusView});

  final ViewPB? focusView;

  @override
  Widget build(BuildContext context) {
    final identity = context.select(
      (UserWorkspaceBloc bloc) => (
        bloc.state.userProfile.id.toString(),
        bloc.state.currentWorkspace?.workspaceId,
      ),
    );
    final workspaceId = identity.$2;
    if (workspaceId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return BlocProvider(
      key: ValueKey((identity, focusView?.id)),
      create: (_) => KnowledgeGraphCubit(
        workspaceId: workspaceId,
        focusViewId: focusView?.id,
        cache: GraphExtractionCache(
          userId: identity.$1,
          workspaceId: workspaceId,
          viewId: focusView?.id,
        ),
      )..start(),
      child: KnowledgeGraphView(
        focusView: focusView,
        onOpen: (node) {
          context.read<TabsBloc>().openPlugin(node.view);
        },
        onOpenSource: (view, blockId) {
          context.read<TabsBloc>().openPlugin(
            view,
            arguments: {PluginArgumentKeys.blockId: blockId},
          );
        },
        onConfigureModel: () {
          final bloc = context.read<UserWorkspaceBloc>();
          showSettingsDialog(
            context,
            bloc.state.userProfile,
            bloc,
            SettingsPage.aiProvider,
          );
        },
      ),
    );
  }
}

class KnowledgeGraphView extends StatefulWidget {
  const KnowledgeGraphView({
    super.key,
    required this.onOpen,
    this.onOpenSource,
    this.onConfigureModel,
    this.focusView,
  });

  final ValueChanged<GraphNode> onOpen;
  final void Function(ViewPB view, String blockId)? onOpenSource;
  final VoidCallback? onConfigureModel;
  final ViewPB? focusView;

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
  bool _entitiesOnly = true;
  String _entityType = '';
  String? _focus;
  GraphNode? _selected;
  GraphEdge? _selectedEdge;
  KnowledgeGraphData? _source;
  KnowledgeGraphData _scoped = const KnowledgeGraphData();
  KnowledgeGraphData _visible = const KnowledgeGraphData();

  @override
  void initState() {
    super.initState();
    _entitiesOnly = widget.focusView == null;
  }

  @override
  void didUpdateWidget(KnowledgeGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusView?.id != widget.focusView?.id) {
      _source = null;
      _focus = null;
      _selected = null;
      _selectedEdge = null;
      _entitiesOnly = widget.focusView == null;
      _search.clear();
    }
  }

  void _filter() {
    _source = null;
    setState(() {});
  }

  void _reset() {
    _search.clear();
    _hierarchy = _orphans = true;
    _entityType = '';
    _focus = null;
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
    final toolbarColor = theme.colorScheme.onSurface.withValues(alpha: 0.3);
    final canExtract = widget.focusView == null ||
        KnowledgeGraphBuilder.isDocument(widget.focusView!);
    final toolbarStyle = IconButton.styleFrom(
      fixedSize: const Size.square(40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return BlocBuilder<KnowledgeGraphCubit, KnowledgeGraphState>(
      builder: (context, state) {
        if (!identical(_source, state.data)) {
          _source = state.data;
          _scoped = widget.focusView == null
              ? state.data
              : state.data.filtered(
                  focus: widget.focusView!.id,
                  hierarchy: _hierarchy,
                );
          _selected =
              state.data.nodes.where((n) => n.id == _selected?.id).firstOrNull;
          _selectedEdge =
              state.data.edges.where((e) => e == _selectedEdge).firstOrNull;
          _visible = _scoped.filtered(
            query: _search.text,
            hierarchy: _hierarchy,
            orphans: _orphans,
            entitiesOnly: _entitiesOnly,
            documentsOnly: !_entitiesOnly,
            entityType: _entityType,
            focus: _focus,
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
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (widget.focusView == null) ...[
                      _tool(
                        'shareUnavailable',
                        Transform.rotate(
                          angle: -math.pi / 4,
                          child: Icon(
                            Icons.send_outlined,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        null,
                        iconSize: 28,
                        style: toolbarStyle,
                      ),
                      _tool(
                        'favoriteUnavailable',
                        Icon(Icons.star_border, color: toolbarColor),
                        null,
                        iconSize: 34,
                        style: toolbarStyle,
                      ),
                    ],
                    ValueListenableBuilder<bool>(
                      valueListenable: FullWindowController.isFullWindow,
                      builder: (context, isFullWindow, _) => _tool(
                        isFullWindow ? 'exitFullscreen' : 'fullscreen',
                        Icon(
                          isFullWindow
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: toolbarColor,
                        ),
                        () => isFullWindow
                            ? FullWindowController.exitAndExpandMenu(context)
                            : FullWindowController.enter(),
                        iconSize: 36,
                        style: toolbarStyle,
                      ),
                    ),
                    SizedBox.square(
                      dimension: 40,
                      child: PopupMenuButton<VoidCallback>(
                        tooltip: LocaleKeys.button_more.tr(),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz,
                          size: 32,
                          color: toolbarColor,
                        ),
                        onSelected: (action) => action(),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            enabled: state.extracting ||
                                !(state.loading ||
                                    state.indexing ||
                                    state.error ||
                                    state.data.nodes.isEmpty ||
                                    !canExtract),
                            value: state.extracting
                                ? context
                                    .read<KnowledgeGraphCubit>()
                                    .cancelExtraction
                                : context.read<KnowledgeGraphCubit>().extract,
                            child: Text(
                              graphText(
                                context,
                                state.extracting ? 'cancel' : 'extract',
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            enabled: !state.indexing && !state.extracting,
                            value: () =>
                                context.read<KnowledgeGraphCubit>().refresh(),
                            child: Text(graphText(context, 'refresh')),
                          ),
                          PopupMenuItem(
                            value: () => setState(() => _settings = !_settings),
                            child: Text(graphText(context, 'filters')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entities in [if (canExtract) true, false]) ...[
                      ChoiceChip(
                        label: Text(
                          graphText(
                            context,
                            entities ? 'entityGraph' : 'documentLinks',
                          ),
                        ),
                        selected: _entitiesOnly == entities,
                        onSelected: (_) {
                          _entitiesOnly = entities;
                          _selected = null;
                          _selectedEdge = null;
                          _reset();
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (state.extracting ||
                  state.extractionError.isNotEmpty ||
                  state.cacheError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      if (state.extracting) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          state.extracting
                              ? '${graphText(context, 'extracting')} ${state.completedChunks}/${state.totalChunks}'
                              : graphText(
                                  context,
                                  state.cacheError
                                      ? 'cacheError'
                                      : 'aiErrors.${state.extractionError}',
                                ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (state.extractionError == 'notConfigured' &&
                          widget.onConfigureModel != null)
                        TextButton(
                          onPressed: widget.onConfigureModel,
                          child: Text(graphText(context, 'configureModel')),
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
                                    const Icon(Icons.add),
                                    () => _canvasKey.currentState?.zoom(1.25),
                                  ),
                                  _tool(
                                    'zoomOut',
                                    const Icon(Icons.remove),
                                    () => _canvasKey.currentState?.zoom(0.8),
                                  ),
                                  _tool(
                                    'fit',
                                    const Icon(
                                      Icons.center_focus_strong_outlined,
                                    ),
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
                        if ((_settings || _selected != null) && !wide)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 0,
                            width:
                                constraints.maxWidth.clamp(0, 320).toDouble(),
                            child: _settings ? _panel() : _details(state.data),
                          ),
                      ],
                    );
                    return Row(
                      children: [
                        Expanded(child: graph),
                        if ((_settings || _selected != null) && wide)
                          SizedBox(
                            width: 320,
                            child: _settings ? _panel() : _details(state.data),
                          ),
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
    if (_entitiesOnly && !_scoped.nodes.any((n) => n.entityType != null)) {
      if (state.indexing || state.extracting) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      final needsModel = state.extractionError == 'notConfigured';
      final completed = state.totalChunks > 0 &&
          state.completedChunks == state.totalChunks &&
          state.extractionError.isEmpty;
      return _message(
        needsModel
            ? 'setupTitle'
            : completed
                ? 'noEntities'
                : 'emptyGraph',
        hint: needsModel ? 'setupHint' : 'extractHint',
        action: needsModel ? 'configureModel' : 'extract',
        onTap: needsModel
            ? widget.onConfigureModel
            : context.read<KnowledgeGraphCubit>().extract,
      );
    }
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
        selectedId: _selected?.id ?? widget.focusView?.id,
        onOpen: (node) {
          if (node.entityType == null) {
            widget.onOpen(node);
          } else {
            setState(() {
              _selected = node;
              _selectedEdge = null;
              _settings = false;
            });
          }
        },
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
    Widget icon,
    VoidCallback? onTap, {
    double iconSize = 18,
    ButtonStyle? style,
  }) =>
      IconButton(
        tooltip: graphText(context, label),
        onPressed: onTap,
        iconSize: iconSize,
        style: style,
        visualDensity: VisualDensity.compact,
        icon: icon,
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
            if (_entitiesOnly)
              DropdownButtonFormField<String>(
                key: ValueKey(_entityType),
                initialValue: _entityType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: graphText(context, 'entityType'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(graphText(context, 'allTypes')),
                  ),
                  for (final type in graphEntityTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(graphText(context, 'types.$type')),
                    ),
                ],
                onChanged: (type) {
                  _entityType = type ?? '';
                  _filter();
                },
              ),
            if (!_entitiesOnly)
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
            if (widget.onConfigureModel != null)
              TextButton(
                onPressed: widget.onConfigureModel,
                child: Text(graphText(context, 'configureModel')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details(KnowledgeGraphData data) {
    final node = _selected!;
    final relations = data.edges.where(
      (e) =>
          e.kind == GraphEdgeKind.relation &&
          (e.source == node.id || e.target == node.id),
    );
    final nodes = {for (final n in data.nodes) n.id: n};
    final theme = Theme.of(context);
    final sources = _selectedEdge?.sources ?? node.sources;
    return Material(
      color: theme.scaffoldBackgroundColor,
      shape: Border(
        left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(node.label, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => setState(() {
                  _selected = null;
                  _selectedEdge = null;
                }),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Text(
            graphText(context, 'types.${node.entityType}'),
            style: theme.textTheme.labelMedium,
          ),
          if (node.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(node.description),
          ],
          TextButton.icon(
            onPressed: () {
              _focus = node.id;
              _filter();
            },
            icon: const Icon(Icons.hub_outlined, size: 16),
            label: Text(graphText(context, 'neighbors')),
          ),
          if (_focus != null)
            TextButton(
              onPressed: () {
                _focus = null;
                _filter();
              },
              child: Text(graphText(context, 'showAll')),
            ),
          const Divider(),
          Text(
            graphText(context, 'relations'),
            style: theme.textTheme.titleSmall,
          ),
          if (relations.isEmpty) Text(graphText(context, 'noRelations')),
          for (final edge in relations)
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: _selectedEdge == edge,
              title: Text(
                '${nodes[edge.source]?.label} → ${nodes[edge.target]?.label}',
              ),
              subtitle: Text(edge.label),
              onTap: () => setState(() => _selectedEdge = edge),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  graphText(context, 'sources'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (_selectedEdge != null)
                IconButton(
                  tooltip: graphText(context, 'entitySources'),
                  onPressed: () => setState(() => _selectedEdge = null),
                  icon: const Icon(Icons.clear, size: 16),
                ),
            ],
          ),
          if (_selectedEdge != null) Text(_selectedEdge!.label),
          for (final source in sources)
            if (nodes[source.viewId] case final page?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        if (widget.onOpenSource != null) {
                          widget.onOpenSource!(page.view, source.blockId);
                        } else {
                          widget.onOpen(page);
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(
                        page.label.isEmpty
                            ? graphText(context, 'untitled')
                            : page.label,
                      ),
                    ),
                    SelectableText(
                      source.text,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
        ],
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
