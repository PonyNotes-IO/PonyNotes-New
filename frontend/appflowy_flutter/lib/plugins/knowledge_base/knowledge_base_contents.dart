import 'package:appflowy/plugins/knowledge_base/knowledge_base_cubit.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_canvas.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const knowledgeBaseMiddlePaneWidth = 280.0;

TabBar knowledgeBaseTabs(
  BuildContext context, {
  required ValueChanged<int> onTap,
}) =>
    TabBar(
      labelPadding: EdgeInsets.zero,
      labelStyle:
          Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 13),
      tabs: [
        Tab(text: kbText(context, '文件', 'Files')),
        const Tab(text: 'Wiki'),
        Tab(text: kbText(context, '图谱', 'Graph')),
      ],
      onTap: onTap,
    );

class KnowledgeBaseContents extends StatefulWidget {
  const KnowledgeBaseContents({
    super.key,
    required this.base,
    required this.onBack,
    required this.onRefreshBases,
    this.initialTab = 0,
  });

  final KnowledgeBase base;
  final VoidCallback onBack;
  final VoidCallback onRefreshBases;
  final int initialTab;

  @override
  State<KnowledgeBaseContents> createState() => _KnowledgeBaseContentsState();
}

class _KnowledgeBaseContentsState extends State<KnowledgeBaseContents> {
  Future<Map<String, dynamic>>? _files;
  Future<Map<String, dynamic>>? _sources;
  Future<Map<String, dynamic>>? _wiki;
  Future<Map<String, dynamic>>? _preview;
  Map<String, dynamic>? _selected;
  bool _isSource = false;
  late int _tab = widget.initialTab;
  String _query = '';
  Map<String, dynamic>? _graphSource;
  KnowledgeGraphData _graph = const KnowledgeGraphData();

  KnowledgeBaseService get _service =>
      context.read<KnowledgeBaseCubit>().service;

  Future<Map<String, dynamic>> _request(String action) =>
      _service.post(action, widget.base.target);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _files = _tab == 0 ? _request('documents') : null;
    _sources = _tab == 0 ? _request('sources') : null;
    _wiki = _tab != 0 ? _request('wiki') : null;
    _selected = null;
    _preview = null;
  }

  void _open(Map<String, dynamic> entry, {bool source = false}) {
    setState(() {
      _selected = entry;
      _isSource = source;
      _preview = source
          ? null
          : _service.post(_tab == 0 ? 'document' : 'wiki_page', {
              ...widget.base.target,
              _tab == 0 ? 'document_id' : 'slug': entry['id'],
            });
    });
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            SizedBox(
              key: const ValueKey('knowledge-base-middle-pane'),
              width: knowledgeBaseMiddlePaneWidth,
              child: DefaultTabController(
                length: 3,
                initialIndex: widget.initialTab,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: kbText(
                              context,
                              '返回知识库列表',
                              'Back to knowledge bases',
                            ),
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.chevron_left, size: 20),
                          ),
                          Expanded(
                            child: Text(
                              widget.base.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: kbText(context, '刷新', 'Refresh'),
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: () {
                              setState(_load);
                              widget.onRefreshBases();
                            },
                          ),
                        ],
                      ),
                    ),
                    knowledgeBaseTabs(
                      context,
                      onTap: (index) => setState(() {
                        _tab = index;
                        _query = '';
                        _selected = null;
                        _preview = null;
                        if (index == 0) {
                          _files ??= _request('documents');
                          _sources ??= _request('sources');
                        } else {
                          _wiki ??= _request('wiki');
                        }
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        key: ValueKey(_tab),
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 16),
                          hintText: kbText(
                            context,
                            '搜索当前知识库',
                            'Search this knowledge base',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: _sources,
                        builder: (_, sources) => _navigation(sources),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _selected != null
                  ? _detail()
                  : _tab == 2
                      ? _graphView()
                      : _notice(
                          kbText(
                            context,
                            '选择左侧条目以查看内容。',
                            'Select an item to view its content.',
                          ),
                        ),
            ),
          ],
        ),
      );

  Widget _navigation(AsyncSnapshot<Map<String, dynamic>> sources) =>
      FutureBuilder<Map<String, dynamic>>(
        future: _tab == 0 ? _files : _wiki,
        builder: (context, snapshot) {
          final field = _tab == 0 ? 'documents' : 'pages';
          final entries = (snapshot.data?[field] as List? ?? [])
              .cast<Map<String, dynamic>>();
          final filtered = entries
              .where(
                (entry) =>
                    (entry['title'] as String).toLowerCase().contains(_query),
              )
              .toList();
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: filtered.length + 2,
            itemBuilder: (_, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heading(
                      '${_tab == 0 ? kbText(context, '文件', 'Files') : 'Wiki'} (${entries.length})',
                    ),
                    if (snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator()
                    else if (snapshot.hasError)
                      _listError(
                        snapshot.error,
                        () => setState(() {
                          if (_tab == 0) {
                            _files = _request('documents');
                          } else {
                            _wiki = _request('wiki');
                          }
                        }),
                      )
                    else if (snapshot.data?['status'] == 'awaiting_sync')
                      _hint(kbText(context, '等待知识库同步', 'Awaiting sync'))
                    else if (filtered.isEmpty)
                      _hint(
                        _query.isNotEmpty
                            ? kbText(context, '无匹配内容', 'No matches')
                            : kbText(
                                context,
                                _tab == 0 ? '暂无可访问的文件' : '暂无 Wiki 页面',
                                _tab == 0
                                    ? 'No accessible files'
                                    : 'No Wiki pages',
                              ),
                      ),
                  ],
                );
              }
              if (index <= filtered.length) {
                final entry = filtered[index - 1];
                return _entry(entry);
              }
              return _tab == 0 ? _sourceList(sources) : const SizedBox.shrink();
            },
          );
        },
      );

  Widget _sourceList(AsyncSnapshot<Map<String, dynamic>> snapshot) {
    final sources =
        (snapshot.data?['sources'] as List? ?? []).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _heading(
          '${kbText(context, '数据源', 'Data sources')} (${sources.length})',
        ),
        if (snapshot.connectionState != ConnectionState.done)
          const LinearProgressIndicator()
        else if (snapshot.hasError)
          _listError(
            snapshot.error,
            () => setState(() {
              _sources = _request('sources');
            }),
          )
        else if (sources.isEmpty)
          _hint(kbText(context, '暂无已连接的数据源', 'No connected data sources'))
        else
          for (final source in sources)
            if ((source['name'] as String).toLowerCase().contains(_query))
              _entry(source, source: true),
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );

  Widget _listError(Object? error, VoidCallback retry) => Column(
        children: [
          _hint(kbError(context, error)),
          TextButton(
            onPressed: retry,
            child: Text(kbText(context, '重试', 'Retry')),
          ),
        ],
      );

  String _status(String? status) => switch (status) {
        'completed' ||
        'success' ||
        'ready' ||
        'active' ||
        'published' =>
          kbText(context, '已完成', 'Ready'),
        'pending' || 'queued' => kbText(context, '等待中', 'Pending'),
        'processing' ||
        'running' ||
        'syncing' =>
          kbText(context, '处理中', 'Processing'),
        'failed' || 'error' => kbText(context, '失败', 'Failed'),
        'disabled' ||
        'inactive' ||
        'paused' =>
          kbText(context, '已暂停', 'Paused'),
        _ => status ?? '',
      };

  Widget _entry(Map<String, dynamic> entry, {bool source = false}) => ListTile(
        dense: true,
        selected: _selected?['id'] == entry['id'] && _isSource == source,
        selectedTileColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        minLeadingWidth: 0,
        horizontalTitleGap: 8,
        leading: Icon(
          source
              ? Icons.input_outlined
              : _tab == 0
                  ? Icons.description_outlined
                  : Icons.article_outlined,
          size: 17,
        ),
        title: Text(
          (source ? entry['name'] : entry['title']) as String,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: source
            ? Text(
                entry['type'] as String? ?? '',
                style: const TextStyle(fontSize: 10),
              )
            : null,
        trailing: Text(
          _status(entry['status'] as String?),
          style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
        ),
        onTap: () => _open(entry, source: source),
      );

  Widget _detail() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 24, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: kbText(context, '返回', 'Back'),
                  onPressed: () => setState(() {
                    _selected = null;
                    _preview = null;
                  }),
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
                Expanded(
                  child: Text(
                    (_isSource ? _selected!['name'] : _selected!['title'])
                        as String,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isSource
                ? ListView(
                    padding: const EdgeInsets.all(28),
                    children: [
                      _hint(
                        '${kbText(context, '类型', 'Type')}：${_selected!['type'] ?? ''}',
                      ),
                      _hint(
                        '${kbText(context, '状态', 'Status')}：${_status(_selected!['status'] as String?)}',
                      ),
                      _hint(
                        '${kbText(context, '已同步条目', 'Synced items')}：${_selected!['total_items_synced'] ?? 0}',
                      ),
                      _hint(
                        '${kbText(context, '最近同步', 'Last sync')}：${_selected!['last_sync_at'] ?? kbText(context, '尚未同步', 'Never synced')}',
                      ),
                    ],
                  )
                : FutureBuilder<Map<String, dynamic>>(
                    future: _preview,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _notice(
                          kbError(context, snapshot.error),
                          retry: () => _open(_selected!),
                        );
                      }
                      if (snapshot.data?['status'] == 'awaiting_sync') {
                        return _notice(
                          kbText(context, '等待知识库同步', 'Awaiting sync'),
                        );
                      }
                      final content =
                          snapshot.data?['content'] as String? ?? '';
                      if (content.isEmpty) {
                        return _notice(
                          kbText(
                            context,
                            '此条目暂无文本预览。',
                            'No text preview is available for this item.',
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              content,
                              style: const TextStyle(fontSize: 15, height: 1.7),
                            ),
                            if (snapshot.data?['truncated'] == true)
                              _hint(
                                kbText(
                                  context,
                                  '预览内容较长，已截取前半部分。',
                                  'This preview has been shortened.',
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );

  Widget _graphView() => FutureBuilder<Map<String, dynamic>>(
        future: _wiki,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _notice(
              kbError(context, snapshot.error),
              retry: () => setState(() {
                _wiki = _request('wiki');
              }),
            );
          }
          final pages = (snapshot.data?['pages'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          if (pages.isEmpty) {
            return _notice(
              kbText(context, '暂无 Wiki 关系图谱。', 'No Wiki graph yet.'),
            );
          }
          if (!identical(_graphSource, snapshot.data)) {
            _graphSource = snapshot.data;
            _graph = KnowledgeGraphData(
              nodes: [
                for (final page in pages)
                  GraphNode(
                    id: page['id'] as String,
                    label: page['title'] as String,
                    view: ViewPB(
                      id: page['id'] as String,
                      name: page['title'] as String,
                    ),
                  ),
              ],
              edges: [
                for (final page in pages)
                  for (final target in page['out_links'] as List? ?? [])
                    GraphEdge(
                      page['id'] as String,
                      target as String,
                      GraphEdgeKind.reference,
                    ),
              ],
            );
          }
          return KnowledgeGraphCanvas(
            data: _graph.filtered(query: _query),
            showLabels: true,
            onOpen: (node) =>
                _open(pages.firstWhere((page) => page['id'] == node.id)),
          );
        },
      );

  Widget _notice(String text, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 32,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              if (retry != null)
                TextButton(
                  onPressed: retry,
                  child: Text(kbText(context, '重试', 'Retry')),
                ),
            ],
          ),
        ),
      );
}
