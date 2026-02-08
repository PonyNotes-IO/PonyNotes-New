import 'dart:convert'; // ✅ 引入 base64 支持
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// ✅ 编辑器图片基类
/// 支持 PNG、JPG、SVG 等格式的图片
abstract class EditorImage {
  EditorImage({
    required this.id,
    required this.pageIndex,
    required this.pageSize,
    this.dstRect,
  });

  final String id; // 图片唯一标识符
  final int pageIndex; // 所在页面索引
  final Size pageSize; // 页面大小
  Rect? dstRect; // 目标位置和大小

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
    if (dstRect != null) {
      dstRect = dstRect!.translate(offset.dx, offset.dy);
    }
  }

  /// 调整图片大小
  void resize(Size newSize) {
    if (dstRect != null) {
      dstRect = Rect.fromLTWH(
        dstRect!.left,
        dstRect!.top,
        newSize.width,
        newSize.height,
      );
    }
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
      // ✅ 优化：改用 Base64 存储，比原始 List<int> 效率更高，JSON 尺寸更小
      'imageBytesBase64': base64Encode(imageBytes),
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
    Uint8List imageBytes = Uint8List(0);

    // ✅ 向下兼容逻辑：优先读取 Base64，如果不存在则回退到旧的 List<int> 格式
    if (json.containsKey('imageBytesBase64')) {
      final String? base64Str = json['imageBytesBase64'] as String?;
      if (base64Str != null && base64Str.isNotEmpty) {
        try {
          imageBytes = base64Decode(base64Str);
        } catch (e) {
          debugPrint('Failed to decode image Base64: $e');
        }
      }
    } else if (json.containsKey('imageBytes')) {
      final List<dynamic>? imageBytesList =
          json['imageBytes'] as List<dynamic>?;
      if (imageBytesList != null) {
        imageBytes = Uint8List.fromList(imageBytesList.cast<int>());
      }
    }

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
