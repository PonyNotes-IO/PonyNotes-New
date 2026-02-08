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

      // 🔍 策略改进：
      // 1. 尝试动态获取 cropBox (如果 pdfrx 支持)
      // 2. 强制使用 BoxFit.contain 计算目标区域，杜绝变形

      Rect? cropRect;
      try {
        // 尝试反射获取名为 cropBox 或 visibleRect 的属性
        dynamic p = pdfPage;
        // 常见的 PDF 库 cropBox 可能叫 cropBox, visibleRect, mediaBox 等
        // 这里尝试几个可能的名称
        final dynamic box =
            _tryGetProperty(p, 'cropBox') ?? _tryGetProperty(p, 'viewRect');
        if (box != null && box.toString().contains('Rect')) {
          // 假设是 Rect 类型 (left, top, width, height)
          // 我们能否直接转为 Rect? 依赖于具体实现，这里做保守处理
          // 如果能拿到 x, y, w, h 就太好了
          debugPrint('✅ [EditorExporter] Found cropBox/viewRect: $box');
          // 暂无法确定类型，仅作为日志。若 pdfrx 更新支持我们会用到。
          // 如果 box 是具体对象，可以尝试提取 left/top/width/height
        }
      } catch (e) {
        debugPrint('⚠️ [EditorExporter] CropBox probe error: $e');
      }

      // 计算目标渲染尺寸：
      // 我们希望最终绘制的图片宽度能填满 pageSize.width * pixelRatio
      final int renderWidth = (pageSize.width * exportPixelRatio).toInt();

      // 执行渲染
      // 如果 pdfrx 的 render 方法支持 x, y, width, height 为源裁剪区域
      // 我们目前无法确知，所以使用标准 render
      final pdfPageImage = await pdfPage.render(
        width: renderWidth,
        // height auto
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

      // 4. 绘制逻辑：基于 CropBox 的精确裁剪
      // 核心假设：屏幕上的 PdfPageView 渲染的是 CropBox，而导出渲染的是 MediaBox
      // 我们必须找到 CropBox，并只绘制这部分内容

      Rect? cropRect;
      // Rect? cropRect; // This was the duplicate declaration, removed.
      try {
        // [Probe] 尝试获取 CropBox
        // pdfrx 可能使用 unsafe c++ binding，或者属性名可能是 cropBox / viewRect
        // 我们尝试获取 left, top, right, bottom 或者 rect 对象
        dynamic p = pdfPage;

        // 尝试1: 直接获取 cropBox
        dynamic box = _tryGetProperty(p, 'cropBox');
        if (box == null) box = _tryGetProperty(p, 'viewRect'); // fallback
        if (box == null) box = _tryGetProperty(p, 'visibleRect'); // fallback

        if (box != null) {
          // 假设 box 是 PdfRect 或类似结构，尝试访问 left, top, width, height
          final double? l = _castToDouble(
              _tryGetProperty(box, 'left') ?? _tryGetProperty(box, 'x'));
          final double? t = _castToDouble(
              _tryGetProperty(box, 'top') ?? _tryGetProperty(box, 'y'));
          final double? w = _castToDouble(
              _tryGetProperty(box, 'width') ?? _tryGetProperty(box, 'w'));
          final double? h = _castToDouble(
              _tryGetProperty(box, 'height') ?? _tryGetProperty(box, 'h'));

          if (l != null && t != null && w != null && h != null) {
            cropRect = Rect.fromLTWH(l, t, w, h);
            debugPrint('✅ [EditorExporter] Detected CropBox: $cropRect');
          }
        }

        // 尝试2: 如果没有 cropBox 对象，直接在 page 上找 cropX, cropY 等
        if (cropRect == null) {
          final double? x = _castToDouble(_tryGetProperty(p, 'cropX'));
          final double? y = _castToDouble(_tryGetProperty(p, 'cropY'));
          final double? w = _castToDouble(_tryGetProperty(p, 'cropW'));
          final double? h = _castToDouble(_tryGetProperty(p, 'cropH'));
          if (x != null && y != null && w != null && h != null) {
            cropRect = Rect.fromLTWH(x, y, w, h);
            debugPrint(
                '✅ [EditorExporter] Detected Crop properties: $cropRect');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [EditorExporter] CropBox detection failed: $e');
      }

      // 准备绘制源/目标
      Rect srcRect;
      Rect dstRect;

      if (cropRect != null) {
        // --- 方案 A: 使用探测到的 CropBox ---
        // render() 产生的是 MediaBox 图像 (naturalImage尺寸)
        // 我们需要从 MediaBox 图像中切出 CropBox 区域

        // 坐标转换：PDF坐标 (points) -> 渲染图像坐标 (pixels)
        // scaleFactor = renderWidth / pdfPageWidth (assuming pdfPageWidth is MediaBox width)
        // 如果 pdfPageWidth 是 CropBox width, 那么我们需要用 naturalWidth / MediaBoxWidth?
        // 我们已知 uiImage.width 是 renderWidth
        // 假设 pdfPageWidth/Height 是 MediaBox 尺寸 (因为之前推断 ratio=1)

        final double imageWidth = uiImage.width.toDouble();
        final double imageHeight = uiImage.height.toDouble();

        final double scaleX = imageWidth / pdfPageWidth;
        final double scaleY =
            imageHeight / pdfPageHeight; // 如果 pdfPageHeight 是 MediaBox

        // 如果 pdfPage.* 是 MediaBox，那么 cropRect 是相对于 MediaBox 的
        srcRect = Rect.fromLTWH(cropRect.left * scaleX, cropRect.top * scaleY,
            cropRect.width * scaleX, cropRect.height * scaleY);

        // 目标：填满 pageSize (CropBox 比例)
        dstRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

        debugPrint(
            '📄[EditorExporter] Application CropBox: PDF=$cropRect -> Pixels=$srcRect');
      } else {
        // --- 方案 B: 无法探测 CropBox (Fallback) ---
        // 使用 BoxFit.contain 保证不变形，居中显示
        // 这是之前的防御性策略

        final double imageWidth = uiImage.width.toDouble();
        final double imageHeight = uiImage.height.toDouble();

        final Size srcSize = Size(imageWidth, imageHeight);
        final Size dstSize = Size(pageSize.width, pageSize.height);

        final FittedSizes fittedSizes =
            applyBoxFit(BoxFit.contain, srcSize, dstSize);

        dstRect = Alignment.center.inscribe(
          fittedSizes.destination,
          Rect.fromLTWH(0, 0, dstSize.width, dstSize.height),
        );

        srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);

        debugPrint(
            '⚠️ [EditorExporter] No CropBox found. Using Fallback BoxFit.contain');
      }

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

  static double? _castToDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return null;
  }

  static dynamic _tryGetProperty(Object obj, String name) {
    try {
      return (obj as dynamic).noSuchMethod(Invocation.getter(Symbol(name)));
    } catch (_) {
      return null;
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
