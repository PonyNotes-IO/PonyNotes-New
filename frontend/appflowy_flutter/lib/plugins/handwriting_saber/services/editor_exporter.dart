import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/components/canvas/image/editor_image.dart';
import '../third_party/saber_core/data/editor/editor_core_info.dart';
import '../third_party/saber_core/data/editor/page.dart';
import '../third_party/saber_core/data/tools/tool.dart';

/// PDF导出器 - 高性能版本
/// 使用直接Canvas绘制方式，避免Widget截图的性能问题
abstract class EditorExporter {
  /// 默认背景颜色
  static const defaultBackgroundColor = Color(0xFFFCFCFC);
  
  /// 导出分辨率倍数（1.0 = 原始分辨率，1.5 = 1.5倍清晰度）
  static const double exportPixelRatio = 1.5;

  /// 生成PDF文档（高性能版本）
  /// 
  /// [coreInfo] 编辑器核心信息
  /// [context] BuildContext（用于获取图片资源，可选）
  /// [pageNotifiers] 页面状态通知器
  /// [onProgress] 进度回调 (当前页, 总页数)
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

    debugPrint('📄[EditorExporter] 开始生成PDF，共 $totalPages 页（高性能模式）');
    final startTime = DateTime.now();

    // 逐页渲染
    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final page = pageNotifiers != null && pageIndex < pageNotifiers.length
          ? pageNotifiers[pageIndex].page
          : pages[pageIndex];
      
      debugPrint('📄[EditorExporter] 正在处理第 ${pageIndex + 1}/$totalPages 页');
      onProgress?.call(pageIndex + 1, totalPages);

      try {
        // 使用Canvas直接绘制
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

  /// 使用Canvas直接渲染页面为图片
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
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, renderWidth.toDouble(), renderHeight.toDouble()));
    
    // 应用缩放
    canvas.scale(exportPixelRatio, exportPixelRatio);
    
    // 1. 绘制背景色
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, pageSize.width, pageSize.height), bgPaint);
    
    // 2. 绘制背景图案
    _drawBackgroundPattern(
      canvas, 
      pageSize, 
      coreInfo.backgroundPattern, 
      coreInfo.lineHeight, 
      coreInfo.lineThickness,
    );
    
    // 3. 绘制图片
    for (final image in page.images) {
      await _drawImage(canvas, image);
    }
    
    // 4. 绘制笔迹
    _drawStrokes(canvas, page.strokes);
    
    // 5. 绘制文本框
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
        for (double y = lineHeight.toDouble(); y < size.height; y += lineHeight) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case CanvasBackgroundPattern.grid:
        for (double y = lineHeight.toDouble(); y < size.height; y += lineHeight) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (double x = lineHeight.toDouble(); x < size.width; x += lineHeight) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;
      case CanvasBackgroundPattern.dots:
        final dotPaint = Paint()
          ..color = Colors.grey.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        for (double y = lineHeight.toDouble(); y < size.height; y += lineHeight) {
          for (double x = lineHeight.toDouble(); x < size.width; x += lineHeight) {
            canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
          }
        }
        break;
      case CanvasBackgroundPattern.none:
        break;
    }
  }

  /// 绘制图片
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
          Rect.fromLTWH(0, 0, uiImage.width.toDouble(), uiImage.height.toDouble()),
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
