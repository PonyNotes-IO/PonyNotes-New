class AgentReference {
  const AgentReference({
    required this.kind,
    required this.id,
    required this.name,
    this.subtitle = '',
    this.available = true,
  });

  factory AgentReference.fromJson(Map value) {
    final name = value['name'] as String? ?? '';
    return AgentReference(
      kind: value['kind'] as String,
      id: value['id'] as String,
      name: name.trim().isEmpty ? '未命名' : name,
      subtitle: value['subtitle'] as String? ?? '',
      available: value['kind'] == 'note' ||
          (value['knowledge_ids'] as List? ?? []).isNotEmpty,
    );
  }

  final String kind;
  final String id;
  final String name;
  final String subtitle;
  final bool available;
  String get key => '$kind:$id';
  Map<String, String> toJson() => {'kind': kind, 'id': id};
}
