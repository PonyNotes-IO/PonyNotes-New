import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../../third_party/saber_core/data/editor/editor_core_info.dart';
import '../../third_party/saber_core/data/editor/page.dart';
import '../../third_party/saber_core/data/editor/shape_strokes.dart';
import '../../third_party/saber_core/data/editor/stroke_extensions.dart';
import '../../third_party/saber_core/data/tools/tool.dart';

/// 页面预览组件（缩略图渲染）
/// 
/// 参考 Saber 源版的 CanvasPreview 实现，用于在左侧页面管理器中显示页面缩略图。
/// 使用简化的渲染逻辑，只绘制笔迹和基本背景，不包含完整的交互功能。
class CanvasPreview extends StatelessWidget implements PreferredSizeWidget {
  const CanvasPreview({
    super.key,
    required this.coreInfo,
    this.pageIndex = 0,
    this.height,
    this.highQuality = false,
  });

  final EditorCoreInfo coreInfo;
  final int pageIndex;
  final double? height;
  
  /// 是否使用高质量渲染
  final bool highQuality;

  EditorPage? get _page {
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) {
      return null;
    }
    return coreInfo.pages[pageIndex];
  }

  Size get _pageSize => _page?.size ?? EditorPage.defaultSize;

  @override
  Size get preferredSize => Size(_pageSize.width, height ?? _pageSize.height);

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return Container(
        width: preferredSize.width,
        height: preferredSize.height,
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.error_outline, color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      width: preferredSize.width,
      height: height ?? preferredSize.height,
      child: CustomPaint(
        painter: _CanvasPreviewPainter(
          page: page,
          coreInfo: coreInfo,
          highQuality: highQuality,
        ),
        size: Size(preferredSize.width, height ?? preferredSize.height),
      ),
    );
  }
}

/// 预览画布绘制器
class _CanvasPreviewPainter extends CustomPainter {
  _CanvasPreviewPainter({
    required this.page,
    required this.coreInfo,
    this.highQuality = false,
  });

  final EditorPage page;
  final EditorCoreInfo coreInfo;
  final bool highQuality;

  @override
  void paint(Canvas canvas, Size size) {
    // 计算缩放比例
    final double scaleX = size.width / page.size.width;
    final double scaleY = size.height / page.size.height;
    final double scale = math.min(scaleX, scaleY);
    
    final double drawWidth = page.size.width * scale;
    final double drawHeight = page.size.height * scale;
    final double offsetX = (size.width - drawWidth) / 2;
    final double offsetY = (size.height - drawHeight) / 2;

    // 保存画布状态
    canvas.save();
    
    // 裁剪到绘制区域
    canvas.clipRect(Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight));
    
    // 绘制背景
    _drawBackground(canvas, Size(drawWidth, drawHeight), offsetX, offsetY, scale);
    
    // 绘制笔迹
    for (final stroke in page.strokes) {
      _drawStroke(canvas, stroke, scale, offsetX, offsetY);
    }
    
    // 绘制文本框指示（简化显示）
    for (final textBox in page.textBoxes) {
      _drawTextBoxIndicator(canvas, textBox.rect, scale, offsetX, offsetY);
    }
    
    // 恢复画布状态
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size drawSize, double offsetX, double offsetY, double scale) {
    // 如果有PDF背景，绘制灰色占位符
    if (page.backgroundImage != null) {
      final bgPaint = Paint()
        ..color = Colors.grey.shade100;
      canvas.drawRect(
        Rect.fromLTWH(offsetX, offsetY, drawSize.width, drawSize.height),
        bgPaint,
      );
      
      // 绘制PDF图标指示
      final iconPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.fill;
      final iconSize = math.min(drawSize.width, drawSize.height) * 0.3;
      final iconRect = Rect.fromCenter(
        center: Offset(offsetX + drawSize.width / 2, offsetY + drawSize.height / 2),
        width: iconSize,
        height: iconSize * 1.3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(iconRect, Radius.circular(iconSize * 0.1)),
        iconPaint,
      );
      return;
    }

    // 绘制背景色
    final Paint bgPaint = Paint()
      ..color = coreInfo.backgroundColor ?? const Color(0xFFFCFCFC);
    canvas.drawRect(
      Rect.fromLTWH(offsetX, offsetY, drawSize.width, drawSize.height),
      bgPaint,
    );

    // 绘制背景图案（简化版，减少线条数量）
    final CanvasBackgroundPattern pattern = coreInfo.backgroundPattern;
    final double lineHeight = coreInfo.lineHeight.toDouble();

    if (pattern == CanvasBackgroundPattern.none) {
      return;
    }

    final Paint linePaint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 0.5;

    final double visualSpacing = lineHeight * scale;
    // 预览中减少线条数量，每隔2条线绘制1条
    final int skipLines = visualSpacing < 5 ? 3 : (visualSpacing < 10 ? 2 : 1);

    switch (pattern) {
      case CanvasBackgroundPattern.lined:
        int lineCount = 0;
        for (double y = visualSpacing; y < drawSize.height; y += visualSpacing) {
          lineCount++;
          if (lineCount % skipLines != 0) continue;
          canvas.drawLine(
            Offset(offsetX, offsetY + y),
            Offset(offsetX + drawSize.width, offsetY + y),
            linePaint,
          );
        }
        break;
      case CanvasBackgroundPattern.grid:
        int lineCount = 0;
        for (double y = visualSpacing * 2; y < drawSize.height; y += visualSpacing) {
          lineCount++;
          if (lineCount % skipLines != 0) continue;
          canvas.drawLine(
            Offset(offsetX, offsetY + y),
            Offset(offsetX + drawSize.width, offsetY + y),
            linePaint,
          );
        }
        lineCount = 0;
        for (double x = 0; x < drawSize.width; x += visualSpacing) {
          lineCount++;
          if (lineCount % skipLines != 0) continue;
          canvas.drawLine(
            Offset(offsetX + x, offsetY + visualSpacing * 2),
            Offset(offsetX + x, offsetY + drawSize.height),
            linePaint,
          );
        }
        break;
      case CanvasBackgroundPattern.dots:
        // 预览中点阵可以省略
        break;
      case CanvasBackgroundPattern.none:
        break;
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.isEmpty) return;
    
    // 跳过橡皮擦和激光笔
    if (stroke.toolId == ToolId.eraser || stroke.toolId == ToolId.laserPointer) {
      return;
    }
    
    // 处理形状笔迹
    if (stroke is LineStroke || stroke is ArrowLineStroke) {
      _drawLineStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is RectangleStroke) {
      _drawRectangleStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is CircleStroke) {
      _drawCircleStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is TriangleStroke) {
      _drawTriangleStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is DiamondStroke) {
      _drawDiamondStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    }
    
    // 普通笔迹
    Color strokeColor = stroke.color;
    
    // 荧光笔使用半透明
    if (stroke.toolId == ToolId.highlighter) {
      strokeColor = stroke.color.withValues(alpha: 0.4);
    }
    
    // 使用 perfect_freehand 生成平滑路径
    final smoothPath = stroke.getSmoothPath(isComplete: true);
    if (smoothPath.getBounds().isEmpty) {
      // 单点绘制
      if (stroke.points.isNotEmpty) {
        final p = _transform(stroke.points.first, scale, offsetX, offsetY);
        final paint = Paint()
          ..color = strokeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, stroke.strokeWidth * scale / 2, paint);
      }
      return;
    }
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(smoothPath, paint);
    canvas.restore();
  }

  void _drawLineStroke(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    final lineStroke = stroke is LineStroke ? stroke : (stroke as ArrowLineStroke);
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = lineStroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineStroke.strokeWidth
      ..strokeCap = StrokeCap.round;
    
    canvas.drawLine(lineStroke.startPoint, lineStroke.endPoint, paint);
    
    // 简化箭头绘制
    if (stroke is ArrowLineStroke) {
      final arrowSize = lineStroke.strokeWidth * 2;
      final dx = lineStroke.endPoint.dx - lineStroke.startPoint.dx;
      final dy = lineStroke.endPoint.dy - lineStroke.startPoint.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) {
        final unitX = dx / length;
        final unitY = dy / length;
        final arrowAngle = math.pi / 6;
        final cosAngle = math.cos(arrowAngle);
        final sinAngle = math.sin(arrowAngle);
        
        final left = Offset(
          lineStroke.endPoint.dx - arrowSize * (unitX * cosAngle - unitY * sinAngle),
          lineStroke.endPoint.dy - arrowSize * (unitY * cosAngle + unitX * sinAngle),
        );
        final right = Offset(
          lineStroke.endPoint.dx - arrowSize * (unitX * cosAngle + unitY * sinAngle),
          lineStroke.endPoint.dy - arrowSize * (unitY * cosAngle - unitX * sinAngle),
        );
        
        final arrowPath = Path()
          ..moveTo(lineStroke.endPoint.dx, lineStroke.endPoint.dy)
          ..lineTo(left.dx, left.dy)
          ..lineTo(right.dx, right.dy)
          ..close();
        
        canvas.drawPath(arrowPath, Paint()
          ..color = lineStroke.color
          ..style = PaintingStyle.fill);
      }
    }
    
    canvas.restore();
  }

  void _drawRectangleStroke(Canvas canvas, RectangleStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.rect.isEmpty) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    if (stroke.fillColor != null) {
      canvas.drawRect(stroke.rect, Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill);
    }
    
    canvas.drawRect(stroke.rect, Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth);
    
    canvas.restore();
  }

  void _drawCircleStroke(Canvas canvas, CircleStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 2) return;
    
    final left = stroke.points.map((p) => p.dx).reduce(math.min);
    final top = stroke.points.map((p) => p.dy).reduce(math.min);
    final right = stroke.points.map((p) => p.dx).reduce(math.max);
    final bottom = stroke.points.map((p) => p.dy).reduce(math.max);
    final rect = Rect.fromLTRB(left, top, right, bottom);
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    if (stroke.fillColor != null) {
      canvas.drawOval(rect, Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill);
    }
    
    canvas.drawOval(rect, Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth);
    
    canvas.restore();
  }

  void _drawTriangleStroke(Canvas canvas, TriangleStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 3) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final path = Path()
      ..moveTo(stroke.point1.dx, stroke.point1.dy)
      ..lineTo(stroke.point2.dx, stroke.point2.dy)
      ..lineTo(stroke.point3.dx, stroke.point3.dy)
      ..close();
    
    if (stroke.fillColor != null) {
      canvas.drawPath(path, Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill);
    }
    
    canvas.drawPath(path, Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth);
    
    canvas.restore();
  }

  void _drawDiamondStroke(Canvas canvas, DiamondStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 4) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final path = Path()
      ..moveTo(stroke.points[0].dx, stroke.points[0].dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    path.close();
    
    if (stroke.fillColor != null) {
      canvas.drawPath(path, Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill);
    }
    
    canvas.drawPath(path, Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth);
    
    canvas.restore();
  }

  void _drawTextBoxIndicator(Canvas canvas, Rect rect, double scale, double offsetX, double offsetY) {
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    // 绘制文本框区域指示
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);
    
    canvas.restore();
  }

  Offset _transform(Offset p, double scale, double offsetX, double offsetY) {
    return Offset(
      offsetX + p.dx * scale,
      offsetY + p.dy * scale,
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasPreviewPainter oldDelegate) {
    return page.strokes.length != oldDelegate.page.strokes.length ||
           page.textBoxes.length != oldDelegate.page.textBoxes.length ||
           (page.backgroundImage != null) != (oldDelegate.page.backgroundImage != null);
  }
}
