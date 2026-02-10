import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI模型信息
class AIModel {
  final String id;
  final String name;
  final String description;
  final bool isDefault;

  /// 是否支持图片/文件等多模态输入
  final bool supportsImages;

  AIModel({
    required this.id,
    required this.name,
    required this.description,
    required this.isDefault,
    this.supportsImages = false, // 默认不支持图片
  });

  factory AIModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    // 【强制修复】通义千问(qwen)和豆包(doubao)确认为多模态模型
    // 即使后端返回false，前端也强制视为支持图片
    final isKnownMultimodal = id.toLowerCase().contains('qwen') ||
        id.toLowerCase().contains('doubao');

    return AIModel(
      id: id,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
      supportsImages:
          isKnownMultimodal || (json['supports_images'] as bool? ?? false),
    );
  }

  @override
  String toString() =>
      'AIModel(id: $id, name: $name, isDefault: $isDefault, supportsImages: $supportsImages)';
}

/// AI模型服务
class AIModelService {
  static final AIModelService _instance = AIModelService._();
  static AIModelService get instance => _instance;

  AIModelService._();

  List<AIModel> _cachedModels = [];
  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 30);

  /// 获取可用的AI模型列表
  Future<List<AIModel>> fetchAvailableModels(
      {bool forceRefresh = false}) async {
    // 如果有缓存且未过期，直接返回缓存
    if (!forceRefresh &&
        _cachedModels.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      debugPrint('✅ 使用缓存的AI模型列表，共 ${_cachedModels.length} 个模型');
      return _cachedModels;
    }

    try {
      // 从环境变量或配置获取API地址
      const apiBaseUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api.xiaomabiji.com',
      );

      debugPrint('🔍 正在从 $apiBaseUrl 获取AI模型列表...');

      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/ai/chat/models'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final modelsData = jsonData['data']['models'] as List<dynamic>;

        _cachedModels = modelsData
            .map((model) => AIModel.fromJson(model as Map<String, dynamic>))
            .toList();
        _lastFetchTime = DateTime.now();

        debugPrint('✅ 成功获取 ${_cachedModels.length} 个AI模型');
        for (final model in _cachedModels) {
          debugPrint(
              '   - ${model.name} (${model.id})${model.isDefault ? ' [默认]' : ''}');
        }

        return _cachedModels;
      } else {
        throw Exception('获取模型列表失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ 获取AI模型列表失败: $e');

      // 如果有旧缓存，返回旧缓存
      if (_cachedModels.isNotEmpty) {
        debugPrint('⚠️  使用缓存的模型列表');
        return _cachedModels;
      }

      // 返回默认硬编码列表作为fallback
      debugPrint('⚠️  使用默认硬编码模型列表');
      return _getDefaultModels();
    }
  }

  /// 获取默认模型列表（作为fallback）
  List<AIModel> _getDefaultModels() {
    return [
      AIModel(
        id: 'deepseek-chat',
        name: 'DeepSeek',
        description: '高性能对话模型',
        isDefault: true,
        supportsImages: false, // DeepSeek不支持图片
      ),
      AIModel(
        id: 'qwen3-vl-plus',
        name: '通义千问',
        description: '阿里云通义千问qwen3',
        isDefault: false,
        supportsImages: true, // 通义千问支持图片
      ),
      AIModel(
        id: 'doubao',
        name: '豆包',
        description: '字节跳动豆包',
        isDefault: false,
        supportsImages: true, // 豆包支持图片
      ),
    ];
  }

  /// 清除缓存
  void clearCache() {
    _cachedModels = [];
    _lastFetchTime = null;
    debugPrint('🗑️  清除AI模型缓存');
  }

  /// 获取支持图片/文件的模型列表
  /// 当需要上传图片或文件时使用
  Future<List<AIModel>> fetchModelsForImage({bool forceRefresh = false}) async {
    final allModels = await fetchAvailableModels(forceRefresh: forceRefresh);
    return allModels.where((model) => model.supportsImages).toList();
  }

  /// 判断模型ID是否支持图片
  bool isModelSupportsImages(String modelId) {
    // 检查缓存的模型
    for (final model in _cachedModels) {
      if (model.id == modelId) {
        return model.supportsImages;
      }
    }
    // 如果缓存中没有，检查默认模型
    for (final model in _getDefaultModels()) {
      if (model.id == modelId) {
        return model.supportsImages;
      }
    }
    return false;
  }
}
