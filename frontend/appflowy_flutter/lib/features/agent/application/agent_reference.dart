class AgentReference {
  const AgentReference({
    required this.kind,
    required this.id,
    required this.name,
    this.subtitle = '',
    this.available = true,
    this.visibility,
    this.spaceName = '',
  });

  factory AgentReference.fromJson(Map value) {
    final name = value['name'] as String? ?? '';
    return AgentReference(
      kind: value['kind'] as String,
      id: value['id'] as String,
      name: name.trim().isEmpty ? '未命名' : name,
      subtitle: value['subtitle'] as String? ?? '',
      visibility: value['visibility'] as String?,
      spaceName: value['space_name'] as String? ?? '',
      available: value['kind'] == 'note' ||
          (value['knowledge_ids'] as List? ?? []).isNotEmpty,
    );
  }

  final String kind;
  final String id;
  final String name;
  final String subtitle;
  final bool available;

  /// Optional catalog metadata. Missing visibility must not imply private access.
  final String? visibility;
  final String spaceName;

  String get noteSection => switch (visibility) {
        'private' => '私有笔记',
        'shared' || 'public' => '协作笔记',
        _ => '笔记',
      };

  String get noteSpace {
    if (spaceName.trim().isNotEmpty) return spaceName;
    final path = subtitle.split('/').map((part) => part.trim());
    return path.firstWhere((part) => part.isNotEmpty, orElse: () => '当前工作空间');
  }

  String get key => '$kind:$id';
  Map<String, String> toJson() => {'kind': kind, 'id': id};
}
