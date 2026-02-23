import 'dart:async';
import 'dart:convert';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// WhiteboardCollabAdapter
///
/// 完全模仿 TransactionAdapter 的实现
/// 立即同步白板数据变更到 Collab 后端（不使用定时器）
///
/// 核心思路：
/// 1. 监听白板数据变更（模仿 DocumentBloc 的 transactionStream）
/// 2. **立即调用** WhiteboardDataService.saveWhiteboardData()（模仿 TransactionAdapter.apply()）
/// 3. 使用防抖机制避免过于频繁的调用
/// 4. 提供强制同步方法（用于手动保存）
/// 5. ✅ 关键修复：在 Widget 销毁前强制同步，确保数据不丢失
class WhiteboardCollabAdapter {
  WhiteboardCollabAdapter({
    required this.viewId,
    required this.onDataChanged,
  }) {
    _service = WhiteboardDataService();
  }

  final String viewId;
  final Function(Map<String, dynamic>) onDataChanged;

  late final WhiteboardDataService _service;

  // ✅ 减少防抖延迟：从 500ms 改为 100ms，更及时保存
  static const _debounceDuration = Duration(milliseconds: 100);

  bool _disposed = false;
  bool _isSyncing = false;
  bool _hasUnsavedChanges = false;
  
  // 待同步的数据（增量）
  final Map<String, dynamic> _pendingData = {};
  String _pendingType = "";

  // 正在同步的数据（增量）
  final Map<String, dynamic> _syncData = {};
  String _syncType = "";

  Timer? _debounceTimer;
  // 缓存完整白板数据（全量状态）
  final Map<String, dynamic> _fullData = {};

  // ✅ 修复：添加待处理的 files 数据
  final Map<String, dynamic> _pendingFiles = {};
  final Map<String, dynamic> _syncFiles = {};

  /// 设置初始数据
  /// ✅ 关键修复：标准化键名，避免 localStorage 原始键名和标准键名共存导致数据混乱
  void setInitialData(Map<String, dynamic>? data) {
    if (data != null) {
      // 标准化键名后再设置
      final normalized = _normalizeKeys(data);
      _fullData.addAll(normalized);
      // 同时初始化 files 数据
      if (normalized.containsKey('files') && normalized['files'] is Map) {
        _fullData['files'] = Map<String, dynamic>.from(normalized['files'] as Map);
      }
      print('[WhiteboardCollabAdapter] setInitialData: keys=${_fullData.keys.toList()}');
    }
  }

  /// ✅ 标准化键名：将 localStorage 原始键名转换为标准键名
  /// excalidraw -> elements, excalidraw-state -> appState, excalidraw-files -> files
  Map<String, dynamic> _normalizeKeys(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{};
    
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (key == 'excalidraw' || key.endsWith('_excalidraw')) {
        if (!normalized.containsKey('elements')) {
          normalized['elements'] = value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'excalidraw-state' || key.endsWith('_excalidraw-state')) {
        if (!normalized.containsKey('appState')) {
          normalized['appState'] = value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'excalidraw-files' || key.endsWith('_excalidraw-files')) {
        if (!normalized.containsKey('files')) {
          normalized['files'] = value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'elements' || key == 'appState' || key == 'files') {
        // 标准键名优先（不覆盖已有的标准键名数据）
        normalized[key] = value is String ? _tryParseJson(value) : value;
      } else {
        normalized[key] = value;
      }
    }
    
    return normalized;
  }

  /// 尝试解析 JSON 字符串，失败则返回原始值
  dynamic _tryParseJson(String value) {
    try {
      return jsonDecode(value);
    } catch (e) {
      return value;
    }
  }

  /// 白板数据变更回调（模仿 DocumentBloc 的 transactionStream）
  ///
  /// 关键：立即同步到后端（模仿 TransactionAdapter.apply()）
  void onWhiteboardDataChanged(String type, Map<String, dynamic> data) {
    if (_disposed) {
      return;
    }

    print('[WhiteboardCollabAdapter] onWhiteboardDataChanged called, type: $type, keys: ${data.keys.toList()}');

    // 更新全量数据缓存
    data.forEach((key, value) {
      if (key == 'files' && value is Map) {
        _fullData[key] = _mergeFiles(_fullData[key] as Map<String, dynamic>?, value as Map<String, dynamic>);
        _pendingFiles.addAll(value);
      } else {
        _fullData[key] = value;
      }
    });

    _hasUnsavedChanges = true;
    _pendingData.addAll(data);
    _pendingType = type;

    // 通知上层数据已变更（用于 UI 更新）
    onDataChanged(data);

    // 取消之前的防抖定时器，重新开始计时
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _syncImmediately();
    });
  }

  /// 合并 files 数据（保留已存在的文件）
  Map<String, dynamic> _mergeFiles(Map<String, dynamic>? existing, Map<String, dynamic> newFiles) {
    final result = <String, dynamic>{};
    if (existing != null) {
      result.addAll(existing);
    }
    result.addAll(newFiles);
    return result;
  }

  /// 立即同步到 Collab 后端（模仿 TransactionAdapter.apply()）
  Future<void> _syncImmediately() async {
    if (!_hasUnsavedChanges || _isSyncing || _disposed) {
      return;
    }

    _isSyncing = true;
    _hasUnsavedChanges = false;
    _syncData.addAll(_pendingData);
    _syncType = _pendingType;
    _pendingType = "";
    _pendingData.clear();

    _syncFiles.addAll(_pendingFiles);
    _pendingFiles.clear();

    try {
      var success = false;

      if (_syncType == 'update') {
        if (_syncFiles.isNotEmpty) {
          _fullData['files'] = _mergeFiles(_fullData['files'] as Map<String, dynamic>?, _syncFiles);
        }
        
        print('[WhiteboardCollabAdapter] Saving whiteboard data, fullData keys: ${_fullData.keys.toList()}');
        if (_fullData.containsKey('files')) {
          final files = _fullData['files'] as Map<String, dynamic>;
          print('[WhiteboardCollabAdapter] Files count: ${files.length}');
        }
        
        success = await _service.saveWhiteboardData(viewId, _fullData);
      } else {
        success = await _service.deleteWhiteboardData(viewId, _syncData);
      }

      if (!success) {
        _hasUnsavedChanges = true;
        _pendingData.addAll(_syncData);
        _pendingFiles.addAll(_syncFiles);
        print('[WhiteboardCollabAdapter] ⚠️ Sync failed, will retry');
      } else {
        print('[WhiteboardCollabAdapter] ✅ Sync completed successfully');
      }
    } catch (e) {
      _hasUnsavedChanges = true;
      _pendingData.addAll(_syncData);
      _pendingFiles.addAll(_syncFiles);
      print('[WhiteboardCollabAdapter] ❌ Sync error: $e');
    } finally {
      _isSyncing = false;
      _syncData.clear();
      _syncFiles.clear();
    }

    // 同步期间如果有新变更积累，安排下一次同步
    if (_hasUnsavedChanges && !_disposed) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () {
        _syncImmediately();
      });
    }
  }

  /// 强制立即同步（用于手动保存和 Widget 销毁前）
  /// 会等待正在进行的同步完成，然后如果有未保存的变更则再次同步
  Future<void> forceSync() async {
    if (_disposed) {
      return;
    }

    _debounceTimer?.cancel();

    // 等待正在进行的同步完成（最多等待 5 秒）
    int attempts = 0;
    while (_isSyncing && !_disposed && attempts < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }

    if (_hasUnsavedChanges && !_disposed) {
      await _syncImmediately();
    }
  }

  /// 销毁适配器
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingData.clear();
    _syncData.clear();
    _fullData.clear();
    _pendingFiles.clear();
    _syncFiles.clear();
  }
}
