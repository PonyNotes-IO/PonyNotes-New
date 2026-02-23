import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 编辑器图片基类
/// 支持 PNG、JPG、SVG 等格式的图片，以及缩放、移动、旋转
abstract class EditorImage extends ChangeNotifier {
  EditorImage({
    required this.id,
    required this.pageIndex,
    required this.pageSize,
    this.newImage = true,
    Rect? dstRect,
    double rotation = 0.0,
  })  : _dstRect = dstRect ?? Rect.zero,
        _rotation = rotation;

  final String id;
  final int pageIndex;
  final Size pageSize;

  /// 如果是新图片，加载时将处于 [active] 状态（可拖动）
  bool newImage;

  Rect _dstRect;
  Rect get dstRect => _dstRect;
  static const double minImageSize = 10;

  set dstRect(Rect value) {
    if (value.width < minImageSize || value.height < minImageSize) {
      final scale = math.max(
        minImageSize / value.width,
        minImageSize / value.height,
      );
      _dstRect = Rect.fromLTWH(
        value.left,
        value.top,
        value.width * scale,
        value.height * scale,
      );
    } else {
      _dstRect = value;
    }
    _notifySafe();
  }

  /// 旋转角度（弧度）
  double _rotation;
  double get rotation => _rotation;
  set rotation(double value) {
    _rotation = value;
    _notifySafe();
  }

  void _notifySafe() {
    try {
      notifyListeners();
    } catch (_) {}
  }

  String get imageType;

  Map<String, dynamic> toJson();

  static EditorImage fromJson(Map<String, dynamic> json) {
    final String? type = json['type'] as String?;
    if (type == 'png' || type == 'jpg' || type == 'jpeg' || type == 'image') {
      return PngEditorImage.fromJson(json);
    } else if (type == 'svg') {
      return SvgEditorImage.fromJson(json);
    }
    throw Exception('未知的图片类型: $type');
  }

  void move(Offset offset) {
    dstRect = dstRect.translate(offset.dx, offset.dy);
  }

  void resize(Size newSize) {
    dstRect = Rect.fromLTWH(
      dstRect.left,
      dstRect.top,
      newSize.width,
      newSize.height,
    );
  }

  /// 获取旋转后的边界框（用于碰撞检测）
  Rect get rotatedBounds {
    if (_rotation == 0.0) return _dstRect;
    final center = _dstRect.center;
    final hw = _dstRect.width / 2;
    final hh = _dstRect.height / 2;
    final cosA = math.cos(_rotation).abs();
    final sinA = math.sin(_rotation).abs();
    final newHW = hw * cosA + hh * sinA;
    final newHH = hw * sinA + hh * cosA;
    return Rect.fromCenter(center: center, width: newHW * 2, height: newHH * 2);
  }
}

/// PNG/JPG 图片
class PngEditorImage extends EditorImage {
  PngEditorImage({
    required super.id,
    required this.imageBytes,
    required this.extension,
    required super.pageIndex,
    required super.pageSize,
    super.newImage = true,
    super.dstRect,
    super.rotation = 0.0,
  });

  final Uint8List imageBytes;
  final String extension;

  @override
  String get imageType => 'image';

  ImageProvider get imageProvider => MemoryImage(imageBytes);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': imageType,
      'id': id,
      'imageBytes': imageBytes.toList(),
      'extension': extension,
      'pageIndex': pageIndex,
      'rotation': rotation,
      'pageSize': {
        'width': pageSize.width,
        'height': pageSize.height,
      },
      'dstRect': {
        'left': dstRect.left,
        'top': dstRect.top,
        'width': dstRect.width,
        'height': dstRect.height,
      },
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
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// SVG 图片
class SvgEditorImage extends EditorImage {
  SvgEditorImage({
    required super.id,
    required this.svgString,
    required super.pageIndex,
    required super.pageSize,
    super.newImage = true,
    super.dstRect,
    super.rotation = 0.0,
  });

  final String svgString;

  @override
  String get imageType => 'svg';

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': imageType,
      'id': id,
      'svgString': svgString,
      'pageIndex': pageIndex,
      'rotation': rotation,
      'pageSize': {
        'width': pageSize.width,
        'height': pageSize.height,
      },
      'dstRect': {
        'left': dstRect.left,
        'top': dstRect.top,
        'width': dstRect.width,
        'height': dstRect.height,
      },
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
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
