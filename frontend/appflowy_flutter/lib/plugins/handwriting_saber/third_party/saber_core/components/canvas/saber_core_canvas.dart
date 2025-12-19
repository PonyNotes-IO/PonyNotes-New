import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../canvas/canvas_background_pattern.dart';
import '../canvas/image/pdf_editor_image.dart';
import '../../data/editor/editor_core_info.dart';
import '../../data/editor/page.dart';
import '../../data/editor/shape_strokes.dart';
import '../../data/editor/stroke_extensions.dart';
import '../../data/tools/tool.dart';

/// 简化版的 Saber 画布组件，用于 PoC 阶段。
///
/// 目前仅支持：
/// - 单页面绘制
/// - 简单笔迹渲染
/// - 由外部提供当前正在绘制的一笔（可选）
class SaberCoreCanvas extends StatelessWidget {
  const SaberCoreCanvas({
    super.key,
    required this.coreInfo,
    this.currentStroke,
  });

  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;

  @override
  Widget build(BuildContext context) {
    final EditorPage page = coreInfo.firstPage;
    return LayoutBuilder(
      builder: (context, constraints) {
        // ✅ 计算当前缩放级别
        final double scaleX = constraints.maxWidth / page.size.width;
        final double scaleY = constraints.maxHeight / page.size.height;
        final double scale = scaleX < scaleY ? scaleX : scaleY;
        
        // ✅ 如果有 PDF 背景图片，使用 Stack 叠加显示
        if (page.backgroundImage != null) {
          return Stack(
            children: [
              // PDF 背景层
              Positioned.fill(
                child: _buildPdfBackground(page.backgroundImage!, scale),
              ),
              // 画布层（绘制笔迹）
              CustomPaint(
                painter: _SaberCoreCanvasPainter(
                  page: page,
                  coreInfo: coreInfo,
                  currentStroke: currentStroke,
                  currentScale: scale,
                  laserStrokes: coreInfo.laserStrokes,
                ),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ],
          );
        }
        
        return CustomPaint(
          painter: _SaberCoreCanvasPainter(
            page: page,
            coreInfo: coreInfo,
            currentStroke: currentStroke,
            currentScale: scale,  // ✅ 传递缩放级别
            laserStrokes: coreInfo.laserStrokes,  // ✅ 传递激光笔笔迹列表
          ),
        );
      },
    );
  }
  
  /// ✅ 构建 PDF 背景 Widget
  Widget _buildPdfBackground(PdfEditorImage pdfImage, double scale) {
    // 异步加载 PDF 文档
    pdfImage.loadPdfDocument();
    
    // 计算 PDF 显示区域
    final dstRect = pdfImage.dstRect ?? Rect.fromLTWH(
      0,
      0,
      pdfImage.naturalSize.width,
      pdfImage.naturalSize.height,
    );
    
    return Positioned(
      left: dstRect.left * scale,
      top: dstRect.top * scale,
      width: dstRect.width * scale,
      height: dstRect.height * scale,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: pdfImage.naturalSize.width,
            height: pdfImage.naturalSize.height,
            child: pdfImage.buildPdfPageWidget(
              boxFit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _SaberCoreCanvasPainter extends CustomPainter {
  _SaberCoreCanvasPainter({
    required this.page,
    required this.coreInfo,
    this.currentStroke,
    this.currentScale = 1.0,  // ✅ 添加缩放级别，用于判断是否使用铅笔 shader
    this.laserStrokes = const [],  // ✅ 激光笔笔迹列表
  });

  final EditorPage page;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final double currentScale;  // ✅ 当前缩放级别
  final List<Stroke> laserStrokes;  // ✅ 激光笔笔迹列表

  @override
  void paint(Canvas canvas, Size size) {
    // 简单按比例映射到当前画布大小
    final double scaleX = size.width / page.size.width;
    final double scaleY = size.height / page.size.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final double drawWidth = page.size.width * scale;
    final double drawHeight = page.size.height * scale;
    final double offsetX = (size.width - drawWidth) / 2;
    final double offsetY = (size.height - drawHeight) / 2;

    // 保存画布状态
    canvas.save();
    
    // 裁剪到绘制区域
    canvas.clipRect(Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight));
    
    // 绘制背景
    _drawBackground(canvas, Size(drawWidth, drawHeight), offsetX, offsetY);
    
          // ✅ 分离荧光笔和其他笔迹，需要特殊处理
          // 激光笔笔迹已经从 laserStrokes 列表获取，不需要从 page.strokes 中分离
          final highlighterStrokes = <Stroke>[];
          final otherStrokes = <Stroke>[];

          for (final stroke in page.strokes) {
            if (stroke.toolId == ToolId.highlighter) {
              highlighterStrokes.add(stroke);
            } else {
              otherStrokes.add(stroke);
            }
          }
    
    // 先绘制荧光笔（使用半透明叠加效果）
    if (highlighterStrokes.isNotEmpty) {
      final canvasRect = Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
      final layerPaint = Paint()
        ..blendMode = BlendMode.darken
        ..color = Colors.white.withValues(alpha: 100); // Highlighter.alpha = 100
      
      canvas.saveLayer(canvasRect, layerPaint);
      
      Color? lastColor;
      for (final stroke in highlighterStrokes) {
        final color = stroke.color.withValues(alpha: 1.0);
        
        if (color != lastColor) {
          if (lastColor != null) {
            canvas.restore();
            canvas.saveLayer(canvasRect, layerPaint);
          }
          lastColor = color;
        }
        
        _drawStrokePath(canvas, stroke, scale, offsetX, offsetY, color, stroke.strokeWidth * scale * 2);
      }
      
      canvas.restore();
    }
    
    // ✅ 绘制激光笔笔迹（发光效果，从 laserStrokes 列表获取）
    for (final stroke in laserStrokes) {
      _drawLaserStroke(canvas, stroke, scale, offsetX, offsetY);
    }
    
    // 再绘制其他笔迹
    for (final stroke in otherStrokes) {
      _drawStroke(canvas, stroke, scale, offsetX, offsetY);
    }
    
    // 绘制当前正在绘制的笔迹（使用未完成状态，实时显示）
    if (currentStroke != null) {
      if (currentStroke!.toolId == ToolId.highlighter) {
        final canvasRect = Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
        final layerPaint = Paint()
          ..blendMode = BlendMode.darken
          ..color = Colors.white.withValues(alpha: 100);
        canvas.saveLayer(canvasRect, layerPaint);
        _drawStrokePathIncomplete(
          canvas,
          currentStroke!,
          scale,
          offsetX,
          offsetY,
          currentStroke!.color.withValues(alpha: 1.0),
          currentStroke!.strokeWidth * scale * 2,
        );
        canvas.restore();
      } else if (currentStroke!.toolId == ToolId.laserPointer) {
        _drawLaserStroke(canvas, currentStroke!, scale, offsetX, offsetY);
      } else if (currentStroke!.toolId == ToolId.rectangle || 
                 currentStroke!.toolId == ToolId.circle || 
                 currentStroke!.toolId == ToolId.triangle || 
                 currentStroke!.toolId == ToolId.diamond) {
        // ✅ 形状工具：实时绘制形状预览
        _drawShapePreview(canvas, currentStroke!, scale, offsetX, offsetY);
      } else {
        _drawStrokeIncomplete(canvas, currentStroke!, scale, offsetX, offsetY);
      }
    }
    
    // 恢复画布状态
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size drawSize, double offsetX, double offsetY) {
    // ✅ 如果有 PDF 背景图片，不绘制背景色和背景图案
    if (page.backgroundImage != null) {
      return;
    }
    
    // 绘制背景色
    final Paint bgPaint = Paint()
      ..color = coreInfo.backgroundColor ?? const Color(0xFFFCFCFC);
    canvas.drawRect(
      Rect.fromLTWH(offsetX, offsetY, drawSize.width, drawSize.height),
      bgPaint,
    );

    // 绘制背景图案
    final CanvasBackgroundPattern pattern = coreInfo.backgroundPattern;
    final int lineHeight = coreInfo.lineHeight;
    final int lineThickness = coreInfo.lineThickness;
    
    if (pattern == CanvasBackgroundPattern.none) {
      return;
    }

    final Paint linePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.2)
      ..strokeWidth = lineThickness.toDouble();

    switch (pattern) {
      case CanvasBackgroundPattern.lined:
        // 绘制横线
        for (double y = lineHeight * 2; y < drawSize.height; y += lineHeight) {
          canvas.drawLine(
            Offset(offsetX, offsetY + y),
            Offset(offsetX + drawSize.width, offsetY + y),
            linePaint,
          );
        }
        break;
      case CanvasBackgroundPattern.grid:
        // 绘制网格
        for (double y = lineHeight * 2; y < drawSize.height; y += lineHeight) {
          canvas.drawLine(
            Offset(offsetX, offsetY + y),
            Offset(offsetX + drawSize.width, offsetY + y),
            linePaint,
          );
        }
        for (double x = 0; x < drawSize.width; x += lineHeight) {
          canvas.drawLine(
            Offset(offsetX + x, offsetY + lineHeight * 2),
            Offset(offsetX + x, offsetY + drawSize.height),
            linePaint,
          );
        }
        break;
      case CanvasBackgroundPattern.dots:
        // 绘制点阵
        for (double y = lineHeight * 2; y <= drawSize.height; y += lineHeight) {
          for (double x = 0; x <= drawSize.width; x += lineHeight) {
            canvas.drawCircle(
              Offset(offsetX + x, offsetY + y),
              lineThickness.toDouble() * 2 / 3,
              linePaint,
            );
          }
        }
        break;
      case CanvasBackgroundPattern.none:
        break;
    }
  }

  /// 绘制激光笔笔迹（发光效果）
  void _drawLaserStroke(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.isEmpty) {
      return;
    }
    
    // 使用 perfect_freehand 生成平滑路径
    final smoothPath = stroke.getSmoothPath(isComplete: true);
    if (smoothPath.getBounds().isEmpty) {
      return;
    }
    
    // 应用变换
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    // 绘制外层（红色，带模糊效果）
    final outerPaint = Paint()
      ..color = stroke.color
      ..maskFilter = MaskFilter.blur(
        BlurStyle.solid,
        stroke.strokeWidth * 0.4,
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(smoothPath, outerPaint);
    
    // 绘制内层（白色，更细）
    final innerPolygon = stroke.getSmoothPolygon(isComplete: true);
    if (innerPolygon.isNotEmpty) {
      // 使用更小的尺寸生成内层多边形
      final innerOptions = pf.StrokeOptions(
        size: stroke.strokeWidth * 0.4,
        smoothing: 0.7,
        streamline: 0.7,
      );
      final pointVectors = stroke.points.map((p) => pf.PointVector(p.dx, p.dy)).toList();
      final innerPoly = pf.getStroke(pointVectors, options: innerOptions);
      if (innerPoly.isNotEmpty) {
        final innerPath = Path()..addPolygon(innerPoly, true);
        final innerPaint = Paint()
          ..color = const Color(0xDDffffff)
          ..style = PaintingStyle.fill;
        canvas.drawPath(innerPath, innerPaint);
      }
    }
    
    canvas.restore();
  }

  /// 绘制单个笔迹（非荧光笔、非激光笔，已完成）
  void _drawStroke(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.isEmpty || 
        stroke.toolId == ToolId.highlighter || 
        stroke.toolId == ToolId.laserPointer ||
        stroke.toolId == ToolId.eraser) {
      return;
    }
    
    // ✅ 检查是否是形状笔迹（RectangleStroke, CircleStroke 等）
    if (stroke is RectangleStroke) {
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
    } else if (stroke is FreePolygonStroke) {
      // ✅ 自由多边形使用普通绘制逻辑，继续执行下面的代码
    }
    
    // 根据工具类型应用不同的绘制样式
    Color strokeColor = stroke.color;
    double strokeWidth = stroke.strokeWidth * scale;
    Paint? customPaint;  // ✅ 用于铅笔的特殊绘制
    
    if (stroke.toolId != null) {
      switch (stroke.toolId!) {
        case ToolId.pencil:
          // ✅ 铅笔：实现 Saber 原版的铅笔效果
          // 获取背景色（从 coreInfo 或默认白色）
          final background = coreInfo.backgroundColor ?? Colors.white;
          if (_shouldUsePencilEffect(stroke.strokeWidth)) {
            // 使用模糊效果和颜色混合来模拟铅笔纹理
            strokeColor = Color.lerp(background, stroke.color, 0.6)!;
            customPaint = Paint()
              ..color = strokeColor
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                (stroke.strokeWidth * 0.2).clamp(0.0, 3.0),
              )
              ..style = PaintingStyle.fill;
          } else {
            // 缩放较小时，使用简单的颜色混合
            strokeColor = Color.lerp(background, stroke.color, 0.6)!;
          }
          break;
        case ToolId.ballpointPen:
          // ✅ 圆珠笔：固定线宽，不支持压感，线条更均匀
          // 圆珠笔的线条应该比钢笔稍微细一点，且没有压感变化
          strokeWidth = stroke.strokeWidth * scale * 0.85;
          break;
        case ToolId.fountainPen:
        default:
          // ✅ 钢笔：支持压感变化，线条粗细会根据压力变化
          // 钢笔的线条应该稍微粗一点，且有压感变化效果
          // 如果支持压感，在绘制时会根据点的压力调整线宽
          strokeWidth = stroke.strokeWidth * scale;
          break;
      }
    }
    
    // ✅ 如果铅笔有自定义 Paint，使用它；否则使用默认绘制
    if (customPaint != null && stroke.toolId == ToolId.pencil) {
      _drawStrokePathWithPaint(canvas, stroke, scale, offsetX, offsetY, customPaint);
    } else {
      _drawStrokePath(canvas, stroke, scale, offsetX, offsetY, strokeColor, strokeWidth);
    }
  }
  
  /// ✅ 判断是否使用铅笔特殊效果（参考 Saber 的 shouldUsePencilShader）
  bool _shouldUsePencilEffect(double strokeSize) {
    const double zoomThreshold = 0.9;
    return currentScale >= zoomThreshold && (strokeSize * currentScale) >= 3;
  }
  
  /// ✅ 使用自定义 Paint 绘制笔迹路径（用于铅笔）
  void _drawStrokePathWithPaint(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY, Paint paint) {
    if (stroke.points.isEmpty) {
      return;
    }
    
    final smoothPath = stroke.getSmoothPath(isComplete: true);
    if (smoothPath.getBounds().isEmpty) {
      if (stroke.points.isNotEmpty) {
        final Offset p = _transform(stroke.points.first, scale, offsetX, offsetY);
        canvas.drawCircle(p, paint.maskFilter != null ? stroke.strokeWidth / 2 : stroke.strokeWidth / 2, paint);
      }
      return;
    }
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    canvas.drawPath(smoothPath, paint);
    canvas.restore();
  }
  
  /// 绘制正在绘制的笔迹（未完成状态）
  void _drawStrokeIncomplete(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.isEmpty || 
        stroke.toolId == ToolId.highlighter || 
        stroke.toolId == ToolId.laserPointer ||
        stroke.toolId == ToolId.eraser) {
      return;
    }
    
    // 根据工具类型应用不同的绘制样式
    Color strokeColor = stroke.color;
    double strokeWidth = stroke.strokeWidth * scale;
    Paint? customPaint;  // ✅ 用于铅笔的特殊绘制
    
    if (stroke.toolId != null) {
      switch (stroke.toolId!) {
        case ToolId.pencil:
          // ✅ 铅笔：实现 Saber 原版的铅笔效果
          // 获取背景色（从 coreInfo 或默认白色）
          final background = coreInfo.backgroundColor ?? Colors.white;
          if (_shouldUsePencilEffect(stroke.strokeWidth)) {
            strokeColor = Color.lerp(background, stroke.color, 0.6)!;
            customPaint = Paint()
              ..color = strokeColor
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                (stroke.strokeWidth * 0.2).clamp(0.0, 3.0),
              )
              ..style = PaintingStyle.fill;
          } else {
            strokeColor = Color.lerp(background, stroke.color, 0.6)!;
          }
          break;
        case ToolId.ballpointPen:
          strokeWidth = stroke.strokeWidth * scale * 0.9;
          break;
        case ToolId.fountainPen:
        default:
          break;
      }
    }
    
    // ✅ 如果铅笔有自定义 Paint，使用它；否则使用默认绘制
    if (customPaint != null && stroke.toolId == ToolId.pencil) {
      _drawStrokePathIncompleteWithPaint(canvas, stroke, scale, offsetX, offsetY, customPaint);
    } else {
      _drawStrokePathIncomplete(canvas, stroke, scale, offsetX, offsetY, strokeColor, strokeWidth);
    }
  }
  
  /// ✅ 使用自定义 Paint 绘制未完成的笔迹路径（用于铅笔）
  void _drawStrokePathIncompleteWithPaint(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY, Paint paint) {
    if (stroke.points.isEmpty) {
      return;
    }
    
    final smoothPath = stroke.getSmoothPath(isComplete: false);
    if (smoothPath.getBounds().isEmpty) {
      if (stroke.points.isNotEmpty) {
        final Offset p = _transform(stroke.points.first, scale, offsetX, offsetY);
        canvas.drawCircle(p, stroke.strokeWidth / 2, paint);
      }
      return;
    }
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    canvas.drawPath(smoothPath, paint);
    canvas.restore();
  }
  
  /// 绘制未完成的笔迹路径（实时绘制，不闭合）
  void _drawStrokePathIncomplete(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY, Color color, double strokeWidth) {
    if (stroke.points.isEmpty) {
      return;
    }
    
    // 对于未完成的笔迹，使用未完成状态生成路径
    final smoothPath = stroke.getSmoothPath(isComplete: false);
    if (smoothPath.getBounds().isEmpty) {
      if (stroke.points.isNotEmpty) {
        final Offset p = _transform(stroke.points.first, scale, offsetX, offsetY);
        final Paint paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, strokeWidth / 2, paint);
      }
      return;
    }
    
    // 应用变换
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(smoothPath, paint);
    canvas.restore();
  }
  
  /// 绘制笔迹路径（通用方法）
  /// 使用 perfect_freehand 生成平滑路径
  void _drawStrokePath(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY, Color color, double strokeWidth) {
    if (stroke.points.isEmpty) {
      return;
    }
    
    // 使用 perfect_freehand 生成平滑路径
    final smoothPath = stroke.getSmoothPath(isComplete: true);
    if (smoothPath.getBounds().isEmpty) {
      // 如果路径为空，绘制单个点
      if (stroke.points.isNotEmpty) {
        final Offset p = _transform(stroke.points.first, scale, offsetX, offsetY);
        final Paint paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, strokeWidth / 2, paint);
      }
      return;
    }
    
    // 应用变换（缩放和偏移）
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill  // 使用填充模式绘制平滑路径
      ..strokeWidth = 0;  // 填充模式不需要线宽
    
    // 绘制平滑路径
    canvas.drawPath(smoothPath, paint);
    
    canvas.restore();
  }

  Offset _transform(Offset p, double scale, double offsetX, double offsetY) {
    return Offset(
      offsetX + p.dx * scale,
      offsetY + p.dy * scale,
    );
  }

  /// ✅ 绘制矩形笔迹
  void _drawRectangleStroke(Canvas canvas, RectangleStroke stroke, double scale, double offsetX, double offsetY) {
    final rect = stroke.rect;
    if (rect.isEmpty) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    canvas.drawRect(rect, paint);
    canvas.restore();
  }
  
  /// ✅ 绘制圆形笔迹
  void _drawCircleStroke(Canvas canvas, CircleStroke stroke, double scale, double offsetX, double offsetY) {
    final center = stroke.center;
    final radius = stroke.radius;
    if (radius <= 0) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    canvas.drawCircle(center, radius, paint);
    canvas.restore();
  }
  
  /// ✅ 绘制三角形笔迹
  void _drawTriangleStroke(Canvas canvas, TriangleStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 3) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    final path = Path();
    path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }
  
  /// ✅ 绘制菱形笔迹
  void _drawDiamondStroke(Canvas canvas, DiamondStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 4) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    final path = Path();
    path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }
  
  /// ✅ 绘制形状预览（用于实时显示正在绘制的形状）
  void _drawShapePreview(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 2) {
      return;
    }
    
    final startPoint = stroke.points.first;
    final endPoint = stroke.points[1];
    final color = stroke.color;
    final strokeWidth = stroke.strokeWidth * scale;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    
    final toolId = stroke.toolId;
    if (toolId == ToolId.rectangle) {
      // ✅ 矩形
      final left = math.min(startPoint.dx, endPoint.dx);
      final top = math.min(startPoint.dy, endPoint.dy);
      final right = math.max(startPoint.dx, endPoint.dx);
      final bottom = math.max(startPoint.dy, endPoint.dy);
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
    } else if (toolId == ToolId.circle) {
      // ✅ 圆形
      final center = Offset(
        (startPoint.dx + endPoint.dx) / 2,
        (startPoint.dy + endPoint.dy) / 2,
      );
      final radius = (startPoint - endPoint).distance / 2;
      canvas.drawCircle(center, radius, paint);
    } else if (toolId == ToolId.triangle) {
      // ✅ 三角形
      final center = Offset(
        (startPoint.dx + endPoint.dx) / 2,
        (startPoint.dy + endPoint.dy) / 2,
      );
      final width = (endPoint.dx - startPoint.dx).abs();
      final height = (endPoint.dy - startPoint.dy).abs();
      final radius = math.max(width, height) / 2;
      
      final top = Offset(center.dx, center.dy - radius);
      final bottomLeft = Offset(
        center.dx - radius * math.cos(math.pi / 6),
        center.dy + radius * math.sin(math.pi / 6),
      );
      final bottomRight = Offset(
        center.dx + radius * math.cos(math.pi / 6),
        center.dy + radius * math.sin(math.pi / 6),
      );
      
      final path = Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(bottomRight.dx, bottomRight.dy)
        ..lineTo(bottomLeft.dx, bottomLeft.dy)
        ..close();
      canvas.drawPath(path, paint);
    } else if (toolId == ToolId.diamond) {
      // ✅ 菱形
      final center = Offset(
        (startPoint.dx + endPoint.dx) / 2,
        (startPoint.dy + endPoint.dy) / 2,
      );
      final width = (endPoint.dx - startPoint.dx).abs() / 2;
      final height = (endPoint.dy - startPoint.dy).abs() / 2;
      
      final top = Offset(center.dx, center.dy - height);
      final right = Offset(center.dx + width, center.dy);
      final bottom = Offset(center.dx, center.dy + height);
      final left = Offset(center.dx - width, center.dy);
      
      final path = Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(bottom.dx, bottom.dy)
        ..lineTo(left.dx, left.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SaberCoreCanvasPainter oldDelegate) {
    return oldDelegate.page != page ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.currentScale != currentScale ||  // ✅ 缩放级别改变时需要重绘
        oldDelegate.laserStrokes.length != laserStrokes.length;  // ✅ 激光笔笔迹数量改变时需要重绘
  }
}


