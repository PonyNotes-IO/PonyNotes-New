import 'page.dart';
import 'text_box.dart' as saber_text;
import '../../components/canvas/image/editor_image.dart';

/// 编辑器历史记录管理器（参考 Saber 的 EditorHistory 实现）
class EditorHistory {
  static const maxHistoryLength = 100;

  /// 已执行的操作栈（用于撤销）
  final List<EditorHistoryItem> _past = [];

  /// 已撤销的操作栈（用于恢复）
  final List<EditorHistoryItem> _future = [];

  /// 是否可以撤销
  bool get canUndo => _past.isNotEmpty;

  /// 是否可以恢复
  bool get canRedo => _future.isNotEmpty;

  /// 撤销：从 _past 移除最后一个操作，添加到 _future
  EditorHistoryItem undo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    final item = _past.removeLast();
    _future.add(item);
    return item;
  }

  /// 恢复：从 _future 移除最后一个操作，添加到 _past
  EditorHistoryItem redo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    final item = _future.removeLast();
    _past.add(item);
    return item;
  }

  /// 记录操作
  void recordChange(EditorHistoryItem item) {
    _past.add(item);
    if (_past.length > maxHistoryLength) {
      _past.removeAt(0);
    }
    /// 记录新操作时，清空恢复栈
    _future.clear();
  }

  /// 清空历史记录
  void clear() {
    _past.clear();
    _future.clear();
  }
  
  // ============================================================
  // 页面操作历史记录方法
  // ============================================================
  
  /// 记录插入页面操作
  void recordPageInsert(int pageIndex, EditorPage page) {
    recordChange(EditorHistoryItem.insertPage(
      pageIndex: pageIndex,
      page: page,
    ));
  }
  
  /// 记录删除页面操作
  void recordPageDelete(int pageIndex, EditorPage page) {
    recordChange(EditorHistoryItem.deletePage(
      pageIndex: pageIndex,
      page: page,
    ));
  }
  
  /// 记录擦除笔迹操作（简化版本，不需要pageIndex）
  void recordErase(List<Stroke> strokes) {
    if (strokes.isEmpty) return;
    recordChange(EditorHistoryItem.erase(
      pageIndex: 0,
      deletedStrokes: strokes,
    ));
  }

  /// 记录图片变更（导入/删除/移动/缩放）
  void recordImageChange(int pageIndex, List<EditorImage> images) {
    recordChange(EditorHistoryItem.imageChange(
      pageIndex: pageIndex,
      images: List.from(images),
    ));
  }
}

/// 历史记录项类型
enum EditorHistoryItemType {
  draw,
  erase,
  delete,
  add,
  modify,
  insertPage,
  deletePage,
  imageChange,
}

/// 历史记录项
class EditorHistoryItem {
  final EditorHistoryItemType type;
  final int pageIndex;
  final List<Stroke> strokes;
  final List<saber_text.TextBox>? textBoxes;
  final List<Stroke>? deletedStrokes;
  final List<saber_text.TextBox>? deletedTextBoxes;
  final List<EditorImage>? images;
  final EditorPage? page;

  EditorHistoryItem({
    required this.type,
    required this.pageIndex,
    required this.strokes,
    this.textBoxes,
    this.deletedStrokes,
    this.deletedTextBoxes,
    this.images,
    this.page,
  });

  /// 创建绘制操作的历史记录
  factory EditorHistoryItem.draw({
    required int pageIndex,
    required List<Stroke> strokes,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.draw,
      pageIndex: pageIndex,
      strokes: strokes,
    );
  }

  /// 创建擦除操作的历史记录
  factory EditorHistoryItem.erase({
    required int pageIndex,
    required List<Stroke> deletedStrokes,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.erase,
      pageIndex: pageIndex,
      strokes: [],
      deletedStrokes: deletedStrokes,
    );
  }

  /// 创建删除操作的历史记录
  factory EditorHistoryItem.delete({
    required int pageIndex,
    List<Stroke>? deletedStrokes,
    List<saber_text.TextBox>? deletedTextBoxes,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.delete,
      pageIndex: pageIndex,
      strokes: [],
      deletedStrokes: deletedStrokes,
      deletedTextBoxes: deletedTextBoxes,
    );
  }

  /// 创建添加操作的历史记录
  factory EditorHistoryItem.add({
    required int pageIndex,
    List<Stroke>? strokes,
    List<saber_text.TextBox>? textBoxes,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.add,
      pageIndex: pageIndex,
      strokes: strokes ?? [],
      textBoxes: textBoxes,
    );
  }
  
  /// 创建插入页面操作的历史记录
  factory EditorHistoryItem.insertPage({
    required int pageIndex,
    required EditorPage page,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.insertPage,
      pageIndex: pageIndex,
      strokes: [],
      page: page,
    );
  }
  
  /// 创建删除页面操作的历史记录
  factory EditorHistoryItem.deletePage({
    required int pageIndex,
    required EditorPage page,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.deletePage,
      pageIndex: pageIndex,
      strokes: [],
      page: page,
    );
  }

  /// 创建图片操作的历史记录（快照式）
  factory EditorHistoryItem.imageChange({
    required int pageIndex,
    required List<EditorImage> images,
  }) {
    return EditorHistoryItem(
      type: EditorHistoryItemType.imageChange,
      pageIndex: pageIndex,
      strokes: [],
      images: images,
    );
  }
}
