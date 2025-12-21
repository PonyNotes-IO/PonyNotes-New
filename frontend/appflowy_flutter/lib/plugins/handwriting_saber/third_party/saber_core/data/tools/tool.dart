import 'package:flutter/material.dart';

/// 工具 ID 枚举
enum ToolId {
  fountainPen,
  ballpointPen,
  pencil,
  highlighter,
  eraser,
  laserPointer,
  // ✅ 形状工具
  line,        // ✅ 直线工具
  rectangle,
  circle,
  triangle,
  diamond,
  freePolygon,
  // ✅ 选择工具
  select,      // ✅ 对象移动工具（选择工具）
  // ✅ 文本工具
  textBox,     // ✅ 文本框工具
  // ✅ 标题工具
  heading1,    // ✅ 一级标题
  heading2,    // ✅ 二级标题
  heading3,    // ✅ 三级标题
  paragraph,   // ✅ 正文
  // ✅ 列表工具
  orderedList,   // ✅ 有序列表
  unorderedList, // ✅ 无序列表
  taskList,      // ✅ 任务列表
}

/// 基础工具抽象类
abstract class Tool {
  const Tool();

  ToolId get toolId;
  Color get color;
  double get strokeWidth;
}

/// 笔类工具
class Pen extends Tool {
  const Pen({
    required this.toolId,
    required this.color,
    required this.strokeWidth,
  });

  @override
  final ToolId toolId;
  @override
  final Color color;
  @override
  final double strokeWidth;

  Pen copyWith({
    ToolId? toolId,
    Color? color,
    double? strokeWidth,
  }) {
    return Pen(
      toolId: toolId ?? this.toolId,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

/// 橡皮擦工具
class Eraser extends Tool {
  const Eraser({
    required this.strokeWidth,
  });

  @override
  ToolId get toolId => ToolId.eraser;
  @override
  Color get color => Colors.transparent; // 橡皮擦不绘制颜色
  @override
  final double strokeWidth;
}

/// ✅ 选择工具（对象移动工具）
class SelectTool extends Tool {
  const SelectTool();

  @override
  ToolId get toolId => ToolId.select;
  @override
  Color get color => Colors.transparent; // 选择工具不绘制颜色
  @override
  double get strokeWidth => 0; // 选择工具不需要笔迹宽度
}

