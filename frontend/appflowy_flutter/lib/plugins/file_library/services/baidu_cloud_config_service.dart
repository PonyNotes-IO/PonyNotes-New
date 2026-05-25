import 'dart:io';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';

/// 百度网盘配置模型
class BaiduCloudConfig {
  final String appKey;
  final String secretKey;
  final String redirectUri;
  final String apiBase;
  final String uploadApi;
  final int downloadTimeout;
  final int maxFileSize;
  final int cacheExpireHours;
  final int maxCacheSize;
  final bool debugMode;

  const BaiduCloudConfig({
    required this.appKey,
    required this.secretKey,
    required this.redirectUri,
    required this.apiBase,
    required this.uploadApi,
    this.downloadTimeout = 300,
    this.maxFileSize = 1073741824, // 1GB
    this.cacheExpireHours = 24,
    this.maxCacheSize = 100,
    this.debugMode = false,
  });

  bool get isValid => 
      appKey.isNotEmpty && 
      appKey != 'your_baidu_app_key_here' &&
      secretKey.isNotEmpty && 
      secretKey != 'your_baidu_secret_key_here';

  BaiduCloudConfig copyWith({
    String? appKey,
    String? secretKey,
    String? redirectUri,
    String? apiBase,
    String? uploadApi,
    int? downloadTimeout,
    int? maxFileSize,
    int? cacheExpireHours,
    int? maxCacheSize,
    bool? debugMode,
  }) {
    return BaiduCloudConfig(
      appKey: appKey ?? this.appKey,
      secretKey: secretKey ?? this.secretKey,
      redirectUri: redirectUri ?? this.redirectUri,
      apiBase: apiBase ?? this.apiBase,
      uploadApi: uploadApi ?? this.uploadApi,
      downloadTimeout: downloadTimeout ?? this.downloadTimeout,
      maxFileSize: maxFileSize ?? this.maxFileSize,
      cacheExpireHours: cacheExpireHours ?? this.cacheExpireHours,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      debugMode: debugMode ?? this.debugMode,
    );
  }
}

/// 百度网盘配置管理服务
class BaiduCloudConfigService {
  static BaiduCloudConfigService? _instance;
  static BaiduCloudConfigService get instance => _instance ??= BaiduCloudConfigService._();
  BaiduCloudConfigService._();

  Map<String, String> _envVars = {};
  bool _isLoaded = false;

  /// 加载百度网盘配置
  /// 为了安全，前端不再从本地文件加载包含 client_secret 的配置 (.env.baidu)。
  /// 所有敏感配置应放在服务器环境变量（BAIDU_CLOUD_*），并通过后端代理完成 OAuth 流程。
  Future<void> loadConfig({bool force = false}) async {
    if (_isLoaded && !force) return;
    _envVars.clear();
    _isLoaded = true;
    Log.info('✅ 前端百度网盘本地配置已禁用；请在后端设置 BAIDU_CLOUD_APP_KEY / BAIDU_CLOUD_SECRET_KEY 等环境变量。');
  }

  /// 解析环境变量内容
  void _parseEnvContent(String content) {
    Log.info('📝 开始解析配置内容，长度: ${content.length}');
    final lines = content.split('\n');
    int parsedCount = 0;
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      
      final parts = trimmed.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        _envVars[key] = value;
        parsedCount++;
        
        // 只记录关键配置
        if (key.contains('APP_KEY') || key.contains('SECRET_KEY')) {
          Log.info('🔑 解析配置: $key = ${value.isNotEmpty ? "${value.substring(0, 8)}..." : "空"}');
        }
      }
    }
    
    Log.info('✅ 解析完成，共解析 $parsedCount 个配置项');
    Log.info('📋 主要配置:');
    Log.info('   - APP_KEY: ${_envVars["BAIDU_CLOUD_APP_KEY"]?.substring(0, 8) ?? "未找到"}...');
    Log.info('   - SECRET_KEY: ${_envVars["BAIDU_CLOUD_SECRET_KEY"]?.substring(0, 8) ?? "未找到"}...');
  }

  /// 获取百度网盘配置
  BaiduCloudConfig getConfig() {
    return BaiduCloudConfig(
      appKey: _envVars['BAIDU_CLOUD_APP_KEY'] ?? '',
      secretKey: _envVars['BAIDU_CLOUD_SECRET_KEY'] ?? '',
      redirectUri: _envVars['BAIDU_CLOUD_REDIRECT_URI'] ?? 'http://localhost:8080/auth/callback',
      apiBase: _envVars['BAIDU_CLOUD_API_BASE'] ?? 'https://pan.baidu.com/rest/2.0',
      uploadApi: _envVars['BAIDU_CLOUD_UPLOAD_API'] ?? 'https://d.pcs.baidu.com/rest/2.0/pcs/file',
      downloadTimeout: int.tryParse(_envVars['BAIDU_CLOUD_DOWNLOAD_TIMEOUT'] ?? '300') ?? 300,
      maxFileSize: int.tryParse(_envVars['BAIDU_CLOUD_MAX_FILE_SIZE'] ?? '1073741824') ?? 1073741824,
      cacheExpireHours: int.tryParse(_envVars['BAIDU_CLOUD_CACHE_EXPIRE_HOURS'] ?? '24') ?? 24,
      maxCacheSize: int.tryParse(_envVars['BAIDU_CLOUD_MAX_CACHE_SIZE'] ?? '100') ?? 100,
      debugMode: _envVars['BAIDU_CLOUD_DEBUG_MODE']?.toLowerCase() == 'true',
    );
  }

  /// Whether to use backend proxy for Baidu Cloud operations.
  /// When true, frontend will call backend endpoints instead of using client_secret.
  bool get useBackendProxy {
    // Default to true to avoid storing client_secret in frontend.
    return (_envVars['BAIDU_CLOUD_USE_BACKEND']?.toLowerCase() ?? 'true') == 'true';
  }

  /// 检查是否有有效的配置
  bool get hasValidConfig {
    final config = getConfig();
    return config.isValid;
  }

  /// 获取配置状态信息
  Map<String, dynamic> getConfigStatus() {
    final config = getConfig();
    return {
      'isLoaded': _isLoaded,
      'hasValidConfig': hasValidConfig,
      'appKey': config.appKey.isNotEmpty ? '${config.appKey.substring(0, 8)}...' : '未设置',
      'apiBase': config.apiBase,
      'debugMode': config.debugMode,
    };
  }

  /// 重新加载配置
  Future<void> reloadConfig() async {
    _isLoaded = false;
    _envVars.clear();
    await loadConfig();
  }
}
