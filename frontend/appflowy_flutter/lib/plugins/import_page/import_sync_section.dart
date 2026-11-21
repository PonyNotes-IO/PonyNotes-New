import 'dart:async';

import 'package:appflowy/plugins/knowledge_base/knowledge_base_data_source_editor.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:flutter/material.dart';

enum _Provider {
  feishu(
    '飞书',
    'Feishu',
    '将飞书 Wiki 文档同步到当前工作空间的「私有」',
    'Sync Feishu Wiki documents to Private in this workspace',
  ),
  notion(
    'Notion',
    'Notion',
    '将选中的 Notion 页面同步到当前工作空间的「私有」',
    'Sync selected Notion pages to Private in this workspace',
  ),
  yuque(
    '语雀',
    'Yuque',
    '将语雀知识库中的文档同步到当前工作空间的「私有」',
    'Sync documents from Yuque to Private in this workspace',
  ),
  gitlab(
    'GitLab',
    'GitLab',
    '将 GitLab 项目的 Markdown、TXT 文档同步到当前工作空间的「私有」',
    'Sync GitLab Markdown and TXT documents to Private in this workspace',
  );

  const _Provider(this.zh, this.en, this.descriptionZh, this.descriptionEn);

  final String zh;
  final String en;
  final String descriptionZh;
  final String descriptionEn;

  String label(BuildContext context) => kbText(context, zh, en);
}

String? _syncStatus(Map<String, dynamic> source) =>
    source['note_sync']?['status'] as String?;

class ImportSyncSection extends StatefulWidget {
  const ImportSyncSection({
    super.key,
    required this.workspaceId,
    required this.service,
    this.onOpenSyncedPage,
  });

  final String? workspaceId;
  final KnowledgeBaseService? service;
  final ValueChanged<String>? onOpenSyncedPage;

  @override
  State<ImportSyncSection> createState() => _ImportSyncSectionState();
}

class _ImportSyncSectionState extends State<ImportSyncSection> {
  List<Map<String, dynamic>>? _connections;
  Object? _error;
  bool _loading = false;
  bool _working = false;
  Timer? _poll;

  KnowledgeBaseService get _service => widget.service!;
  bool get _available => widget.service != null && widget.workspaceId != null;
  bool get _current => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    if (!_available) return;
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_current &&
          !_working &&
          _error == null &&
          _connections?.any((item) => _syncStatus(item) == 'running') == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(String operation, {Object? sourceId}) =>
      _service.post('workspace_sync', {
        'workspace_id': widget.workspaceId,
        'operation': operation,
        if (sourceId != null) 'source_id': sourceId,
      });

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await _call('list');
      if (!mounted) return;
      setState(() {
        _connections = (result['sources'] as List).cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<T?> _choose<T>(
    String title,
    List<T> options,
    String Function(T) label,
  ) {
    if (options.length <= 1) return Future.value(options.firstOrNull);
    return showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Text(label(option)),
            ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || _loading) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted && _current) _notice(kbError(context, error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  Future<void> _edit(String type, {Map<String, dynamic>? source}) async {
    final result = await _call('types');
    if (!mounted || !_current) return;
    final types = (result['types'] as List).cast<Map<String, dynamic>>();
    final definition =
        types.where((definition) => definition['type'] == type).firstOrNull;
    if (definition == null) {
      _notice(
        kbText(
          context,
          '当前服务未启用此连接器。',
          'This connector is unavailable on the server.',
        ),
      );
      return;
    }
    var changed = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 560,
          height: 660,
          child: KnowledgeBaseDataSourceEditor(
            workspaceId: widget.workspaceId,
            service: _service,
            definition: definition,
            source: source,
            onBack: () => Navigator.pop(context),
            onChanged: () => changed = true,
          ),
        ),
      ),
    );
    if (mounted && changed) await _load();
  }

  Future<void> _manage(List<Map<String, dynamic>> options, String operation) =>
      _run(() async {
        final source = await _choose(
          kbText(context, '选择连接', 'Choose a connection'),
          options,
          (item) => item['name'] as String,
        );
        if (!mounted || !_current || source == null) return;
        if (operation == 'edit') {
          await _edit(source['type'] as String, source: source);
          return;
        }
        if (operation == 'delete') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(kbText(context, '断开此连接？', 'Disconnect this source?')),
              content: Text(
                kbText(
                  context,
                  '已同步的页面会保留在「私有」。',
                  'Synced pages will remain in Private.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(kbText(context, '取消', 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(kbText(context, '断开连接', 'Disconnect')),
                ),
              ],
            ),
          );
          if (!_current || confirmed != true) return;
        }
        final result = await _call(operation, sourceId: source['id']);
        if (!mounted) return;
        setState(() {
          _connections = [
            for (final item in _connections!)
              if (item != source)
                item
              else if (operation == 'note_sync')
                {...source, 'note_sync': result},
          ];
        });
      });

  @override
  Widget build(BuildContext context) {
    final initialized = _connections != null;
    final actionable = initialized && _error == null && !_working && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kbText(context, '连接外部应用', 'Connect external apps'),
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (!_available)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              kbText(
                context,
                '请打开云端工作空间后使用同步。',
                'Open a cloud workspace to sync notes.',
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(kbError(context, _error)),
                TextButton(
                  onPressed: _loading || _working ? null : () => _load(),
                  child: Text(kbText(context, '重试', 'Retry')),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 14.0;
            final width = constraints.maxWidth;
            final cardWidth = width >= 624 ? (width - gap) / 2 : width;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final provider in _Provider.values)
                  SizedBox(
                    width: cardWidth,
                    child: _buildCard(provider, actionable: actionable),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCard(_Provider provider, {required bool actionable}) {
    final options = (_connections ?? const <Map<String, dynamic>>[])
        .where((item) => item['type'] == provider.name)
        .toList();
    final idle =
        options.where((item) => _syncStatus(item) != 'running').toList();
    final openable = options
        .where((item) => item['note_sync']?['view_id'] is String)
        .toList();
    return _SyncCard(
      key: ValueKey('sync-${provider.name}'),
      provider: provider,
      connections: options,
      loading: _connections == null && _loading,
      unknown: _error != null,
      onConnect: options.isEmpty && actionable
          ? () => _run(() => _edit(provider.name))
          : null,
      onSync: actionable && idle.isNotEmpty
          ? () => _manage(idle, 'note_sync')
          : null,
      onOpen: widget.onOpenSyncedPage == null || openable.isEmpty
          ? null
          : () async {
              final source = await _choose(
                kbText(context, '打开同步笔记', 'Open synced note'),
                openable,
                (item) => item['name'] as String,
              );
              if (mounted && source != null) {
                widget.onOpenSyncedPage!(
                  source['note_sync']['view_id'] as String,
                );
              }
            },
      onEdit:
          actionable && idle.isNotEmpty ? () => _manage(idle, 'edit') : null,
      onDisconnect:
          actionable && idle.isNotEmpty ? () => _manage(idle, 'delete') : null,
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    super.key,
    required this.provider,
    required this.connections,
    required this.loading,
    required this.unknown,
    this.onConnect,
    this.onSync,
    this.onOpen,
    this.onEdit,
    this.onDisconnect,
  });

  final _Provider provider;
  final List<Map<String, dynamic>> connections;
  final bool loading;
  final bool unknown;
  final VoidCallback? onConnect;
  final VoidCallback? onSync;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _status(context),
          ),
          if (onOpen != null)
            TextButton(
              onPressed: onOpen,
              child: Text(kbText(context, '打开同步笔记', 'Open synced note')),
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.onSurface.withValues(alpha: 0.065)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: onConnect == null
              ? content
              : Tooltip(
                  message: kbText(
                    context,
                    '连接${provider.zh}',
                    'Connect ${provider.en}',
                  ),
                  child: InkWell(
                    borderRadius: radius,
                    onTap: onConnect,
                    child: content,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/images/icons/sync_${provider.name}.png',
            width: 34,
            height: 34,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.label(context),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                kbText(
                  context,
                  provider.descriptionZh,
                  provider.descriptionEn,
                ),
                style: TextStyle(
                  fontSize: 10,
                  height: 1.35,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (connections.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 4), child: identity);
    }
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _action(
          context,
          Icons.refresh,
          kbText(context, '立即同步', 'Sync now'),
          onSync,
        ),
        _action(
          context,
          Icons.edit_outlined,
          kbText(context, '编辑连接', 'Edit connection'),
          onEdit,
        ),
        _action(
          context,
          Icons.link_off,
          kbText(context, '断开连接', 'Disconnect'),
          onDisconnect,
          background: true,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(10) > 13) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 4), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: identity,
              ),
            ),
            actions,
          ],
        );
      },
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? action, {
    bool background = false,
  }) {
    final color = Theme.of(context).colorScheme.onSurface;
    return IconButton(
      tooltip: label,
      onPressed: action,
      icon: Icon(icon, size: 16),
      style: IconButton.styleFrom(
        foregroundColor: color.withValues(alpha: 0.8),
        backgroundColor: background ? color.withValues(alpha: 0.045) : null,
        padding: EdgeInsets.zero,
        fixedSize: const Size.square(26),
        minimumSize: const Size.square(26),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  List<Widget> _status(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (loading) return [_SyncPill(kbText(context, '正在读取', 'Loading'))];
    if (unknown) {
      return [_SyncPill(kbText(context, '状态未知', 'Status unavailable'))];
    }
    if (connections.isEmpty) {
      return [
        _SyncPill(kbText(context, '未连接', 'Not connected'), dot: colors.outline),
      ];
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? const Color(0xFFA1DABD) : const Color(0xFF286249);
    final connected = connections.length == 1
        ? kbText(context, '已连接', 'Connected')
        : kbText(
            context,
            '已连接 ${connections.length} 项',
            '${connections.length} connections',
          );
    final running = connections.any((item) => _syncStatus(item) == 'running');
    final source = connections.length == 1 ? connections.single : null;
    final status = source == null ? null : _syncStatus(source);
    final last = source?['note_sync']?['finished_at'] as String?;
    final stamp = last == null ? null : DateTime.tryParse(last)?.toLocal();
    final (label, tint) = switch ((running, status)) {
      (true, _) => (
          kbText(context, '同步中', 'Syncing'),
          dark ? const Color(0xFFFFB084) : const Color(0xFFAD3B14)
        ),
      (_, 'failed') => (kbText(context, '同步失败', 'Failed'), colors.error),
      (_, 'success') => (kbText(context, '成功', 'Succeeded'), green),
      (_, 'partial') => (
          kbText(context, '部分完成', 'Partial'),
          colors.onSurfaceVariant
        ),
      _ => (stamp == null ? kbText(context, '未同步', 'Not synced') : null, null),
    };
    return [
      _SyncPill(
        connected,
        tint: green,
        dot: dark ? green : const Color(0xFF56AA80),
        fill: green.withValues(alpha: 0.18),
      ),
      if (source != null)
        _SyncPill(
          kbText(context, '手动同步', 'Manual sync'),
          suffix: label,
          suffixTint: tint,
        )
      else if (running)
        _SyncPill(label!, tint: tint),
      if (source?['note_sync']?['saved'] case final int saved)
        _SyncPill(kbText(context, '已保存 $saved 篇', '$saved notes saved')),
      if (source?['note_sync']?['unchanged'] case final int unchanged
          when unchanged > 0)
        _SyncPill(kbText(context, '$unchanged 篇无变化', '$unchanged unchanged')),
      if (source?['note_sync']?['failed'] case final int failed when failed > 0)
        _SyncPill(
          kbText(context, '$failed 篇未同步', '$failed not synced'),
          tint: colors.error,
        ),
      if (stamp != null) _SyncPill(_lastSync(context, stamp), outlined: true),
    ];
  }

  String _lastSync(BuildContext context, DateTime stamp) {
    final formats = MaterialLocalizations.of(context);
    final day = DateUtils.isSameDay(DateTime.now(), stamp)
        ? kbText(context, '今天', 'Today')
        : formats.formatShortDate(stamp);
    final time = formats.formatTimeOfDay(
      TimeOfDay.fromDateTime(stamp),
      alwaysUse24HourFormat:
          Localizations.localeOf(context).languageCode == 'zh' ||
              MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return kbText(context, '最近同步：$day $time', 'Last sync: $day $time');
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill(
    this.label, {
    this.tint,
    this.dot,
    this.fill,
    this.outlined = false,
    this.suffix,
    this.suffixTint,
  });

  final String label;
  final Color? tint;
  final Color? dot;
  final Color? fill;
  final bool outlined;
  final String? suffix;
  final Color? suffixTint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: fill ??
            (outlined ? null : colors.onSurface.withValues(alpha: 0.042)),
        border: outlined
            ? Border.all(color: colors.onSurface.withValues(alpha: 0.06))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Icon(Icons.circle, size: 6, color: dot),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (suffix != null)
                    TextSpan(
                      text: ' · $suffix',
                      style: TextStyle(color: suffixTint),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                color: tint ?? colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
