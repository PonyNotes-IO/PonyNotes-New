import 'package:flutter/material.dart';
import '../application/agent_controller.dart';
import '../application/agent_permissions.dart';

class AgentWorkspaceControls extends StatelessWidget {
  const AgentWorkspaceControls({super.key, required this.agent});
  final AgentController agent;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('产物云同步'),
              selected: agent.cloudSync,
              onSelected: agent.connected && !agent.savingArtifacts
                  ? (enabled) async {
                      try {
                        await agent.configureCloudSync(enabled);
                      } catch (e) {
                        agent.artifactError = '$e';
                        agent.changed();
                      }
                    }
                  : null,
            ),
            if (agent.savingArtifacts)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('正在保存文件…'),
              ),
            if (agent.artifactError != null)
              TextButton(
                onPressed: agent.saveArtifacts,
                child: Text(agent.artifactError!),
              ),
            PopupMenuButton<String>(
              key: const Key('agent-approval-mode'),
              enabled: agent.connected &&
                  !agent.connecting &&
                  !agent.running &&
                  agent.interactions.isEmpty &&
                  agent.prompts.isEmpty,
              tooltip: '选择审批模式',
              initialValue: agent.permissions.mode,
              onSelected: (mode) async {
                if (mode == agent.permissions.mode) return;
                if (mode == 'full') {
                  final allowed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('开启完全放行？'),
                      content:
                          const Text('本对话中所有已启用的笔记操作将直接执行，包括删除笔记、内容块和数据库数据。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('完全放行'),
                        ),
                      ],
                    ),
                  );
                  if (allowed != true) return;
                }
                try {
                  await agent.configurePermissions(mode: mode);
                } catch (e) {
                  agent.error = agentDisplayText('$e');
                  agent.changed();
                }
              },
              itemBuilder: (_) => AgentPermissions.modes
                  .map(
                    (mode) => CheckedPopupMenuItem(
                      value: mode,
                      checked: mode == agent.permissions.mode,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AgentPermissions.labels[mode]!),
                            const SizedBox(height: 4),
                            Text(
                              AgentPermissions.descriptions[mode]!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '审批模式：${AgentPermissions.labels[agent.permissions.mode]}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
            if (agent.credits != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  agent.credits!.label,
                  key: const Key('agent-credits'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (agent.creditsError != null)
              TextButton(
                onPressed: agent.refreshCredits,
                child: Text(
                  agent.creditsError!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      );
}

List<Widget> contextDetails(AgentController agent) => [
      Text('模型：${agent.model}'),
      if (agent.credits != null) Text('剩余额度：${agent.credits!.label}'),
      if (agent.sessionTokens != null) Text('本轮用量：${agent.sessionTokens}'),
    ];
