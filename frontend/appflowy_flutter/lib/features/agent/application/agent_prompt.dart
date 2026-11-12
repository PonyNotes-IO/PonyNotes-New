class AgentPrompt {
  factory AgentPrompt.fromJson(Map value, String messageId) => AgentPrompt(
        id: '${value['pending_id'] ?? value['id']}',
        kind: '${value['kind'] ?? 'tool_approval'}',
        messageId: messageId,
        request: Map<String, dynamic>.from(
          value['request'] is Map ? value['request'] as Map : value,
        ),
        status: '${value['status'] ?? 'pending'}',
        response: Map<String, dynamic>.from(
          value['response'] is Map ? value['response'] as Map : const {},
        ),
        expiresAt: DateTime.tryParse('${value['expires_at'] ?? ''}'),
      );
  AgentPrompt({
    required this.id,
    required this.kind,
    required this.messageId,
    required this.request,
    this.status = 'pending',
    this.response = const {},
    this.expiresAt,
  });

  final String id;
  final String kind;
  final String messageId;
  final Map<String, dynamic> request;
  final DateTime? expiresAt;
  String status;
  Map<String, dynamic> response;
  bool submitting = false;
  String? error;
  bool get open => status == 'pending' || status == 'suspended';
  bool get expired => expiresAt?.isBefore(DateTime.now()) ?? false;
}
