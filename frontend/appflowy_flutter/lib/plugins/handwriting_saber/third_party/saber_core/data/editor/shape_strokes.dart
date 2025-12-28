import 'dart:math';

import 'package:flutter/material.dart';

import 'page.dart';
import '../tools/tool.dart';

/// ✅ 直线笔迹
class LineStroke extends Stroke {
  LineStroke({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
    this.isDashed = false, // ✅ 是否为虚线
  }) : super(
          points: [startPoint, endPoint],
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.line,
          pressureEnabled: false,
        );

  final bool isDashed; // ✅ 是否为虚线

  Offset get startPoint => points.isNotEmpty ? points.first : Offset.zero;
  Offset get endPoint => points.length > 1 ? points[1] : Offset.zero;

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'line';
    json['isDashed'] = isDashed; // ✅ 保存虚线状态
    return json;
  }

  factory LineStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    final isDashed = json['isDashed'] as bool? ?? false; // ✅ 读取虚线状态
    if (stroke.points.length < 2) {
      return LineStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        isDashed: isDashed,
      );
    }
    return LineStroke(
      startPoint: stroke.points.first,
      endPoint: stroke.points[1],
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      isDashed: isDashed,
    );
  }
}

/// ✅ 带箭头直线笔迹
class ArrowLineStroke extends LineStroke {
  ArrowLineStroke({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
    bool isDashed = false, // ✅ 是否为虚线
  }) : super(
          startPoint: startPoint,
          endPoint: endPoint,
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.arrowLine,
          isDashed: isDashed,
        );

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'arrowLine'; // ✅ 标记为箭头直线
    return json;
  }

  factory ArrowLineStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    final isDashed = json['isDashed'] as bool? ?? false;
    if (stroke.points.length < 2) {
      return ArrowLineStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        isDashed: isDashed,
      );
    }
    return ArrowLineStroke(
      startPoint: stroke.points.first,
      endPoint: stroke.points[1],
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      isDashed: isDashed,
    );
  }
}

/// ✅ 矩形笔迹
class RectangleStroke extends Stroke {
  RectangleStroke({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
    this.fillColor, // ✅ 填充颜色（可选）
  }) : super(
          points: _calculateRectanglePoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.rectangle,
          pressureEnabled: false,
        );
  
  final Color? fillColor; // ✅ 填充颜色（null表示不填充）

  static List<Offset> _calculateRectanglePoints(Offset start, Offset end) {
    final left = min(start.dx, end.dx);
    final top = min(start.dy, end.dy);
    final right = max(start.dx, end.dx);
    final bottom = max(start.dy, end.dy);
    
    return [
      Offset(left, top),      // 左上
      Offset(right, top),     // 右上
      Offset(right, bottom),  // 右下
      Offset(left, bottom),   // 左下
      Offset(left, top),      // 闭合
    ];
  }

  Rect get rect {
    if (points.isEmpty) return Rect.zero;
    final left = points.map((p) => p.dx).reduce(min);
    final top = points.map((p) => p.dy).reduce(min);
    final right = points.map((p) => p.dx).reduce(max);
    final bottom = points.map((p) => p.dy).reduce(max);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'rectangle';
    if (fillColor != null) {
      json['fillColor'] = fillColor!.value; // ✅ 保存填充颜色
    }
    return json;
  }

  factory RectangleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    final fillColorValue = json['fillColor'] as int?;
    final fillColor = fillColorValue != null 
        ? Color(fillColorValue) 
        : null; // ✅ 读取填充颜色
    if (stroke.points.length < 2) {
      return RectangleStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        fillColor: fillColor,
      );
    }
    return RectangleStroke(
      startPoint: stroke.points.first,
      endPoint: stroke.points[stroke.points.length - 2], // 倒数第二个点（最后一个点是闭合点）
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      fillColor: fillColor,
    );
  }
}

/// ✅ 圆形笔迹
class CircleStroke extends Stroke {
  CircleStroke({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
    this.fillColor, // ✅ 填充颜色（可选）
  }) : super(
          points: _calculateCirclePoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.circle,
          pressureEnabled: false,
        );
  
  final Color? fillColor; // ✅ 填充颜色（null表示不填充）

  static List<Offset> _calculateCirclePoints(Offset start, Offset end) {
    final center = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );
    // ✅ 支持椭圆：分别计算宽度和高度半径
    final width = (end.dx - start.dx).abs();
    final height = (end.dy - start.dy).abs();
    final radiusX = width / 2;
    final radiusY = height / 2;
    
    // 生成椭圆点（24个点）
    final points = <Offset>[];
    for (int i = 0; i <= 24; i++) {
      final angle = i / 24 * 2 * pi;
      points.add(Offset(
        center.dx + radiusX * cos(angle),
        center.dy + radiusY * sin(angle),
      ));
    }
    return points;
  }

  Offset get center {
    if (points.isEmpty) return Offset.zero;
    final sumX = points.map((p) => p.dx).reduce((a, b) => a + b);
    final sumY = points.map((p) => p.dy).reduce((a, b) => a + b);
    return Offset(sumX / points.length, sumY / points.length);
  }

  double get radius {
    if (points.isEmpty) return 0;
    final c = center;
    return points.map((p) => (p - c).distance).reduce(max);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'circle';
    if (fillColor != null) {
      json['fillColor'] = fillColor!.value; // ✅ 保存填充颜色
    }
    return json;
  }

  factory CircleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    final fillColorValue = json['fillColor'] as int?;
    final fillColor = fillColorValue != null 
        ? Color(fillColorValue) 
        : null; // ✅ 读取填充颜色
    if (stroke.points.length < 2) {
      return CircleStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        fillColor: fillColor,
      );
    }
    // 从圆形点计算起始点和结束点
    final firstPoint = stroke.points.first;
    final lastPoint = stroke.points.last;
    return CircleStroke(
      startPoint: firstPoint,
      endPoint: lastPoint,
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      fillColor: fillColor,
    );
  }
}

/// ✅ 三角形笔迹（支持一笔画出任意三角形）
class TriangleStroke extends Stroke {
  TriangleStroke({
    required List<Offset> points,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
    this.isShiftPressed = false, // ✅ 是否按住Shift键（绘制正三角形或等腰三角形）
    this.fillColor, // ✅ 填充颜色（可选）
  }) : super(
          points: _optimizeToTriangle(points, isShiftPressed: isShiftPressed), // ✅ 优化为三角形（三个顶点）
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.triangle,
          pressureEnabled: false,
        );

  final bool isShiftPressed; // ✅ 是否按住Shift键
  final Color? fillColor; // ✅ 填充颜色（null表示不填充）

  // ✅ 从绘制路径优化为三角形：提取三个关键点
  static List<Offset> _optimizeToTriangle(List<Offset> inputPoints, {bool isShiftPressed = false}) {
    if (inputPoints.isEmpty) {
      return [];
    }
    if (inputPoints.length == 1) {
      return [inputPoints[0], inputPoints[0], inputPoints[0], inputPoints[0]]; // 闭合
    }
    if (inputPoints.length == 2) {
      // 只有两个点，添加第三个点形成三角形
      final p1 = inputPoints[0];
      final p2 = inputPoints[1];
      
      if (isShiftPressed) {
        // ✅ 按住Shift：绘制正三角形或等腰三角形
        // 计算两点之间的距离
        final dx = p2.dx - p1.dx;
        final dy = p2.dy - p1.dy;
        final distance = sqrt(dx * dx + dy * dy);
        
        // 计算中点
        final midX = (p1.dx + p2.dx) / 2;
        final midY = (p1.dy + p2.dy) / 2;
        
        // 正三角形：第三个点在垂直平分线上，距离为边长的√3/2
        final height = distance * sqrt(3) / 2;
        // 垂直方向向量（归一化）
        final perpX = -dy / distance;
        final perpY = dx / distance;
        
        // 第三个点（可以选择上方或下方，这里选择上方）
        final p3 = Offset(midX + perpX * height, midY + perpY * height);
        return [p1, p2, p3, p1]; // 闭合
      } else {
        // 不按Shift：任意三角形
        final midX = (p1.dx + p2.dx) / 2;
        final midY = (p1.dy + p2.dy) / 2;
        final dx = p2.dx - p1.dx;
        final dy = p2.dy - p1.dy;
        // 垂直方向上的点
        final p3 = Offset(midX - dy, midY + dx);
        return [p1, p2, p3, p1]; // 闭合
      }
    }
    
    // ✅ 从多个点中提取三个关键点
    final startPoint = inputPoints.first;
    final endPoint = inputPoints.last;
    
    if (isShiftPressed) {
      // ✅ 按住Shift：绘制正三角形或等腰三角形
      // 计算两点之间的距离
      final dx = endPoint.dx - startPoint.dx;
      final dy = endPoint.dy - startPoint.dy;
      final distance = sqrt(dx * dx + dy * dy);
      
      // 计算中点
      final midX = (startPoint.dx + endPoint.dx) / 2;
      final midY = (startPoint.dy + endPoint.dy) / 2;
      
      // 找到距离起始点和结束点连线最远的点
      double maxDistance = 0;
      Offset farthestPoint = endPoint;
      
      for (int i = 1; i < inputPoints.length - 1; i++) {
        final point = inputPoints[i];
        final distance = _pointToLineDistance(point, startPoint, endPoint);
        if (distance > maxDistance) {
          maxDistance = distance;
          farthestPoint = point;
        }
      }
      
      // 如果最远点距离太小，使用正三角形的第三个点
      if (maxDistance < 10) {
        // 正三角形：第三个点在垂直平分线上
        final height = distance * sqrt(3) / 2;
        final perpX = -dy / distance;
        final perpY = dx / distance;
        farthestPoint = Offset(midX + perpX * height, midY + perpY * height);
      } else {
        // 等腰三角形：第三个点在垂直平分线上，距离为最远点的距离
        final perpX = -dy / distance;
        final perpY = dx / distance;
        final height = maxDistance;
        // 判断最远点在线的哪一侧
        final side = (farthestPoint.dx - midX) * perpX + (farthestPoint.dy - midY) * perpY;
        farthestPoint = Offset(
          midX + perpX * height * (side >= 0 ? 1 : -1),
          midY + perpY * height * (side >= 0 ? 1 : -1),
        );
      }
      
      return [startPoint, farthestPoint, endPoint, startPoint]; // 闭合三角形
    } else {
      // ✅ 不按Shift：任意三角形
      // 找到距离起始点和结束点连线最远的点
      double maxDistance = 0;
      Offset farthestPoint = endPoint;
      
      for (int i = 1; i < inputPoints.length - 1; i++) {
        final point = inputPoints[i];
        // 计算点到起始点和结束点连线的距离
        final distance = _pointToLineDistance(point, startPoint, endPoint);
        if (distance > maxDistance) {
          maxDistance = distance;
          farthestPoint = point;
        }
      }
      
      // 如果最远点距离太小，使用中点
      if (maxDistance < 10) {
        final midX = (startPoint.dx + endPoint.dx) / 2;
        final midY = (startPoint.dy + endPoint.dy) / 2;
        final dx = endPoint.dx - startPoint.dx;
        final dy = endPoint.dy - startPoint.dy;
        farthestPoint = Offset(midX - dy, midY + dx);
      }
      
      return [startPoint, farthestPoint, endPoint, startPoint]; // 闭合三角形
    }
  }

  // ✅ 计算点到直线的距离
  static double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final A = point.dx - lineStart.dx;
    final B = point.dy - lineStart.dy;
    final C = lineEnd.dx - lineStart.dx;
    final D = lineEnd.dy - lineStart.dy;
    
    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    if (lenSq == 0) {
      // 线段退化为点
      return sqrt(A * A + B * B);
    }
    
    final param = dot / lenSq;
    Offset closestPoint;
    if (param < 0) {
      closestPoint = lineStart;
    } else if (param > 1) {
      closestPoint = lineEnd;
    } else {
      closestPoint = Offset(
        lineStart.dx + param * C,
        lineStart.dy + param * D,
      );
    }
    
    final dx = point.dx - closestPoint.dx;
    final dy = point.dy - closestPoint.dy;
    return sqrt(dx * dx + dy * dy);
  }

  Offset get point1 => points.isNotEmpty ? points[0] : Offset.zero;
  Offset get point2 => points.length > 1 ? points[1] : Offset.zero;
  Offset get point3 => points.length > 2 ? points[2] : Offset.zero;

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'triangle';
    json['isShiftPressed'] = isShiftPressed; // ✅ 保存Shift键状态
    if (fillColor != null) {
      json['fillColor'] = fillColor!.value; // ✅ 保存填充颜色
    }
    return json;
  }

  factory TriangleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    final fillColorValue = json['fillColor'] as int?;
    final fillColor = fillColorValue != null 
        ? Color(fillColorValue) 
        : null; // ✅ 读取填充颜色
    // ✅ 从保存的点列表创建三角形（会自动优化为三个顶点）
    return TriangleStroke(
      points: stroke.points,
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      isShiftPressed: json['isShiftPressed'] as bool? ?? false, // ✅ 读取Shift键状态
      fillColor: fillColor,
    );
  }
}

/// ✅ 菱形笔迹
class DiamondStroke extends Stroke {
  DiamondStroke({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
    this.fillColor, // ✅ 填充颜色（可选）
  }) : super(
          points: _calculateDiamondPoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.diamond,
          pressureEnabled: false,
        );
  
  final Color? fillColor; // ✅ 填充颜色（null表示不填充）

  static List<Offset> _calculateDiamondPoints(Offset start, Offset end) {
    final center = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );
    final width = (end.dx - start.dx).abs() / 2;
    final height = (end.dy - start.dy).abs() / 2;
    
    // 菱形的四个顶点
    final top = Offset(center.dx, center.dy - height);
    final right = Offset(center.dx + width, center.dy);
    final bottom = Offset(center.dx, center.dy + height);
    final left = Offset(center.dx - width, center.dy);
    
    return [top, right, bottom, left, top]; // 闭合
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'diamond';
    if (fillColor != null) {
      json['fillColor'] = fillColor!.value; // ✅ 保存填充颜色
    }
    return json;
  }

  factory DiamondStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    final fillColorValue = json['fillColor'] as int?;
    final fillColor = fillColorValue != null 
        ? Color(fillColorValue) 
        : null; // ✅ 读取填充颜色
    if (stroke.points.length < 4) {
      return DiamondStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
        fillColor: fillColor,
      );
    }
    // 从菱形点计算起始点和结束点
    final firstPoint = stroke.points.first;
    final lastPoint = stroke.points[stroke.points.length - 2]; // 倒数第二个点
    return DiamondStroke(
      startPoint: firstPoint,
      endPoint: lastPoint,
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
      fillColor: fillColor,
    );
  }
}

/// ✅ 自由多边形笔迹（使用普通 Stroke，但标记为 freePolygon）
class FreePolygonStroke extends Stroke {
  FreePolygonStroke({
    required List<Offset> points,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
  }) : super(
          points: points,
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.freePolygon,
          pressureEnabled: false,
        );

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'freePolygon';
    return json;
  }

  factory FreePolygonStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    return FreePolygonStroke(
      points: stroke.points,
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
    );
  }
}

