import 'package:flutter/material.dart';

import '../application/agent_automation.dart';
import '../application/agent_automation_service.dart';

/// Run history for one automation. WeKnora keeps the records; Cloud scopes them
/// to the workspace that owns the automation.
class AgentAutomationRunsPage extends StatefulWidget {
  const AgentAutomationRunsPage({
    super.key,
    required this.service,
    required this.workspace,
    required this.automation,
  });

  final AgentAutomationService service;
  final Future<String> Function() workspace;
  final AgentAutomation automation;

  @override
  State<AgentAutomationRunsPage> createState() =>
      _AgentAutomationRunsPageState();
}

class _AgentAutomationRunsPageState extends State<AgentAutomationRunsPage> {
  List<AgentAutomationRun> runs = const [];
  final busy = <String>{};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final items = await widget.service.runs(
        await widget.workspace(),
        widget.automation.id,
      );
      if (!mounted) return;
      setState(() {
        runs = items;
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

  Future<void> _cancel(AgentAutomationRun run) async {
    setState(() => busy.add(run.id));
    try {
      await widget.service.cancelRun(await widget.workspace(), run.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy.remove(run.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.automation.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _summary(context),
            if (error != null) ...[
              const SizedBox(height: 12),
              _banner(context, error!),
            ],
            const SizedBox(height: 16),
            Text('运行记录', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (runs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '还没有运行记录',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else
              for (final run in runs) ...[
                _runTile(context, run),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.automation.description.isNotEmpty) ...[
              Text(widget.automation.description),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(context, widget.automation.scheduleLabel),
                _chip(context, widget.automation.nextRunLabel),
                _chip(context, widget.automation.lastRunLabel),
                _chip(
                  context,
                  widget.automation.enabled ? '已启用' : '已暂停',
                ),
              ],
            ),
            if (widget.automation.pausedReason != null) ...[
              const SizedBox(height: 8),
              Text(
                '暂停原因：${widget.automation.pausedReason}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );

  Widget _runTile(BuildContext context, AgentAutomationRun run) {
    final failed = run.status == 'failed' || run.status == 'needs_attention';
    final color = failed
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: Icon(
          failed ? Icons.error_outline : Icons.check_circle_outline,
          color: color,
          size: 20,
        ),
        title: Row(
          children: [
            Text(run.statusLabel, style: TextStyle(color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                run.startedLabel,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (run.durationLabel.isNotEmpty)
              Text(
                run.durationLabel,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        subtitle: run.error.isEmpty && run.answer.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  run.error.isNotEmpty ? run.error : run.answer,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        children: [
          if (run.answer.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(run.answer),
            ),
          if (run.error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                run.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          if (run.cancellable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy.contains(run.id) ? null : () => _cancel(run),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('取消本次运行'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      );

  Widget _banner(BuildContext context, String message) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      );
}
