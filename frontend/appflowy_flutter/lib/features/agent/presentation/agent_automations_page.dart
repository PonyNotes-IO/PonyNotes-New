import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:flutter/material.dart';

import '../application/agent_automation.dart';
import '../application/agent_automation_service.dart';
import 'agent_automation_editor.dart';
import 'agent_automation_runs.dart';

/// Task list for scheduled Agent runs. WeKnora owns scheduling and execution;
/// this page only shows and controls what Cloud has scoped to the workspace.
class AgentAutomationsPage extends StatefulWidget {
  const AgentAutomationsPage({
    super.key,
    this.service,
    this.workspace,
    this.embedded = false,
  });

  final AgentAutomationService? service;
  final Future<String?> Function()? workspace;
  final bool embedded;

  @override
  State<AgentAutomationsPage> createState() => _AgentAutomationsPageState();
}

class _AgentAutomationsPageState extends State<AgentAutomationsPage> {
  late final service = widget.service ?? AgentAutomationService();
  Future<String?> Function() get workspace =>
      widget.workspace ?? AIChatViewService.getCurrentWorkspaceId;

  List<AgentAutomation> automations = const [];
  final busy = <String>{};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _workspace() async {
    final id = await workspace();
    if (id == null) throw StateError('请先打开工作区');
    return id;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final items = await service.list(await _workspace());
      if (!mounted) return;
      setState(() {
        automations = items;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e'.replaceFirst('Bad state: ', '');
        loading = false;
      });
    }
  }

  Future<void> _guard(String id, Future<void> Function() action) async {
    setState(() => busy.add(id));
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  Future<void> _toggle(AgentAutomation automation, bool enabled) => _guard(
        automation.id,
        () async => service.update(
          await _workspace(),
          automation.id,
          automation.toSaveBody(enabledOverride: enabled),
        ),
      );

  Future<void> _run(AgentAutomation automation) => _guard(
        automation.id,
        () async => service.control(await _workspace(), automation.id, 'run'),
      );

  Future<void> _pause(AgentAutomation automation) => _guard(
        automation.id,
        () async => service.control(
          await _workspace(),
          automation.id,
          automation.enabled ? 'pause' : 'resume',
        ),
      );

  Future<void> _delete(AgentAutomation automation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自动化任务'),
        content: Text('删除「${automation.name}」后，它的运行记录将不再可用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(
      automation.id,
      () async => service.remove(await _workspace(), automation.id),
    );
  }

  Future<void> _openEditor([AgentAutomation? automation]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AgentAutomationEditor(
          service: service,
          workspace: _workspace,
          automation: automation,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  void _openRuns(AgentAutomation automation) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AgentAutomationRunsPage(
          service: service,
          workspace: _workspace,
          automation: automation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) _header(context) else _toolbar(context),
        if (error != null) _errorBanner(context),
        Expanded(child: _content(context)),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(body: SafeArea(child: body));
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Text(
              '自动化任务',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            ..._toolbarActions(context),
          ],
        ),
      );

  Widget _toolbar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Text(
              '自动化任务',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            ..._toolbarActions(context),
          ],
        ),
      );

  List<Widget> _toolbarActions(BuildContext context) => [
        IconButton(
          tooltip: '刷新',
          onPressed: loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: loading ? null : () => _openEditor(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建自动化'),
        ),
      ];

  Widget _errorBanner(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => error = null),
              ),
            ],
          ),
        ),
      );

  Widget _content(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (automations.isEmpty) {
      return _empty(context);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: automations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _tile(context, automations[index]),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有自动化任务',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '把常做的问 AI 操作排成计划，由 Agent 按时执行。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建自动化'),
            ),
          ],
        ),
      );

  Widget _tile(BuildContext context, AgentAutomation automation) {
    final busyNow = busy.contains(automation.id);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: busyNow ? null : () => _openRuns(automation),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      automation.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (busyNow)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Switch(
                      value: automation.enabled,
                      onChanged: (value) => _toggle(automation, value),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _openEditor(automation);
                        case 'run':
                          _run(automation);
                        case 'pause':
                          _pause(automation);
                        case 'delete':
                          _delete(automation);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'run', child: Text('立即运行')),
                      PopupMenuItem(
                        value: 'pause',
                        child: Text(automation.enabled ? '暂停' : '恢复'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _chip(context, automation.scheduleLabel),
                  _chip(context, automation.nextRunLabel),
                  _status(context, automation),
                ],
              ),
              if (automation.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  automation.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      );

  Widget _status(BuildContext context, AgentAutomation automation) {
    final status = automation.activeRunStatus ?? automation.lastRunStatus;
    if (status == null) return const SizedBox.shrink();
    final failed = status == 'failed' || status == 'needs_attention';
    final color = failed
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          failed ? Icons.error_outline : Icons.check_circle_outline,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          AgentAutomationRun.labelOf(status),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
        if (automation.consecutiveFailures > 0) ...[
          const SizedBox(width: 6),
          Text(
            '连续失败 ${automation.consecutiveFailures} 次',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
