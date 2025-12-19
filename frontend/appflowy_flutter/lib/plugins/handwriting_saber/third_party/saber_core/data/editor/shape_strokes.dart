import 'dart:math';

import 'package:flutter/material.dart';

import 'page.dart';
import '../tools/tool.dart';

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
    final radius = (start - end).distance / 2;
    
    // 生成圆形点（24个点）
    final points = <Offset>[];
    for (int i = 0; i <= 24; i++) {
      final angle = i / 24 * 2 * pi;
      points.add(Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
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

/// ✅ 三角形笔迹
class TriangleStroke extends Stroke {
  TriangleStroke({
    required Offset startPoint,
    required Offset endPoint,
    required Color color,
    required double strokeWidth,
    ToolId? toolId,
  }) : super(
          points: _calculateTrianglePoints(startPoint, endPoint),
          color: color,
          strokeWidth: strokeWidth,
          toolId: toolId ?? ToolId.triangle,
          pressureEnabled: false,
        );

  static List<Offset> _calculateTrianglePoints(Offset start, Offset end) {
    final center = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );
    final width = (end.dx - start.dx).abs();
    final height = (end.dy - start.dy).abs();
    final radius = max(width, height) / 2;
    
    // 等边三角形的三个顶点
    final top = Offset(center.dx, center.dy - radius);
    final bottomLeft = Offset(center.dx - radius * cos(pi / 6), center.dy + radius * sin(pi / 6));
    final bottomRight = Offset(center.dx + radius * cos(pi / 6), center.dy + radius * sin(pi / 6));
    
    return [top, bottomRight, bottomLeft, top]; // 闭合
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['shape'] = 'triangle';
    return json;
  }

  factory TriangleStroke.fromJson(Map<String, dynamic> json) {
    final stroke = Stroke.fromJson(json);
    if (stroke.points.length < 3) {
      return TriangleStroke(
        startPoint: stroke.points.isNotEmpty ? stroke.points.first : Offset.zero,
        endPoint: stroke.points.isNotEmpty ? stroke.points.last : Offset.zero,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        toolId: stroke.toolId,
      );
    }
    // 从三角形点计算起始点和结束点
    final firstPoint = stroke.points.first;
    final lastPoint = stroke.points[stroke.points.length - 2]; // 倒数第二个点
    return TriangleStroke(
      startPoint: firstPoint,
      endPoint: lastPoint,
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

