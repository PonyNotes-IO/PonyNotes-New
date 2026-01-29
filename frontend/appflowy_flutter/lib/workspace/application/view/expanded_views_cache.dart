import 'dart:convert';
import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';

/// 缓存 expandedViews 数据，减少 KV 存储的频繁读写操作
/// 这是一个性能优化类，用于加速笔记切换时的视图展开操作
class ExpandedViewsCache {
  ExpandedViewsCache._();
  
  static final ExpandedViewsCache _instance = ExpandedViewsCache._();
  static ExpandedViewsCache get instance => _instance;
  
  /// 内存缓存
  Map<String, bool>? _cache;
  
  /// 是否已初始化
  bool _isInitialized = false;
  
  /// 是否正在保存（用于节流）
  bool _isSaving = false;
  
  /// 待保存的数据（用于批量保存）
  bool _hasPendingChanges = false;
  
  /// 初始化缓存，从 KV 存储加载数据
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final value = await getIt<KeyValueStorage>().get(KVKeys.expandedViews);
      if (value != null) {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          _cache = Map<String, bool>.from(
            decoded.map((key, value) => MapEntry(key.toString(), value == true)),
          );
        } else {
          _cache = {};
        }
      } else {
        _cache = {};
      }
      _isInitialized = true;
    } catch (e) {
      Log.error('ExpandedViewsCache: 初始化失败', e);
      _cache = {};
      _isInitialized = true;
    }
  }
  
  /// 获取当前缓存（同步方法，用于快速访问）
  Map<String, bool> get cache {
    if (!_isInitialized) {
      // 如果未初始化，返回空 Map，不阻塞
      return {};
    }
    return _cache ?? {};
  }
  
  /// 检查视图是否已展开
  bool isExpanded(String viewId) {
    return cache[viewId] == true;
  }
  
  /// 设置视图展开状态
  void setExpanded(String viewId, bool expanded) {
    if (_cache == null) {
      _cache = {};
    }
    
    if (expanded) {
      _cache![viewId] = true;
    } else {
      _cache!.remove(viewId);
    }
    
    _hasPendingChanges = true;
    _scheduleSave();
  }
  
  /// 批量设置视图展开状态
  void setExpandedBatch(List<String> viewIds, bool expanded) {
    if (_cache == null) {
      _cache = {};
    }
    
    for (final viewId in viewIds) {
      if (expanded) {
        _cache![viewId] = true;
      } else {
        _cache!.remove(viewId);
      }
    }
    
    _hasPendingChanges = true;
    _scheduleSave();
  }
  
  /// 安排保存操作（节流，避免频繁写入）
  void _scheduleSave() {
    if (_isSaving) return;
    
    _isSaving = true;
    
    // 延迟 100ms 保存，合并多次修改
    Future.delayed(const Duration(milliseconds: 100), () async {
      if (_hasPendingChanges && _cache != null) {
        try {
          await getIt<KeyValueStorage>().set(
            KVKeys.expandedViews,
            jsonEncode(_cache),
          );
          _hasPendingChanges = false;
        } catch (e) {
          Log.error('ExpandedViewsCache: 保存失败', e);
        }
      }
      _isSaving = false;
    });
  }
  
  /// 立即保存（用于应用退出时）
  Future<void> saveNow() async {
    if (_cache == null || !_hasPendingChanges) return;
    
    try {
      await getIt<KeyValueStorage>().set(
        KVKeys.expandedViews,
        jsonEncode(_cache),
      );
      _hasPendingChanges = false;
    } catch (e) {
      Log.error('ExpandedViewsCache: 立即保存失败', e);
    }
  }
  
  /// 重置缓存（用于切换工作区）
  void reset() {
    _cache = null;
    _isInitialized = false;
    _hasPendingChanges = false;
  }
  
  /// 从 KV 存储重新加载数据
  Future<void> reload() async {
    _isInitialized = false;
    await initialize();
  }
}
