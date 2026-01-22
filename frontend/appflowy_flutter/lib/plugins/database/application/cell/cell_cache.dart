import 'package:appflowy/plugins/database/application/row/row_service.dart';

import 'cell_controller.dart';

/// CellMemCache is used to cache cell data of each block.
/// We use CellContext to index the cell in the cache.
/// Read https://docs.appflowy.io/docs/documentation/software-contributions/architecture/frontend/frontend/grid
/// for more information
class CellMemCache {
  CellMemCache();

  /// fieldId: {rowId: cellData}
  final Map<String, Map<RowId, dynamic>> _cellByFieldId = {};
  
  // 缓存大小限制：最多缓存 10000 个 cell 数据，防止内存溢出
  static const int _maxCacheSize = 10000;
  
  // 记录插入顺序，用于 LRU 清理
  final List<CellContext> _insertionOrder = [];

  void removeCellWithFieldId(String fieldId) {
    _cellByFieldId.remove(fieldId);
    // 清理插入顺序记录
    _insertionOrder.removeWhere((ctx) => ctx.fieldId == fieldId);
  }

  void remove(CellContext context) {
    _cellByFieldId[context.fieldId]?.remove(context.rowId);
    _insertionOrder.remove(context);
  }

  void insert<T>(CellContext context, T data) {
    _cellByFieldId.putIfAbsent(context.fieldId, () => {});
    
    // 如果该 cell 已存在，先移除旧的插入顺序记录
    if (_cellByFieldId[context.fieldId]!.containsKey(context.rowId)) {
      _insertionOrder.remove(context);
    }
    
    _cellByFieldId[context.fieldId]![context.rowId] = data;
    
    // 添加新的插入顺序记录
    _insertionOrder.add(context);
    
    // 检查并清理缓存，防止内存溢出
    _cleanupIfNeeded();
  }
  
  /// 清理缓存，防止内存溢出
  void _cleanupIfNeeded() {
    // 计算当前缓存的总大小
    int totalCells = 0;
    for (final fieldMap in _cellByFieldId.values) {
      totalCells += fieldMap.length;
    }
    
    // 如果超过限制，清理最旧的 20% 的缓存
    if (totalCells > _maxCacheSize) {
      final toRemove = (totalCells * 0.2).ceil();
      final contextsToRemove = _insertionOrder.take(toRemove).toList();
      
      for (final context in contextsToRemove) {
        _cellByFieldId[context.fieldId]?.remove(context.rowId);
        // 如果该 field 的 map 为空，移除整个 field
        if (_cellByFieldId[context.fieldId]?.isEmpty ?? false) {
          _cellByFieldId.remove(context.fieldId);
        }
        _insertionOrder.remove(context);
      }
    }
  }

  T? get<T>(CellContext context) {
    final value = _cellByFieldId[context.fieldId]?[context.rowId];
    return value is T ? value : null;
  }

  void dispose() {
    _cellByFieldId.clear();
  }
}
