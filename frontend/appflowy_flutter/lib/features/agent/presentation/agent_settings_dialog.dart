import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../application/agent_settings.dart';
import '../application/agent_controller.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';

Future<bool> showAgentSettings(BuildContext context) async {
  AgentSettings settings;
  try {
    settings = await AgentSettings.load();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法读取 Agent 设置：$e')));
    }
    return false;
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => AgentSettingsDialog(settings: settings),
      ) ??
      false;
}

class AgentSettingsDialog extends StatefulWidget {
  const AgentSettingsDialog({super.key, required this.settings});
  final AgentSettings settings;
  @override
  State<AgentSettingsDialog> createState() => AgentSettingsDialogState();
}

class AgentSettingsDialogState extends State<AgentSettingsDialog> {
  late final url = TextEditingController(text: widget.settings.remoteUrl);
  late final token = TextEditingController(text: widget.settings.remoteToken);
  late final servers = TextEditingController(
    text:
        const JsonEncoder.withIndent('  ').convert(widget.settings.mcpServers),
  );
  late final skills = widget.settings.skillDirectories.toList();
  late final disabledTools = widget.settings.disabledNoteTools.toSet();
  String? error;
  bool saving = false;
  @override
  void dispose() {
    for (final controller in [url, token, servers]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final remote = url.text.trim();
      if (remote.isNotEmpty) {
        final uri = Uri.parse(remote);
        if (uri.scheme != 'wss' &&
            !(uri.scheme == 'ws' &&
                ['127.0.0.1', 'localhost', '::1'].contains(uri.host))) {
          throw const FormatException('远端地址应为 wss://域名/agent');
        }
        if (token.text.trim().length < 32) {
          throw const FormatException('执行器连接密钥至少需要 32 个字符');
        }
      } else if (!Platform.isWindows &&
          !Platform.isMacOS &&
          !Platform.isLinux) {
        throw const FormatException('此设备需要配置远端执行器');
      }
      final decoded = jsonDecode(servers.text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('MCP 配置应为服务名与配置的 JSON 对象');
      }
      for (final entry in decoded.entries) {
        if (entry.value is! Map ||
            !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(entry.key)) {
          throw const FormatException('请检查 MCP 服务名称和配置');
        }
      }
      await AgentSettings(
        scope: widget.settings.scope,
        remoteUrl: remote,
        remoteToken: token.text.trim(),
        skillDirectories: skills,
        disabledNoteTools: disabledTools.toList(),
        mcpServers: decoded,
      ).save();
      await AgentController.revokeAll();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Agent 设置'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: url,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '远端执行器',
                    hintText: '留空使用本机；远端使用 wss://域名/agent',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: token,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '执行器连接密钥'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '工作目录和权限模式在每个 Agent 文档的输入框下方选择；未选择工作目录时只开放小马笔记的笔记工具，MCP、Skills 与命令也不会加载。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  '已授权的 Skills 目录',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final skill in skills)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(skill, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: '移除授权',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => skills.remove(skill)),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final selected =
                        await FilePicker.platform.getDirectoryPath();
                    if (selected != null && mounted) {
                      setState(() {
                        if (!skills.contains(selected)) skills.add(selected);
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加 Skills 目录'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: servers,
                  minLines: 5,
                  maxLines: 12,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'MCP 服务',
                    hintText: '{"docs":{"url":"https://example.com/mcp"}}',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('笔记工具权限'),
                  subtitle: const Text('仅影响内置 Agent；写入仍需确认'),
                  children: McpTools(endpoint: 'settings', version: '1.0.0')
                      .toolSpecs
                      .map(
                        (spec) => CheckboxListTile(
                          dense: true,
                          title: Text(spec.name),
                          subtitle: Text(spec.description),
                          value: !disabledTools.contains(spec.name),
                          onChanged: (allowed) => setState(() {
                            if (allowed == true) {
                              disabledTools.remove(spec.name);
                            } else {
                              disabledTools.add(spec.name);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
                const Text('保存后重新连接。MCP 服务和启动命令应来自你信任的提供者。'),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: const Text('保存'),
          ),
        ],
      );
}
