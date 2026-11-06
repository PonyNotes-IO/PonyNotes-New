import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:uuid/uuid.dart';

class AgentSettings {
  AgentSettings({
    this.remoteUrl = '',
    this.scope = '',
    this.remoteToken = '',
    this.directory = '',
    this.allowCommands = false,
    this.mcpServers = const {},
    this.skillDirectories = const [],
    this.disabledNoteTools = const [],
  });
  final String scope;
  final String remoteUrl;
  final String remoteToken;
  final String directory;
  final bool allowCommands;
  final Map<String, dynamic> mcpServers;
  final List<String> skillDirectories;
  final List<String> disabledNoteTools;
  static const _storage = FlutterSecureStorage();
  static const _key = 'ponynotes.agent.settings.v1';
  static Future<String?> loadMcpCredentials(String scope) =>
      _storage.read(key: 'ponynotes.agent.mcp.$scope');
  static Future<void> saveMcpCredentials(String scope, String value) =>
      _storage.write(key: 'ponynotes.agent.mcp.$scope', value: value);
  static Future<String> currentIdentity() async {
    final profile = await UserBackendService.getCurrentUserProfile();
    final userId = profile.fold(
      (user) => user.id.toString(),
      (_) => throw StateError('请先登录'),
    );
    final workspace = await AIChatViewService.getCurrentWorkspaceId();
    if (workspace == null) throw StateError('请先打开工作区');
    final backend = getIt.isRegistered<AppFlowyCloudSharedEnv>()
        ? getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url
        : 'local';
    return '$backend|$userId|$workspace';
  }

  static Future<AgentSettings> load({String? scope}) async {
    scope ??= const Uuid().v5(Namespace.url.value, await currentIdentity());
    final raw = await _storage.read(key: '$_key.$scope');
    if (raw == null) return AgentSettings(scope: scope);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AgentSettings(
      scope: scope,
      remoteUrl: json['remoteUrl'] as String? ?? '',
      remoteToken: json['remoteToken'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
      allowCommands: json['allowCommands'] == true,
      disabledNoteTools:
          (json['disabledNoteTools'] as List? ?? []).cast<String>(),
      skillDirectories:
          (json['skillDirectories'] as List? ?? []).cast<String>(),
      mcpServers: Map<String, dynamic>.from(json['mcpServers'] as Map? ?? {}),
    );
  }

  Future<void> save() => _storage.write(
        key: '$_key.$scope',
        value: jsonEncode({
          'remoteUrl': remoteUrl,
          'remoteToken': remoteToken,
          'directory': directory,
          'allowCommands': allowCommands,
          'mcpServers': mcpServers,
          'skillDirectories': skillDirectories,
          'disabledNoteTools': disabledNoteTools,
        }),
      );
}
