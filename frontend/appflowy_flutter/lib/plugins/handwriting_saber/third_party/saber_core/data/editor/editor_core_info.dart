import 'dart:convert';
import 'dart:ui';

import '../../components/canvas/canvas_background_pattern.dart';
import 'page.dart';

/// 简化版 EditorCoreInfo，负责管理整份手写笔记的数据。
///
/// 这里只实现单文件、单文档的最小能力：
/// - 页面列表（当前仅用第一页）
/// - 背景纸模式、行高、线粗等配置
/// - JSON 序列化/反序列化（用于本地 PoC 存储）
class EditorCoreInfo {
  EditorCoreInfo({
    required this.pages,
    this.backgroundColor,
    this.backgroundPattern = CanvasBackgroundPattern.lined,
    this.lineHeight = 28, // ✅ 增大默认横线间距，便于视觉阅读（由 20 -> 28）
    this.lineThickness = 1,
  });

  final List<EditorPage> pages;
  final Color? backgroundColor;
  final CanvasBackgroundPattern backgroundPattern;
  final int lineHeight;
  final int lineThickness;
  
  /// ✅ 激光笔笔迹列表（单独管理，用于淡出效果）
  final List<Stroke> laserStrokes = [];

  EditorPage get firstPage {
    if (pages.isEmpty) {
      return EditorPage(size: const Size(800, 600));
    }
    return pages.first;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pages': pages.map((EditorPage p) => p.toJson()).toList(),
      'backgroundColor': backgroundColor?.value,
      'backgroundPattern': backgroundPattern.name,
      'lineHeight': lineHeight,
      'lineThickness': lineThickness,
      'laserStrokes': laserStrokes.map((Stroke s) => s.toJson()).toList(),  // ✅ 保存激光笔笔迹
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory EditorCoreInfo.fromJson(Map<String, dynamic> json) {
    final List<dynamic> pageList = json['pages'] as List<dynamic>? ?? <dynamic>[];
    final int? backgroundColorValue = json['backgroundColor'] as int?;
    final String? patternName = json['backgroundPattern'] as String?;
    final List<dynamic> laserStrokesList = json['laserStrokes'] as List<dynamic>? ?? <dynamic>[];  // ✅ 读取激光笔笔迹
    
    final coreInfo = EditorCoreInfo(
      pages: pageList
          .whereType<Map<String, dynamic>>()
          .map(EditorPage.fromJson)
          .toList(),
      backgroundColor: backgroundColorValue != null 
          ? Color.fromARGB(
              (backgroundColorValue >> 24) & 0xFF,
              (backgroundColorValue >> 16) & 0xFF,
              (backgroundColorValue >> 8) & 0xFF,
              backgroundColorValue & 0xFF,
            ) 
          : null,
      backgroundPattern: patternName != null
          ? CanvasBackgroundPattern.values.firstWhere(
              (p) => p.name == patternName,
              orElse: () => CanvasBackgroundPattern.lined,
            )
          : CanvasBackgroundPattern.lined,
      lineHeight: json['lineHeight'] as int? ?? 20,
      lineThickness: json['lineThickness'] as int? ?? 1,
    );
    
    // ✅ 加载激光笔笔迹
    coreInfo.laserStrokes.addAll(
      laserStrokesList
          .whereType<Map<String, dynamic>>()
          .map(Stroke.fromJson)
          .toList(),
    );
    
    return coreInfo;
  }

  factory EditorCoreInfo.empty() {
    return EditorCoreInfo(
      pages: <EditorPage>[
        EditorPage(size: const Size(800, 600)),
      ],
      backgroundColor: const Color(0xFFFCFCFC), // 浅灰色背景
      backgroundPattern: CanvasBackgroundPattern.lined,
      lineHeight: 20,
      lineThickness: 1,
    );
  }

  static EditorCoreInfo fromJsonString(String content) {
    if (content.trim().isEmpty) {
      return EditorCoreInfo.empty();
    }
    final dynamic decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return EditorCoreInfo.fromJson(decoded);
    }
    return EditorCoreInfo.empty();
  }
}


