import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'agent_service.dart';
import 'package:file_picker/file_picker.dart';

class AgentConversation {
  const AgentConversation({required this.id, required this.title});
  factory AgentConversation.fromJson(Map value) => AgentConversation(
        id: value['id'] as String,
        title: value['title'] as String,
      );
  final String id;
  final String title;
}

class AgentConversations extends ChangeNotifier {
  AgentConversations({
    AgentService? service,
    Future<String?> Function()? workspace,
  })  : service = service ?? AgentService(),
        workspace = workspace ?? AIChatViewService.getCurrentWorkspaceId;
  static final requestedConversation = ValueNotifier<String?>(null);
  static final openRequests = ValueNotifier(0);
  static void requestOpen([String? id]) {
    requestedConversation.value = id;
    openRequests.value++;
  }

  static final requestedPrompt =
      ValueNotifier<(String, List<PlatformFile>)?>(null);
  final AgentService service;
  final Future<String?> Function() workspace;
  final entries = <AgentConversation>[];
  String? workspaceId;
  String? identity;
  bool loading = false;
  bool creating = false;
  String? error;
  bool _disposed = false;
  int _epoch = 0;
  String? _pendingCreate;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (creating) return;
    final epoch = ++_epoch;
    loading = true;
    error = null;
    changed();
    try {
      final wid = await workspace();
      if (wid == null) throw StateError('请先打开工作区');
      final account = await service.identity(wid);
      final rows = <AgentConversation>[];
      var offset = 0;
      while (true) {
        final data = await service.request('GET', wid, '', '?offset=$offset');
        final batch = data['conversations'] as List;
        rows.addAll(batch.map((e) => AgentConversation.fromJson(e as Map)));
        if (batch.length < 100) break;
        offset += batch.length;
      }
      if (_disposed || epoch != _epoch) return;
      if (await workspace() != wid || await service.identity(wid) != account) {
        throw StateError('账号或工作区已切换');
      }
      if (_disposed || epoch != _epoch) return;
      workspaceId = wid;
      identity = account;
      entries
        ..clear()
        ..addAll(rows);
    } catch (e) {
      if (epoch == _epoch) error = '$e';
    } finally {
      if (epoch == _epoch) {
        loading = false;
        changed();
      }
    }
  }

  Future<AgentConversation?> create(String query) async {
    if (creating || loading) return null;
    final wid = workspaceId;
    final account = identity;
    if (wid == null || account == null) {
      error = '请先加载会话列表';
      changed();
      return null;
    }
    creating = true;
    error = null;
    changed();
    final epoch = _epoch;
    try {
      if (await workspace() != wid || await service.identity(wid) != account) {
        throw StateError('账号或工作区已切换');
      }
      final title = query.trim().replaceAll(RegExp(r'\s+'), ' ');
      final row = await service.request('POST', wid, '', '', {
        'id': _pendingCreate ??= const Uuid().v4(),
        'title':
            title.isEmpty ? '新对话' : String.fromCharCodes(title.runes.take(40)),
      });
      if (_disposed ||
          epoch != _epoch ||
          await workspace() != wid ||
          await service.identity(wid) != account) {
        return null;
      }
      if (_disposed || epoch != _epoch) return null;
      final conversation = AgentConversation.fromJson(row);
      _pendingCreate = null;
      entries.insert(0, conversation);
      return conversation;
    } catch (e) {
      if (epoch == _epoch) error = '$e';
      return null;
    } finally {
      if (epoch == _epoch) {
        creating = false;
        changed();
      }
    }
  }

  void clear() {
    ++_epoch;
    entries.clear();
    workspaceId = null;
    identity = null;
    error = null;
    loading = false;
    creating = false;
    requestedConversation.value = null;
    requestedPrompt.value = null;
    _pendingCreate = null;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
