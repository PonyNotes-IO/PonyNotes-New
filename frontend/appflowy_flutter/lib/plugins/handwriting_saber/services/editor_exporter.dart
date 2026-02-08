import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/editor_image.dart';
import '../third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/page.dart';
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
  /// 关键修复：正确处理PDF页面缩放，确保与页面坐标系对齐
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

      // 获取目标矩形
      // ✅ 修复：强制使用页面尺寸作为目标区域，忽略 pdfImage.dstRect
      // 屏幕上的渲染逻辑（SaberCoreCanvas -> _PdfBackground）总是填满整个页面区域（BoxFit.contain）
      // 使用 pdfImage.dstRect 会导致导出时与屏幕显示不一致（偏移或缩放错误）
      final dstRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);

      // ✅ 关键修复：正确计算缩放比例
      // PDF页面需要缩放以适应dstRect（类似BoxFit.contain）
      // 使用最小缩放比例，确保整个PDF页面都能显示在目标区域内
      final scaleX = dstRect.width / pdfPageWidth;
      final scaleY = dstRect.height / pdfPageHeight;
      final scale = scaleX < scaleY ? scaleX : scaleY;

      // 计算渲染尺寸（基于缩放后的尺寸）
      final scaledWidth = pdfPageWidth * scale;
      final scaledHeight = pdfPageHeight * scale;
      final renderWidth = (scaledWidth * exportPixelRatio).toInt();
      final renderHeight = (scaledHeight * exportPixelRatio).toInt();

      debugPrint(
          '📄[EditorExporter] PDF原始尺寸: ${pdfPageWidth}x${pdfPageHeight}, dstRect: $dstRect');
      debugPrint(
          '📄[EditorExporter] 缩放比例: $scale, 缩放后尺寸: ${scaledWidth}x${scaledHeight}, 渲染尺寸: ${renderWidth}x$renderHeight');

      // 渲染PDF页面为图片
      final pdfPageImage = await pdfPage.render(
        width: renderWidth,
        height: renderHeight,
        backgroundColor: Colors.white,
      );

      if (pdfPageImage == null) {
        debugPrint('⚠️ [EditorExporter] PDF页面渲染失败');
        pdfDocument.dispose();
        return;
      }

      // 转换为ui.Image
      final uiImage = await pdfPageImage.createImage();

      // ✅ 正确绘制到dstRect（保持与Saber原版预览一致的行为）
      // 计算居中偏移
      final offsetX = dstRect.left + (dstRect.width - scaledWidth) / 2;
      final offsetY = dstRect.top + (dstRect.height - scaledHeight) / 2;

      // 创建正确的目标矩形
      final alignedDstRect =
          Rect.fromLTWH(offsetX, offsetY, scaledWidth, scaledHeight);

      canvas.drawImageRect(
        uiImage,
        Rect.fromLTWH(
            0, 0, uiImage.width.toDouble(), uiImage.height.toDouble()),
        alignedDstRect,
        Paint(),
      );

      debugPrint('📄[EditorExporter] PDF背景渲染完成，绘制位置: $alignedDstRect');

      // 清理资源
      uiImage.dispose();
      pdfPageImage.dispose();
      pdfDocument.dispose();
    } catch (e) {
      debugPrint('❌ [EditorExporter] 绘制PDF背景失败: $e');
      // 不抛出异常，继续渲染其他内容
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

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // 处理荧光笔
      if (stroke.toolId == ToolId.highlighter) {
        paint.color = stroke.color.withValues(alpha: 0.5);
        paint.strokeWidth = stroke.strokeWidth * 2;
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
        // 绘制路径
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }

        canvas.drawPath(path, paint);
      }
    }
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
