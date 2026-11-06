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
  });

  /// OpenAI 兼容端点，例如 `https://api.deepseek.com`。
  final String baseUrl;

  /// 模型名，例如 `deepseek-chat`。
  final String modelName;

  /// 用户自己的 API Key，只用于小马访问模型服务，与 MCP Token 无关。
  final String apiKey;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      modelName.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  AiProviderConfig copyWith({
    String? baseUrl,
    String? modelName,
    String? apiKey,
  }) {
    return AiProviderConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      modelName: modelName ?? this.modelName,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

/// 地址/模型保留原配置；凭据迁入系统安全存储，成功后移除旧明文键。
class AiProviderConfigStorage {
  const AiProviderConfigStorage();

  static const _baseUrlKey = 'ai_internal.base_url';
  static const _modelKey = 'ai_internal.model';
  static const _apiKeyKey = 'ai_internal.api_key';
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
    );
  }

  Future<void> save(AiProviderConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: _apiKeyKey, value: config.apiKey.trim());
    await prefs.remove(_apiKeyKey);
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
    await prefs.setString(_modelKey, config.modelName.trim());
  }

  /// 只用于测试与「清空配置」。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _secure.delete(key: _apiKeyKey);
    await prefs.remove(_baseUrlKey);
    await prefs.remove(_modelKey);
    await prefs.remove(_apiKeyKey);
  }
}
