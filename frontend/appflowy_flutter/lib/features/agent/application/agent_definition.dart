/// A WeKnora agent identity. Shared IDs are qualified by their source tenant.
class AgentDefinition {
  const AgentDefinition({
    required this.id,
    required this.name,
    required this.mode,
    this.description = '',
    this.group = 'builtin',
    this.sourceTenantId,
    this.knowledgeScope = 'all',
    this.multiTurn = true,
    this.webSearch = false,
    this.imageUpload = false,
  });

  factory AgentDefinition.fromJson(Map value) => AgentDefinition(
        id: value['id'] as String,
        name: value['name'] as String,
        mode: value['mode'] as String,
        description: value['description'] as String? ?? '',
        group: value['group'] as String? ?? 'private',
        sourceTenantId: (value['source_tenant_id'] as num?)?.toInt(),
        knowledgeScope: value['knowledge_scope'] as String? ?? 'none',
        multiTurn: value['multi_turn'] == true,
        webSearch: value['web_search'] == true,
        imageUpload: value['image_upload'] == true,
      );

  final String id;
  final String name;
  final String mode;
  final String description;
  final String group;
  final int? sourceTenantId;
  final String knowledgeScope;
  final bool multiTurn;
  final bool webSearch;
  final bool imageUpload;
  bool get smart => mode == 'smart-reasoning';
  String get key => '${sourceTenantId ?? 0}:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode,
        'description': description,
        'group': group,
        if (sourceTenantId != null) 'source_tenant_id': sourceTenantId,
        'knowledge_scope': knowledgeScope,
        'multi_turn': multiTurn,
        'web_search': webSearch,
        'image_upload': imageUpload,
      };

  static const quick = AgentDefinition(
    id: 'builtin-quick-answer',
    name: '快速问答',
    mode: 'quick-answer',
    description: '基于知识库检索，快速回答问题',
  );
  static const smartReasoning = AgentDefinition(
    id: 'builtin-smart-reasoning',
    name: '智能推理',
    mode: 'smart-reasoning',
    description: '多步思考，深入分析与执行任务',
  );
}
