import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/presentation/note_block_navigation.dart';
import 'package:appflowy/plugins/note_graph/application/note_graph_cubit.dart';
import 'package:appflowy/plugins/note_graph/application/note_graph_data.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'note_graph_canvas.dart';

String noteGraphText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

class NoteGraphPage extends StatelessWidget {
  const NoteGraphPage({super.key, this.focusView});
  final ViewPB? focusView;

  @override
  Widget build(BuildContext context) {
    final identity = context.select(
      (UserWorkspaceBloc bloc) => (
        bloc.state.userProfile.id.toString(),
        bloc.state.currentWorkspace?.workspaceId,
      ),
    );
    final workspace = identity.$2;
    if (workspace == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return BlocProvider(
      key: ValueKey((identity, focusView?.id)),
      create: (_) => NoteGraphCubit(workspaceId: workspace)..start(),
      child: NoteGraphView(
        focusId: focusView?.id,
        onOpen: (view, block) {
          if (block != null && block.isNotEmpty) {
            NoteBlockNavigation.request(view.id, block);
          }
          context.read<TabsBloc>().openPlugin(
            view,
            arguments: {
              if (block != null) PluginArgumentKeys.blockId: block,
            },
          );
        },
      ),
    );
  }
}

class NoteGraphView extends StatefulWidget {
  const NoteGraphView({super.key, this.focusId, required this.onOpen});
  final String? focusId;
  final void Function(ViewPB view, String? blockId) onOpen;
  @override
  State<NoteGraphView> createState() => _NoteGraphViewState();
}

class _NoteGraphViewState extends State<NoteGraphView> {
  final _canvas = GlobalKey<NoteGraphCanvasState>();
  final _search = TextEditingController();
  String? _focus;
  String? _selected;
  (String, String)? _edge;
  int _depth = 1;
  bool _isolated = true;
  bool _blocksOnly = false;
  bool _labels = true;
  bool _inspector = false;
  int _referenceLimit = 20;
  NoteGraphDirection _direction = NoteGraphDirection.both;
  NoteGraphData? _source;
  NoteGraphData? _visible;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusId;
    _selected = widget.focusId;
  }

  @override
  void didUpdateWidget(NoteGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusId != widget.focusId) {
      _focus = widget.focusId;
      _selected = widget.focusId;
      _edge = null;
      _visible = null;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(VoidCallback change) => setState(() {
        change();
        _visible = null;
      });
  void _selectNote(String id) => setState(() {
        _selected = id;
        _edge = null;
        _inspector = true;
      });
  void _selectEdge(NoteGraphEdge edge) => setState(() {
        _edge = edge.key;
        _referenceLimit = 20;
        _selected = null;
        _inspector = true;
      });
  String text(String zh, String en) => noteGraphText(context, zh, en);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NoteGraphCubit, NoteGraphState>(
        builder: (context, state) {
          if (!identical(_source, state.data)) {
            _source = state.data;
            _visible = null;
          }
          final data = _visible ??= state.data.filtered(
            query: _search.text,
            focus: _focus,
            depth: _depth,
            direction: _direction,
            showIsolated: _isolated,
            blocksOnly: _blocksOnly,
          );
          final focusView = state.data.notes[_focus];
          final selectedView = state.data.notes[_selected];
          final selectedEdge =
              state.data.edges.where((edge) => edge.key == _edge).firstOrNull;
          final theme = Theme.of(context);
          return Material(
            color: theme.scaffoldBackgroundColor,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text('双链图谱', 'Note link graph'),
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              text(
                                '笔记之间真实建立的引用关系',
                                'Explicit references between your notes',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: text('刷新关系', 'Refresh relationships'),
                        onPressed: state.loading
                            ? null
                            : context.read<NoteGraphCubit>().refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: text('关系详情', 'Relationship details'),
                        onPressed: () =>
                            setState(() => _inspector = !_inspector),
                        icon: Icon(
                          _inspector
                              ? Icons.view_sidebar
                              : Icons.view_sidebar_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    key: const ValueKey('note-graph-search'),
                    controller: _search,
                    onChanged: (_) => _filter(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: text('搜索笔记名称', 'Search note titles'),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: text('清除搜索', 'Clear search'),
                              onPressed: () => _filter(_search.clear),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: Text(text('全部笔记', 'All notes')),
                        selected: _focus == null,
                        onSelected: (_) => _filter(() {
                          _focus = null;
                          _direction = NoteGraphDirection.both;
                        }),
                      ),
                      if (focusView != null)
                        InputChip(
                          label: Text(
                            text(
                              '围绕：${focusView.name}',
                              'Around: ${focusView.name}',
                            ),
                          ),
                          selected: true,
                          onDeleted: () => _filter(() => _focus = null),
                        ),
                      if (_focus != null) ...[
                        DropdownButton<int>(
                          value: _depth,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final value in [1, 2, 3])
                              DropdownMenuItem(
                                value: value,
                                child: Text(
                                  text('$value 跳关系', '$value hops'),
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              _filter(() => _depth = value ?? 1),
                        ),
                        DropdownButton<NoteGraphDirection>(
                          value: _direction,
                          underline: const SizedBox.shrink(),
                          items: [
                            DropdownMenuItem(
                              value: NoteGraphDirection.both,
                              child: Text(text('全部方向', 'Both directions')),
                            ),
                            DropdownMenuItem(
                              value: NoteGraphDirection.incoming,
                              child: Text(
                                text('谁引用它', 'Incoming references'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: NoteGraphDirection.outgoing,
                              child: Text(
                                text('它引用谁', 'Outgoing references'),
                              ),
                            ),
                          ],
                          onChanged: (value) => _filter(
                            () => _direction = value ?? NoteGraphDirection.both,
                          ),
                        ),
                      ],
                      FilterChip(
                        label: Text(text('只看段落引用', 'Paragraph references')),
                        selected: _blocksOnly,
                        onSelected: (value) =>
                            _filter(() => _blocksOnly = value),
                      ),
                      if (_focus == null)
                        FilterChip(
                          label: Text(text('显示未关联笔记', 'Unconnected notes')),
                          selected: _isolated,
                          onSelected: (value) =>
                              _filter(() => _isolated = value),
                        ),
                      FilterChip(
                        label: Text(text('显示标题', 'Titles')),
                        selected: _labels,
                        onSelected: (value) => setState(() => _labels = value),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 850;
                      final inspector =
                          _inspector && !state.loading && !state.error;
                      final graph = state.loading
                          ? const Center(child: CircularProgressIndicator())
                          : state.error
                              ? _empty(
                                  Icons.cloud_off_outlined,
                                  text(
                                    '暂时无法读取笔记关系',
                                    'Could not load note relationships',
                                  ),
                                  text('请重试加载', 'Try loading again'),
                                  onRetry:
                                      context.read<NoteGraphCubit>().refresh,
                                )
                              : data.notes.isEmpty
                                  ? _empty(
                                      Icons.account_tree_outlined,
                                      _focus != null &&
                                              !state.data.notes
                                                  .containsKey(_focus)
                                          ? text(
                                              '这篇笔记暂不可用',
                                              'This note is unavailable',
                                            )
                                          : text(
                                              '没有匹配的笔记',
                                              'No matching notes',
                                            ),
                                      _search.text.isNotEmpty || _blocksOnly
                                          ? text(
                                              '试试清除搜索或调整筛选',
                                              'Try clearing the search or changing filters',
                                            )
                                          : text(
                                              '在正文中使用 [[ 或“引用段落”，关系会自动出现在这里',
                                              'Use [[ or “Reference a paragraph” in a note to create a connection',
                                            ),
                                    )
                                  : Stack(
                                      children: [
                                        NoteGraphCanvas(
                                          key: _canvas,
                                          data: data,
                                          focusNote: _focus,
                                          selectedNote: _selected,
                                          selectedEdge: _edge,
                                          labels: _labels,
                                          untitled: text('未命名', 'Untitled'),
                                          onSelectNote: _selectNote,
                                          onSelectEdge: _selectEdge,
                                          onOpenNote: (id) {
                                            final view = state.data.notes[id];
                                            if (view != null) {
                                              widget.onOpen(view, null);
                                            }
                                          },
                                        ),
                                        PositionedDirectional(
                                          top: 12,
                                          end: 12,
                                          child: Card(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip:
                                                      text('放大', 'Zoom in'),
                                                  onPressed: () => _canvas
                                                      .currentState
                                                      ?.zoom(1.25),
                                                  icon: const Icon(Icons.add),
                                                ),
                                                IconButton(
                                                  tooltip:
                                                      text('缩小', 'Zoom out'),
                                                  onPressed: () => _canvas
                                                      .currentState
                                                      ?.zoom(.8),
                                                  icon:
                                                      const Icon(Icons.remove),
                                                ),
                                                IconButton(
                                                  tooltip:
                                                      text('适应画布', 'Fit graph'),
                                                  onPressed: () => _canvas
                                                      .currentState
                                                      ?.fit(),
                                                  icon: const Icon(
                                                    Icons.center_focus_strong,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                      final details =
                          _details(state, selectedView, selectedEdge);
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: graph),
                            if (inspector)
                              SizedBox(
                                width: 330,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: BorderDirectional(
                                      start: BorderSide(
                                        color: theme.dividerColor,
                                      ),
                                    ),
                                  ),
                                  child: details,
                                ),
                              ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(child: graph),
                          if (inspector)
                            SizedBox(
                              height: constraints.maxHeight * .44,
                              child: details,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.loading
                              ? text('正在加载关系…', 'Loading relationships…')
                              : text(
                                  '${data.notes.length} 篇笔记 · ${data.edges.length} 条有向关系',
                                  '${data.notes.length} notes · ${data.edges.length} directed relationships',
                                ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Tooltip(
                        message: text(
                          '箭头由引用者指向被引用者；点击连线查看片段',
                          'Arrows point from source to target. Select a connection to see passages.',
                        ),
                        child: const Icon(Icons.info_outline, size: 16),
                      ),
                    ],
                  ),
                ),
                if (state.incomplete ||
                    state.truncated ||
                    data.omittedNotes > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      data.omittedNotes > 0
                          ? text(
                              '当前隐藏 ${data.omittedNotes} 篇笔记，可通过搜索或局部图谱缩小范围',
                              '${data.omittedNotes} notes hidden. Search or focus on a note to narrow the graph.',
                            )
                          : state.truncated
                              ? text(
                                  '关系较多，当前显示部分结果',
                                  'Only part of the relationships are shown',
                                )
                              : text(
                                  '部分笔记尚未同步，关系可能不完整',
                                  'Some notes are not synced yet; relationships may be incomplete',
                                ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _empty(
    IconData icon,
    String title,
    String detail, {
    VoidCallback? onRetry,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: Theme.of(context).hintColor),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(text('重试', 'Retry')),
                ),
            ],
          ),
        ),
      );

  Widget _details(NoteGraphState state, ViewPB? view, NoteGraphEdge? edge) {
    final graph = state.data;
    final cubit = context.read<NoteGraphCubit>();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          ListTile(
            title: Text(text('引用详情', 'Reference details')),
            trailing: IconButton(
              tooltip: text('关闭详情', 'Close details'),
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _inspector = false),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (view == null && edge == null)
                  Text(
                    text(
                      '选择笔记查看双向关系，或选择连线查看引用片段',
                      'Select a note to explore its links, or a connection to inspect passages.',
                    ),
                  ),
                if (view != null) ...[
                  Text(
                    view.name.isEmpty ? text('未命名', 'Untitled') : view.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      Text(
                        text(
                          '${graph.incomingTo(view.id).length} 篇引用它',
                          '${graph.incomingTo(view.id).length} incoming notes',
                        ),
                      ),
                      Text(
                        text(
                          '引用 ${graph.outgoingFrom(view.id).length} 篇',
                          '${graph.outgoingFrom(view.id).length} outgoing notes',
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => widget.onOpen(view, null),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(text('打开笔记', 'Open note')),
                      ),
                      TextButton.icon(
                        onPressed: () => _filter(() => _focus = view.id),
                        icon: const Icon(Icons.center_focus_weak, size: 16),
                        label: Text(text('围绕此笔记', 'Focus on this note')),
                      ),
                    ],
                  ),
                  for (final incoming in [true, false]) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 6),
                      child: Text(
                        incoming
                            ? text('引用此笔记', 'References to this note')
                            : text('本文引用', 'References from this note'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (!graph.edges.any(
                      (edge) =>
                          (incoming ? edge.target : edge.source) == view.id,
                    ))
                      Text(
                        text('暂无引用', 'No references yet'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final relation in graph.edges.where(
                      (edge) =>
                          (incoming ? edge.target : edge.source) == view.id,
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          incoming ? Icons.call_received : Icons.call_made,
                          size: 16,
                        ),
                        title: Text(
                          graph
                              .notes[
                                  incoming ? relation.source : relation.target]!
                              .name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          text(
                            '${relation.occurrences} 处引用',
                            '${relation.occurrences} references',
                          ),
                        ),
                        onTap: () => _selectEdge(relation),
                      ),
                  ],
                ],
                if (edge != null) ...[
                  Text(
                    '${graph.notes[edge.source]!.name} → ${graph.notes[edge.target]!.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text(
                      '${edge.occurrences} 处引用 · ${edge.blockReferences} 处指向段落',
                      '${edge.occurrences} references · ${edge.blockReferences} passage targets',
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final reference in edge.references.take(_referenceLimit))
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              text('来源片段', 'Source passage'),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            _excerpt(
                              cubit,
                              edge.source,
                              reference.srcBlockId,
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                onPressed: () => widget.onOpen(
                                  graph.notes[edge.source]!,
                                  reference.srcBlockId,
                                ),
                                child: Text(
                                  text(
                                    '返回引用位置',
                                    'Open source passage',
                                  ),
                                ),
                              ),
                            ),
                            const Divider(),
                            Text(
                              reference.dstBlockId.isEmpty
                                  ? text('引用整篇笔记', 'Whole-note reference')
                                  : text('目标片段', 'Target passage'),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            if (reference.dstBlockId.isNotEmpty)
                              _excerpt(
                                cubit,
                                edge.target,
                                reference.dstBlockId,
                              ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                onPressed: () => widget.onOpen(
                                  graph.notes[edge.target]!,
                                  reference.dstBlockId.isEmpty
                                      ? null
                                      : reference.dstBlockId,
                                ),
                                child: Text(
                                  reference.dstBlockId.isEmpty
                                      ? text('打开目标笔记', 'Open target note')
                                      : text(
                                          '定位目标段落',
                                          'Open target passage',
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (edge.references.length > _referenceLimit)
                    TextButton(
                      onPressed: () => setState(() => _referenceLimit += 20),
                      child: Text(text('查看更多引用片段', 'Show more passages')),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _excerpt(NoteGraphCubit cubit, String page, String block) =>
      FutureBuilder<String>(
        key: ValueKey((cubit.state.data, page, block)),
        future: cubit.excerpt(page, block),
        builder: (context, snapshot) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            snapshot.connectionState != ConnectionState.done
                ? text('正在读取片段…', 'Loading passage…')
                : snapshot.data?.isNotEmpty == true
                    ? snapshot.data!
                    : text('片段为空或暂不可用', 'Passage is empty or unavailable'),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}
