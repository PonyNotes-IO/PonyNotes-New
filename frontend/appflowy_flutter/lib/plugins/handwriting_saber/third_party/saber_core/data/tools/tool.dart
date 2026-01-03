import 'package:flutter/material.dart';

/// 虚线样式枚举
enum DashStyle {
  solid,      // 实线
  dot,        // 点虚线（由点组成）
  shortDash,  // 短虚线（短划线）
  longDash,   // 长虚线（长划线）
  dashDot,    // 点划线（点和线交替）
}

/// 箭头样式枚举
enum ArrowStyle {
  filled,       // 实心箭头
  hollow,       // 空心箭头
  line,         // 线条箭头
  doubleArrow,  // 双向箭头
}

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
  arrowLine,   // ✅ 带箭头直线工具
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
  // ✅ PDF文本选择工具
  pdfTextSelect, // ✅ PDF文本选择工具
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

/// ✅ 选择模式枚举
enum SelectMode {
  click,      // 点选模式（默认）
  rectangle,  // 矩形框选模式
  lasso,      // 套索选择模式
}

/// ✅ 选择工具（对象移动工具）
class SelectTool extends Tool {
  const SelectTool({
    this.selectMode = SelectMode.click,
  });

  /// 选择模式
  final SelectMode selectMode;

  @override
  ToolId get toolId => ToolId.select;
  @override
  Color get color => Colors.transparent; // 选择工具不绘制颜色
  @override
  double get strokeWidth => 0; // 选择工具不需要笔迹宽度
  
  /// 创建新的选择工具实例
  SelectTool copyWith({
    SelectMode? selectMode,
  }) {
    return SelectTool(
      selectMode: selectMode ?? this.selectMode,
    );
  }
}

/// ✅ PDF文本选择模式枚举
enum PdfTextSelectMode {
  linear,    // 线性文本选择（沿着文本行选择）
  rectangle, // 矩形文本选择（在矩形区域内选择）
}

/// ✅ PDF文本选择工具
class PdfTextSelectTool extends Tool {
  const PdfTextSelectTool({
    this.selectMode = PdfTextSelectMode.rectangle,
  });

  /// 选择模式
  final PdfTextSelectMode selectMode;

  @override
  ToolId get toolId => ToolId.pdfTextSelect;
  @override
  Color get color => Colors.transparent; // PDF文本选择工具不绘制颜色
  @override
  double get strokeWidth => 0; // PDF文本选择工具不需要笔迹宽度
  
  /// 创建新的PDF文本选择工具实例
  PdfTextSelectTool copyWith({
    PdfTextSelectMode? selectMode,
  }) {
    return PdfTextSelectTool(
      selectMode: selectMode ?? this.selectMode,
    );
  }
}

