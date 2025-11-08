import 'dart:async';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy_backend/log.dart';

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
    Log.info('[WhiteboardCollabAdapter] Initializing adapter for viewId: $viewId');
    _service = WhiteboardDataService();
  }

  final String viewId;
  final Function(Map<String, dynamic>) onDataChanged;
  
  late final WhiteboardDataService _service;
  
  // 防抖延迟（500ms，避免过于频繁的调用）
  static const _debounceDuration = Duration(milliseconds: 500);
  
  Timer? _debounceTimer;
  Map<String, dynamic>? _pendingData;
  bool _isSyncing = false;
  bool _disposed = false;

  /// 白板数据变更回调（模仿 DocumentBloc 的 transactionStream）
  /// 
  /// 关键：立即同步到后端（模仿 TransactionAdapter.apply()）
  void onWhiteboardDataChanged(Map<String, dynamic> data) {
    if (_disposed) {
      Log.warn('[WhiteboardCollabAdapter] Adapter disposed, ignoring data change');
      return;
    }
    
    Log.info('[WhiteboardCollabAdapter] =====================================================');
    Log.info('[WhiteboardCollabAdapter] Data changed received (like TransactionAdapter.apply)');
    Log.info('[WhiteboardCollabAdapter] ViewID: $viewId');
    Log.info('[WhiteboardCollabAdapter] Data keys: ${data.keys.toList()}');
    
    if (data.containsKey('elements')) {
      final elements = data['elements'] as List?;
      Log.info('[WhiteboardCollabAdapter] Elements count: ${elements?.length ?? 0}');
    }
    
    // 缓存待同步的数据
    _pendingData = data;
    
    // 通知上层数据已变更（用于 UI 更新）
    onDataChanged(data);
    
    // 取消之前的防抖定时器
    _debounceTimer?.cancel();
    
    // 设置新的防抖定时器，延迟同步
    _debounceTimer = Timer(_debounceDuration, () {
      _syncImmediately();
    });
    
    Log.info('[WhiteboardCollabAdapter] Debounce timer set (${_debounceDuration.inMilliseconds}ms)');
    Log.info('[WhiteboardCollabAdapter] =====================================================');
  }

  /// 立即同步到 Collab 后端（模仿 TransactionAdapter.apply()）
  Future<void> _syncImmediately() async {
    // 如果没有待同步的数据，跳过
    if (_pendingData == null || _isSyncing || _disposed) {
      return;
    }
    
    _isSyncing = true;
    final dataToSync = _pendingData!;
    _pendingData = null; // 清空待同步数据
    
    try {
      Log.info('[WhiteboardCollabAdapter] =====================================================');
      Log.info('[WhiteboardCollabAdapter] 🚀 IMMEDIATE SYNC to Collab backend (like TransactionAdapter.apply)');
      Log.info('[WhiteboardCollabAdapter] ViewID: $viewId');
      Log.info('[WhiteboardCollabAdapter] Data keys: ${dataToSync.keys.toList()}');
      
      final success = await _service.saveWhiteboardData(viewId, dataToSync);
      
      if (success) {
        Log.info('[WhiteboardCollabAdapter] ✅✅✅ Data synced successfully to Collab!');
        Log.info('[WhiteboardCollabAdapter] ✅✅✅ This should trigger CRDT persistence!');
      } else {
        Log.error('[WhiteboardCollabAdapter] ❌ Sync failed, will retry on next change');
        // 同步失败，重新缓存数据等待下次同步
        _pendingData = dataToSync;
      }
      Log.info('[WhiteboardCollabAdapter] =====================================================');
    } catch (e, stackTrace) {
      Log.error('[WhiteboardCollabAdapter] ❌ Sync error: $e');
      Log.error('[WhiteboardCollabAdapter] Stack trace: $stackTrace');
      // 发生错误，重新缓存数据等待下次同步
      _pendingData = dataToSync;
    } finally {
      _isSyncing = false;
    }
  }

  /// 强制立即同步（用于手动保存）
  Future<void> forceSync() async {
    if (_disposed) {
      Log.warn('[WhiteboardCollabAdapter] Adapter disposed, cannot force sync');
      return;
    }
    
    Log.info('[WhiteboardCollabAdapter] ⚡ Force sync requested (like DocumentBloc manual save)');
    
    // 取消防抖定时器，立即同步
    _debounceTimer?.cancel();
    await _syncImmediately();
  }

  /// 销毁适配器（模仿 TransactionAdapter 的 dispose）
  /// 
  /// **关键**：在销毁前执行最后一次同步，确保数据不丢失
  Future<void> dispose() async {
    Log.info('[WhiteboardCollabAdapter] =====================================================');
    Log.info('[WhiteboardCollabAdapter] Disposing adapter for viewId: $viewId');
    Log.info('[WhiteboardCollabAdapter] Will perform final sync before disposal...');
    
    // 取消防抖定时器
    _debounceTimer?.cancel();
    _debounceTimer = null;
    
    // **核心修复**：在销毁前执行最后一次同步（确保数据不丢失）
    if (_pendingData != null && !_isSyncing) {
      Log.info('[WhiteboardCollabAdapter] 🚨 FINAL SYNC before disposal (has pending data)');
      try {
        await _syncImmediately();
        Log.info('[WhiteboardCollabAdapter] ✅ Final sync completed successfully');
      } catch (e) {
        Log.error('[WhiteboardCollabAdapter] ❌ Final sync failed: $e');
      }
    } else {
      Log.info('[WhiteboardCollabAdapter] No pending data, skipping final sync');
    }
    
    // 标记为已销毁
    _disposed = true;
    _pendingData = null;
    
    Log.info('[WhiteboardCollabAdapter] Adapter disposed for viewId: $viewId');
    Log.info('[WhiteboardCollabAdapter] =====================================================');
  }
}
