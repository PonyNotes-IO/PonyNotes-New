import 'dart:convert';
import 'dart:ui';

import 'page.dart';

/// 简化版 EditorCoreInfo，负责管理整份手写笔记的数据。
///
/// 这里只实现单文件、单文档的最小能力：
/// - 页面列表（当前仅用第一页）
/// - JSON 序列化/反序列化（用于本地 PoC 存储）
class EditorCoreInfo {
  EditorCoreInfo({
    required this.pages,
  });

  final List<EditorPage> pages;

  EditorPage get firstPage {
    if (pages.isEmpty) {
      return EditorPage(size: const Size(800, 600));
    }
    return pages.first;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pages': pages.map((EditorPage p) => p.toJson()).toList(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory EditorCoreInfo.fromJson(Map<String, dynamic> json) {
    final List<dynamic> pageList = json['pages'] as List<dynamic>? ?? <dynamic>[];
    return EditorCoreInfo(
      pages: pageList
          .whereType<Map<String, dynamic>>()
          .map(EditorPage.fromJson)
          .toList(),
    );
  }

  factory EditorCoreInfo.empty() {
    return EditorCoreInfo(
      pages: <EditorPage>[
        EditorPage(size: const Size(800, 600)),
      ],
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


