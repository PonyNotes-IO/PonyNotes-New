import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// AI配置模型
class AIConfig {
  final String apiKey;
  final String apiBase;
  final String modelName;
  final int maxTokens;
  final double temperature;
  final bool streamEnabled;

  const AIConfig({
    required this.apiKey,
    required this.apiBase,
    required this.modelName,
    this.maxTokens = 4096,
    this.temperature = 0.7,
    this.streamEnabled = true,
  });

  bool get isValid => apiKey.isNotEmpty && apiKey != 'your_${_getProviderKey()}_api_key_here';
  
  /// 为了兼容性，添加 model getter
  String get model => modelName;

  String _getProviderKey() {
    if (apiBase.contains('deepseek')) return 'deepseek';
    if (apiBase.contains('dashscope')) return 'qwen';
    if (apiBase.contains('volces')) return 'doubao';
    return 'unknown';
  }

  AIConfig copyWith({
    String? apiKey,
    String? apiBase,
    String? modelName,
    int? maxTokens,
    double? temperature,
    bool? streamEnabled,
  }) {
    return AIConfig(
      apiKey: apiKey ?? this.apiKey,
      apiBase: apiBase ?? this.apiBase,
      modelName: modelName ?? this.modelName,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      streamEnabled: streamEnabled ?? this.streamEnabled,
    );
  }
}

/// AI配置管理服务
class AIConfigService {
  static AIConfigService? _instance;
  static AIConfigService get instance => _instance ??= AIConfigService._();
  AIConfigService._();

  Map<String, String> _envVars = {};
  bool _isLoaded = false;

  /// 加载AI配置（已弃用，保留用于兼容性）
  Future<void> loadConfig() async {
    if (_isLoaded) return;

    try {
      String? content;
      
      // 首先尝试从Flutter资源系统读取
      try {
        content = await rootBundle.loadString('.env.ai');
        debugPrint('✅ 从Flutter资源系统加载AI配置成功');
      } catch (e) {
        debugPrint('⚠️ 无法从Flutter资源系统加载.env.ai: $e');
        
        // 如果从资源系统读取失败，尝试从文件系统读取（开发环境）
        final possiblePaths = [
          '.env.ai',
          'frontend/appflowy_flutter/.env.ai',
          '../.env.ai',
        ];
        
        File? configFile;
        for (final path in possiblePaths) {
          final file = File(path);
          if (await file.exists()) {
            configFile = file;
            break;
          }
        }
        
        if (configFile != null) {
          content = await configFile.readAsString();
          debugPrint('✅ 从文件系统加载AI配置成功: ${configFile.path}');
        }
      }
      
      if (content != null) {
        _parseEnvContent(content);
        _isLoaded = true;
        
        debugPrint('✅ AI配置解析成功（已弃用此配置系统，使用公开API）');
      } else {
        debugPrint('⚠️ AI配置文件未找到（已弃用此配置系统，使用公开API）');
      }
    } catch (e) {
      debugPrint('❌ 加载AI配置失败: $e');
    }
  }

  /// 解析环境变量内容
  void _parseEnvContent(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      
      final parts = trimmed.split('=');
      if (parts.length == 2) {
        final key = parts[0].trim();
        final value = parts[1].trim();
        _envVars[key] = value;
      }
    }
  }

  /// 检查是否有可用的AI配置（已弃用）
  @deprecated
  bool get hasValidConfig {
    return _isLoaded;
  }

  /// 重新加载配置
  Future<void> reloadConfig() async {
    _isLoaded = false;
    _envVars.clear();
    await loadConfig();
  }
}


