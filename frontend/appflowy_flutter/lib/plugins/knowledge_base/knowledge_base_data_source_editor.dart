import 'dart:async';

import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class KnowledgeBaseDataSourceEditor extends StatefulWidget {
  const KnowledgeBaseDataSourceEditor({
    super.key,
    this.base,
    this.workspaceId,
    required this.service,
    required this.definition,
    required this.onBack,
    required this.onChanged,
    this.source,
  }) : assert((base == null) != (workspaceId == null));

  final KnowledgeBase? base;
  final String? workspaceId;
  final KnowledgeBaseService service;
  final Map<String, dynamic> definition;
  final Map<String, dynamic>? source;
  final VoidCallback onBack;
  final VoidCallback onChanged;

  @override
  State<KnowledgeBaseDataSourceEditor> createState() =>
      _KnowledgeBaseDataSourceEditorState();
}

class _KnowledgeBaseDataSourceEditorState
    extends State<KnowledgeBaseDataSourceEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _feed = TextEditingController();
  final _folder = TextEditingController();
  final _project = TextEditingController();
  final _ref = TextEditingController();
  final _paths = TextEditingController();
  final _credentials = <String, TextEditingController>{};
  final _resources = <String, Map<String, dynamic>>{};
  final _expanded = <String>{};
  final _loaded = <String>{};
  final _ids = <String>{};
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic>? _source;
  String _requestId = const Uuid().v4();
  String _schedule = '';
  String _mode = 'incremental';
  String _conflict = 'overwrite';
  bool _deletions = false;
  bool _busy = false;
  bool _replaceCredentials = false;
  bool _dirty = false;
  String? _error;
  String? _notice;
  Timer? _poll;

  String get _type => widget.definition['type'] as String;
  bool get _forWorkspace => widget.workspaceId != null;
  bool get _explicitPages => _forWorkspace && _type == 'notion';
  bool get _drive => _type == 'feishu_drive' || _type == 'lark_drive';
  bool get _syncing => _source?['latest_sync_log']?['status'] == 'running';
  List<Map<String, dynamic>> get _fields =>
      (widget.definition['fields'] as List).cast<Map<String, dynamic>>();
  String text(String zh, String en) => kbText(context, zh, en);

  @override
  void initState() {
    super.initState();
    _name.text = widget.definition['name'] as String;
    for (final field in _fields) {
      final key = field['key'] as String;
      _credentials[key] = TextEditingController(
        text: key == 'edition'
            ? 'server'
            : _type == 'gitlab' && key == 'base_url'
                ? 'https://gitlab.com'
                : '',
      );
    }
    if (widget.source != null) _adopt(widget.source!);
    if (!_forWorkspace) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_busy && _syncing) unawaited(_run(_refresh));
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final controller in [
      _name,
      _feed,
      _folder,
      _project,
      _ref,
      _paths,
      ..._credentials.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String operation, [
    Map<String, dynamic> data = const {},
  ]) =>
      widget.service.post(_forWorkspace ? 'workspace_sync' : 'data_source', {
        if (_forWorkspace)
          'workspace_id': widget.workspaceId
        else
          ...widget.base!.target,
        'operation': operation,
        if (_source != null) 'source_id': _source!['id'],
        ...data,
      });

  void _adopt(Map<String, dynamic> source) {
    _source = source;
    _name.text = source['name'] as String;
    _ids
      ..clear()
      ..addAll((source['config']['resource_ids'] as List).cast<String>());
    _schedule = source['sync_schedule'] as String? ?? '';
    _mode = source['sync_mode'] as String? ?? 'incremental';
    _conflict = source['conflict_strategy'] as String? ?? 'overwrite';
    _deletions = source['sync_deletions'] == true;
    _feed.text = source['config']['settings']?['feed_urls'] as String? ?? '';
    if (_type == 'gitlab') {
      final project = (source['config']['settings']?['projects'] as List?)
          ?.cast<Map<String, dynamic>>()
          .firstOrNull;
      _project.text = project?['project_id'] as String? ?? '';
      _ref.text = project?['ref'] as String? ?? '';
      _paths.text = (project?['paths'] as List?)?.join('\n') ?? '';
      final baseUrl = source['config']['settings']?['base_url'] as String?;
      if (baseUrl != null) _credentials['base_url']?.text = baseUrl;
    }
    _dirty = false;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _error = kbError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, String> get _credentialValues => {
        for (final entry in _credentials.entries)
          if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
      };

  void _clearCredentialInputs() {
    for (final entry in _credentials.entries) {
      if (_type != 'gitlab' || entry.key != 'base_url') entry.value.clear();
    }
  }

  String get _folderToken {
    final input = _folder.text.trim();
    return RegExp('/drive/folder/([^/?#]+)').firstMatch(input)?.group(1) ??
        input;
  }

  Map<String, dynamic> get _connection => {
        'type': _type,
        'credentials': _credentialValues,
        'settings': {
          if (['feishu', 'lark', 'feishu_drive', 'lark_drive'].contains(_type))
            'parse_mode': 'blocks',
          if (_type == 'rss') 'feed_urls': _feed.text.trim(),
          if (_type == 'confluence')
            for (final key in ['edition', 'base_url', 'username'])
              key: _credentials[key]!.text.trim(),
          if (!_forWorkspace && _type == 'gitlab')
            'base_url': _credentials['base_url']!.text.trim(),
          if (_type == 'gitlab')
            // ponytail: one project per connection; add a project list when needed.
            'projects': [
              {
                'project_id': _project.text.trim(),
                'ref': _ref.text.trim(),
                'paths': _paths.text
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
              },
            ],
        },
        if (!_forWorkspace || _type != 'gitlab')
          'resource_ids': _drive
              ? [_folderToken]
              : _type == 'gitlab'
                  ? [_project.text.trim()]
                  : <String>[],
      };

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      if (_source != null && !_replaceCredentials) {
        await _call('validate');
      } else {
        await _call('test', _connection);
      }
      if (mounted) _notice = text('连接测试成功。', 'Connection test succeeded.');
    });
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final result = await _call('create', {
        ..._connection,
        'name': _name.text.trim(),
        'request_id': _requestId,
      });
      if (!mounted) return;
      _adopt(result['source'] as Map<String, dynamic>);
      _clearCredentialInputs();
      _notice = _forWorkspace && _type == 'gitlab'
          ? text(
              '连接及同步范围已保存，可返回卡片点击「立即同步」。',
              'Connection and scope saved. Use Sync now on the sync card.',
            )
          : _forWorkspace
              ? text(
                  '连接已保存。请选择并保存同步范围。',
                  'Connection saved. Select and save its scope.',
                )
              : text(
                  '连接已保存并暂停。请选择同步范围，保存后可手动同步或启用计划同步。',
                  'Connection saved and paused. Select and save its scope before syncing.',
                );
      widget.onChanged();
    });
  }

  Future<void> _save() => _run(() async {
        if (_ids.isEmpty) {
          _error = text('请至少选择一个同步资源。', 'Select at least one resource.');
          return;
        }
        final result = await _call('save', {
          'resource_ids': _ids.where((id) {
            if (_explicitPages) return true;
            final parent = _resources[id]?['parent_id'] as String?;
            return parent == null || !_covered(parent);
          }).toList(),
          'sync_schedule': _schedule,
          'sync_mode': _mode,
          'conflict_strategy': _conflict,
          'sync_deletions': _deletions,
        });
        if (!mounted) return;
        _adopt(result['source'] as Map<String, dynamic>);
        _notice = text('同步配置已保存。', 'Sync settings saved.');
        widget.onChanged();
      });

  Future<void> _refresh() async {
    final result = await _call('list');
    final source = (result['sources'] as List)
        .cast<Map<String, dynamic>>()
        .where((s) => s['id'] == _source!['id'])
        .firstOrNull;
    if (!mounted) return;
    if (source == null) {
      widget.onChanged();
      widget.onBack();
      return;
    }
    if (_dirty) {
      _source = source;
    } else {
      _adopt(source);
    }
    final logs = await _call('logs');
    if (!mounted) return;
    _logs = (logs['logs'] as List).cast<Map<String, dynamic>>();
    widget.onChanged();
  }

  Future<void> _operate(String operation) => _run(() async {
        if (_dirty && (operation == 'sync' || operation == 'resume')) {
          _error = text('请先保存同步配置。', 'Save the sync settings first.');
          return;
        }
        final result = await _call(operation);
        if (!mounted) return;
        if (operation == 'sync') {
          _source = {..._source!, 'latest_sync_log': result['log']};
          _notice = text('同步任务已提交。', 'Sync task submitted.');
        } else {
          await _refresh();
        }
        widget.onChanged();
      });

  Future<void> _loadResources([String parent = '']) => _run(() async {
        final result = await _call('resources', {'parent_id': parent});
        if (!mounted) return;
        if (parent.isEmpty) {
          _resources.clear();
          _loaded.clear();
          _expanded.clear();
        }
        for (final resource
            in (result['resources'] as List).cast<Map<String, dynamic>>()) {
          _resources[resource['external_id'] as String] = resource;
        }
        _loaded.add(parent);
        if (parent.isNotEmpty) _expanded.add(parent);
      });

  bool _covered(String id, [Set<String> visited = const {}]) {
    if (_ids.contains(id)) return true;
    if (_explicitPages || visited.contains(id)) return false;
    final parent = _resources[id]?['parent_id'] as String?;
    return parent != null &&
        parent.isNotEmpty &&
        _covered(parent, {...visited, id});
  }

  void _select(String id, bool selected) => setState(() {
        if (selected) {
          if (_type == 'seafile' &&
              _ids.any(
                (other) => other.split(':').first != id.split(':').first,
              )) {
            _error = text(
              '一个 Seafile 数据源只能选择一个资料库。',
              'Select one Seafile library per connection.',
            );
            return;
          }
          _ids.add(id);
        } else {
          _ids.remove(id);
        }
        _dirty = true;
      });

  Widget _resource(Map<String, dynamic> resource, Set<String> ancestors) {
    final id = resource['external_id'] as String;
    if (ancestors.contains(id)) return const SizedBox.shrink();
    final parent = resource['parent_id'] as String?;
    final inherited = !_explicitPages && parent != null && _covered(parent);
    final selectable = !_explicitPages || resource['type'] == 'page';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: _covered(id),
              onChanged: _busy || inherited || !selectable
                  ? null
                  : (value) => _select(id, value!),
            ),
            Expanded(
              child: Text(
                resource['name'] as String,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (resource['has_children'] == true)
              IconButton(
                tooltip: text('展开或收起', 'Expand or collapse'),
                icon: Icon(
                  _expanded.contains(id)
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                onPressed: _busy
                    ? null
                    : () {
                        if (_expanded.contains(id)) {
                          setState(() => _expanded.remove(id));
                        } else if (_loaded.contains(id) ||
                            _resources.values
                                .any((r) => r['parent_id'] == id)) {
                          setState(() => _expanded.add(id));
                        } else {
                          unawaited(_loadResources(id));
                        }
                      },
              ),
          ],
        ),
        if (_expanded.contains(id))
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: [
                for (final child
                    in _resources.values.where((r) => r['parent_id'] == id))
                  _resource(child, {...ancestors, id}),
              ],
            ),
          ),
      ],
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    bool required = false,
    bool secret = false,
    bool multiline = false,
    bool readOnly = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          key: ValueKey('source-$key'),
          controller: controller,
          enabled: !_busy,
          readOnly: readOnly,
          obscureText: secret && !multiline,
          enableSuggestions: !secret,
          autocorrect: !secret,
          minLines: 1,
          maxLines: multiline ? 4 : 1,
          decoration: _decoration(label),
          validator: (value) => required && (value?.trim().isEmpty ?? true)
              ? text('请填写此项', 'Required')
              : null,
          onChanged: (_) => _requestId = const Uuid().v4(),
        ),
      );

  Widget _credentialForm() => Column(
        children: [
          for (final field in _fields)
            _field(
              _credentials[field['key']]!,
              field['key'] as String,
              Localizations.localeOf(context).languageCode == 'zh'
                  ? field['label'] as String
                  : field['key'] as String,
              required: field['required'] == true,
              secret: field['secret'] == true,
              readOnly: _type == 'gitlab' &&
                  _source != null &&
                  field['key'] == 'base_url',
              multiline: field['key'] == 'auth_headers',
            ),
        ],
      );

  String _status(Object? value) => switch (value) {
        'paused' => text('已暂停', 'Paused'),
        'active' => text('已启用', 'Active'),
        'error' || 'failed' => text(
            '失败，请检查连接与资源权限',
            'Failed; check the connection and resource access',
          ),
        'running' => text('同步中', 'Syncing'),
        'success' => text('同步完成', 'Synced'),
        'partial' => text('部分完成', 'Partially synced'),
        'canceled' => text('已取消', 'Canceled'),
        _ => text('尚未同步', 'Never synced'),
      };

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_notice != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(_notice!),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : widget.onBack,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: Text(text('返回数据源', 'Back to data sources')),
                    ),
                  ),
                  if (_source == null) ...[
                    _field(
                      _name,
                      'name',
                      text('连接名称', 'Connection name'),
                      required: true,
                    ),
                    _credentialForm(),
                    if (_type == 'rss')
                      _field(
                        _feed,
                        'feed_urls',
                        text('订阅地址（每行一个）', 'Feed URLs (one per line)'),
                        required: true,
                        multiline: true,
                      ),
                    if (_drive)
                      _field(
                        _folder,
                        'folder',
                        text('云盘文件夹链接或 Token', 'Drive folder URL or token'),
                        required: true,
                      ),
                    if (_type == 'gitlab') ...[
                      _field(
                        _project,
                        'project',
                        text('项目 ID 或路径', 'Project ID or path'),
                        required: true,
                      ),
                      _field(
                        _ref,
                        'ref',
                        text('分支或标签（留空使用默认分支）', 'Branch or tag (optional)'),
                      ),
                      _field(
                        _paths,
                        'paths',
                        text(
                          '目录路径（可选，每行一个，留空同步整个项目）',
                          'Directories (one per line; empty means entire project)',
                        ),
                        multiline: true,
                      ),
                      Text(
                        text(
                          _forWorkspace
                              ? '每个连接一个项目。地址如 https://gitlab.com，项目填写数字 ID 或 group/project。仅同步 Markdown、TXT 文档；建议指定文档目录，单次最多 100 篇。'
                              : '每个连接一个项目，填写数字 ID 或 group/project。目录会包含下级文件。',
                          _forWorkspace
                              ? 'One project per connection. Enter a GitLab URL and a numeric project ID or group/project. Only Markdown and TXT documents are imported, up to 100 per run. Prefer a documentation directory.'
                              : 'One project per connection. Enter a numeric project ID or group/project. Directories include descendant files.',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy ? null : _test,
                          child: Text(text('测试连接', 'Test connection')),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _create,
                          child: Text(text('保存连接', 'Save connection')),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      _name.text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_forWorkspace) Text(_status(_source!['status'])),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _test,
                          child: Text(text('测试连接', 'Test connection')),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                    () => _replaceCredentials =
                                        !_replaceCredentials,
                                  ),
                          child: Text(text('更新凭据', 'Replace credentials')),
                        ),
                        if (!_forWorkspace)
                          TextButton(
                            onPressed: _busy ? null : () => _run(_refresh),
                            child: Text(
                              text('刷新状态与日志', 'Refresh status and logs'),
                            ),
                          ),
                      ],
                    ),
                    if (_replaceCredentials) ...[
                      _credentialForm(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (!_form.currentState!.validate()) return;
                                  await _run(() async {
                                    await _call(
                                      'credentials',
                                      {'credentials': _credentialValues},
                                    );
                                    if (!mounted) return;
                                    _clearCredentialInputs();
                                    _replaceCredentials = false;
                                    _notice =
                                        text('凭据已更新。', 'Credentials updated.');
                                  });
                                },
                          child: Text(text('保存新凭据', 'Save new credentials')),
                        ),
                      ),
                    ],
                    const Divider(height: 28),
                    Text(
                      text('同步范围', 'Sync scope'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_type == 'gitlab') ...[
                      SelectableText(
                        '${text('项目', 'Project')}: ${_project.text}',
                      ),
                      Text(
                        '${text('分支 / 标签', 'Branch / tag')}: ${_ref.text.isEmpty ? text('默认分支', 'Default branch') : _ref.text}',
                      ),
                      SelectableText(
                        '${text('目录', 'Directories')}: ${_paths.text.isEmpty ? text('整个项目', 'Entire project') : _paths.text}',
                      ),
                      Text(
                        text(
                          _forWorkspace
                              ? '项目、分支和目录已随连接保存。更换范围请新建连接。仅将 Markdown、TXT 文档写入「私有」。'
                              : '项目、分支和目录已随连接保存。更换范围请新建连接。',
                          _forWorkspace
                              ? 'The project, branch and directories are saved with this connection. Create a new connection to change its scope. Only Markdown and TXT documents go to Private.'
                              : 'The project, branch and directories are saved with this connection. Create a new connection to change its scope.',
                        ),
                      ),
                    ] else ...[
                      Text(
                        text(
                          _explicitPages
                              ? '逐页选择，最多 50 页。子页面需单独选择。'
                              : '选择目录会包含其下级内容；最多选择 50 项。',
                          _explicitPages
                              ? 'Select up to 50 pages individually, including subpages.'
                              : 'Selected folders include descendants. Select up to 50 items.',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _loadResources,
                          child: Text(text('加载资源', 'Load resources')),
                        ),
                      ),
                      if (_loaded.contains('') && _resources.isEmpty)
                        Text(
                          text(
                            '没有可访问资源，请检查应用授权范围。',
                            'No accessible resources. Check the app permissions.',
                          ),
                        ),
                      for (final resource in _resources.values.where(
                        (r) =>
                            r['parent_id'] == null ||
                            r['parent_id'] == '' ||
                            !_resources.containsKey(r['parent_id']),
                      ))
                        _resource(resource, {}),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final id in _ids)
                            InputChip(
                              label: Text(
                                _resources[id]?['name'] as String? ?? id,
                              ),
                              onDeleted:
                                  _busy ? null : () => _select(id, false),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_forWorkspace)
                      Text(
                        text(
                          '同步到当前工作空间的「私有」。在同步卡片点击「立即同步」。',
                          'Pages go to Private in this workspace. Use Sync now on the sync card.',
                        ),
                      ),
                    if (!_forWorkspace) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey('source-schedule-$_schedule'),
                        initialValue: _schedule,
                        isExpanded: true,
                        decoration: _decoration(text('同步计划', 'Schedule')),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(text('仅手动同步', 'Manual only')),
                          ),
                          DropdownMenuItem(
                            value: '0 0 * * * *',
                            child: Text(text('每小时', 'Hourly')),
                          ),
                          DropdownMenuItem(
                            value: '0 0 */6 * * *',
                            child: Text(text('每 6 小时', 'Every 6 hours')),
                          ),
                          DropdownMenuItem(
                            value: '0 0 */12 * * *',
                            child: Text(text('每 12 小时', 'Every 12 hours')),
                          ),
                          if (![
                            '',
                            '0 0 * * * *',
                            '0 0 */6 * * *',
                            '0 0 */12 * * *',
                          ].contains(_schedule))
                            DropdownMenuItem(
                              value: _schedule,
                              child: Text(_schedule),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _schedule = value!;
                                  _dirty = true;
                                }),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('source-mode-$_mode'),
                        initialValue: _mode,
                        decoration: _decoration(text('同步方式', 'Sync mode')),
                        items: [
                          DropdownMenuItem(
                            value: 'incremental',
                            child: Text(text('增量同步', 'Incremental')),
                          ),
                          DropdownMenuItem(
                            value: 'full',
                            child: Text(text('全量同步', 'Full')),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _mode = value!;
                                  _dirty = true;
                                }),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('source-conflict-$_conflict'),
                        initialValue: _conflict,
                        decoration:
                            _decoration(text('内容冲突处理', 'Conflict handling')),
                        items: [
                          DropdownMenuItem(
                            value: 'overwrite',
                            child: Text(text('覆盖已有内容', 'Overwrite')),
                          ),
                          DropdownMenuItem(
                            value: 'skip',
                            child: Text(text('跳过已有内容', 'Skip')),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _conflict = value!;
                                  _dirty = true;
                                }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(text('同步源端删除', 'Sync source deletions')),
                        subtitle: Text(
                          text(
                            '开启后，源端移除的文档也会从知识库中删除。',
                            'Removing source documents will also remove their knowledge base copies.',
                          ),
                        ),
                        value: _deletions,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _deletions = value;
                                  _dirty = true;
                                }),
                      ),
                    ],
                    if (_dirty)
                      Text(text('更改尚未保存。', 'Changes are not saved yet.')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!_forWorkspace || _type != 'gitlab')
                          FilledButton(
                            onPressed: _busy ? null : _save,
                            child: Text(text('保存同步配置', 'Save sync settings')),
                          ),
                        if (!_forWorkspace) ...[
                          OutlinedButton(
                            onPressed: _busy || _syncing
                                ? null
                                : () => _operate('sync'),
                            child: Text(text('立即同步', 'Sync now')),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _operate(
                                      _source!['status'] == 'paused'
                                          ? 'resume'
                                          : 'pause',
                                    ),
                            child: Text(
                              _source!['status'] == 'paused'
                                  ? text('启用计划同步', 'Resume schedule')
                                  : text('暂停计划同步', 'Pause schedule'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!_forWorkspace) ...[
                      const Divider(height: 28),
                      Text(
                        text('同步记录', 'Sync history'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (_source!['latest_sync_log'] != null)
                        Text(_status(_source!['latest_sync_log']['status'])),
                      for (final log in _logs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_status(log['status'])),
                          subtitle: Text(
                            '${log['started_at'] ?? ''}\n${text('新增 / 更新 / 删除 / 失败', 'Created / updated / deleted / failed')}: ${log['items_created'] ?? 0} / ${log['items_updated'] ?? 0} / ${log['items_deleted'] ?? 0} / ${log['items_failed'] ?? 0}',
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      text(
                                        '删除数据源连接？',
                                        'Delete this connection?',
                                      ),
                                    ),
                                    content: Text(
                                      text(
                                        '删除后将停止此连接的后续同步。',
                                        'This stops future syncs for this connection.',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(text('取消', 'Cancel')),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(text('删除', 'Delete')),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !mounted) return;
                                await _run(() async {
                                  await _call('delete');
                                  if (mounted) {
                                    widget.onChanged();
                                    widget.onBack();
                                  }
                                });
                              },
                        child: Text(text('删除连接', 'Delete connection')),
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
