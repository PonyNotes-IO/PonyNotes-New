import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import 'page.dart';
import '../tools/tool.dart';

/// Stroke 扩展方法，用于生成平滑路径
extension StrokeExtensions on Stroke {
  /// 获取平滑的多边形路径（使用 perfect_freehand）
  List<Offset> getSmoothPolygon({bool isComplete = true}) {
    if (points.isEmpty) {
      return [];
    }

    // 将 Offset 转换为 PointVector（无压力信息）
    final pointVectors = points.map((p) => pf.PointVector(p.dx, p.dy)).toList();

    // 根据工具类型获取 StrokeOptions
    final options = _getStrokeOptionsForTool(toolId, strokeWidth);

    // 使用 perfect_freehand 生成平滑多边形
    final polygon = pf.getStroke(
      pointVectors,
      options: options.copyWith(isComplete: isComplete),
    );

    return polygon;
  }

  /// 将多边形转换为平滑路径
  Path getSmoothPath({bool isComplete = true}) {
    final polygon = getSmoothPolygon(isComplete: isComplete);
    if (polygon.isEmpty) {
      return Path();
    }

    if (isComplete && polygon.length > 2) {
      return _smoothPathFromPolygon(polygon);
    }

    // 未完成时使用直线连接
    final path = Path();
    if (polygon.isNotEmpty) {
      path.moveTo(polygon.first.dx, polygon.first.dy);
      for (var i = 1; i < polygon.length; i++) {
        path.lineTo(polygon[i].dx, polygon[i].dy);
      }
    }
    return path;
  }

  /// 从多边形生成平滑路径（使用二次贝塞尔曲线）
  /// perfect_freehand 生成的多边形已经是闭合的，直接转换为路径即可
  static Path _smoothPathFromPolygon(List<Offset> polygon) {
    if (polygon.isEmpty) {
      return Path();
    }
    if (polygon.length == 1) {
      return Path()..addOval(Rect.fromCircle(center: polygon.first, radius: 1));
    }

    // perfect_freehand 生成的多边形已经是闭合的，直接使用 addPolygon
    return Path()..addPolygon(polygon, true);
  }

  /// 根据工具类型获取 StrokeOptions
  static pf.StrokeOptions _getStrokeOptionsForTool(ToolId? toolId, double strokeWidth) {
    final baseSize = strokeWidth;

    switch (toolId) {
      case ToolId.highlighter:
        // 荧光笔：更大的尺寸
        return pf.StrokeOptions(size: baseSize * 2);
      case ToolId.pencil:
        // 铅笔：较小的平滑度和流线化
        return pf.StrokeOptions(
          size: baseSize,
          streamline: 0.1,
          start: pf.StrokeEndOptions.start(taperEnabled: true, customTaper: 1),
          end: pf.StrokeEndOptions.end(taperEnabled: true, customTaper: 1),
        );
      case ToolId.ballpointPen:
        // 圆珠笔：默认选项
        return pf.StrokeOptions(size: baseSize);
      case ToolId.laserPointer:
        // 激光笔：使用平滑和流线化
        return pf.StrokeOptions(
          size: baseSize,
          smoothing: 0.7,
          streamline: 0.7,
        );
      case ToolId.eraser:
        // 橡皮擦不应该被绘制
        return pf.StrokeOptions(size: baseSize);
      case ToolId.fountainPen:
      default:
        // 钢笔：默认选项
        return pf.StrokeOptions(size: baseSize);
    }
  }
}

