import 'package:flutter/material.dart';
import '../application/agent_controller.dart';
import 'agent_workspace.dart';

/// One Agent Ask AI document owns one pi conversation.
class AiConversation extends StatefulWidget {
  const AiConversation({
    super.key,
    required this.documentId,
    this.initialMessage = '',
    this.initialImagePaths = const [],
    this.onInitialAccepted,
  });
  final String documentId;
  final String initialMessage;
  final List<String> initialImagePaths;
  final Future<void> Function()? onInitialAccepted;
  @override
  State<AiConversation> createState() => _AiConversationState();
}

class _AiConversationState extends State<AiConversation> {
  late final controller = AgentController(
    chatId: widget.documentId,
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AgentWorkspace(
        controller: controller,
        initialMessage: widget.initialMessage,
        initialImagePaths: widget.initialImagePaths,
        onInitialAccepted: widget.onInitialAccepted,
      );
}
