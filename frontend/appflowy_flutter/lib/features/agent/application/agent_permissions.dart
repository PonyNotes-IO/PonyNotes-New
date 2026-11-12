import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Reuse existing note-tool choices without loading retired executor settings.
class AgentPermissions {
  String mode = 'ask';
  final disabledTools = <String>{};
  static const modes = ['ask', 'auto', 'full'];
  static const labels = {'ask': '请求批准', 'auto': '自动审批', 'full': '完全放行'};
  static const descriptions = {
    'ask': '创建、修改和删除笔记前请求批准',
    'auto': '自动批准普通修改，删除等破坏性操作仍需确认',
    'full': '所有已启用的笔记操作直接执行，包括删除',
  };
  String _scope = '';
  String _document = '';

  Future<void> load(String identity, String document) async {
    _scope = const Uuid().v5(Namespace.url.value, identity);
    _document = document;
    final raw = await const FlutterSecureStorage()
        .read(key: 'ponynotes.agent.settings.v1.$_scope');
    disabledTools.clear();
    if (raw != null) {
      disabledTools.addAll(
        (jsonDecode(raw)['disabledNoteTools'] as List? ?? []).cast<String>(),
      );
    }
    final saved = (await SharedPreferences.getInstance())
        .getString('ponynotes.agent.workspace.$document');
    final value = saved == null ? null : jsonDecode(saved)['permissionMode'];
    mode = modes.contains(value) ? value as String : 'ask';
  }

  Future<void> save() async {
    if (!modes.contains(mode)) throw ArgumentError.value(mode);
    await const FlutterSecureStorage().write(
      key: 'ponynotes.agent.settings.v1.$_scope',
      value: jsonEncode({'disabledNoteTools': disabledTools.toList()}),
    );
    await (await SharedPreferences.getInstance()).setString(
      'ponynotes.agent.workspace.$_document',
      jsonEncode({'permissionMode': mode}),
    );
  }
}

String agentDisplayText(String text) =>
    text.replaceAll(RegExp('weknora', caseSensitive: false), '小马 Agent');
