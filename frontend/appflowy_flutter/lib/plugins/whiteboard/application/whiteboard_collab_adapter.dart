import 'dart:async';
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
class WhiteboardCollabAdapter {
  WhiteboardCollabAdapter({
    required this.viewId,
    required this.onDataChanged,
  }) {
    Log.info(
        '[WhiteboardCollabAdapter] Initializing adapter for viewId: $viewId');
    _service = WhiteboardDataService();
  }

  final String viewId;
  final Function(Map<String, dynamic>) onDataChanged;

  late final WhiteboardDataService _service;

  // 防抖延迟（500ms，避免过于频繁的调用）
  static const _debounceDuration = Duration(milliseconds: 500);

  Timer? _debounceTimer;
  final Map<String, dynamic> _pendingData = {};
  String _pendingType = "";
  final Map<String, dynamic> _syncData = {};
  String _syncType = "";
  bool _isSyncing = false;
  bool _disposed = false;

  /// 白板数据变更回调（模仿 DocumentBloc 的 transactionStream）
  ///
  /// 关键：立即同步到后端（模仿 TransactionAdapter.apply()）
  void onWhiteboardDataChanged(String type, Map<String, dynamic> data) {
    if (_disposed) {
      Log.warn(
          '[WhiteboardCollabAdapter] Adapter disposed, ignoring data change');
      return;
    }

    Log.info(
        '[WhiteboardCollabAdapter] =====================================================');
    Log.info(
        '[WhiteboardCollabAdapter] Data changed received (like TransactionAdapter.apply)');
    Log.info('[WhiteboardCollabAdapter] ViewID: $viewId');
    Log.info('[WhiteboardCollabAdapter] Data keys: ${data.keys.toList()}');

    // 首先，data不能一样。
    if (_pendingType == type && mapEquals(_pendingData, data)){
      Log.info('[WhiteboardCollabAdapter] [check-1] The data remained unchanged.');
      return;
    }

    // 正在同步和等待同步的数据不一样
    if (_pendingType == _syncType && !mapEquals(_pendingData, _syncData)){
      Log.info('[WhiteboardCollabAdapter] [check-2] The data remained unchanged.');
      return;
    }

    // 缓存待同步的数据
    _pendingData.addAll(data);
    _pendingType = type;

    // 通知上层数据已变更（用于 UI 更新）
    onDataChanged(data);

    // 取消之前的防抖定时器
    _debounceTimer?.cancel();

    // 设置新的防抖定时器，延迟同步
    _debounceTimer = Timer(_debounceDuration, () {
      _syncImmediately();
    });

    Log.info(
        '[WhiteboardCollabAdapter] Debounce timer set (${_debounceDuration
            .inMilliseconds}ms)');
    Log.info(
        '[WhiteboardCollabAdapter] =====================================================');
  }

  /// 立即同步到 Collab 后端（模仿 TransactionAdapter.apply()）
  Future<void> _syncImmediately() async {
    // 如果没有待同步的数据，跳过
    if (_pendingData.isEmpty || _isSyncing || _disposed) {
      return;
    }

    _isSyncing = true;
    _syncData.addAll(_pendingData);
    _syncType = _pendingType;
    _pendingType = "";
    _pendingData.clear(); // 清空待同步数据

    try {
      Log.info(
          '[WhiteboardCollabAdapter] =====================================================');
      Log.info(
          '[WhiteboardCollabAdapter] 🚀 IMMEDIATE SYNC to Collab backend (like TransactionAdapter.apply)');
      Log.info('[WhiteboardCollabAdapter] ViewID: $viewId');
      Log.info(
          '[WhiteboardCollabAdapter] Data keys: ${_syncData.keys.toList()}');


      var success = false;

      if (_syncType == 'update'){
        success = await _service.saveWhiteboardData(viewId, _syncData);
      }else{
        success = await _service.deleteWhiteboardData(viewId, _syncData);
      }

      if (success) {
        Log.info(
            '[WhiteboardCollabAdapter] ✅✅✅ Data synced successfully to Collab!');
        Log.info(
            '[WhiteboardCollabAdapter] ✅✅✅ This should trigger CRDT persistence!');
      } else {
        Log.error(
            '[WhiteboardCollabAdapter] ❌ Sync failed, will retry on next change');
        // 同步失败，重新缓存数据等待下次同步
        _pendingData.addAll(_syncData);
      }
      Log.info(
          '[WhiteboardCollabAdapter] =====================================================');
    } catch (e, stackTrace) {
      Log.error('[WhiteboardCollabAdapter] ❌ Sync error: $e');
      Log.error('[WhiteboardCollabAdapter] Stack trace: $stackTrace');
      // 发生错误，重新缓存数据等待下次同步
      _pendingData.addAll(_syncData);
    } finally {
      _isSyncing = false;
      _syncData.clear();
    }
  }

  /// 强制立即同步（用于手动保存）
  Future<void> forceSync() async {
    if (_disposed) {
      Log.warn('[WhiteboardCollabAdapter] Adapter disposed, cannot force sync');
      return;
    }

    Log.info(
        '[WhiteboardCollabAdapter] ⚡ Force sync requested (like DocumentBloc manual save)');

    // 取消防抖定时器，立即同步
    _debounceTimer?.cancel();
    await _syncImmediately();
  }

  /// 销毁适配器
  void dispose() {
    Log.info('[WhiteboardCollabAdapter] Disposing adapter for viewId: $viewId');
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingData.clear();
    _syncData.clear();
  }
}
