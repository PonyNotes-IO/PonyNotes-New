import 'dart:convert';

import 'package:appflowy/features/mcp/application/mcp_audit_log.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
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

  /// 只用来读取工具清单，不参与实际注册。
  final _registry = McpTools(endpoint: '', version: '');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _service,
        McpPermissions.instance,
        McpAuditLog.instance,
      ]),
      builder: (context, _) {
        return SettingsBody(
          title: 'AI 接入 (MCP)',
          description: '开启后，外部 Agent 可通过本机 MCP 服务、以当前账号权限读取和修改小马笔记。'
              '服务只监听 127.0.0.1，关闭客户端即停止。',
          autoSeparate: false,
          children: [
            _buildServiceCard(context),
            const VSpace(16),
            _buildTokenCard(context),
            const VSpace(16),
            _buildAgentCards(context),
            const VSpace(16),
            _buildToolPermissions(context),
            const VSpace(16),
            _buildAuditLog(context),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- 服务

  Widget _buildServiceCard(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return _Section(
      title: '服务',
      trailing: _service.isStarting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch.adaptive(
              value: _service.isRunning,
              onChanged: _toggle,
            ),
      children: [
        _KeyValueRow(
          label: '状态',
          value: _service.isRunning ? '运行中' : '已关闭',
        ),
        _KeyValueRow(
          label: '连接地址',
          value: _service.endpoint,
          monospace: true,
          onCopy: () => _copy(_service.endpoint, '连接地址已复制'),
        ),
        if (_service.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FlowyText(
              _service.lastError!,
              fontSize: 13,
              color: theme.textColorScheme.primary,
            ),
          ),
        const VSpace(12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _service.isRunning ? _probe : null,
              child: const Text('服务自检'),
            ),
            TextButton(
              onPressed: _service.hasToken ? _revoke : null,
              child: const Text('撤销授权'),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Token

  Widget _buildTokenCard(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final token = _service.token;
    return _Section(
      title: 'Token',
      trailing: TextButton(
        onPressed: _resetToken,
        child: Text(_service.hasToken ? '重置' : '生成'),
      ),
      children: [
        if (token == null)
          FlowyText(
            '尚未生成 Token。生成后可直接复制到下面的 Agent 配置里。',
            fontSize: 13,
            color: theme.textColorScheme.secondary,
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  token,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: theme.textColorScheme.primary,
                  ),
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
            'Token 只保存在本机，用于把配置粘到 Agent 里；鉴权仍按摘要比对。'
            '重置后旧 Token 立即失效。',
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------- Agent 配置

  Widget _buildAgentCards(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final token = _service.token;
    if (token == null) {
      return _Section(
        title: 'Agent 配置',
        children: [
          FlowyText(
            '生成 Token 后，这里会给出可直接复制的配置片段。',
            fontSize: 13,
            color: theme.textColorScheme.secondary,
          ),
        ],
      );
    }

    final presets = _agentPresets(token);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < presets.length; i++) ...[
          if (i > 0) const VSpace(12),
          _AgentConfigCard(
            preset: presets[i],
            onCopy: () => _copy(presets[i].json, '${presets[i].name} 配置已复制'),
          ),
        ],
      ],
    );
  }

  List<_AgentPreset> _agentPresets(String token) {
    final endpoint = _service.endpoint;
    final bridgePath =
        '<PonyNotes-New>/frontend/tools/mcp_stdio_bridge/bin/mcp_stdio_bridge.dart';
    return [
      _AgentPreset(
        name: 'Cursor',
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
        name: 'Claude Desktop',
        hint: 'claude_desktop_config.json（走 stdio 桥）',
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
        name: 'Cline / Continue / 其他 HTTP 客户端',
        hint: '填 URL + Authorization 头',
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
          '关掉的工具不会出现在 Agent 的工具列表里，也就无法调用。改动对下一个连接生效。',
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
                  width: 132,
                  child: Text(
                    spec.name,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: theme.textColorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: FlowyText(
                    spec.description.split('。').first,
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
                    width: 62,
                    child: Text(
                      _formatTime(entry.at),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 128,
                    child: Text(
                      entry.tool,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: entry.isError
                            ? theme.textColorScheme.primary
                            : theme.textColorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FlowyText(
                      [
                        if (entry.agent.isNotEmpty) entry.agent,
                        if (entry.target.isNotEmpty) entry.target,
                        '${entry.durationMs}ms',
                        if (entry.isError) '失败',
                      ].join(' · '),
                      fontSize: 12,
                      lineHeight: 1.3,
                      color: entry.isError
                          ? theme.textColorScheme.primary
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
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
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

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.onCopy,
  });

  final String label;
  final String value;
  final bool monospace;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: FlowyText(
              label,
              fontSize: 13,
              color: theme.textColorScheme.secondary,
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: monospace ? 'monospace' : null,
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          if (onCopy != null)
            TextButton(
              onPressed: onCopy,
              child: const Text('复制'),
            ),
        ],
      ),
    );
  }
}

class _AgentPreset {
  const _AgentPreset({
    required this.name,
    required this.hint,
    required this.json,
  });

  final String name;
  final String hint;
  final String json;
}

class _AgentConfigCard extends StatelessWidget {
  const _AgentConfigCard({required this.preset, required this.onCopy});

  final _AgentPreset preset;
  final VoidCallback onCopy;

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
                  preset.name,
                  fontSize: 14,
                  color: theme.textColorScheme.primary,
                ),
              ),
              TextButton(
                onPressed: onCopy,
                child: const Text('复制配置'),
              ),
            ],
          ),
          FlowyText(
            preset.hint,
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
          const VSpace(8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.surfaceColorScheme.layer01,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.borderColorScheme.primary),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                preset.json,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.45,
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
