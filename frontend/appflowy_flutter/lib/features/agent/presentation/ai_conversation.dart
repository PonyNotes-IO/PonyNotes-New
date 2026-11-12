import 'package:flutter/material.dart';
import '../application/agent_controller.dart';
import 'agent_workspace.dart';

/// One Agent Ask AI document opens its Cloud-owned WeKnora conversation.
class AiConversation extends StatefulWidget {
  const AiConversation({
    super.key,
    required this.documentId,
    this.documentName = '',
    this.initialMessage = '',
    this.initialImagePaths = const [],
    this.onInitialAccepted,
    this.mode = 'smart-reasoning',
    this.cloudArtifacts = const {},
  });
  final String documentId;
  final String documentName;
  final String initialMessage;
  final List<String> initialImagePaths;
  final Future<void> Function()? onInitialAccepted;
  final String mode;
  final Map<String, dynamic> cloudArtifacts;
  @override
  State<AiConversation> createState() => _AiConversationState();
}

class _AiConversationState extends State<AiConversation> {
  late final controller = AgentController(
    chatId: widget.documentId,
    documentName: widget.documentName,
    mode: widget.mode,
    cloudArtifacts: widget.cloudArtifacts,
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
