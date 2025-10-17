import 'dart:io';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
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
  Future<void> loadConfig({bool force = false}) async {
    if (_isLoaded && !force) return;

    try {
      String? content;
      
      // 首先尝试从Flutter资源系统读取
      try {
        content = await rootBundle.loadString('.env.baidu');
        Log.info('✅ 从Flutter资源系统加载百度网盘配置成功');
      } catch (e) {
        Log.info('⚠️ 无法从Flutter资源系统加载.env.baidu: $e');
        
        // 如果从资源系统读取失败，尝试从文件系统读取（开发环境）
        final possiblePaths = [
          '.env.baidu',
          'appflowy_flutter/.env.baidu',
          'frontend/appflowy_flutter/.env.baidu',
          '../.env.baidu',
          '../../.env.baidu',
        ];
        
        File? configFile;
        for (final path in possiblePaths) {
          final file = File(path);
          Log.info('🔍 尝试加载配置文件: ${file.absolute.path}');
          if (await file.exists()) {
            configFile = file;
            Log.info('✅ 找到配置文件: ${file.absolute.path}');
            break;
          }
        }
        
        if (configFile != null) {
          content = await configFile.readAsString();
          Log.info('✅ 从文件系统加载百度网盘配置成功: ${configFile.absolute.path}');
        }
      }
      
      if (content != null) {
        _parseEnvContent(content);
        _isLoaded = true;
        Log.info('✅ 百度网盘配置解析成功');
      } else {
        Log.info('⚠️ 百度网盘配置文件未找到');
        Log.info('📝 请确保.env.baidu文件存在并包含在Flutter资源中');
      }
    } catch (e) {
      Log.info('❌ 加载百度网盘配置失败: $e');
    }
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
