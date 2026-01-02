import 'package:flutter/material.dart';

import '../editor/page.dart';
import '../tools/tool.dart';
import '../../components/canvas/image/pdf_editor_image.dart';
import '../../components/canvas/webview/webview_editor_element.dart';

/// ✅ 选择结果（存储选中的对象）
class SelectResult {
  SelectResult({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.webViews,
    required this.selectionPath,
    this.selectMode = SelectMode.click,
    this.selectionStartPoint,
    this.selectionEndPoint,
  });

  int pageIndex; // 页面索引
  List<Stroke> strokes; // 选中的笔迹列表（可修改）
  List<PdfEditorImage> images; // 选中的图片列表（可修改）
  List<WebViewEditorElement> webViews; // 选中的WebView列表（可修改）
  Path selectionPath; // 选择区域的路径（用于套索模式）
  
  /// ✅ 新增：选择模式
  SelectMode selectMode;
  
  /// ✅ 新增：选择起点（用于矩形框选）
  Offset? selectionStartPoint;
  
  /// ✅ 新增：选择终点（用于矩形框选）
  Offset? selectionEndPoint;

  bool get isEmpty => strokes.isEmpty && images.isEmpty && webViews.isEmpty;
  
  /// ✅ 获取矩形选择框（用于矩形框选模式）
  Rect? getSelectionRect() {
    if (selectMode != SelectMode.rectangle || 
        selectionStartPoint == null || 
        selectionEndPoint == null) {
      return null;
    }
    
    return Rect.fromPoints(selectionStartPoint!, selectionEndPoint!);
  }

  /// ✅ 移动选中的对象
  void move(Offset offset) {
    // 移动所有选中的笔迹
    for (final stroke in strokes) {
      for (int i = 0; i < stroke.points.length; i++) {
        stroke.points[i] = stroke.points[i] + offset;
      }
    }

    // 移动所有选中的图片
    for (final image in images) {
      if (image.dstRect != null) {
        image.dstRect = image.dstRect!.shift(offset);
      }
    }

    // 移动所有选中的WebView
    for (final webView in webViews) {
      webView.dstRect = webView.dstRect.shift(offset);
    }

    // 移动选择路径
    selectionPath = selectionPath.shift(offset);
  }

  /// ✅ 获取选择区域的边界框
  Rect? getBoundingBox() {
    if (isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    // 从笔迹中获取边界
    for (final stroke in strokes) {
      for (final point in stroke.points) {
        minX = minX < point.dx ? minX : point.dx;
        minY = minY < point.dy ? minY : point.dy;
        maxX = maxX > point.dx ? maxX : point.dx;
        maxY = maxY > point.dy ? maxY : point.dy;
      }
    }

    // 从图片中获取边界
    for (final image in images) {
      if (image.dstRect != null) {
        final rect = image.dstRect!;
        minX = minX < rect.left ? minX : rect.left;
        minY = minY < rect.top ? minY : rect.top;
        maxX = maxX > rect.right ? maxX : rect.right;
        maxY = maxY > rect.bottom ? maxY : rect.bottom;
      }
    }

    // 从WebView中获取边界
    for (final webView in webViews) {
      final rect = webView.dstRect;
      minX = minX < rect.left ? minX : rect.left;
      minY = minY < rect.top ? minY : rect.top;
      maxX = maxX > rect.right ? maxX : rect.right;
      maxY = maxY > rect.bottom ? maxY : rect.bottom;
    }

    if (minX == double.infinity) return null;

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

