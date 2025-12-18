import 'dart:ui';

/// 简化版的 EditorPage 数据结构，参考 Saber 的页面模型。
///
/// 后续可以逐步对齐 Saber 仓库中的字段与行为，这里先提供最小可用集合：
/// - 页面尺寸
/// - 笔迹列表
class EditorPage {
  EditorPage({
    required this.size,
    List<Stroke>? strokes,
  }) : strokes = strokes ?? <Stroke>[];

  final Size size;
  final List<Stroke> strokes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'width': size.width,
      'height': size.height,
      'strokes': strokes.map((Stroke s) => s.toJson()).toList(),
    };
  }

  factory EditorPage.fromJson(Map<String, dynamic> json) {
    final double width = (json['width'] as num?)?.toDouble() ?? 0;
    final double height = (json['height'] as num?)?.toDouble() ?? 0;
    final List<dynamic> strokeList = json['strokes'] as List<dynamic>? ?? <dynamic>[];
    return EditorPage(
      size: Size(width, height),
      strokes: strokeList
          .whereType<Map<String, dynamic>>()
          .map(Stroke.fromJson)
          .toList(),
    );
  }
}

/// 简化版 Stroke，参考 Saber 的 Stroke 结构，仅保留点集合。
class Stroke {
  Stroke(this.points);

  final List<Offset> points;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'points': points
          .map(
            (Offset p) => <String, double>{
              'x': p.dx,
              'y': p.dy,
            },
          )
          .toList(),
    };
  }

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final List<dynamic> list = json['points'] as List<dynamic>? ?? <dynamic>[];
    final List<Offset> pts = <Offset>[];
    for (final dynamic item in list) {
      if (item is Map<String, dynamic>) {
        final double? x = (item['x'] as num?)?.toDouble();
        final double? y = (item['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          pts.add(Offset(x, y));
        }
      }
    }
    return Stroke(pts);
  }
}


