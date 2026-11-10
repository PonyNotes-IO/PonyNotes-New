import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/agent_controller.dart';
import '../application/agent_settings.dart';

const permissionLabels = {
  'ask': '逐次确认',
  'auto': '自动审批',
  'full': '完全开放',
};
const permissionHints = {
  'ask': '每次写入笔记、修改文件或执行命令前确认',
  'auto': '笔记写入和工作目录内的文件修改直接执行；删除、命令和外部 MCP 工具仍需确认',
  'full': '所有操作都不再确认，包括删除和执行命令',
};

/// Composer controls for the working directory, permission mode and context usage.
class AgentWorkspaceControls extends StatelessWidget {
  const AgentWorkspaceControls({
    super.key,
    required this.agent,
    required this.onShowContext,
  });
  final AgentController agent;
  final VoidCallback onShowContext;

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      agent.error = '$e';
      agent.changed();
    }
  }

  Future<void> _pickDirectory(BuildContext context) async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null || !context.mounted) return;
    await _guard(
      context,
      () => agent.configureWorkspace(directory: selected),
    );
  }

  Future<void> _setMode(BuildContext context, String mode) async {
    if (mode == 'full') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启完全开放？'),
          content: Text(
            '${permissionHints['full']}。'
            '命令拥有执行器系统用户的权限，可访问工作目录以外的文件。'
            '仅在信任当前任务时使用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开启'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    await _guard(context, () => agent.configureWorkspace(permissionMode: mode));
  }

  @override
  Widget build(BuildContext context) {
    final directory = agent.workspace.directory;
    final busy = agent.running || agent.compacting || agent.connecting;
    final canPickLocal = !agent.remote &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final label = directory.isEmpty
        ? '默认会话目录'
        : directory == AgentWorkspaceConfig.remoteDirectory
            ? '远端任务目录'
            : p.basename(directory);
    final mode = agent.workspace.permissionMode;
    final percent = (agent.contextUsage?['percent'] as num?)?.toDouble();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          tooltip:
              '工作目录：${directory.isEmpty ? agent.effectiveDirectory ?? '默认会话目录' : directory == AgentWorkspaceConfig.remoteDirectory ? '远端任务目录' : directory}',
          enabled: !busy,
          onSelected: (value) => switch (value) {
            'pick' => _pickDirectory(context),
            'remote' => _guard(
                context,
                () => agent.configureWorkspace(
                  directory: AgentWorkspaceConfig.remoteDirectory,
                ),
              ),
            _ => _guard(context, () => agent.configureWorkspace(directory: '')),
          },
          itemBuilder: (_) => [
            if (canPickLocal)
              const PopupMenuItem(
                value: 'pick',
                child: Text('选择本地工作目录…'),
              ),
            if (agent.remote)
              const PopupMenuItem(
                value: 'remote',
                child: Text('使用远端任务目录'),
              ),
            PopupMenuItem(
              value: 'none',
              enabled: directory.isNotEmpty,
              child: const Text('使用默认会话目录'),
            ),
          ],
          child: _chip(
            context,
            Icons.folder_outlined,
            label,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '权限模式：${permissionHints[mode]}',
          initialValue: mode,
          onSelected: (value) => _setMode(context, value),
          itemBuilder: (_) => AgentWorkspaceConfig.modes
              .map(
                (value) => PopupMenuItem(
                  value: value,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(permissionLabels[value]!),
                    subtitle: Text(permissionHints[value]!),
                  ),
                ),
              )
              .toList(),
          child: _chip(
            context,
            mode == 'full'
                ? Icons.lock_open_outlined
                : mode == 'auto'
                    ? Icons.verified_user_outlined
                    : Icons.shield_outlined,
            permissionLabels[mode]!,
            warning: mode == 'full',
          ),
        ),
        if (agent.contextUsage != null)
          Tooltip(
            key: const Key('agent-context-gauge'),
            message: contextSummary(agent),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onShowContext,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: ((percent ?? 0) / 100).clamp(0, 1),
                    strokeWidth: 2.5,
                    backgroundColor: Theme.of(context).dividerColor,
                    color: (percent ?? 0) >= 80
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
          ),
        if (agent.credits != null)
          Tooltip(
            key: const Key('agent-credits'),
            message: '${agent.credits!.label}，由模型服务按实际用量结算',
            child: _chip(
              context,
              Icons.toll_outlined,
              agent.credits!.label,
              warning: !agent.credits!.unlimited && agent.credits!.credits <= 0,
            ),
          ),
        if (agent.creditsError != null)
          Tooltip(
            message: agent.creditsError!,
            child: TextButton(
              onPressed: agent.refreshCredits,
              child: const Text('重试积分查询'),
            ),
          ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    IconData icon,
    String text, {
    bool warning = false,
  }) {
    final color = warning ? Theme.of(context).colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _count(num? value) => value == null
    ? '—'
    : value >= 1000
        ? '${(value / 1000).toStringAsFixed(1)}k'
        : '$value';

String contextSummary(AgentController agent) {
  final usage = agent.contextUsage;
  if (usage == null) return '上下文：开始对话后显示';
  final percent = (usage['percent'] as num?)?.toStringAsFixed(0);
  return '上下文 ${_count(usage['tokens'] as num?)} / ${_count(usage['contextWindow'] as num?)} tokens'
      '${percent == null ? '' : '（$percent%）'}；接近上限时自动压缩';
}

/// Rows for the details pane: what the Agent can reach and how full its context is.
List<Widget> contextDetails(AgentController agent) {
  final tokens = agent.sessionTokens;
  final directory = agent.workspace.directory;
  final tools = agent.activeTools;
  return [
    if (agent.credits != null) Text('剩余额度：${agent.credits!.label}'),
    Text(contextSummary(agent)),
    if (tokens != null)
      Text(
        '本文档累计：输入 ${_count(tokens['input'] as num?)} · 输出 ${_count(tokens['output'] as num?)} · 缓存 ${_count(tokens['cacheRead'] as num?)}',
        style: const TextStyle(fontSize: 12),
      ),
    const SizedBox(height: 8),
    Text(
      '工作目录：${directory.isEmpty ? agent.effectiveDirectory ?? '默认会话目录' : directory == AgentWorkspaceConfig.remoteDirectory ? '远端任务目录' : directory}',
    ),
    Text('权限：${permissionLabels[agent.workspace.permissionMode]}'),
    if (tools.isNotEmpty)
      Text(
        '可用工具：${tools.length} 个',
        style: const TextStyle(fontSize: 12),
      ),
  ];
}
