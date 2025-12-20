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
  }) : super(
          points: [startPoint, endPoint],
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.line,
          pressureEnabled: false,
        );

  Offset get startPoint => points.isNotEmpty ? points.first : Offset.zero;
  Offset get endPoint => points.length > 1 ? points[1] : Offset.zero;

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'line';
    return json;
  }

  factory LineStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    if (stroke.points.length < 2) {
      return LineStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
      );
    }
    return LineStroke(
      startPoint: stroke.points.first,
      endPoint: stroke.points[1],
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
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
  }) : super(
          points: _calculateRectanglePoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.rectangle,
          pressureEnabled: false,
        );

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
    return json;
  }

  factory RectangleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    if (stroke.points.length < 2) {
      return RectangleStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
      );
    }
    return RectangleStroke(
      startPoint: stroke.points.first,
      endPoint: stroke.points[stroke.points.length - 2], // 倒数第二个点（最后一个点是闭合点）
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
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
  }) : super(
          points: _calculateCirclePoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.circle,
          pressureEnabled: false,
        );

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
    return json;
  }

  factory CircleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    if (stroke.points.length < 2) {
      return CircleStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
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
    );
  }
}

/// ✅ 三角形笔迹（支持任意三角形，通过三个点定义）
class TriangleStroke extends Stroke {
  TriangleStroke({
    required Offset point1,
    required Offset point2,
    required Offset point3,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
  }) : super(
          points: [point1, point2, point3, point1], // 闭合三角形
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.triangle,
          pressureEnabled: false,
        );

  // ✅ 兼容旧版本的构造函数（基于start和end的矩形区域）
  TriangleStroke.fromRect({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
  }) : super(
          points: _calculateTrianglePointsFromRect(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.triangle,
          pressureEnabled: false,
        );

  static List<Offset> _calculateTrianglePointsFromRect(Offset start, Offset end) {
    // ✅ 基于start和end的矩形区域（兼容旧版本）
    final left = min(start.dx, end.dx);
    final top = min(start.dy, end.dy);
    final right = max(start.dx, end.dx);
    final bottom = max(start.dy, end.dy);
    
    // 三角形的三个顶点：左上角、右上角、底部中心
    final topLeft = Offset(left, top);
    final topRight = Offset(right, top);
    final bottomCenter = Offset((left + right) / 2, bottom);
    
    return [topLeft, topRight, bottomCenter, topLeft]; // 闭合
  }

  Offset get point1 => points.isNotEmpty ? points[0] : Offset.zero;
  Offset get point2 => points.length > 1 ? points[1] : Offset.zero;
  Offset get point3 => points.length > 2 ? points[2] : Offset.zero;

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'triangle';
    return json;
  }

  factory TriangleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    if (stroke.points.length < 3) {
      // ✅ 兼容旧版本：如果只有2个点，使用fromRect构造函数
      if (stroke.points.length == 2) {
        return TriangleStroke.fromRect(
          startPoint: stroke.points[0],
          endPoint: stroke.points[1],
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          toolId: stroke.toolId,
        );
      }
      // 如果只有1个点或没有点，使用默认值
      return TriangleStroke(
        point1: stroke.points.isNotEmpty ? stroke.points[0] : Offset.zero,
        point2: stroke.points.length > 1 ? stroke.points[1] : const Offset(100, 0),
        point3: stroke.points.length > 2 ? stroke.points[2] : const Offset(50, 100),
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
      );
    }
    // ✅ 新版本：从三个点创建三角形（最后一个点是闭合点，忽略）
    final point1 = stroke.points[0];
    final point2 = stroke.points[1];
    final point3 = stroke.points[2];
    return TriangleStroke(
      point1: point1,
      point2: point2,
      point3: point3,
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      toolId: stroke.toolId,
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
  }) : super(
          points: _calculateDiamondPoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.diamond,
          pressureEnabled: false,
        );

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
    return json;
  }

  factory DiamondStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    if (stroke.points.length < 4) {
      return DiamondStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
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

