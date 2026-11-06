import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 内部 AI 使用的模型服务配置：地址、模型名、API Key。
///
/// 与 Ollama 的 `LocalAISetting` **分开存**。两者面向不同后端（Ollama 无鉴权、
/// 外部模型需要 Key），共用一份存储会互相覆盖：在「内部 AI 模型」里填地址，
/// 会把 Ollama 的 server_url / 聊天模型一起改掉。
class AiProviderConfig {
  const AiProviderConfig({
    this.baseUrl = '',
    this.modelName = '',
    this.apiKey = '',
    this.supportsReasoning = false,
  });

  /// OpenAI 兼容端点，例如 `https://api.deepseek.com`。
  final String baseUrl;

  /// 模型名，例如 `deepseek-chat`。
  final String modelName;

  /// 用户自己的 API Key，只用于小马访问模型服务，与 MCP Token 无关。
  final String apiKey;
  final bool supportsReasoning;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      modelName.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  AiProviderConfig copyWith({
    String? baseUrl,
    String? modelName,
    String? apiKey,
    bool? supportsReasoning,
  }) {
    return AiProviderConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      modelName: modelName ?? this.modelName,
      apiKey: apiKey ?? this.apiKey,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
    );
  }
}

/// 地址/模型保留原配置；凭据迁入系统安全存储，成功后移除旧明文键。
class AiProviderConfigStorage {
  const AiProviderConfigStorage();

  static const _baseUrlKey = 'ai_internal.base_url';
  static const _modelKey = 'ai_internal.model';
  static const _apiKeyKey = 'ai_internal.api_key';
  static const _profilesKey = 'ai_internal.profiles';
  static const _reasoningKey = 'ai_internal.supports_reasoning';
  static const _secure = FlutterSecureStorage();

  Future<AiProviderConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    var apiKey = await _secure.read(key: _apiKeyKey);
    final legacy = prefs.getString(_apiKeyKey);
    if (apiKey == null && legacy != null) {
      await _secure.write(key: _apiKeyKey, value: legacy);
      apiKey = legacy;
    }
    if (legacy != null) await prefs.remove(_apiKeyKey);
    return AiProviderConfig(
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      modelName: prefs.getString(_modelKey) ?? '',
      apiKey: apiKey ?? '',
      supportsReasoning: prefs.getBool(_reasoningKey) ?? false,
    );
  }

  Future<void> save(AiProviderConfig config) async {
    final profiles = await loadProfiles();
    profiles.removeWhere(
      (p) =>
          p.baseUrl == config.baseUrl.trim() &&
          p.modelName == config.modelName.trim(),
    );
    if (config.isComplete) profiles.add(config);
    await _secure.write(
      key: _profilesKey,
      value: jsonEncode(
        profiles
            .map(
              (p) => {
                'baseUrl': p.baseUrl.trim(),
                'modelName': p.modelName.trim(),
                'apiKey': p.apiKey.trim(),
                'supportsReasoning': p.supportsReasoning,
              },
            )
            .toList(),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: _apiKeyKey, value: config.apiKey.trim());
    await prefs.remove(_apiKeyKey);
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
    await prefs.setString(_modelKey, config.modelName.trim());
    await prefs.setBool(_reasoningKey, config.supportsReasoning);
  }

  Future<List<AiProviderConfig>> loadProfiles() async {
    final raw = await _secure.read(key: _profilesKey);
    final profiles = raw == null
        ? <AiProviderConfig>[]
        : (jsonDecode(raw) as List)
            .map(
              (p) => AiProviderConfig(
                baseUrl: p['baseUrl'] as String,
                modelName: p['modelName'] as String,
                apiKey: p['apiKey'] as String,
                supportsReasoning: p['supportsReasoning'] == true,
              ),
            )
            .toList();
    final active = await load();
    if (active.isComplete &&
        !profiles.any(
          (p) => p.baseUrl == active.baseUrl && p.modelName == active.modelName,
        )) {
      profiles.add(active);
    }
    return profiles;
  }

  /// 只用于测试与「清空配置」。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: _apiKeyKey);
    await _secure.delete(key: _profilesKey);
    await prefs.remove(_reasoningKey);
    await prefs.remove(_baseUrlKey);
    await prefs.remove(_modelKey);
    await prefs.remove(_apiKeyKey);
  }
}
