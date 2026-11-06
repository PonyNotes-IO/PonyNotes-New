import 'package:flutter/material.dart';
import '../application/agent_controller.dart';
import 'agent_workspace.dart';

class AiModeShell extends StatefulWidget {
  const AiModeShell({
    super.key,
    required this.chatId,
    required this.chat,
    this.chatBusy = false,
    this.chatContext,
  });
  final String chatId;
  final Widget chat;
  final bool chatBusy;
  final String Function()? chatContext;
  @override
  State<AiModeShell> createState() => _AiModeShellState();
}

class _AiModeShellState extends State<AiModeShell> {
  late final agent = AgentController(chatId: widget.chatId);
  bool agentMode = false;
  @override
  void dispose() {
    agent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: agent,
        builder: (context, _) => AiModeScope(
          agentMode: agentMode,
          busy: widget.chatBusy ||
              agent.running ||
              agent.connecting ||
              agent.compacting,
          select: (value) => setState(() => agentMode = value),
          child: IndexedStack(
            index: agentMode ? 1 : 0,
            children: [
              widget.chat,
              AgentWorkspace(
                controller: agent,
                chatContext: widget.chatContext,
                modeControl:
                    Builder(builder: (context) => const AiModeButton()),
              ),
            ],
          ),
        ),
      );
}

class AiModeScope extends InheritedWidget {
  const AiModeScope({
    super.key,
    required this.agentMode,
    required this.busy,
    required this.select,
    required super.child,
  });
  final bool agentMode;
  final bool busy;
  final ValueChanged<bool> select;
  static AiModeScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AiModeScope>();
  @override
  bool updateShouldNotify(AiModeScope oldWidget) =>
      oldWidget.agentMode != agentMode || oldWidget.busy != busy;
}

class AiModeButton extends StatelessWidget {
  const AiModeButton({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = AiModeScope.of(context);
    if (scope == null) return const SizedBox.shrink();
    return PopupMenuButton<bool>(
      enabled: !scope.busy,
      tooltip: '切换对话模式',
      initialValue: scope.agentMode,
      onSelected: scope.select,
      itemBuilder: (_) => const [
        PopupMenuItem(value: false, child: Text('Chat · 问答')),
        PopupMenuItem(value: true, child: Text('Agent · 执行任务')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              scope.agentMode ? 'Agent' : 'Chat',
              style: const TextStyle(fontSize: 13),
            ),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}
