import 'package:appflowy/plugins/knowledge_base/knowledge_base_data_source_editor.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class KnowledgeBaseDataSources extends StatefulWidget {
  const KnowledgeBaseDataSources({
    super.key,
    required this.base,
    required this.service,
    required this.onClose,
    required this.onChanged,
  });

  final KnowledgeBase base;
  final KnowledgeBaseService service;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<KnowledgeBaseDataSources> createState() =>
      _KnowledgeBaseDataSourcesState();
}

class _KnowledgeBaseDataSourcesState extends State<KnowledgeBaseDataSources> {
  static const _green = Color(0xFF07BE78);
  static const _providers = {
    'feishu': (
      '飞书',
      'Feishu',
      '同步飞书知识库中的文档、表格、文件',
      Icons.cloud,
      Color(0xFF14B8A6)
    ),
    'lark': (
      'Lark（飞书国际版）',
      'Lark',
      '同步 Lark 知识库中的文档、表格、文件',
      Icons.send_rounded,
      Color(0xFF557DF5)
    ),
    'feishu_drive': (
      '飞书云盘',
      'Feishu Drive',
      '同步飞书云盘文件夹中的文档、表格、文件',
      Icons.cloud,
      Color(0xFF14B8A6)
    ),
    'lark_drive': (
      'Lark 云盘',
      'Lark Drive',
      '同步 Lark 云盘文件夹中的文档、表格、文件',
      Icons.send_rounded,
      Color(0xFF557DF5)
    ),
    'notion': (
      'Notion',
      'Notion',
      '同步 Notion 中的页面和数据库',
      Icons.article_outlined,
      Color(0xFF383838)
    ),
    'confluence': (
      'Confluence',
      'Confluence',
      '将 Confluence 空间和页面同步为 Markdown',
      FontAwesomeIcons.confluence,
      Color(0xFF1868DB)
    ),
    'yuque': (
      '语雀',
      'Yuque',
      '同步语雀知识库中的文档',
      Icons.eco_rounded,
      Color(0xFF4CB571)
    ),
    'dingtalk': (
      '钉钉文档',
      'DingTalk',
      '同步钉钉知识库中的在线文档',
      Icons.bolt_rounded,
      Color(0xFF168BF0)
    ),
    'ima': (
      '腾讯 IMA',
      'Tencent IMA',
      '同步腾讯 IMA 知识库中的文档、笔记与文件',
      Icons.hub_rounded,
      Color(0xFF50BD45)
    ),
    'rss': (
      'RSS / Atom 订阅',
      'RSS / Atom',
      '同步 RSS / Atom 订阅源中的文章',
      Icons.rss_feed_rounded,
      Color(0xFFF28B37)
    ),
    'gitlab': (
      'GitLab',
      'GitLab',
      '同步 GitLab 项目中的文件',
      FontAwesomeIcons.gitlab,
      Color(0xFFEB6D35)
    ),
    'seafile': (
      'Seafile',
      'Seafile',
      '同步 Seafile 资料库中的目录与文件',
      Icons.cloud_sync_outlined,
      Color(0xFFF3AE25)
    ),
  };
  late Future<Map<String, dynamic>> _data = _load();
  Map<String, dynamic>? _definition;
  Map<String, dynamic>? _source;

  Future<Map<String, dynamic>> _load() async {
    if (!widget.base.canManage) throw const KnowledgeBaseException(403);
    final results = await Future.wait([
      for (final operation in ['types', 'list'])
        widget.service.post(
          'data_source',
          {...widget.base.target, 'operation': operation},
        ),
    ]);
    return {...results[0], ...results[1]};
  }

  void _back() => setState(() {
        _definition = null;
        _source = null;
        _data = _load();
      });

  String _label(String type) {
    final provider = _providers[type];
    return provider == null ? type : kbText(context, provider.$1, provider.$2);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (constraints.maxWidth >= 600) ...[
              SizedBox(width: 140, child: _sidebar(context)),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            kbText(
                              context,
                              '数据源管理',
                              'Data source management',
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: kbText(
                            context,
                            '关闭数据源设置',
                            'Close data sources',
                          ),
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Text(
                      kbText(
                        context,
                        '配置外部数据源，自动同步内容到知识库',
                        'Configure external data sources to sync content to this knowledge base',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _definition != null
                        ? KnowledgeBaseDataSourceEditor(
                            key: ValueKey(
                              (_source?['id'], _definition!['type']),
                            ),
                            base: widget.base,
                            service: widget.service,
                            definition: _definition!,
                            source: _source,
                            onBack: _back,
                            onChanged: widget.onChanged,
                          )
                        : FutureBuilder<Map<String, dynamic>>(
                            future: _data,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                          kbError(
                                            context,
                                            snapshot.error,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _back,
                                        child: Text(
                                          kbText(context, '重试', 'Retry'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final types = (snapshot.data!['types'] as List)
                                  .cast<Map<String, dynamic>>();
                              final sources =
                                  (snapshot.data!['sources'] as List)
                                      .cast<Map<String, dynamic>>();
                              return ListView(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                children: [
                                  if (sources.isNotEmpty) ...[
                                    Text(
                                      kbText(
                                        context,
                                        '已连接的数据源',
                                        'Connected data sources',
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    for (final source in sources)
                                      ListTile(
                                        key: ValueKey(
                                          'connected-source-${source['id']}',
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(source['name'] as String),
                                        subtitle: Text(
                                          '${_label(source['type'] as String)} · ${source['status'] == 'paused' ? kbText(context, '已暂停', 'Paused') : source['latest_sync_log']?['status'] == 'running' ? kbText(context, '同步中', 'Syncing') : source['status'] == 'error' ? kbText(context, '连接异常', 'Connection error') : kbText(context, '已启用', 'Active')}',
                                        ),
                                        trailing:
                                            const Icon(Icons.chevron_right),
                                        onTap: () => setState(() {
                                          _source = source;
                                          _definition = types
                                              .where(
                                                (t) =>
                                                    t['type'] == source['type'],
                                              )
                                              .firstOrNull;
                                        }),
                                      ),
                                    const Divider(height: 28),
                                  ],
                                  Row(
                                    children: [
                                      Container(
                                        width: 3,
                                        height: 14,
                                        color: _green,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        kbText(context, '选择类型', 'Select type'),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (types.isEmpty)
                                    Text(
                                      kbText(
                                        context,
                                        '当前服务没有可用的数据源连接器。',
                                        'No data source connectors are available.',
                                      ),
                                    ),
                                  LayoutBuilder(
                                    builder: (context, grid) => GridView(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: grid.maxWidth >= 450
                                            ? 3
                                            : grid.maxWidth >= 290
                                                ? 2
                                                : 1,
                                        mainAxisExtent: 110,
                                        mainAxisSpacing: 10,
                                        crossAxisSpacing: 10,
                                      ),
                                      children: [
                                        for (final type in types)
                                          _typeCard(type),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: OutlinedButton(
                        onPressed: widget.onClose,
                        child: Text(kbText(context, '关闭', 'Close')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _typeCard(Map<String, dynamic> definition) {
    final type = definition['type'] as String;
    final provider = _providers[type];
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: ValueKey('data-source-type-${provider?.$2 ?? type}'),
      onPressed: () => setState(() {
        _definition = definition;
        _source = null;
      }),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(12),
        alignment: Alignment.topLeft,
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                provider?.$4 ?? Icons.input,
                size: 18,
                color: provider?.$5 ?? _green,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _label(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            kbText(
              context,
              provider?.$3 ?? definition['description'] as String,
              definition['description'] as String,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                kbText(context, '知识库设置', 'Knowledge base settings'),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final (zh, en, entries) in const [
                    (
                      '基础',
                      'General',
                      [
                        ('基本信息', 'Basic info', Icons.info_outline),
                        ('模型配置', 'Models', Icons.view_in_ar_outlined),
                        ('向量存储', 'Vector storage', Icons.storage_outlined),
                      ]
                    ),
                    (
                      '索引与解析',
                      'Indexing & parsing',
                      [
                        ('解析引擎', 'Parser engine', Icons.find_in_page_outlined),
                        ('分块设置', 'Chunk settings', Icons.content_copy_outlined),
                        ('图像处理', 'Images', Icons.image_outlined),
                        ('音频处理', 'Audio', Icons.volume_up_outlined),
                        ('知识图谱', 'Knowledge graph', Icons.schema_outlined),
                        ('高级设置', 'Advanced', Icons.settings_outlined),
                      ]
                    ),
                    (
                      '存储与数据',
                      'Storage & data',
                      [
                        ('存储引擎', 'Storage engine', Icons.cloud_outlined),
                        ('数据源', 'Data sources', Icons.cloud_upload_outlined),
                      ]
                    ),
                    (
                      '发布集成',
                      'Publishing',
                      [
                        ('共享管理', 'Sharing', Icons.share_outlined),
                      ]
                    ),
                    (
                      '管理与审计',
                      'Audit',
                      [
                        ('清理记录', 'Cleanup history', Icons.history_outlined),
                      ]
                    ),
                  ]) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                      child: Text(
                        kbText(context, zh, en),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                    for (final (label, english, icon) in entries)
                      Semantics(
                        selected: label == '数据源',
                        child: Container(
                          decoration: label == '数据源'
                              ? BoxDecoration(
                                  color: _green.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(4),
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: label == '数据源' ? _green : null,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  kbText(context, label, english),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: label == '数据源' ? _green : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
