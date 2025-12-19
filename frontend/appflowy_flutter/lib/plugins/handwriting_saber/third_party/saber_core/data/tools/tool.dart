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
  rectangle,
  circle,
  triangle,
  diamond,
  freePolygon,
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

