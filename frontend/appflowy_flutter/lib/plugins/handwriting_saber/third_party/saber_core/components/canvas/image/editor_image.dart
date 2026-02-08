import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// ✅ 编辑器图片基类
/// 支持 PNG、JPG、SVG 等格式的图片
/// 已修改为继承自 ChangeNotifier 以支持图片位置变化的监听
abstract class EditorImage extends ChangeNotifier {
  EditorImage({
    required this.id,
    required this.pageIndex,
    required this.pageSize,
    this.newImage = true,
    Rect? dstRect,
  }) : _dstRect = dstRect ?? Rect.zero;

  final String id; // 图片唯一标识符
  final int pageIndex; // 所在页面索引
  final Size pageSize; // 页面大小

  /// 如果是新图片，加载时将处于 [active] 状态（可拖动）
  bool newImage;

  Rect _dstRect;
  Rect get dstRect => _dstRect;
  set dstRect(Rect value) {
    if (_dstRect != value) {
      _dstRect = value;
      // 通知监听器（图片位置已更改）
      try {
        notifyListeners();
      } catch (e) {
        // 忽略通知错误
      }
    }
  }

  /// 获取图片类型
  String get imageType;

  /// 序列化为 JSON
  Map<String, dynamic> toJson();

  /// 从 JSON 反序列化
  static EditorImage fromJson(Map<String, dynamic> json) {
    final String? type = json['type'] as String?;
    if (type == 'png' || type == 'jpg' || type == 'jpeg' || type == 'image') {
      return PngEditorImage.fromJson(json);
    } else if (type == 'svg') {
      return SvgEditorImage.fromJson(json);
    }
    throw Exception('未知的图片类型: $type');
  }

  /// 移动图片
  void move(Offset offset) {
    dstRect = dstRect.translate(offset.dx, offset.dy);
  }

  /// 调整图片大小
  void resize(Size newSize) {
    dstRect = Rect.fromLTWH(
      dstRect.left,
      dstRect.top,
      newSize.width,
      newSize.height,
    );
  }
}

/// ✅ PNG/JPG 图片
class PngEditorImage extends EditorImage {
  PngEditorImage({
    required super.id,
    required this.imageBytes,
    required this.extension,
    required super.pageIndex,
    required super.pageSize,
    super.newImage = true,
    super.dstRect,
  });

  final Uint8List imageBytes; // 图片字节数据
  final String extension; // 文件扩展名 (.png, .jpg, .jpeg等)

  @override
  String get imageType => 'image';

  /// 获取图片作为 ImageProvider
  ImageProvider get imageProvider => MemoryImage(imageBytes);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': imageType,
      'id': id,
      'imageBytes': imageBytes.toList(), // 转换为 List<int> 以便序列化
      'extension': extension,
      'pageIndex': pageIndex,
      'pageSize': {
        'width': pageSize.width,
        'height': pageSize.height,
      },
      'dstRect': dstRect != null
          ? {
              'left': dstRect!.left,
              'top': dstRect!.top,
              'width': dstRect!.width,
              'height': dstRect!.height,
            }
          : null,
    };
  }

  factory PngEditorImage.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? imageBytesList = json['imageBytes'] as List<dynamic>?;
    final Uint8List imageBytes = imageBytesList != null
        ? Uint8List.fromList(imageBytesList.cast<int>())
        : Uint8List(0);

    final pageSizeJson = json['pageSize'] as Map<String, dynamic>?;
    final pageSize = pageSizeJson != null
        ? Size(
            (pageSizeJson['width'] as num?)?.toDouble() ?? 0,
            (pageSizeJson['height'] as num?)?.toDouble() ?? 0,
          )
        : const Size(595, 842);

    final dstRectJson = json['dstRect'] as Map<String, dynamic>?;
    Rect? dstRect;
    if (dstRectJson != null) {
      dstRect = Rect.fromLTWH(
        (dstRectJson['left'] as num?)?.toDouble() ?? 0,
        (dstRectJson['top'] as num?)?.toDouble() ?? 0,
        (dstRectJson['width'] as num?)?.toDouble() ?? 0,
        (dstRectJson['height'] as num?)?.toDouble() ?? 0,
      );
    }

    return PngEditorImage(
      id: json['id'] as String? ?? '',
      imageBytes: imageBytes,
      extension: json['extension'] as String? ?? '.png',
      pageIndex: json['pageIndex'] as int? ?? 0,
      pageSize: pageSize,
      dstRect: dstRect,
    );
  }
}

/// ✅ SVG 图片
class SvgEditorImage extends EditorImage {
  SvgEditorImage({
    required super.id,
    required this.svgString,
    required super.pageIndex,
    required super.pageSize,
    super.newImage = true,
    super.dstRect,
  });

  final String svgString; // SVG 字符串内容

  @override
  String get imageType => 'svg';

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': imageType,
      'id': id,
      'svgString': svgString,
      'pageIndex': pageIndex,
      'pageSize': {
        'width': pageSize.width,
        'height': pageSize.height,
      },
      'dstRect': dstRect != null
          ? {
              'left': dstRect!.left,
              'top': dstRect!.top,
              'width': dstRect!.width,
              'height': dstRect!.height,
            }
          : null,
    };
  }

  factory SvgEditorImage.fromJson(Map<String, dynamic> json) {
    final pageSizeJson = json['pageSize'] as Map<String, dynamic>?;
    final pageSize = pageSizeJson != null
        ? Size(
            (pageSizeJson['width'] as num?)?.toDouble() ?? 0,
            (pageSizeJson['height'] as num?)?.toDouble() ?? 0,
          )
        : const Size(595, 842);

    final dstRectJson = json['dstRect'] as Map<String, dynamic>?;
    Rect? dstRect;
    if (dstRectJson != null) {
      dstRect = Rect.fromLTWH(
        (dstRectJson['left'] as num?)?.toDouble() ?? 0,
        (dstRectJson['top'] as num?)?.toDouble() ?? 0,
        (dstRectJson['width'] as num?)?.toDouble() ?? 0,
        (dstRectJson['height'] as num?)?.toDouble() ?? 0,
      );
    }

    return SvgEditorImage(
      id: json['id'] as String? ?? '',
      svgString: json['svgString'] as String? ?? '',
      pageIndex: json['pageIndex'] as int? ?? 0,
      pageSize: pageSize,
      dstRect: dstRect,
    );
  }
}
