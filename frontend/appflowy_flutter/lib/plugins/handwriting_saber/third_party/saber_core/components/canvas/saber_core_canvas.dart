import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../canvas/canvas_background_pattern.dart';
import '../canvas/image/pdf_editor_image.dart';
import '../../../../../../util/log_utils.dart';
import '../../data/editor/editor_core_info.dart';
import '../../data/editor/page.dart';
import '../../data/editor/shape_strokes.dart';
import '../../data/editor/stroke_extensions.dart';
import '../../data/editor/text_box.dart' as saber_text;
import '../../data/tools/select_result.dart';
import '../../data/tools/tool.dart';

/// 专门的PDF背景组件，参考Saber的CanvasImage设计
/// 使用StatefulWidget确保组件稳定性，完全隔离于画布重绘逻辑
class _PdfBackground extends StatefulWidget {
  const _PdfBackground({
    super.key, // 使用稳定的key确保组件身份
    required this.pdfImage,
    required this.offsetX,
    required this.offsetY,
    required this.drawWidth,
    required this.drawHeight,
    required this.pageSize,
  });

  final PdfEditorImage pdfImage;
  final double offsetX;
  final double offsetY;
  final double drawWidth;
  final double drawHeight;
  final Size pageSize;

  @override
  State<_PdfBackground> createState() => _PdfBackgroundState();
}

class _PdfBackgroundState extends State<_PdfBackground> {
  @override
  void initState() {
    super.initState();
    // 预加载PDF，确保显示
    widget.pdfImage.preloadPdfDocument();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.offsetX,
      top: widget.offsetY,
      width: widget.drawWidth,
      height: widget.drawHeight,
      child: IgnorePointer(
        child: SizedBox(
          width: widget.drawWidth,
          height: widget.drawHeight,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: widget.pageSize.width,
              height: widget.pageSize.height,
              child: RepaintBoundary(
                child: widget.pdfImage.buildPdfPageWidget(
                  boxFit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


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
    this.currentStrokeListenable,
    this.repaintListenable,
    this.selectResult, // ✅ 选择结果
    this.isSelecting = false, // ✅ 是否正在选择
    this.pdfTextSelectionRect, // ✅ PDF文本选择区域
  });

  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  /// 如果提供了 [currentStrokeListenable]，画布会使用该 Listenable 来触发重绘，
  /// 从而避免在每次笔迹更新时回到父级 Widget 调用 setState 导致整页重建。
  final ValueListenable<Stroke?>? currentStrokeListenable;
  /// 额外的重绘监听器（用于激光笔等需要独立驱动的重绘）
  final Listenable? repaintListenable;
  final SelectResult? selectResult; // ✅ 选择结果
  final bool isSelecting; // ✅ 是否正在选择
  final Rect? pdfTextSelectionRect; // ✅ PDF文本选择区域

  @override
  Widget build(BuildContext context) {
    final EditorPage page = coreInfo.firstPage;

    // 只在需要时输出详细布局/构建日志，默认关闭（可在运行时通过 LogUtils.setVerbose(true) 打开）
    LogUtils.debug('🎨 [SaberCoreCanvas] build: page.strokes=${page.strokes.length}, currentStroke=$currentStroke, selectResult=$selectResult, isSelecting=$isSelecting');

    return LayoutBuilder(
      builder: (context, constraints) {
        // ✅ 计算当前缩放级别
        final double scaleX = constraints.maxWidth / page.size.width;
        final double scaleY = constraints.maxHeight / page.size.height;
        final double scale = scaleX < scaleY ? scaleX : scaleY;

        // ✅ 计算绘制区域的实际大小和偏移
        final double drawWidth = page.size.width * scale;
        final double drawHeight = page.size.height * scale;
        final double offsetX = (constraints.maxWidth - drawWidth) / 2;
        final double offsetY = (constraints.maxHeight - drawHeight) / 2;

        LogUtils.debug('📐 [SaberCoreCanvas] layout: scale=$scale, offset=($offsetX,$offsetY), size=(${drawWidth}x${drawHeight})');
        
        // ✅ 参考Saber原版架构：PDF背景和笔迹完全分离
        // 使用专门的StatefulWidget确保PDF背景完全隔离于画布重绘
        return Stack(
          children: [
            // ✅ PDF背景层 - 使用专门的StatefulWidget，完全隔离重绘逻辑
            if (page.backgroundImage != null)
              _PdfBackground(
                key: ValueKey('pdf_bg_${page.backgroundImage!.pdfFilePath}_${page.backgroundImage!.pdfPageIndex}'),
                pdfImage: page.backgroundImage!,
                offsetX: offsetX,
                offsetY: offsetY,
                drawWidth: drawWidth,
                drawHeight: drawHeight,
                pageSize: page.size,
              ),
            // ✅ 笔迹层 - CustomPaint只负责绘制笔迹和选择框，完全不包含PDF
            CustomPaint(
              painter: _SaberCoreCanvasPainter(
                page: page,
                coreInfo: coreInfo,
                currentStroke: currentStroke,
                currentStrokeListenable: currentStrokeListenable,
                currentScale: scale,
                selectResult: selectResult,
                isSelecting: isSelecting,
                pdfTextSelectionRect: pdfTextSelectionRect,
                repaint: repaintListenable ?? currentStrokeListenable,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            ),
          ],
        );
      },
    );
  }
}

class _SaberCoreCanvasPainter extends CustomPainter {
  _SaberCoreCanvasPainter({
    required this.page,
    required this.coreInfo,
    this.currentStroke,
    this.currentStrokeListenable,
    this.currentScale = 1.0,  // ✅ 添加缩放级别，用于判断是否使用铅笔 shader
    this.selectResult, // ✅ 选择结果
    this.isSelecting = false, // ✅ 是否正在选择
    this.pdfTextSelectionRect, // ✅ PDF文本选择区域
    Listenable? repaint,
  }) : super(repaint: repaint);

  final EditorPage page;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final ValueListenable<Stroke?>? currentStrokeListenable;
  final double currentScale;  // ✅ 当前缩放级别
  // 激光笔笔迹列表（不再作为独立字段，直接从 coreInfo 使用）
  final SelectResult? selectResult; // ✅ 选择结果
  final bool isSelecting; // ✅ 是否正在选择
  final Rect? pdfTextSelectionRect; // ✅ PDF文本选择区域

  @override
  void paint(Canvas canvas, Size size) {
    // 减少调试日志输出，避免影响性能
    // debugPrint('🦋[SaberCoreCanvasPainter] paint: page.strokes=${page.strokes.length}, currentStroke=${currentStroke != null}, laserStrokes=${laserStrokes.length}, selectResult=${selectResult != null}, isSelecting=$isSelecting');
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
    
    // 绘制背景（传入当前缩放 scale，使背景线间距能根据缩放正确显示）
    _drawBackground(canvas, Size(drawWidth, drawHeight), offsetX, offsetY, scale);
    
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
    
    // 先绘制荧光笔（直接使用半透明填充，不使用 saveLayer，以避免 save/restore 不平衡问题）
    if (highlighterStrokes.isNotEmpty) {
      for (final stroke in highlighterStrokes) {
        final Color drawColor = stroke.color.withValues(alpha: 0.32); // 半透明叠加效果
        _drawStrokePath(canvas, stroke, scale, offsetX, offsetY, drawColor, stroke.strokeWidth * scale * 2);
      }
    }
    
    // ✅ 绘制激光笔笔迹（发光效果，从 coreInfo.laserStrokes 获取）
    if (coreInfo.laserStrokes.isNotEmpty) {
      debugPrint('🔴 [SaberCanvas] Drawing ${coreInfo.laserStrokes.length} laser strokes');
    }
    for (final stroke in coreInfo.laserStrokes) {
      _drawLaserStroke(canvas, stroke, scale, offsetX, offsetY);
    }
    
    // 再绘制其他笔迹
    for (final stroke in otherStrokes) {
      _drawStroke(canvas, stroke, scale, offsetX, offsetY);
    }
    
    // 绘制当前正在绘制的笔迹（使用未完成状态，实时显示）
    final Stroke? strokeToDraw = currentStrokeListenable?.value ?? currentStroke;
    if (strokeToDraw != null) {
      if (strokeToDraw.toolId == ToolId.highlighter) {
        // 不使用 saveLayer，为未完成的荧光笔直接绘制半透明路径
        _drawStrokePathIncomplete(
          canvas,
          strokeToDraw,
          scale,
          offsetX,
          offsetY,
          strokeToDraw.color.withValues(alpha: 0.32),
          strokeToDraw.strokeWidth * scale * 2,
        );
      } else if (strokeToDraw.toolId == ToolId.laserPointer) {
        _drawLaserStroke(canvas, strokeToDraw, scale, offsetX, offsetY);
      } else if (strokeToDraw is LineStroke || strokeToDraw is ArrowLineStroke) {
        // ✅ 直线和箭头：使用专门的绘制方法
        debugPrint('🎨 [SaberCanvas] Drawing current LineStroke/ArrowLine');
        _drawLineStroke(canvas, strokeToDraw, scale, offsetX, offsetY);
      } else if (strokeToDraw is RectangleStroke) {
        // ✅ 矩形：使用专门的绘制方法
        debugPrint('🎨 [SaberCanvas] Drawing current RectangleStroke');
        _drawRectangleStroke(canvas, strokeToDraw, scale, offsetX, offsetY);
      } else if (strokeToDraw is CircleStroke) {
        // ✅ 圆形：使用专门的绘制方法
        debugPrint('🎨 [SaberCanvas] Drawing current CircleStroke');
        _drawCircleStroke(canvas, strokeToDraw, scale, offsetX, offsetY);
      } else if (strokeToDraw is TriangleStroke) {
        // ✅ 三角形：使用专门的绘制方法
        debugPrint('🎨 [SaberCanvas] Drawing current TriangleStroke');
        _drawTriangleStroke(canvas, strokeToDraw, scale, offsetX, offsetY);
      } else if (strokeToDraw is DiamondStroke) {
        // ✅ 菱形：使用专门的绘制方法
        debugPrint('🎨 [SaberCanvas] Drawing current DiamondStroke');
        _drawDiamondStroke(canvas, strokeToDraw, scale, offsetX, offsetY);
      } else {
        debugPrint('🎨 [SaberCanvas] Drawing current stroke as incomplete: toolId=${strokeToDraw.toolId}, type=${strokeToDraw.runtimeType}');
        _drawStrokeIncomplete(canvas, strokeToDraw, scale, offsetX, offsetY);
      }
    }
    
    // ✅ 绘制文本框
    for (final textBox in page.textBoxes) {
      _drawTextBox(canvas, textBox, scale, offsetX, offsetY);
    }
    
    // ✅ 绘制选择框（page.pageIndex 可能不存在，使用页面在列表中的索引）
    if (selectResult != null) {
      // ✅ 检查是否是当前页面（通过比较页面大小或使用第一个页面）
      // 由于我们只传递了当前页面，所以直接绘制
      _drawSelection(canvas, selectResult!, scale, offsetX, offsetY, isSelecting);
    }
    
    // ✅ 绘制PDF文本选择区域
    if (pdfTextSelectionRect != null) {
      _drawPdfTextSelection(canvas, pdfTextSelectionRect!, scale, offsetX, offsetY);
    }
    
    // 恢复画布状态
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size drawSize, double offsetX, double offsetY, double scale) {
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
    final double lineHeight = coreInfo.lineHeight.toDouble();
    final int lineThickness = coreInfo.lineThickness;

    if (pattern == CanvasBackgroundPattern.none) {
      return;
    }

    // 使用更明显的灰色线条以提高可见性（默认横格纸/网格纸）
    final Paint linePaint = Paint()
      ..color = const Color(0xFFCCCCCC) // 更明显的浅灰色
      ..strokeWidth = lineThickness.toDouble();

    // 将 lineHeight（页面单位）转换为屏幕像素：乘以当前缩放 scale
    final double visualSpacing = lineHeight * scale;

    switch (pattern) {
      case CanvasBackgroundPattern.lined:
        // 绘制横线（从较小的偏移开始，以便顶部也有线）
        final double startY = visualSpacing * 0.5;
        for (double y = startY; y < drawSize.height; y += visualSpacing) {
          canvas.drawLine(
            Offset(offsetX, offsetY + y),
            Offset(offsetX + drawSize.width, offsetY + y),
            linePaint,
          );
        }
        break;
      case CanvasBackgroundPattern.grid:
        // 绘制网格（垂直与水平间距相同）
        for (double y = visualSpacing * 2; y < drawSize.height; y += visualSpacing) {
          canvas.drawLine(
            Offset(offsetX, offsetY + y),
            Offset(offsetX + drawSize.width, offsetY + y),
            linePaint,
          );
        }
        for (double x = 0; x < drawSize.width; x += visualSpacing) {
          canvas.drawLine(
            Offset(offsetX + x, offsetY + visualSpacing * 2),
            Offset(offsetX + x, offsetY + drawSize.height),
            linePaint,
          );
        }
        break;
      case CanvasBackgroundPattern.dots:
        // 绘制点阵
        for (double y = visualSpacing * 2; y <= drawSize.height; y += visualSpacing) {
          for (double x = 0; x <= drawSize.width; x += visualSpacing) {
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
    debugPrint('🔴 [SaberCanvas] Drawing laser stroke: points=${stroke.points.length}');
    
    if (stroke.points.isEmpty) {
      debugPrint('🔴 [SaberCanvas] Laser stroke is empty, skipping');
      return;
    }
    
    // 使用 perfect_freehand 生成平滑路径
    final smoothPath = stroke.getSmoothPath(isComplete: true);
    if (smoothPath.getBounds().isEmpty) {
      debugPrint('🔴 [SaberCanvas] Laser stroke smooth path is empty, skipping');
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
    
    // ✅ 检查是否是形状笔迹（LineStroke, ArrowLineStroke, RectangleStroke, CircleStroke 等）
    if (stroke is LineStroke || stroke is ArrowLineStroke) {
      _drawLineStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is RectangleStroke) {
      debugPrint('🖼️ [SaberCanvas] Drawing saved RectangleStroke');
      _drawRectangleStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is CircleStroke) {
      debugPrint('🖼️ [SaberCanvas] Drawing saved CircleStroke');
      _drawCircleStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is TriangleStroke) {
      debugPrint('🖼️ [SaberCanvas] Drawing saved TriangleStroke');
      _drawTriangleStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is DiamondStroke) {
      debugPrint('🖼️ [SaberCanvas] Drawing saved DiamondStroke');
      _drawDiamondStroke(canvas, stroke, scale, offsetX, offsetY);
      return;
    } else if (stroke is FreePolygonStroke) {
      // ✅ 自由多边形使用普通绘制逻辑，继续执行下面的代码
      debugPrint('🖼️ [SaberCanvas] Drawing saved FreePolygonStroke');
    } else {
      debugPrint('🖼️ [SaberCanvas] Drawing saved regular stroke: toolId=${stroke.toolId}, type=${stroke.runtimeType}');
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

  /// ✅ 绘制直线笔迹
  void _drawLineStroke(Canvas canvas, Stroke stroke, double scale, double offsetX, double offsetY) {
    // ✅ 支持 LineStroke 和 ArrowLineStroke
    final LineStroke lineStroke = stroke is LineStroke 
        ? stroke 
        : (stroke as ArrowLineStroke);
    
    final start = lineStroke.startPoint;
    final end = lineStroke.endPoint;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final paint = Paint()
      ..color = lineStroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineStroke.strokeWidth
      ..strokeCap = StrokeCap.round;
    
    // ✅ 根据虚线样式绘制不同的线条
    if (lineStroke.dashStyle != DashStyle.solid) {
      final path = Path();
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      
      if (length > 0) {
        final unitX = dx / length;
        final unitY = dy / length;
        
        // ✅ 根据虚线样式设置不同的参数
        double dashLength;
        double gapLength;
        bool isDotStyle = false;
        
        switch (lineStroke.dashStyle) {
          case DashStyle.dot:
            // 点虚线：小圆点
            dashLength = 2.0;
            gapLength = 3.0;
            isDotStyle = true;
            break;
          case DashStyle.shortDash:
            // 短虚线
            dashLength = 5.0;
            gapLength = 3.0;
            break;
          case DashStyle.longDash:
            // 长虚线
            dashLength = 10.0;
            gapLength = 5.0;
            break;
          case DashStyle.dashDot:
            // 点划线：交替绘制点和短线
            dashLength = 5.0;
            gapLength = 3.0;
            break;
          case DashStyle.solid:
            dashLength = length;
            gapLength = 0;
            break;
        }
        
        double currentLength = 0;
        bool isDot = false; // 用于点划线模式
        
        while (currentLength < length) {
          if (lineStroke.dashStyle == DashStyle.dashDot) {
            // 点划线：交替绘制点和短线
            final currentDashLength = isDot ? 2.0 : dashLength;
            final dashStart = Offset(
              start.dx + unitX * currentLength,
              start.dy + unitY * currentLength,
            );
            final dashEndLength = math.min(currentLength + currentDashLength, length);
            final dashEnd = Offset(
              start.dx + unitX * dashEndLength,
              start.dy + unitY * dashEndLength,
            );
            
            if (isDot) {
              // 绘制点
              canvas.drawCircle(dashStart, lineStroke.strokeWidth / 2, paint);
            } else {
              // 绘制短线
              path.moveTo(dashStart.dx, dashStart.dy);
              path.lineTo(dashEnd.dx, dashEnd.dy);
            }
            
            currentLength += currentDashLength + gapLength;
            isDot = !isDot;
          } else if (isDotStyle) {
            // 点虚线：绘制小圆点
            final dotPos = Offset(
              start.dx + unitX * currentLength,
              start.dy + unitY * currentLength,
            );
            canvas.drawCircle(dotPos, lineStroke.strokeWidth / 2, paint);
            currentLength += dashLength + gapLength;
          } else {
            // 普通虚线
            final dashStart = Offset(
              start.dx + unitX * currentLength,
              start.dy + unitY * currentLength,
            );
            final dashEndLength = math.min(currentLength + dashLength, length);
            final dashEnd = Offset(
              start.dx + unitX * dashEndLength,
              start.dy + unitY * dashEndLength,
            );
            path.moveTo(dashStart.dx, dashStart.dy);
            path.lineTo(dashEnd.dx, dashEnd.dy);
            currentLength += dashLength + gapLength;
          }
        }
        
        if (!isDotStyle) {
          canvas.drawPath(path, paint);
        }
      }
    } else {
      // ✅ 绘制实线
      canvas.drawLine(start, end, paint);
    }
    
    // ✅ 如果是箭头直线，绘制箭头
    if (stroke is ArrowLineStroke) {
      debugPrint('🎯 [SaberCanvas] Drawing arrow: arrowStyle=${stroke.arrowStyle}');
      if (stroke.arrowStyle == ArrowStyle.doubleArrow) {
        // ✅ 双向箭头：在两端都绘制箭头
        debugPrint('🎯 [SaberCanvas] Drawing double arrow');
        _drawSingleArrow(canvas, start, end, lineStroke.strokeWidth, lineStroke.color, ArrowStyle.filled, isEndArrow: true);
        _drawSingleArrow(canvas, start, end, lineStroke.strokeWidth, lineStroke.color, ArrowStyle.filled, isEndArrow: false);
      } else {
        // ✅ 单向箭头：只在末端绘制
        debugPrint('🎯 [SaberCanvas] Drawing single arrow: style=${stroke.arrowStyle}');
        _drawSingleArrow(canvas, start, end, lineStroke.strokeWidth, lineStroke.color, stroke.arrowStyle, isEndArrow: true);
      }
    }
    
    canvas.restore();
  }
  
  /// ✅ 绘制单个箭头（在直线的一端）
  void _drawSingleArrow(Canvas canvas, Offset start, Offset end, double strokeWidth, Color color, ArrowStyle arrowStyle, {required bool isEndArrow}) {
    // 箭头大小（根据线宽调整）
    final arrowSize = strokeWidth * 2.5;
    final arrowAngle = math.pi / 6; // 30度角
    
    // 计算直线的方向向量
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    
    if (length < 0.1) return; // 直线太短，不绘制箭头
    
    // 归一化方向向量
    final unitX = dx / length;
    final unitY = dy / length;
    
    // ✅ 箭头尖端位置和起点位置（根据是否是末端箭头来确定）
    final arrowTip = isEndArrow ? end : start;
    final arrowBase = Offset(
      arrowTip.dx - unitX * arrowSize * 0.3 * (isEndArrow ? 1 : -1),
      arrowTip.dy - unitY * arrowSize * 0.3 * (isEndArrow ? 1 : -1),
    );
    
    // 计算箭头两个边的方向
    final cosAngle = math.cos(arrowAngle);
    final sinAngle = math.sin(arrowAngle);
    
    // ✅ 计算箭头方向（对于起始箭头需要反向）
    final directionMultiplier = isEndArrow ? -1.0 : 1.0;
    
    // 箭头左点
    final arrowLeft = Offset(
      arrowBase.dx + directionMultiplier * arrowSize * (unitX * cosAngle - unitY * sinAngle),
      arrowBase.dy + directionMultiplier * arrowSize * (unitY * cosAngle + unitX * sinAngle),
    );
    
    // 箭头右点
    final arrowRight = Offset(
      arrowBase.dx + directionMultiplier * arrowSize * (unitX * cosAngle + unitY * sinAngle),
      arrowBase.dy + directionMultiplier * arrowSize * (unitY * cosAngle - unitX * sinAngle),
    );
    
    // ✅ 根据箭头样式绘制不同的箭头
    switch (arrowStyle) {
      case ArrowStyle.filled:
        // 实心箭头（填充三角形）
        final arrowPath = Path()
          ..moveTo(arrowTip.dx, arrowTip.dy)
          ..lineTo(arrowLeft.dx, arrowLeft.dy)
          ..lineTo(arrowRight.dx, arrowRight.dy)
          ..close();
        
        final filledPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        
        canvas.drawPath(arrowPath, filledPaint);
        break;
        
      case ArrowStyle.hollow:
        // 空心箭头（三角形描边）
        final arrowPath = Path()
          ..moveTo(arrowTip.dx, arrowTip.dy)
          ..lineTo(arrowLeft.dx, arrowLeft.dy)
          ..lineTo(arrowRight.dx, arrowRight.dy)
          ..close();
        
        final hollowPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        
        canvas.drawPath(arrowPath, hollowPaint);
        break;
        
      case ArrowStyle.line:
        // 线条箭头（两条斜线组成的 > 形状）
        final linePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        
        // 绘制左边斜线
        canvas.drawLine(arrowTip, arrowLeft, linePaint);
        // 绘制右边斜线
        canvas.drawLine(arrowTip, arrowRight, linePaint);
        break;
        
      case ArrowStyle.doubleArrow:
        // ✅ 双向箭头不应该单独绘制，这是一个内部状态
        // 双向箭头的绘制已经在调用处理（两次调用 _drawSingleArrow）
        break;
    }
  }

  /// ✅ 绘制矩形笔迹（支持填充和描边）
  void _drawRectangleStroke(Canvas canvas, RectangleStroke stroke, double scale, double offsetX, double offsetY) {
    final rect = stroke.rect;
    debugPrint('🎨🎨🎨 [SaberCanvas] _drawRectangleStroke: rect=$rect, isEmpty=${rect.isEmpty}, color=${stroke.color}, strokeWidth=${stroke.strokeWidth}');
    if (rect.isEmpty) {
      debugPrint('⚠️⚠️⚠️ [SaberCanvas] _drawRectangleStroke: rect is empty, skipping');
      return;
    }
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    // ✅ 先绘制填充（如果有fillColor）
    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);
      debugPrint('🎨🎨🎨 [SaberCanvas] Drew rectangle fill: ${stroke.fillColor}');
    }
    
    // ✅ 再绘制描边（支持虚线）
    final strokePaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    // ✅ 如果是虚线样式，使用虚线绘制
    if (stroke.dashStyle != DashStyle.solid) {
      final path = Path()..addRect(rect);
      _drawDashedPath(canvas, path, strokePaint, stroke.dashStyle);
      debugPrint('🎨🎨🎨 [SaberCanvas] Drew rectangle dashed stroke: dashStyle=${stroke.dashStyle}');
    } else {
      canvas.drawRect(rect, strokePaint);
      debugPrint('🎨🎨🎨 [SaberCanvas] Drew rectangle stroke: color=${stroke.color}, width=${stroke.strokeWidth}');
    }
    canvas.restore();
  }
  
  /// ✅ 绘制圆形/椭圆笔迹（支持填充和描边）
  void _drawCircleStroke(Canvas canvas, CircleStroke stroke, double scale, double offsetX, double offsetY) {
    debugPrint('🎨🎨🎨 [SaberCanvas] _drawCircleStroke: points=${stroke.points.length}, color=${stroke.color}, strokeWidth=${stroke.strokeWidth}');
    if (stroke.points.length < 2) {
      debugPrint('⚠️⚠️⚠️ [SaberCanvas] _drawCircleStroke: not enough points, skipping');
      return;
    }
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    // ✅ 支持椭圆：计算边界矩形
    final left = stroke.points.map((p) => p.dx).reduce(math.min);
    final top = stroke.points.map((p) => p.dy).reduce(math.min);
    final right = stroke.points.map((p) => p.dx).reduce(math.max);
    final bottom = stroke.points.map((p) => p.dy).reduce(math.max);
    final rect = Rect.fromLTRB(left, top, right, bottom);
    
    // ✅ 先绘制填充（如果有fillColor）
    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawOval(rect, fillPaint);
    }
    
    // ✅ 再绘制描边（支持虚线）
    final strokePaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    // ✅ 如果是虚线样式，使用虚线绘制
    if (stroke.dashStyle != DashStyle.solid) {
      final path = Path()..addOval(rect);
      _drawDashedPath(canvas, path, strokePaint, stroke.dashStyle);
    } else {
      canvas.drawOval(rect, strokePaint);
    }
    canvas.restore();
  }
  
  /// ✅ 绘制三角形笔迹（支持任意三角形，支持填充和描边）
  void _drawTriangleStroke(Canvas canvas, TriangleStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 3) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    // ✅ 使用三个点绘制三角形路径
    final point1 = stroke.point1;
    final point2 = stroke.point2;
    final point3 = stroke.point3;
    
    final path = Path()
      ..moveTo(point1.dx, point1.dy)
      ..lineTo(point2.dx, point2.dy)
      ..lineTo(point3.dx, point3.dy)
      ..close();
    
    // ✅ 先绘制填充（如果有fillColor）
    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }
    
    // ✅ 再绘制描边（支持虚线）
    final strokePaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    // ✅ 如果是虚线样式，使用虚线绘制
    if (stroke.dashStyle != DashStyle.solid) {
      _drawDashedPath(canvas, path, strokePaint, stroke.dashStyle);
    } else {
      canvas.drawPath(path, strokePaint);
    }
    canvas.restore();
  }
  
  /// ✅ 绘制菱形笔迹（支持填充和描边）
  void _drawDiamondStroke(Canvas canvas, DiamondStroke stroke, double scale, double offsetX, double offsetY) {
    if (stroke.points.length < 4) return;
    
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final path = Path();
    path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    path.close();
    
    // ✅ 先绘制填充（如果有fillColor）
    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }
    
    // ✅ 再绘制描边（支持虚线）
    final strokePaint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;
    
    // ✅ 如果是虚线样式，使用虚线绘制
    if (stroke.dashStyle != DashStyle.solid) {
      _drawDashedPath(canvas, path, strokePaint, stroke.dashStyle);
    } else {
      canvas.drawPath(path, strokePaint);
    }
    canvas.restore();
  }

  /// ✅ 绘制选择框
  void _drawSelection(Canvas canvas, SelectResult selectResult, double scale, double offsetX, double offsetY, bool isSelecting) {
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    if (isSelecting) {
      // ✅ 绘制拖拽选择区域
      final dashPaint = Paint()
        ..color = const Color(0xFF2196F3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
      
      final fillPaint = Paint()
        ..color = const Color(0xFF2196F3).withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
      
      if (selectResult.selectMode == SelectMode.rectangle) {
        // ✅ 矩形框选模式：绘制矩形
        final selectionRect = selectResult.getSelectionRect();
        if (selectionRect != null && !selectionRect.isEmpty) {
          canvas.drawRect(selectionRect, dashPaint);
          canvas.drawRect(selectionRect, fillPaint);
        }
      } else if (selectResult.selectMode == SelectMode.lasso) {
        // ✅ 套索选择模式：绘制自由路径
        final path = selectResult.selectionPath;
        if (!path.getBounds().isEmpty) {
          canvas.drawPath(path, dashPaint);
          canvas.drawPath(path, fillPaint);
        }
      }
    } else if (!selectResult.isEmpty) {
      // ✅ 绘制选中对象的边界框
      final boundingBox = selectResult.getBoundingBox();
      if (boundingBox != null) {
        // 绘制边界框（虚线边框）
        final borderPaint = Paint()
          ..color = const Color(0xFF2196F3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / scale;
        
        // 绘制虚线边框（使用Path绘制虚线效果）
        final path = Path()
          ..addRect(boundingBox.inflate(4.0 / scale));
        
        canvas.drawPath(path, borderPaint);
        
        // 绘制半透明填充
        final fillPaint = Paint()
          ..color = const Color(0xFF2196F3).withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;
        canvas.drawRect(boundingBox.inflate(4.0 / scale), fillPaint);
      }
    }
    
    canvas.restore();
  }

  /// ✅ 绘制PDF文本选择区域
  void _drawPdfTextSelection(Canvas canvas, Rect selectionRect, double scale, double offsetX, double offsetY) {
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    // 绘制选择矩形（虚线边框 + 半透明填充）
    final dashPaint = Paint()
      ..color = const Color(0xFF4CAF50) // 使用绿色区分PDF文本选择
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale;
    
    final fillPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(selectionRect, fillPaint);
    canvas.drawRect(selectionRect, dashPaint);
    
    canvas.restore();
  }

  /// ✅ 绘制文本框
  void _drawTextBox(Canvas canvas, saber_text.TextBox textBox, double scale, double offsetX, double offsetY) {
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    
    final rect = textBox.rect;
    
    // ✅ 绘制背景（如果有）
    if (textBox.backgroundColor != null) {
      final bgPaint = Paint()
        ..color = textBox.backgroundColor!
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, bgPaint);
    }
    
    // ✅ 绘制边框（如果有）
    if (textBox.borderColor != null && textBox.borderWidth > 0) {
      final borderPaint = Paint()
        ..color = textBox.borderColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = textBox.borderWidth;
      canvas.drawRect(rect, borderPaint);
    }
    
    // ✅ 绘制文本（优先使用 Quill 富文本，如果为空则使用纯文本）
    final plainTextContent = textBox.quillContent.plainText.trim();
    if (plainTextContent.isNotEmpty || textBox.text.isNotEmpty) {
      final baseTextStyle = textBox.textStyle ?? const TextStyle(
        fontSize: 16,
        color: Colors.black,
      );
      
      // ✅ 优先使用 Quill 富文本内容
      final TextSpan textSpan;
      if (plainTextContent.isNotEmpty) {
        // 使用 Quill 的富文本内容（支持所有格式）
        textSpan = textBox.quillContent.toTextSpan(baseStyle: baseTextStyle);
      } else {
        // 向后兼容：使用纯文本
        textSpan = TextSpan(
          text: textBox.text,
          style: baseTextStyle,
        );
      }
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: null,
      );
      
      textPainter.layout(maxWidth: rect.width);
      
      // 文本从左上角开始绘制
      textPainter.paint(canvas, rect.topLeft);
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SaberCoreCanvasPainter oldDelegate) {
    // 参考Saber原版的精确重绘控制逻辑，确保PDF背景完全不参与重绘

    // 调试日志：详细记录重绘触发原因
    bool needsRepaint = false;
    String repaintReason = '';

    // 当前笔画正在绘制时，强制重绘
    if (currentStroke != null || oldDelegate.currentStroke != null) {
      needsRepaint = true;
      repaintReason = 'currentStroke changed';
    }
    // 激光笔笔迹正在淡出时，强制重绘
    else if (coreInfo.laserStrokes.isNotEmpty || oldDelegate.coreInfo.laserStrokes.isNotEmpty) {
      needsRepaint = true;
      repaintReason = 'laserStrokes changed';
    }
    // 页面笔迹数量变化时重绘（参考Saber原版，简化比较逻辑）
    else if (page.strokes.length != oldDelegate.page.strokes.length) {
      needsRepaint = true;
      repaintReason = 'strokes length changed (${page.strokes.length} vs ${oldDelegate.page.strokes.length})';
    }
    // 页面文本框变化时重绘
    else if (!_areTextBoxesEqual(page.textBoxes, oldDelegate.page.textBoxes)) {
      needsRepaint = true;
      repaintReason = 'textBoxes changed';
    }
    // 选择状态变化时重绘（只在真正需要时）
    else if (!_areSelectResultsEqual(selectResult, oldDelegate.selectResult)) {
      needsRepaint = true;
      repaintReason = 'selectResult changed';
    }
    // 选择操作状态变化时重绘
    else if (isSelecting != oldDelegate.isSelecting) {
      needsRepaint = true;
      repaintReason = 'isSelecting changed';
    }
    // 缩放级别变化时重绘
    else if (currentScale != oldDelegate.currentScale) {
      needsRepaint = true;
      repaintReason = 'currentScale changed';
    }
    // 背景配置变化时重绘（不影响PDF层）
    else if (coreInfo.backgroundColor != oldDelegate.coreInfo.backgroundColor ||
             coreInfo.backgroundPattern != oldDelegate.coreInfo.backgroundPattern) {
      needsRepaint = true;
      repaintReason = 'background config changed';
    }

    // 只有在真正需要重绘时才输出日志，避免日志过多
    if (needsRepaint) {
      debugPrint('🖌️ [SaberCoreCanvasPainter] shouldRepaint: true - $repaintReason');
    }

    return needsRepaint;
  }

  /// 检查文本框列表是否相等
  bool _areTextBoxesEqual(List<saber_text.TextBox> a, List<saber_text.TextBox> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 检查笔画列表是否相等
  bool _areStrokesEqual(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }


  /// 检查选择结果是否相等
  bool _areSelectResultsEqual(SelectResult? a, SelectResult? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.pageIndex == b.pageIndex &&
           _areStrokesEqual(a.strokes, b.strokes);
  }

  /// ✅ 绘制虚线路径（通用方法）
  void _drawDashedPath(Canvas canvas, Path path, Paint paint, DashStyle dashStyle) {
    // 根据虚线样式设置不同的参数
    double dashLength;
    double gapLength;
    
    switch (dashStyle) {
      case DashStyle.dot:
        // 点虚线：小圆点
        dashLength = 2.0;
        gapLength = 3.0;
        break;
      case DashStyle.shortDash:
        // 短虚线
        dashLength = 5.0;
        gapLength = 3.0;
        break;
      case DashStyle.longDash:
        // 长虚线
        dashLength = 10.0;
        gapLength = 5.0;
        break;
      case DashStyle.dashDot:
        // 点划线：交替绘制点和短线
        dashLength = 5.0;
        gapLength = 3.0;
        break;
      case DashStyle.solid:
        // 实线
        canvas.drawPath(path, paint);
        return;
    }
    
    // 使用 PathMetric 来沿路径绘制虚线
    final pathMetrics = path.computeMetrics();
    for (final pathMetric in pathMetrics) {
      double distance = 0.0;
      bool isDash = true;
      
      while (distance < pathMetric.length) {
        final double length = isDash ? dashLength : gapLength;
        final double end = math.min(distance + length, pathMetric.length);
        
        if (isDash) {
          final extractPath = pathMetric.extractPath(distance, end);
          canvas.drawPath(extractPath, paint);
        }
        
        distance = end;
        isDash = !isDash;
      }
    }
  }
}


