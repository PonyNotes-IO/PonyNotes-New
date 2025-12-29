import 'dart:ui';

import 'package:flutter/material.dart';

import '../../components/canvas/image/pdf_editor_image.dart';
import '../tools/tool.dart';
import 'shape_strokes.dart';
import 'text_box.dart' as saber_text;
import 'list_box.dart' as saber_list;

/// 简化版的 EditorPage 数据结构，参考 Saber 的页面模型。
///
/// 后续可以逐步对齐 Saber 仓库中的字段与行为，这里先提供最小可用集合：
/// - 页面尺寸
/// - 笔迹列表
class EditorPage {
  /// ✅ 默认页面宽度（改为 A4 纸尺寸，单位：逻辑像素）
  /// A4 纸（纵向）常用点数：595 x 842（72 DPI），保持与之前相同的长宽比（sqrt(2)）
  static const double defaultWidth = 595.0; // A4 宽度（逻辑像素）
  static const double defaultHeight = 842.0; // A4 高度（逻辑像素）
  static const defaultSize = Size(defaultWidth, defaultHeight);

  EditorPage({
    required this.size,
    List<Stroke>? strokes,
    this.backgroundImage,  // ✅ PDF 背景图片
    List<saber_text.TextBox>? textBoxes, // ✅ 文本框列表
    List<saber_list.ListBox>? listBoxes, // ✅ 列表框列表
    List<saber_list.TaskListBox>? taskListBoxes, // ✅ 任务列表框列表
  }) : strokes = strokes ?? <Stroke>[],
       textBoxes = textBoxes ?? <saber_text.TextBox>[],
       listBoxes = listBoxes ?? <saber_list.ListBox>[],
       taskListBoxes = taskListBoxes ?? <saber_list.TaskListBox>[];

  final Size size;
  final List<Stroke> strokes;
  final PdfEditorImage? backgroundImage;  // ✅ PDF 背景图片
  final List<saber_text.TextBox> textBoxes; // ✅ 文本框列表
  final List<saber_list.ListBox> listBoxes; // ✅ 列表框列表
  final List<saber_list.TaskListBox> taskListBoxes; // ✅ 任务列表框列表

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'width': size.width,
      'height': size.height,
      'strokes': strokes.map((Stroke s) => s.toJson()).toList(),
      'textBoxes': textBoxes.map((saber_text.TextBox t) => t.toJson()).toList(), // ✅ 保存文本框列表
      'listBoxes': listBoxes.map((saber_list.ListBox l) => l.toJson()).toList(), // ✅ 保存列表框列表
      'taskListBoxes': taskListBoxes.map((saber_list.TaskListBox t) => t.toJson()).toList(), // ✅ 保存任务列表框列表
      // ✅ 保存 PDF 背景图片信息
      'backgroundImage': backgroundImage != null
          ? <String, dynamic>{
              'pdfFilePath': backgroundImage!.pdfFilePath,
              'pdfPageIndex': backgroundImage!.pdfPageIndex,
              'naturalSize': <String, double>{
                'width': backgroundImage!.naturalSize.width,
                'height': backgroundImage!.naturalSize.height,
              },
              'dstRect': backgroundImage!.dstRect != null
                  ? <String, double>{
                      'left': backgroundImage!.dstRect!.left,
                      'top': backgroundImage!.dstRect!.top,
                      'width': backgroundImage!.dstRect!.width,
                      'height': backgroundImage!.dstRect!.height,
                    }
                  : null,
            }
          : null,
    };
  }

  factory EditorPage.fromJson(Map<String, dynamic> json) {
    final double width = (json['width'] as num?)?.toDouble() ?? defaultWidth;  // ✅ 使用默认宽度而不是0
    final double height = (json['height'] as num?)?.toDouble() ?? defaultHeight;  // ✅ 使用默认高度而不是0
    final List<dynamic> strokeList = json['strokes'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> textBoxList = json['textBoxes'] as List<dynamic>? ?? <dynamic>[]; // ✅ 读取文本框列表
    final List<dynamic> listBoxList = json['listBoxes'] as List<dynamic>? ?? <dynamic>[]; // ✅ 读取列表框列表
    final List<dynamic> taskListBoxList = json['taskListBoxes'] as List<dynamic>? ?? <dynamic>[]; // ✅ 读取任务列表框列表
    
    // ✅ 读取 PDF 背景图片信息
    PdfEditorImage? backgroundImage;
    final bgImageJson = json['backgroundImage'] as Map<String, dynamic>?;
    if (bgImageJson != null) {
      final pdfFilePath = bgImageJson['pdfFilePath'] as String?;
      final pdfPageIndex = bgImageJson['pdfPageIndex'] as int? ?? 0;
      final naturalSizeJson = bgImageJson['naturalSize'] as Map<String, dynamic>?;
      final dstRectJson = bgImageJson['dstRect'] as Map<String, dynamic>?;
      
      if (pdfFilePath != null && naturalSizeJson != null) {
        final naturalSize = Size(
          (naturalSizeJson['width'] as num?)?.toDouble() ?? 0,
          (naturalSizeJson['height'] as num?)?.toDouble() ?? 0,
        );
        
        Rect? dstRect;
        if (dstRectJson != null) {
          dstRect = Rect.fromLTWH(
            (dstRectJson['left'] as num?)?.toDouble() ?? 0,
            (dstRectJson['top'] as num?)?.toDouble() ?? 0,
            (dstRectJson['width'] as num?)?.toDouble() ?? 0,
            (dstRectJson['height'] as num?)?.toDouble() ?? 0,
          );
        }
        
        backgroundImage = PdfEditorImage(
          pdfFilePath: pdfFilePath,
          pdfPageIndex: pdfPageIndex,
          naturalSize: naturalSize,
          dstRect: dstRect,
        );
      }
    }
    
    return EditorPage(
      size: Size(width, height),
      strokes: strokeList
          .whereType<Map<String, dynamic>>()
          .map((json) {
            // ✅ 根据 shape 字段创建对应的形状笔迹
            final shape = json['shape'] as String?;
            switch (shape) {
              case 'line':
                return LineStroke.fromJson(json) as Stroke;
              case 'arrowLine':
                return ArrowLineStroke.fromJson(json) as Stroke;
              case 'rectangle':
                return RectangleStroke.fromJson(json) as Stroke;
              case 'circle':
                return CircleStroke.fromJson(json) as Stroke;
              case 'triangle':
                return TriangleStroke.fromJson(json) as Stroke;
              case 'diamond':
                return DiamondStroke.fromJson(json) as Stroke;
              case 'freePolygon':
                return FreePolygonStroke.fromJson(json) as Stroke;
              default:
                return Stroke.fromJson(json);
            }
          })
          .toList(),
      backgroundImage: backgroundImage,  // ✅ 设置 PDF 背景图片
      textBoxes: textBoxList
          .whereType<Map<String, dynamic>>()
          .map((json) => saber_text.TextBox.fromJson(json))
          .toList(), // ✅ 设置文本框列表
      listBoxes: listBoxList
          .whereType<Map<String, dynamic>>()
          .map((json) => saber_list.ListBox.fromJson(json))
          .toList(), // ✅ 设置列表框列表
      taskListBoxes: taskListBoxList
          .whereType<Map<String, dynamic>>()
          .map((json) => saber_list.TaskListBox.fromJson(json))
          .toList(), // ✅ 设置任务列表框列表
    );
  }
}

/// 简化版 Stroke，参考 Saber 的 Stroke 结构，包含点集合、颜色、线宽和工具类型。
class Stroke {
  Stroke({
    required this.points,
    this.color = Colors.black,
    this.strokeWidth = 3,
    this.toolId,
    this.pressureEnabled = false,  // ✅ 是否支持压感（钢笔支持，圆珠笔不支持）
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final ToolId? toolId;
  final bool pressureEnabled;  // ✅ 压感支持标志

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
      'color': color.value,
      'strokeWidth': strokeWidth,
      'toolId': toolId?.name,
      'pressureEnabled': pressureEnabled,  // ✅ 保存压感支持标志
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
    final int? colorValue = json['color'] as int?;
    final double? strokeWidth = (json['strokeWidth'] as num?)?.toDouble();
    final String? toolIdName = json['toolId'] as String?;
    final bool? pressureEnabled = json['pressureEnabled'] as bool?;  // ✅ 读取压感支持标志
    ToolId? toolId;
    if (toolIdName != null) {
      toolId = ToolId.values.firstWhere(
        (id) => id.name == toolIdName,
        orElse: () => ToolId.fountainPen,
      );
    }
    // ✅ 根据工具类型自动设置压感支持（如果未保存）
    final bool finalPressureEnabled = pressureEnabled ?? 
        (toolId == ToolId.fountainPen);  // 钢笔默认支持压感，其他工具不支持
    return Stroke(
      points: pts,
      color: colorValue != null
          ? Color.fromARGB(
              (colorValue >> 24) & 0xFF,
              (colorValue >> 16) & 0xFF,
              (colorValue >> 8) & 0xFF,
              colorValue & 0xFF,
            )
          : Colors.black,
      strokeWidth: strokeWidth ?? 3,
      toolId: toolId,
      pressureEnabled: finalPressureEnabled,  // ✅ 设置压感支持标志
    );
  }
  
  /// ✅ 删除第一个点（用于激光笔淡出）
  void popFirstPoint() {
    if (points.isNotEmpty) {
      points.removeAt(0);
    }
  }
}

/// ✅ 页面状态包装器，用于精确的状态更新通知
/// 避免橡皮擦操作时触发全量重建
class EditorPageNotifier extends ChangeNotifier {
  EditorPageNotifier(this._page);

  EditorPage _page;

  EditorPage get page => _page;

  /// 更新页面数据并通知监听器
  void updatePage(EditorPage newPage) {
    _page = newPage;
    notifyListeners();
  }

  /// 只更新笔迹列表
  void updateStrokes(List<Stroke> newStrokes) {
    _page = EditorPage(
      size: _page.size,
      strokes: newStrokes,
      backgroundImage: _page.backgroundImage,
      textBoxes: _page.textBoxes,
      listBoxes: _page.listBoxes,
      taskListBoxes: _page.taskListBoxes,
    );
    notifyListeners();
  }

  /// 删除指定的笔迹
  void removeStrokes(List<Stroke> strokesToRemove) {
    final newStrokes = List<Stroke>.from(_page.strokes)
      ..removeWhere((stroke) => strokesToRemove.contains(stroke));

    updateStrokes(newStrokes);
  }
}


