import 'package:flutter/material.dart';

import '../../data/editor/editor_core_info.dart';
import '../../data/editor/page.dart';

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
    return CustomPaint(
      painter: _SaberCoreCanvasPainter(
        page: page,
        currentStroke: currentStroke,
      ),
    );
  }
}

class _SaberCoreCanvasPainter extends CustomPainter {
  _SaberCoreCanvasPainter({
    required this.page,
    this.currentStroke,
  });

  final EditorPage page;
  final Stroke? currentStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 简单按比例映射到当前画布大小
    final double scaleX = size.width / page.size.width;
    final double scaleY = size.height / page.size.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final double drawWidth = page.size.width * scale;
    final double drawHeight = page.size.height * scale;
    final double offsetX = (size.width - drawWidth) / 2;
    final double offsetY = (size.height - drawHeight) / 2;

    void drawStroke(Stroke stroke) {
      if (stroke.points.isEmpty) {
        return;
      }
      if (stroke.points.length == 1) {
        final Offset p = _transform(stroke.points.first, scale, offsetX, offsetY);
        canvas.drawCircle(p, 1.5, paint);
        return;
      }
      final Path path = Path();
      final Offset first = _transform(stroke.points.first, scale, offsetX, offsetY);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        final Offset p =
            _transform(stroke.points[i], scale, offsetX, offsetY);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    for (final Stroke stroke in page.strokes) {
      drawStroke(stroke);
    }
    if (currentStroke != null) {
      drawStroke(currentStroke!);
    }
  }

  Offset _transform(Offset p, double scale, double offsetX, double offsetY) {
    return Offset(
      offsetX + p.dx * scale,
      offsetY + p.dy * scale,
    );
  }

  @override
  bool shouldRepaint(covariant _SaberCoreCanvasPainter oldDelegate) {
    return oldDelegate.page != page ||
        oldDelegate.currentStroke != currentStroke;
  }
}


