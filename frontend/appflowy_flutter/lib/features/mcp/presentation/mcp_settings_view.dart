import 'dart:convert';

import 'package:appflowy/features/mcp/application/mcp_audit_log.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// MCP 接入设置：服务开关、Token、Agent 配置、工具权限、审计日志。
class McpSettingsView extends StatefulWidget {
  const McpSettingsView({super.key});

  @override
  State<McpSettingsView> createState() => _McpSettingsViewState();
}

class _McpSettingsViewState extends State<McpSettingsView> {
  final _service = McpServerService.instance;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  int _selectedTab = 0;
  bool _showSearch = false;
  bool _showToken = false;

  /// 只用来读取工具清单，不参与实际注册。
  final _registry = McpTools(endpoint: '', version: '');

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _service,
        McpPermissions.instance,
        McpAuditLog.instance,
      ]),
      builder: (context, _) {
        final theme = AppFlowyTheme.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: theme.textColorScheme.primary,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.textColorScheme.primary,
                side: BorderSide(color: theme.borderColorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth < 480 ? 16 : 28,
                  28,
                  constraints.maxWidth < 480 ? 16 : 28,
                  32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '小马笔记 MCP',
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                    const VSpace(8),
                    Text(
                      '在其他应用中使用小马笔记。让 AI 客户端连接你的工作区，查找、整理和编辑笔记。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                    const VSpace(24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _tab(context, 0, '发现 MCP 客户端'),
                        _tab(context, 1, '连接与权限'),
                      ],
                    ),
                    const VSpace(20),
                    _buildServiceCard(context),
                    const VSpace(20),
                    if (_selectedTab == 0) ...[
                      _buildRecentClients(context),
                      const VSpace(20),
                      _buildAgentCards(context),
                    ] else ...[
                      _buildTokenCard(context),
                      const VSpace(24),
                      _buildToolPermissions(context),
                      const VSpace(24),
                      _buildAuditLog(context),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tab(BuildContext context, int index, String label) {
    final theme = AppFlowyTheme.of(context);
    final selected = _selectedTab == index;
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: selected ? theme.fillColorScheme.primary : null,
        foregroundColor: selected
            ? theme.textColorScheme.primary
            : theme.textColorScheme.secondary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        minimumSize: const Size(0, 34),
        shape: const StadiumBorder(),
      ),
      onPressed: () {
        setState(() => _selectedTab = index);
        _scrollController.jumpTo(0);
      },
      child: Text(label),
    );
  }

  // ---------------------------------------------------------------- 服务

  Widget _buildServiceCard(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.borderColorScheme.primary),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 7,
                color: _service.isRunning
                    ? theme.textColorScheme.success
                    : theme.textColorScheme.tertiary,
              ),
              const HSpace(8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _service.isStarting
                          ? '本机服务 · 启动中'
                          : _service.isRunning
                              ? '本机服务 · 运行中'
                              : '本机服务 · 已关闭',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                    const VSpace(5),
                    Text(
                      _service.endpoint,
                      style: TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 11,
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '复制连接地址',
                onPressed: () => _copy(_service.endpoint, '连接地址已复制'),
                icon: const Icon(Icons.copy_outlined, size: 15),
                color: theme.iconColorScheme.secondary,
                visualDensity: VisualDensity.compact,
              ),
              if (_service.isStarting)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                SizedBox(
                  height: 30,
                  child: Semantics(
                    label: '本机 MCP 服务',
                    child: Switch.adaptive(
                      value: _service.isRunning,
                      activeTrackColor: theme.fillColorScheme.infoThick,
                      onChanged: _toggle,
                    ),
                  ),
                ),
            ],
          ),
          if (_service.lastError != null) ...[
            const VSpace(8),
            Text(
              _service.lastError!,
              style: TextStyle(
                fontSize: 12,
                color: theme.textColorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentClients(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final agents = <String, McpAuditEntry>{};
    for (final entry in McpAuditLog.instance.entries) {
      if (entry.agent.trim().isNotEmpty) {
        agents.putIfAbsent(entry.agent, () => entry);
      }
    }
    final presets = _agentPresets(_service.token ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '最近使用的客户端 (${agents.length})'),
        const VSpace(16),
        if (agents.isEmpty)
          Text(
            '还没有使用记录。从下方选择客户端，完成配置后即可开始。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: theme.textColorScheme.secondary,
            ),
          )
        else
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              for (final agent in agents.entries.take(8))
                SizedBox(
                  width: 88,
                  child: Column(
                    children: [
                      _ClientLogo(
                        asset: presets
                            .where(
                              (p) => agent.key.toLowerCase().contains(p.id),
                            )
                            .firstOrNull
                            ?.asset,
                        size: 44,
                      ),
                      const VSpace(8),
                      Tooltip(
                        message: agent.key,
                        child: Text(
                          agent.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textColorScheme.primary,
                          ),
                        ),
                      ),
                      const VSpace(3),
                      Text(
                        '上次 ${_formatTime(agent.value.at)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.textColorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppFlowyTheme.of(context).textColorScheme.primary,
        ),
      );

  // ---------------------------------------------------------------- Token

  Widget _buildTokenCard(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final token = _service.token;
    return _Section(
      title: '连接凭证',
      trailing: TextButton(
        onPressed: _resetToken,
        child: Text(_service.hasToken ? '重置' : '生成'),
      ),
      children: [
        if (token == null)
          FlowyText(
            '开启本机服务后会自动生成 Token，也可以手动生成。',
            maxLines: null,
            fontSize: 13,
            color: theme.textColorScheme.secondary,
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  _showToken ? token : '••••••••••••••••••••••••',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: theme.textColorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                tooltip: _showToken ? '隐藏 Token' : '显示 Token',
                onPressed: () => setState(() => _showToken = !_showToken),
                icon: Icon(
                  _showToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
              TextButton(
                onPressed: () => _copy(token, 'Token 已复制'),
                child: const Text('复制'),
              ),
            ],
          ),
          const VSpace(6),
          FlowyText(
            'Token 用于授权客户端访问笔记，请妥善保管。重置后需要重新配置客户端。',
            maxLines: null,
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
        ],
        const VSpace(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _service.isRunning ? _probe : null,
              child: const Text('服务自检'),
            ),
            TextButton(
              onPressed: _service.hasToken ? _revoke : null,
              style: TextButton.styleFrom(
                foregroundColor: theme.textColorScheme.error,
              ),
              child: const Text('撤销授权'),
            ),
          ],
        ),
        const VSpace(8),
        Text(
          '服务仅在本机运行，关闭小马笔记后停止。客户端以当前账号权限访问当前工作区。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.textColorScheme.secondary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- Agent 配置

  Widget _buildAgentCards(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final presets = _agentPresets(_service.token ?? '')
        .where(
          (preset) => '${preset.name} ${preset.description}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            _sectionTitle(context, '可与小马笔记配合使用的客户端'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _showSearch ? '收起搜索' : '搜索客户端',
                  icon: const Icon(Icons.search, size: 18),
                  color: theme.iconColorScheme.secondary,
                  onPressed: () => setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _searchController.clear();
                  }),
                ),
                const HSpace(4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.fillColorScheme.infoThick,
                    foregroundColor: theme.textColorScheme.onFill,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => _openAgentConfig(
                    _agentPresets(_service.token ?? '').last.id,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('连接客户端'),
                ),
              ],
            ),
          ],
        ),
        if (_showSearch) ...[
          const VSpace(12),
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style:
                TextStyle(fontSize: 13, color: theme.textColorScheme.primary),
            decoration: InputDecoration(
              hintText: '搜索客户端',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
        const VSpace(16),
        if (presets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '没有找到匹配的客户端，试试其他关键词。',
              style: TextStyle(
                fontSize: 13,
                color: theme.textColorScheme.secondary,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 490 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 24) / columns;
              return Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  for (final preset in presets)
                    SizedBox(
                      width: width,
                      child: _ClientTile(
                        preset: preset,
                        onConnect: () => _openAgentConfig(preset.id),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  List<_AgentPreset> _agentPresets(String token) {
    final endpoint = _service.endpoint;
    final bridgePath =
        '<PonyNotes-New>/frontend/tools/mcp_stdio_bridge/bin/mcp_stdio_bridge.dart';
    return [
      _AgentPreset(
        id: 'codex',
        name: 'Codex',
        description: '读取和整理笔记，协助完成任务。',
        asset: 'assets/images/setting/mcp_codex.svg',
        hint: '~/.codex/config.toml',
        json: '[mcp_servers.ponynotes]\n'
            'url = "$endpoint"\n\n'
            '[mcp_servers.ponynotes.http_headers]\n'
            'Authorization = "Bearer $token"',
      ),
      _AgentPreset(
        id: 'claude',
        name: 'Claude Desktop',
        description: '与 Claude 协作，整理和创作笔记。',
        asset: 'assets/images/setting/mcp_claude.svg',
        hint: 'claude_desktop_config.json',
        json: _pretty({
          'mcpServers': {
            'ponynotes': {
              'command': 'dart',
              'args': ['run', bridgePath],
              'env': {
                'PONYNOTES_MCP_URL': endpoint,
                'PONYNOTES_MCP_TOKEN': token,
              },
            },
          },
        }),
      ),
      _AgentPreset(
        id: 'cursor',
        name: 'Cursor',
        description: '编程时检索笔记，获取项目上下文。',
        asset: 'assets/images/setting/mcp_cursor.svg',
        hint: '~/.cursor/mcp.json',
        json: _pretty({
          'mcpServers': {
            'ponynotes': {
              'type': 'streamable-http',
              'url': endpoint,
              'headers': {'Authorization': 'Bearer $token'},
            },
          },
        }),
      ),
      _AgentPreset(
        id: 'other',
        name: '其他 MCP 客户端',
        description: '连接 Cline、Continue 等 HTTP 客户端。',
        hint: '在客户端的 MCP 设置中添加以下配置',
        json: _pretty({
          'mcpServers': {
            'ponynotes': {
              'url': endpoint,
              'headers': {'Authorization': 'Bearer $token'},
            },
          },
        }),
      ),
    ];
  }

  String _pretty(Map<String, dynamic> value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  Future<void> _openAgentConfig(String id) async {
    final theme = AppFlowyTheme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final preset = _agentPresets(_service.token ?? '')
              .firstWhere((preset) => preset.id == id);
          final ready = _service.isRunning && _service.token != null;
          return Dialog(
            backgroundColor: theme.backgroundColorScheme.primary,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ClientLogo(asset: preset.asset, size: 44),
                        const HSpace(12),
                        Expanded(
                          child: Text(
                            '连接 ${preset.name}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: theme.textColorScheme.primary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                    const VSpace(20),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ready
                                  ? '将配置添加到 ${preset.name}，保存后在客户端中启用小马笔记。'
                                  : '先开启本机服务，再复制配置到客户端。',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: theme.textColorScheme.secondary,
                              ),
                            ),
                            if (ready) ...[
                              const VSpace(16),
                              SelectableText(
                                preset.hint,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textColorScheme.secondary,
                                ),
                              ),
                              const VSpace(8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme.surfaceColorScheme.layer01,
                                  border: Border.all(
                                    color: theme.borderColorScheme.primary,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  preset.json,
                                  style: TextStyle(
                                    fontFamily: 'RobotoMono',
                                    fontSize: 12,
                                    height: 1.6,
                                    color: theme.textColorScheme.primary,
                                  ),
                                ),
                              ),
                              if (id == 'claude') ...[
                                const VSpace(10),
                                Text(
                                  '需要安装 Dart，并将 <PonyNotes-New> 替换为本机项目的实际路径。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.6,
                                    color: theme.textColorScheme.secondary,
                                  ),
                                ),
                              ],
                              const VSpace(10),
                              Text(
                                '配置含有访问凭证，请仅粘贴到你信任的客户端。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textColorScheme.secondary,
                                ),
                              ),
                            ],
                            if (_service.lastError != null) ...[
                              const VSpace(12),
                              Text(
                                _service.lastError!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textColorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const VSpace(20),
                    if (ready) ...[
                      Text(
                        '将连接提示词发给 AI，让它帮你配置并验证连接。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.textColorScheme.secondary,
                        ),
                      ),
                      const VSpace(12),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (ready)
                            OutlinedButton.icon(
                              onPressed: () => _copy(
                                preset.aiConnectionPrompt,
                                'AI 连接提示词已复制，可直接发送给 AI',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.textColorScheme.primary,
                                side: BorderSide(
                                  color: theme.borderColorScheme.primary,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              icon: const Icon(
                                Icons.auto_awesome_outlined,
                                size: 16,
                              ),
                              label: const Text('复制 AI 连接提示词'),
                            ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.fillColorScheme.infoThick,
                              foregroundColor: theme.textColorScheme.onFill,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            onPressed: _service.isStarting
                                ? null
                                : ready
                                    ? () => _copy(
                                          preset.json,
                                          '${preset.name} 配置已复制',
                                        )
                                    : () async {
                                        if (_service.isRunning) {
                                          await _resetToken();
                                        } else {
                                          await _toggle(true);
                                        }
                                      },
                            child: Text(
                              ready
                                  ? '复制配置'
                                  : _service.isStarting
                                      ? '正在开启…'
                                      : _service.isRunning
                                          ? '生成连接凭证'
                                          : '开启本机服务',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ 工具权限

  Widget _buildToolPermissions(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final specs = _registry.toolSpecs;
    final readOnly = specs.where((s) => s.readOnly).toList();
    final writable = specs.where((s) => !s.readOnly).toList();
    final disabled = McpPermissions.instance.disabledTools;
    return _Section(
      title: '工具权限',
      trailing: disabled.isEmpty
          ? null
          : TextButton(
              onPressed: McpPermissions.instance.allowAll,
              child: const Text('全部开启'),
            ),
      children: [
        FlowyText(
          '选择客户端可以使用的工具。关闭后，客户端将无法发现和调用该工具；改动对新连接生效。',
          maxLines: null,
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const VSpace(8),
        _toolGroup(context, '只读（${readOnly.length}）', readOnly),
        const VSpace(8),
        _toolGroup(context, '写入（${writable.length}）', writable),
      ],
    );
  }

  Widget _toolGroup(
    BuildContext context,
    String title,
    List<McpToolSpec> specs,
  ) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          title,
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        for (final spec in specs)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 124,
                  child: Text(
                    spec.name,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: theme.textColorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: FlowyText(
                    spec.description.split('。').first,
                    maxLines: null,
                    fontSize: 12,
                    lineHeight: 1.3,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
                Switch.adaptive(
                  value: McpPermissions.instance.isAllowed(spec.name),
                  onChanged: (allowed) =>
                      McpPermissions.instance.setAllowed(spec.name, allowed),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ 审计日志

  Widget _buildAuditLog(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final entries = McpAuditLog.instance.entries;
    return _Section(
      title: '审计日志',
      trailing: entries.isEmpty
          ? null
          : TextButton(
              onPressed: McpAuditLog.instance.clear,
              child: const Text('清空'),
            ),
      children: [
        if (entries.isEmpty)
          FlowyText(
            '还没有 Agent 调用记录。'
            '连上 Agent 后，这里会显示每次调用的时间、客户端、工具、目标 ID 和耗时。',
            maxLines: null,
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          )
        else
          for (final entry in entries.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      _formatTime(entry.at),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FlowyText(
                      [
                        entry.tool,
                        if (entry.agent.isNotEmpty) entry.agent,
                        if (entry.target.isNotEmpty) entry.target,
                        '${entry.durationMs}ms',
                        if (entry.isError) '失败',
                      ].join(' · '),
                      maxLines: null,
                      fontSize: 12,
                      lineHeight: 1.3,
                      color: entry.isError
                          ? theme.textColorScheme.error
                          : theme.textColorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  String _formatTime(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.month)}/${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  // ------------------------------------------------------------ 动作

  Future<void> _probe() async {
    final error = await _service.probe();
    _showMessage(error ?? '自检通过：服务可达且要求 Token');
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销 MCP 授权'),
        content: const Text('撤销后将停止本地服务并删除 Token，已连接的 Agent 会立即失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.revoke();
    _showMessage('已撤销授权并关闭服务');
  }

  Future<void> _toggle(bool enabled) async {
    try {
      if (enabled) {
        if (!_service.hasToken) {
          await _service.generateToken();
        }
        await _service.start();
        if (!_service.isRunning && _service.lastError != null) {
          _showMessage(_service.lastError!);
        }
      } else {
        await _service.stop();
      }
    } on StateError catch (e) {
      _showMessage(e.message.toString());
    }
  }

  Future<void> _resetToken() async {
    try {
      await _service.resetToken();
      _showMessage('已生成新 Token，旧 Token 立即失效');
    } on StateError catch (e) {
      _showMessage(e.message.toString());
    }
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FlowyText(
                  title,
                  fontSize: 15,
                  color: theme.textColorScheme.primary,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const VSpace(10),
          ...children,
        ],
      ),
    );
  }
}

class _AgentPreset {
  const _AgentPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.hint,
    required this.json,
    this.asset,
  });

  final String id;
  final String name;
  final String description;
  final String hint;
  final String json;
  final String? asset;

  String get aiConnectionPrompt {
    final client = id == 'other' ? '你当前所在的 AI 客户端' : name;
    final location = id == 'other'
        ? '请先识别当前客户端支持的 MCP 配置格式与保存位置。以下是通用 HTTP 配置，请按客户端要求适配。'
        : '配置文件：$hint';
    final bridgeInstructions = id == 'claude'
        ? '\n此配置使用本机 stdio 桥接：请检查 Dart 是否可用，找到 PonyNotes-New 项目目录，'
            '将配置中的 <PonyNotes-New> 替换为实际绝对路径，并确认桥接脚本存在。'
            '找不到目录时请向我询问，不要猜测路径。\n'
        : '';
    final format = id == 'codex' ? 'toml' : 'json';
    return '''请帮我将小马笔记（PonyNotes）的 MCP 服务接入$client，服务名称为 ponynotes，并完成连接验证。

$location
$bridgeInstructions
请按以下步骤操作：
1. 在运行小马笔记的这台电脑上检查现有 MCP 配置，保留其他服务，将下面的 ponynotes 配置合并到正确位置。若你不能操作本机文件或管理 MCP 连接，请给我对应客户端的具体操作步骤。
2. 保存配置后重新加载 MCP 服务；若需要我启用服务或重启客户端，请告诉我具体操作。
3. 连接后先发现可用工具，再实际调用 ponynotes 的 get_context，向我确认当前账号、工作区和连接状态。只有真实调用成功后，才能报告连接成功；本次验证只读取信息，不修改笔记。
4. 如果连接失败，请根据实际错误检查小马笔记是否已打开、MCP 服务是否已开启、地址是否可达、Authorization 是否正确，以及客户端是否支持此连接方式。配置中的 127.0.0.1 是运行小马笔记的本机地址，云端 AI 无法直接访问；无法访问时请说明原因，不要虚构结果。

以下配置已包含连接地址和访问凭证，请直接用于本机配置，不要在回复中回显 Token，也不要将凭证提交到代码仓库。

```$format
$json
```
''';
  }
}

class _ClientLogo extends StatelessWidget {
  const _ClientLogo({this.asset, this.size = 48});

  final String? asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.23),
      decoration: BoxDecoration(
        color: theme.backgroundColorScheme.primary,
        border: Border.all(color: theme.borderColorScheme.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: asset == null
          ? Icon(
              Icons.hub_outlined,
              size: size * 0.54,
              color: theme.iconColorScheme.secondary,
            )
          : FlowySvg(
              FlowySvgData(asset!),
              size: Size.square(size * 0.54),
              color: theme.iconColorScheme.primary,
              blendMode: asset!.contains('claude') ? null : BlendMode.srcIn,
            ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.preset, required this.onConnect});

  final _AgentPreset preset;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onConnect,
        borderRadius: BorderRadius.circular(8),
        hoverColor: theme.surfaceColorScheme.primaryHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ClientLogo(asset: preset.asset),
              const HSpace(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                    const VSpace(5),
                    Text(
                      preset.description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const HSpace(8),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton(
                  onPressed: onConnect,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('连接'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
