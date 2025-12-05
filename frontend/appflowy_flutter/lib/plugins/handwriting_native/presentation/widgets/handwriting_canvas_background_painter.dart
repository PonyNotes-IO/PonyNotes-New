import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 手写笔记画布背景绘制器
/// 绘制蓝色横格线和红色竖线，对齐 Xournal++ 的 Lined Background 样式
class HandwritingCanvasBackgroundPainter extends CustomPainter {
  const HandwritingCanvasBackgroundPainter({
    required this.pageWidth,
    required this.pageHeight,
    this.lineSpacing = 24.0,
    this.headerSize = 80.0,
    this.footerSize = 60.0,
    this.margin = 72.0,
    this.hLineColor = const Color(0xFF1E90FF), // dodgerblue (Xournal++ 默认横格线颜色)
    this.vLineColor = const Color(0xFFFF1493), // deeppink (Xournal++ 默认竖线颜色)
    this.lineWidth = 0.5,
    this.backgroundColor = Colors.white,
  });

  /// 页面宽度（点）
  final double pageWidth;

  /// 页面高度（点）
  final double pageHeight;

  /// 行间距（点，默认24.0）
  final double lineSpacing;

  /// 顶部留白（点，默认80.0）
  final double headerSize;

  /// 底部留白（点，默认60.0）
  final double footerSize;

  /// 左边距（点，默认72.0，约1英寸）
  final double margin;

  /// 横格线颜色（蓝色）
  final Color hLineColor;

  /// 竖线颜色（红色）
  final Color vLineColor;

  /// 线宽（点，默认0.5）
  final double lineWidth;

  /// 背景颜色（白色）
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制白色背景
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // 2. 计算缩放比例（画布尺寸 vs 页面尺寸），保持宽高比
    final scaleX = size.width / pageWidth;
    final scaleY = size.height / pageHeight;
    final scale = math.min(scaleX, scaleY);

    // 3. 计算实际绘制区域（居中显示）
    final drawWidth = pageWidth * scale;
    final drawHeight = pageHeight * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    // 4. 保存画布状态并应用变换
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    // 5. 绘制横格线
    final paintHLine = Paint()
      ..color = hLineColor
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;

    final startY = headerSize;
    final endY = pageHeight - footerSize;
    var currentY = startY;

    while (currentY <= endY) {
      canvas.drawLine(
        Offset(0, currentY),
        Offset(pageWidth, currentY),
        paintHLine,
      );
      currentY += lineSpacing;
    }

    // 6. 绘制竖线（左边距）
    final paintVLine = Paint()
      ..color = vLineColor
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(margin, 0),
      Offset(margin, pageHeight),
      paintVLine,
    );

    // 7. 恢复画布状态
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HandwritingCanvasBackgroundPainter oldDelegate) {
    return oldDelegate.pageWidth != pageWidth ||
        oldDelegate.pageHeight != pageHeight ||
        oldDelegate.lineSpacing != lineSpacing ||
        oldDelegate.headerSize != headerSize ||
        oldDelegate.footerSize != footerSize ||
        oldDelegate.margin != margin ||
        oldDelegate.hLineColor != hLineColor ||
        oldDelegate.vLineColor != vLineColor ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}


