import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/features/agent/application/agent_internal_service.dart';

enum KnowledgeModelType {
  chat('KnowledgeQA', '对话', 'chat'),
  embedding('Embedding', 'Embedding', 'embedding'),
  rerank('Rerank', 'ReRank', 'rerank'),
  vision('VLLM', '视觉', 'vllm'),
  speech('ASR', '语音', 'asr');

  const KnowledgeModelType(this.apiValue, this.label, this.providerKey);
  final String apiValue;
  final String label;
  final String providerKey;
  static KnowledgeModelType fromApi(String type) =>
      values.firstWhere((t) => t.apiValue == type);
}

class KnowledgeModel {
  KnowledgeModel(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  String get label => (data['display_name'] as String?)?.isNotEmpty == true
      ? data['display_name'] as String
      : name;
  KnowledgeModelType get type =>
      KnowledgeModelType.fromApi(data['type'] as String);
  Map<String, dynamic> get parameters =>
      Map<String, dynamic>.from(data['parameters'] as Map? ?? {});
  bool get builtin => data['is_builtin'] == true;
  bool get canEdit => data['can_edit'] as bool? ?? !builtin;
  String get provider => parameters['provider'] as String? ?? 'generic';
}

class KnowledgeModelProvider {
  KnowledgeModelProvider(this.data);
  final Map<String, dynamic> data;
  String get id => data['value'] as String;
  String get label => data['label'] as String? ?? id;
  String get icon => data['icon'] as String? ?? '';
  String url(KnowledgeModelType type) =>
      (data['defaultUrls'] as Map?)?[type.providerKey] as String? ?? '';
  List<Map<String, dynamic>> models(KnowledgeModelType type) => [
        for (final item in data['models'] as List? ?? [])
          if (item['type'] == type.providerKey || item['type'] == type.apiValue)
            Map<String, dynamic>.from(item as Map),
      ];
  List<Map<String, dynamic>> get fields => [
        for (final field in data['extraFields'] as List? ?? [])
          Map<String, dynamic>.from(field as Map),
      ];
}

/// Cloud authenticates the account and resolves the single WeKnora tenant; clients only send workspace/KB IDs.
class KnowledgeModelService {
  KnowledgeModelService(
    this.knowledge,
    this.workspaceId, {
    AgentInternalService? customService,
  }) : customService = customService ?? AgentInternalService();
  final KnowledgeBaseService knowledge;
  final String workspaceId;
  final AgentInternalService customService;
  bool canManage = false;
  bool canManageChat = false;
  List<KnowledgeModelProvider> catalog = [];

  static Future<KnowledgeModelService> current({String? workspaceId}) async {
    final profile = (await UserBackendService.getCurrentUserProfile()).fold(
      (value) => value,
      (_) => throw const KnowledgeBaseException(401),
    );
    workspaceId ??= (await UserBackendService.getCurrentWorkspace()).fold(
      (value) => value.id,
      (_) => throw const KnowledgeBaseException(503),
    );
    return KnowledgeModelService(
      KnowledgeBaseService.forUser(profile.id.toString()),
      workspaceId!,
    );
  }

  Future<List<KnowledgeModel>> list() async {
    final data = await knowledge.post('models', {'workspace_id': workspaceId});
    final custom = await customService.customCatalog(workspaceId);
    canManageChat = custom['can_manage'] == true;
    canManage = data['can_manage'] == true;
    catalog = [
      for (final p in data['providers'] as List? ?? [])
        KnowledgeModelProvider(Map<String, dynamic>.from(p as Map)),
    ];
    return [
      for (final item in data['models'] as List)
        KnowledgeModel(Map<String, dynamic>.from(item as Map)),
      for (final item in custom['models'] as List)
        KnowledgeModel(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<List<KnowledgeModelProvider>> providers(
    KnowledgeModelType type,
  ) async {
    final data = await knowledge.post(
      'model_providers',
      {'workspace_id': workspaceId, 'type': type.apiValue},
    );
    return [
      for (final item in data['providers'] as List)
        KnowledgeModelProvider(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<void> save(Map<String, dynamic> model, {String? id}) async {
    if (id?.startsWith('custom:') == true ||
        (id == null && model['type'] == KnowledgeModelType.chat.apiValue)) {
      await customService.saveCustomModel(workspaceId, model, id: id);
      return;
    }
    await knowledge.post('model_save', {
      'workspace_id': workspaceId,
      if (id != null) 'id': id,
      'model': model,
    });
  }

  Future<List<KnowledgeBase>> bases() async => (await knowledge.bases())
      .where((b) => b.workspaceId == workspaceId && b.canManage && b.ready)
      .toList();
  Future<void> delete(String id) async {
    if (id.startsWith('custom:')) {
      await customService.deleteCustomModel(workspaceId, id);
      return;
    }
    await knowledge
        .post('model_delete', {'workspace_id': workspaceId, 'id': id});
  }

  Future<({Map<String, dynamic> values, bool embeddingLocked})> settings(
    String baseId,
  ) async {
    final result = await knowledge.post(
      'model_settings',
      {'workspace_id': workspaceId, 'base_id': baseId},
    );
    return (
      values: Map<String, dynamic>.from(result['settings'] as Map),
      embeddingLocked: result['embedding_locked'] == true
    );
  }

  Future<void> bind(String baseId, Map<String, dynamic> settings) async {
    await knowledge.post(
      'model_bind',
      {'workspace_id': workspaceId, 'base_id': baseId, 'settings': settings},
    );
  }

  void close() => knowledge.close();
}
