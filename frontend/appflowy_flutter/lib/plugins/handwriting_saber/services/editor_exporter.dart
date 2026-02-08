import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/editor_image.dart';
import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/page.dart';
import '../third_party/saber_core/data/editor/shape_strokes.dart';
import '../third_party/saber_core/data/tools/tool.dart';

/// PDF导出器 - 高性能版本（包含PDF背景支持）
/// 使用直接Canvas绘制方式，避免Widget截图的性能问题
abstract class EditorExporter {
  /// 默认背景颜色
  static const defaultBackgroundColor = Color(0xFFFCFCFC);

  /// 导出分辨率倍数
  static const double exportPixelRatio = 1.5;

  /// 生成PDF文档
  static Future<pw.Document> generatePdf(
    EditorCoreInfo coreInfo,
    BuildContext context, {
    List<EditorPageNotifier>? pageNotifiers,
    void Function(int current, int total)? onProgress,
  }) async {
    // 复制页面列表
    var pages = List<EditorPage>.from(coreInfo.pages);

    // 移除最后的空页面
    if (pages.isNotEmpty && _isEmptyPage(pages.last)) {
      pages = pages.sublist(0, pages.length - 1);
    }

    if (pages.isEmpty) {
      throw Exception('没有可导出的页面');
    }

    final pdf = pw.Document();
    final totalPages = pages.length;

    debugPrint('📄[EditorExporter] 开始生成PDF，共 $totalPages 页');
    final startTime = DateTime.now();

    // 逐页渲染
    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final page = pageNotifiers != null && pageIndex < pageNotifiers.length
          ? pageNotifiers[pageIndex].page
          : pages[pageIndex];

      debugPrint('📄[EditorExporter] 正在处理第 ${pageIndex + 1}/$totalPages 页');
      onProgress?.call(pageIndex + 1, totalPages);

      try {
        // 渲染页面为图片
        final imageBytes = await _renderPageToImage(
          coreInfo: coreInfo,
          page: page,
        );

        // 添加PDF页面
        final pageSize = page.size;
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageSize.width, pageSize.height),
            margin: pw.EdgeInsets.zero,
            build: (pw.Context ctx) {
              return pw.Image(
                pw.MemoryImage(imageBytes),
                width: pageSize.width,
                height: pageSize.height,
                fit: pw.BoxFit.contain,
              );
            },
          ),
        );

        debugPrint('📄[EditorExporter] 第 ${pageIndex + 1} 页完成');
      } catch (e) {
        debugPrint('❌ [EditorExporter] 第 ${pageIndex + 1} 页失败: $e');
        rethrow;
      }
    }

    final elapsed = DateTime.now().difference(startTime);
    debugPrint('📄[EditorExporter] PDF生成完成，耗时: ${elapsed.inMilliseconds}ms');
    return pdf;
  }

  /// 检查页面是否为空
  static bool _isEmptyPage(EditorPage page) {
    return page.strokes.isEmpty &&
        page.images.isEmpty &&
        page.textBoxes.isEmpty &&
        page.listBoxes.isEmpty &&
        page.taskListBoxes.isEmpty &&
        page.backgroundImage == null;
  }

  /// 渲染页面为图片
  static Future<Uint8List> _renderPageToImage({
    required EditorCoreInfo coreInfo,
    required EditorPage page,
  }) async {
    final pageSize = page.size;
    final backgroundColor = coreInfo.backgroundColor ?? defaultBackgroundColor;

    // 计算渲染尺寸
    final renderWidth = (pageSize.width * exportPixelRatio).toInt();
    final renderHeight = (pageSize.height * exportPixelRatio).toInt();

    // 创建PictureRecorder
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, renderWidth.toDouble(), renderHeight.toDouble()));

    // 应用缩放
    canvas.scale(exportPixelRatio, exportPixelRatio);

    // 1. 绘制背景色
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, pageSize.width, pageSize.height), bgPaint);

    // 2. 绘制背景图案（仅在没有PDF背景时绘制）
    if (page.backgroundImage == null) {
      _drawBackgroundPattern(
        canvas,
        pageSize,
        coreInfo.backgroundPattern,
        coreInfo.lineHeight,
        coreInfo.lineThickness,
      );
    }

    // 3. ✅ 绘制PDF背景图（关键修复）
    if (page.backgroundImage != null) {
      await _drawPdfBackground(canvas, page.backgroundImage!, pageSize);
    }

    // 4. 绘制普通图片
    for (final image in page.images) {
      await _drawImage(canvas, image);
    }

    // 5. 绘制笔迹
    _drawStrokes(canvas, page.strokes);

    // 6. 绘制文本框
    _drawTextBoxes(canvas, page.textBoxes);

    // 结束录制
    final picture = recorder.endRecording();

    // 转换为图片
    final img = await picture.toImage(renderWidth, renderHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    // 清理资源
    picture.dispose();
    img.dispose();

    if (byteData == null) {
      throw Exception('无法将页面渲染为图片');
    }

    return byteData.buffer.asUint8List();
  }

  /// ✅ 绘制PDF背景图
  /// 说明：由于导入PDF时，pageSize已经按PDF宽高比计算
  /// (pageSize.height = defaultWidth * pdfPage.height / pdfPage.width)
  /// 所以PDF应该完美填充整个pageSize区域
  static Future<void> _drawPdfBackground(
    Canvas canvas,
    PdfEditorImage pdfImage,
    Size pageSize,
  ) async {
    try {
      debugPrint(
          '📄[EditorExporter] 开始渲染PDF背景: ${pdfImage.pdfFilePath}, 页面: ${pdfImage.pdfPageIndex}');

      // 加载PDF文档
      final pdfDocument =
          await pdfrx.PdfDocument.openFile(pdfImage.pdfFilePath);

      // 检查页面索引有效性
      if (pdfImage.pdfPageIndex < 0 ||
          pdfImage.pdfPageIndex >= pdfDocument.pages.length) {
        debugPrint('⚠️ [EditorExporter] PDF页面索引无效: ${pdfImage.pdfPageIndex}');
        pdfDocument.dispose();
        return;
      }

      // 获取PDF页面
      final pdfPage = pdfDocument.pages[pdfImage.pdfPageIndex];
      final pdfPageWidth = pdfPage.width;
      final pdfPageHeight = pdfPage.height;

      // 🔍 探测 PDF 页面属性（CropBox/MediaBox）
      try {
        // 使用 dynamic 访问潜在的未公开属性，用于调试
        dynamic p = pdfPage;
        // 尝试打印所有可能的属性
        debugPrint('🔍[EditorExporter] Probing PdfPage properties:');
        try {
          debugPrint(' - x: ${p.x}');
        } catch (_) {}
        try {
          debugPrint(' - y: ${p.y}');
        } catch (_) {}
        try {
          debugPrint(' - cropBox: ${p.cropBox}');
        } catch (_) {}
        try {
          debugPrint(' - mediaBox: ${p.mediaBox}');
        } catch (_) {}
        try {
          debugPrint(' - viewRect: ${p.viewRect}');
        } catch (_) {}
      } catch (e) {
        debugPrint('🔍[EditorExporter] Property probe failed: $e');
      }

      // 🔍 策略：探测自然渲染尺寸以解决 CropBox vs MediaBox 问题
      // 1. 先按默认参数渲染（通常是 natural size / 72 DPI）
      final naturalImage = await pdfPage.render(
        backgroundColor: Colors.white,
      );

      if (naturalImage == null) {
        debugPrint('⚠️ [EditorExporter] PDF自然尺寸探测失败');
        pdfDocument.dispose();
        return;
      }

      final double naturalWidth = naturalImage.width.toDouble();
      final double naturalHeight = naturalImage.height.toDouble();
      naturalImage.dispose(); // 立即释放

      debugPrint('📄[EditorExporter] 自然渲染尺寸: ${naturalWidth}x${naturalHeight}');
      debugPrint('📄[EditorExporter] 逻辑页面尺寸: ${pdfPageWidth}x${pdfPageHeight}');

      // 2. 计算缩放比例
      // 如果 render() 渲染的是 MediaBox (比如 612)，而 pdfPage.width 是 CropBox (比如 595)
      // 则 naturalWidth > pdfPageWidth。
      // 我们需要的高分辨率渲染目标是对齐 CropBox 的尺寸。

      // 计算 MediaBox 相对于 CropBox 的比例因子
      final widthRatio = naturalWidth / pdfPageWidth;

      // 目标：我们希望 CropBox 部分的宽度 等于 pageSize.width * exportPixelRatio
      // 但 render() 只能控制整体宽度（MediaBox）。
      // 所以我们需要把整体渲染宽度放大 widthRatio 倍。
      final int targetRenderWidth =
          (pageSize.width * exportPixelRatio * widthRatio).toInt();

      debugPrint(
          '📄[EditorExporter] 调整后的渲染宽度: $targetRenderWidth (Ratio: $widthRatio)');

      // 3. 执行高分辨率渲染
      final pdfPageImage = await pdfPage.render(
        width: targetRenderWidth,
        // height: auto
        backgroundColor: Colors.white,
      );

      if (pdfPageImage == null) {
        debugPrint('⚠️ [EditorExporter] PDF页面渲染失败');
        pdfDocument.dispose();
        return;
      }

      // 转换为ui.Image
      final uiImage = await pdfPageImage.createImage();

      debugPrint(
          '📄[EditorExporter] 渲染结果实际尺寸: ${uiImage.width}x${uiImage.height}');

      // 4. 绘制逻辑：Top-Left 裁剪 (0,0 Alignment)
      // 用户反馈 "Markings shifted Right" implies background shifted Left.
      // 这意味着之前的 Center Crop 切到了太右边的内容。
      // 说明实际的 CropBox 偏左（通常是 0,0）。

      final double imageWidth = uiImage.width.toDouble();
      final double imageHeight = uiImage.height.toDouble();

      // 计算 CropBox 在渲染图中的大小
      // srcCropWidth = pageSize.width * exportPixelRatio * (imageWidth / targetRenderWidth)
      // 简化：imageWidth 约等于 targetRenderWidth
      final double srcCropWidth = imageWidth / widthRatio;

      // 高度比例：假设 MediaBox 的宽高比可能与 CropBox 不同
      // naturalHeight 是 MediaBox 高度，pdfPageHeight 是 CropBox 高度
      final double heightRatio = naturalHeight / pdfPageHeight;
      final double srcCropHeight = imageHeight / heightRatio;

      // 修正：强制使用 Top-Left (0,0) 对齐
      // 假设 CropBox 位于 MediaBox 的 (0,0)
      const double srcLeft = 0.0;
      const double srcTop = 0.0;

      final srcRect =
          Rect.fromLTWH(srcLeft, srcTop, srcCropWidth, srcCropHeight);

      // 目标矩形：填满 pageSize
      // 由于 Import 逻辑保证了 pageSize 是 CropBox 比例，直接全填充
      final dstRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

      debugPrint('📄[EditorExporter] 绘制: Source=$srcRect -> Dest=$dstRect');

      canvas.drawImageRect(
        uiImage,
        srcRect,
        dstRect,
        Paint(),
      );

      debugPrint('📄[EditorExporter] PDF背景绘制完成');

      // 清理资源
      uiImage.dispose();
      pdfPageImage.dispose();
      pdfDocument.dispose();
    } catch (e) {
      debugPrint('❌ [EditorExporter] 绘制PDF背景失败: $e');
    }
  }

  /// 计算适应缩放比例
  static double _calculateFitScale(
      double srcWidth, double srcHeight, double destWidth, double destHeight) {
    final scaleX = destWidth / srcWidth;
    final scaleY = destHeight / srcHeight;
    return scaleX < scaleY ? scaleX : scaleY;
  }

  /// 绘制背景图案
  static void _drawBackgroundPattern(
    Canvas canvas,
    Size size,
    CanvasBackgroundPattern pattern,
    int lineHeight,
    int lineThickness,
  ) {
    if (pattern == CanvasBackgroundPattern.none) return;

    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = lineThickness.toDouble()
      ..style = PaintingStyle.stroke;

    switch (pattern) {
      case CanvasBackgroundPattern.lined:
        for (double y = lineHeight.toDouble();
            y < size.height;
            y += lineHeight) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case CanvasBackgroundPattern.grid:
        for (double y = lineHeight.toDouble();
            y < size.height;
            y += lineHeight) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = lineHeight.toDouble();
            x < size.width;
            x += lineHeight) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;
      case CanvasBackgroundPattern.dots:
        final dotPaint = Paint()
          ..color = Colors.grey.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        for (double y = lineHeight.toDouble();
            y < size.height;
            y += lineHeight) {
          for (double x = lineHeight.toDouble();
              x < size.width;
              x += lineHeight) {
            canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
          }
        }
        break;
      case CanvasBackgroundPattern.none:
        break;
    }
  }

  /// 绘制普通图片
  static Future<void> _drawImage(Canvas canvas, EditorImage image) async {
    final dstRect = image.dstRect;
    if (dstRect == null) return;

    if (image is PngEditorImage) {
      try {
        // 解码图片
        final codec = await ui.instantiateImageCodec(image.imageBytes);
        final frame = await codec.getNextFrame();
        final uiImage = frame.image;

        // 绘制图片
        canvas.drawImageRect(
          uiImage,
          Rect.fromLTWH(
              0, 0, uiImage.width.toDouble(), uiImage.height.toDouble()),
          dstRect,
          Paint(),
        );

        uiImage.dispose();
        codec.dispose();
      } catch (e) {
        debugPrint('⚠️ [EditorExporter] 绘制图片失败: $e');
      }
    }
  }

  /// 绘制笔迹
  static void _drawStrokes(Canvas canvas, List<Stroke> strokes) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      // ✅ 检查是否是形状笔迹
      if (stroke is LineStroke || stroke is ArrowLineStroke) {
        _drawLineStroke(canvas, stroke);
        continue;
      } else if (stroke is RectangleStroke) {
        _drawRectangleStroke(canvas, stroke);
        continue;
      } else if (stroke is CircleStroke) {
        _drawCircleStroke(canvas, stroke);
        continue;
      } else if (stroke is TriangleStroke) {
        _drawTriangleStroke(canvas, stroke);
        continue;
      } else if (stroke is DiamondStroke) {
        _drawDiamondStroke(canvas, stroke);
        continue;
      } else if (stroke is FreePolygonStroke) {
        // 自由多边形使用普通绘制逻辑
      }

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // 处理荧光笔
      if (stroke.toolId == ToolId.highlighter) {
        paint.color =
            stroke.color.withValues(alpha: 0.32); // ✅ 使用与屏幕一致的透明度 0.5 -> 0.32
        paint.strokeWidth = stroke.strokeWidth * 2;
        // 荧光笔通常没有strokeCap.round，或者使用butt，这里保持round但调整透明度
      }

      if (stroke.points.length == 1) {
        // 单点绘制为圆点
        canvas.drawCircle(
          stroke.points.first,
          stroke.strokeWidth / 2,
          Paint()
            ..color = paint.color
            ..style = PaintingStyle.fill,
        );
      } else {
        // 绘制普通笔迹路径
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }

        canvas.drawPath(path, paint);
      }
    }
  }

  /// ✅ 绘制直线和箭头
  static void _drawLineStroke(Canvas canvas, Stroke stroke) {
    final LineStroke lineStroke =
        stroke is LineStroke ? stroke : (stroke as ArrowLineStroke);

    final start = lineStroke.startPoint;
    final end = lineStroke.endPoint;

    final paint = Paint()
      ..color = lineStroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineStroke.strokeWidth
      ..strokeCap = StrokeCap.round;

    // ✅ 根据虚线样式绘制
    if (lineStroke.dashStyle != DashStyle.solid) {
      final path = Path();
      path.moveTo(start.dx, start.dy);
      path.lineTo(end.dx, end.dy);
      _drawDashedPath(canvas, path, paint, lineStroke.dashStyle);
    } else {
      canvas.drawLine(start, end, paint);
    }

    // ✅ 绘制箭头
    if (stroke is ArrowLineStroke) {
      if (stroke.arrowStyle == ArrowStyle.doubleArrow) {
        _drawSingleArrow(canvas, start, end, lineStroke.strokeWidth,
            lineStroke.color, ArrowStyle.filled,
            isEndArrow: true);
        _drawSingleArrow(canvas, start, end, lineStroke.strokeWidth,
            lineStroke.color, ArrowStyle.filled,
            isEndArrow: false);
      } else {
        _drawSingleArrow(canvas, start, end, lineStroke.strokeWidth,
            lineStroke.color, stroke.arrowStyle,
            isEndArrow: true);
      }
    }
  }

  /// ✅ 绘制单个箭头
  static void _drawSingleArrow(Canvas canvas, Offset start, Offset end,
      double strokeWidth, Color color, ArrowStyle arrowStyle,
      {required bool isEndArrow}) {
    final arrowSize = strokeWidth * 2.5;
    final arrowAngle = math.pi / 6;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);

    if (length < 0.1) return;

    final unitX = dx / length;
    final unitY = dy / length;

    final arrowTip = isEndArrow ? end : start;
    final arrowBase = Offset(
      arrowTip.dx - unitX * arrowSize * 0.3 * (isEndArrow ? 1 : -1),
      arrowTip.dy - unitY * arrowSize * 0.3 * (isEndArrow ? 1 : -1),
    );

    final cosAngle = math.cos(arrowAngle);
    final sinAngle = math.sin(arrowAngle);
    final directionMultiplier = isEndArrow ? -1.0 : 1.0;

    final arrowLeft = Offset(
      arrowBase.dx +
          directionMultiplier *
              arrowSize *
              (unitX * cosAngle - unitY * sinAngle),
      arrowBase.dy +
          directionMultiplier *
              arrowSize *
              (unitY * cosAngle + unitX * sinAngle),
    );

    final arrowRight = Offset(
      arrowBase.dx +
          directionMultiplier *
              arrowSize *
              (unitX * cosAngle + unitY * sinAngle),
      arrowBase.dy +
          directionMultiplier *
              arrowSize *
              (unitY * cosAngle - unitX * sinAngle),
    );

    switch (arrowStyle) {
      case ArrowStyle.filled:
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
        final linePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(arrowTip, arrowLeft, linePaint);
        canvas.drawLine(arrowTip, arrowRight, linePaint);
        break;
      case ArrowStyle.doubleArrow:
        break;
    }
  }

  /// ✅ 绘制矩形
  static void _drawRectangleStroke(Canvas canvas, RectangleStroke stroke) {
    if (stroke.rect.isEmpty) return;

    // 填充
    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawRect(stroke.rect, fillPaint);
    }

    // 描边
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;

    if (stroke.dashStyle != DashStyle.solid) {
      final path = Path()..addRect(stroke.rect);
      _drawDashedPath(canvas, path, paint, stroke.dashStyle);
    } else {
      canvas.drawRect(stroke.rect, paint);
    }
  }

  /// ✅ 绘制圆形/椭圆
  static void _drawCircleStroke(Canvas canvas, CircleStroke stroke) {
    if (stroke.points.length < 2) return;

    final left = stroke.points.map((p) => p.dx).reduce(math.min);
    final top = stroke.points.map((p) => p.dy).reduce(math.min);
    final right = stroke.points.map((p) => p.dx).reduce(math.max);
    final bottom = stroke.points.map((p) => p.dy).reduce(math.max);
    final rect = Rect.fromLTRB(left, top, right, bottom);

    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawOval(rect, fillPaint);
    }

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;

    if (stroke.dashStyle != DashStyle.solid) {
      final path = Path()..addOval(rect);
      _drawDashedPath(canvas, path, paint, stroke.dashStyle);
    } else {
      canvas.drawOval(rect, paint);
    }
  }

  /// ✅ 绘制三角形
  static void _drawTriangleStroke(Canvas canvas, TriangleStroke stroke) {
    if (stroke.points.length < 3) return;

    final path = Path()
      ..moveTo(stroke.points[0].dx, stroke.points[0].dy)
      ..lineTo(stroke.points[1].dx, stroke.points[1].dy)
      ..lineTo(stroke.points[2].dx, stroke.points[2].dy)
      ..close();

    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;

    if (stroke.dashStyle != DashStyle.solid) {
      _drawDashedPath(canvas, path, paint, stroke.dashStyle);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  /// ✅ 绘制菱形
  static void _drawDiamondStroke(Canvas canvas, DiamondStroke stroke) {
    if (stroke.points.length < 4) return;

    final path = Path();
    path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    path.close();

    if (stroke.fillColor != null) {
      final fillPaint = Paint()
        ..color = stroke.fillColor!
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;

    if (stroke.dashStyle != DashStyle.solid) {
      _drawDashedPath(canvas, path, paint, stroke.dashStyle);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  /// ✅ 绘制虚线路径
  static void _drawDashedPath(
      Canvas canvas, Path path, Paint paint, DashStyle dashStyle) {
    // 简单的DashPath实现，或者提取metric
    // 由于Canvas没有直接drawDashedPath，需要手动计算
    final Path dashedPath = Path();

    double dashLength = 10.0;
    double gapLength = 5.0;

    switch (dashStyle) {
      case DashStyle.dot:
        dashLength = 2.0;
        gapLength = 3.0;
        break;
      case DashStyle.shortDash:
        dashLength = 5.0;
        gapLength = 3.0;
        break;
      case DashStyle.longDash:
        dashLength = 10.0;
        gapLength = 5.0;
        break;
      case DashStyle.dashDot:
        dashLength = 10.0;
        gapLength = 5.0;
        // 简化处理，暂不支持复杂的点划线逻辑，统一用长虚线代替
        break;
      case DashStyle.solid:
        canvas.drawPath(path, paint);
        return;
    }

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        if (draw) {
          dashedPath.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  /// 绘制文本框
  static void _drawTextBoxes(Canvas canvas, List<dynamic> textBoxes) {
    for (final textBox in textBoxes) {
      try {
        final position = textBox.position as Offset;
        final size = textBox.size as Size;
        final text = textBox.text as String;

        // 绘制背景
        if (textBox.backgroundColor != null) {
          canvas.drawRect(
            Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
            Paint()
              ..color = textBox.backgroundColor as Color
              ..style = PaintingStyle.fill,
          );
        }

        // 绘制边框
        if (textBox.borderColor != null) {
          canvas.drawRect(
            Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
            Paint()
              ..color = textBox.borderColor as Color
              ..style = PaintingStyle.stroke
              ..strokeWidth = (textBox.borderWidth as double?) ?? 1.0,
          );
        }

        // 绘制文本
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: size.width - 16);
        textPainter.paint(canvas, Offset(position.dx + 8, position.dy + 8));
      } catch (e) {
        debugPrint('⚠️ [EditorExporter] 绘制文本框失败: $e');
      }
    }
  }
}
