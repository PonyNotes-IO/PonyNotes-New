import 'package:flutter/material.dart';

/// ✅ 列表项数据模型
class ListItem {
  ListItem({
    required this.id,
    required this.text,
    this.textStyle,
  });

  final String id;
  String text;
  TextStyle? textStyle;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'textStyle': textStyle != null
          ? {
              'fontSize': textStyle!.fontSize,
              'fontWeight': textStyle!.fontWeight?.index,
              'fontStyle': textStyle!.fontStyle?.index,
              'color': textStyle!.color?.value,
            }
          : null,
    };
  }

  factory ListItem.fromJson(Map<String, dynamic> json) {
    final textStyleJson = json['textStyle'] as Map<String, dynamic>?;
    TextStyle? textStyle;
    if (textStyleJson != null) {
      textStyle = TextStyle(
        fontSize: (textStyleJson['fontSize'] as num?)?.toDouble(),
        fontWeight: textStyleJson['fontWeight'] != null
            ? FontWeight.values[textStyleJson['fontWeight'] as int]
            : null,
        fontStyle: textStyleJson['fontStyle'] != null
            ? FontStyle.values[textStyleJson['fontStyle'] as int]
            : null,
        color: textStyleJson['color'] != null
            ? Color(textStyleJson['color'] as int)
            : null,
      );
    }
    return ListItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      textStyle: textStyle,
    );
  }
}

/// ✅ 列表类型枚举
enum ListBoxType {
  ordered,    // 有序列表
  unordered,  // 无序列表
}

/// ✅ 列表框数据模型
class ListBox {
  ListBox({
    required this.id,
    required this.position,
    required this.size,
    required this.listType,
    List<ListItem>? items,
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0,
  }) : items = items ?? <ListItem>[];

  final String id;
  Offset position;
  Size size;
  ListBoxType listType;
  List<ListItem> items;
  TextStyle? textStyle;
  Color? backgroundColor;
  Color? borderColor;
  double borderWidth;

  Rect get rect => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  void move(Offset offset) {
    position = position + offset;
  }

  void resize(Size newSize) {
    size = newSize;
  }

  /// ✅ 添加列表项
  void addItem(ListItem item) {
    items.add(item);
  }

  /// ✅ 删除列表项
  void removeItem(String itemId) {
    items.removeWhere((item) => item.id == itemId);
  }

  /// ✅ 移动列表项
  void moveItem(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= items.length ||
        toIndex < 0 || toIndex >= items.length) {
      return;
    }
    final item = items.removeAt(fromIndex);
    items.insert(toIndex, item);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': {'x': position.dx, 'y': position.dy},
      'size': {'width': size.width, 'height': size.height},
      'listType': listType.name,
      'items': items.map((item) => item.toJson()).toList(),
      'textStyle': textStyle != null
          ? {
              'fontSize': textStyle!.fontSize,
              'fontWeight': textStyle!.fontWeight?.index,
              'fontStyle': textStyle!.fontStyle?.index,
              'color': textStyle!.color?.value,
            }
          : null,
      'backgroundColor': backgroundColor?.value,
      'borderColor': borderColor?.value,
      'borderWidth': borderWidth,
    };
  }

  factory ListBox.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'] as Map<String, dynamic>;
    final sizeJson = json['size'] as Map<String, dynamic>;
    final itemsJson = json['items'] as List<dynamic>? ?? <dynamic>[];
    final textStyleJson = json['textStyle'] as Map<String, dynamic>?;
    final listTypeName = json['listType'] as String? ?? 'unordered';

    TextStyle? textStyle;
    if (textStyleJson != null) {
      textStyle = TextStyle(
        fontSize: (textStyleJson['fontSize'] as num?)?.toDouble(),
        fontWeight: textStyleJson['fontWeight'] != null
            ? FontWeight.values[textStyleJson['fontWeight'] as int]
            : null,
        fontStyle: textStyleJson['fontStyle'] != null
            ? FontStyle.values[textStyleJson['fontStyle'] as int]
            : null,
        color: textStyleJson['color'] != null
            ? Color(textStyleJson['color'] as int)
            : null,
      );
    }

    return ListBox(
      id: json['id'] as String,
      position: Offset(
        (positionJson['x'] as num).toDouble(),
        (positionJson['y'] as num).toDouble(),
      ),
      size: Size(
        (sizeJson['width'] as num).toDouble(),
        (sizeJson['height'] as num).toDouble(),
      ),
      listType: listTypeName == 'ordered'
          ? ListBoxType.ordered
          : ListBoxType.unordered,
      items: itemsJson
          .whereType<Map<String, dynamic>>()
          .map((json) => ListItem.fromJson(json))
          .toList(),
      textStyle: textStyle,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : null,
      borderColor: json['borderColor'] != null
          ? Color(json['borderColor'] as int)
          : null,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// ✅ 任务项数据模型
class TaskItem {
  TaskItem({
    required this.id,
    required this.text,
    this.completed = false,
    this.textStyle,
  });

  final String id;
  String text;
  bool completed;
  TextStyle? textStyle;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'completed': completed,
      'textStyle': textStyle != null
          ? {
              'fontSize': textStyle!.fontSize,
              'fontWeight': textStyle!.fontWeight?.index,
              'fontStyle': textStyle!.fontStyle?.index,
              'color': textStyle!.color?.value,
            }
          : null,
    };
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final textStyleJson = json['textStyle'] as Map<String, dynamic>?;
    TextStyle? textStyle;
    if (textStyleJson != null) {
      textStyle = TextStyle(
        fontSize: (textStyleJson['fontSize'] as num?)?.toDouble(),
        fontWeight: textStyleJson['fontWeight'] != null
            ? FontWeight.values[textStyleJson['fontWeight'] as int]
            : null,
        fontStyle: textStyleJson['fontStyle'] != null
            ? FontStyle.values[textStyleJson['fontStyle'] as int]
            : null,
        color: textStyleJson['color'] != null
            ? Color(textStyleJson['color'] as int)
            : null,
      );
    }
    return TaskItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
      textStyle: textStyle,
    );
  }
}

/// ✅ 任务列表框数据模型
class TaskListBox {
  TaskListBox({
    required this.id,
    required this.position,
    required this.size,
    List<TaskItem>? items,
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0,
  }) : items = items ?? <TaskItem>[];

  final String id;
  Offset position;
  Size size;
  List<TaskItem> items;
  TextStyle? textStyle;
  Color? backgroundColor;
  Color? borderColor;
  double borderWidth;

  Rect get rect => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  void move(Offset offset) {
    position = position + offset;
  }

  void resize(Size newSize) {
    size = newSize;
  }

  /// ✅ 添加任务项
  void addItem(TaskItem item) {
    items.add(item);
  }

  /// ✅ 删除任务项
  void removeItem(String itemId) {
    items.removeWhere((item) => item.id == itemId);
  }

  /// ✅ 切换任务完成状态
  void toggleItem(String itemId) {
    final item = items.firstWhere(
      (item) => item.id == itemId,
      orElse: () => throw StateError('Item not found'),
    );
    item.completed = !item.completed;
  }

  /// ✅ 移动任务项
  void moveItem(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= items.length ||
        toIndex < 0 || toIndex >= items.length) {
      return;
    }
    final item = items.removeAt(fromIndex);
    items.insert(toIndex, item);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': {'x': position.dx, 'y': position.dy},
      'size': {'width': size.width, 'height': size.height},
      'items': items.map((item) => item.toJson()).toList(),
      'textStyle': textStyle != null
          ? {
              'fontSize': textStyle!.fontSize,
              'fontWeight': textStyle!.fontWeight?.index,
              'fontStyle': textStyle!.fontStyle?.index,
              'color': textStyle!.color?.value,
            }
          : null,
      'backgroundColor': backgroundColor?.value,
      'borderColor': borderColor?.value,
      'borderWidth': borderWidth,
    };
  }

  factory TaskListBox.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'] as Map<String, dynamic>;
    final sizeJson = json['size'] as Map<String, dynamic>;
    final itemsJson = json['items'] as List<dynamic>? ?? <dynamic>[];
    final textStyleJson = json['textStyle'] as Map<String, dynamic>?;

    TextStyle? textStyle;
    if (textStyleJson != null) {
      textStyle = TextStyle(
        fontSize: (textStyleJson['fontSize'] as num?)?.toDouble(),
        fontWeight: textStyleJson['fontWeight'] != null
            ? FontWeight.values[textStyleJson['fontWeight'] as int]
            : null,
        fontStyle: textStyleJson['fontStyle'] != null
            ? FontStyle.values[textStyleJson['fontStyle'] as int]
            : null,
        color: textStyleJson['color'] != null
            ? Color(textStyleJson['color'] as int)
            : null,
      );
    }

    return TaskListBox(
      id: json['id'] as String,
      position: Offset(
        (positionJson['x'] as num).toDouble(),
        (positionJson['y'] as num).toDouble(),
      ),
      size: Size(
        (sizeJson['width'] as num).toDouble(),
        (sizeJson['height'] as num).toDouble(),
      ),
      items: itemsJson
          .whereType<Map<String, dynamic>>()
          .map((json) => TaskItem.fromJson(json))
          .map((item) => item)
          .toList(),
      textStyle: textStyle,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : null,
      borderColor: json['borderColor'] != null
          ? Color(json['borderColor'] as int)
          : null,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0,
    );
  }
}

