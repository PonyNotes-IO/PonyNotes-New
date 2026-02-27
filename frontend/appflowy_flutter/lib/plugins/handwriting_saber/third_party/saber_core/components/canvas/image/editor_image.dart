import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/plugins/import_page/file_upload_service.dart';
import 'package:uuid/uuid.dart';

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

  Map<String, dynamic> toJson({bool forCollab = false});

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
///
/// 支持两种存储模式：
/// 1. 本地模式（imageBytes）：图片字节直接存储，仅用于本地显示
/// 2. 云存储模式（imageUrl）：图片上传至云存储，只存 URL，跨设备同步时不会因数据量大而失败
///
/// 序列化策略：
/// - toJson() 优先使用云 URL（轻量，适合 Collab 同步）
/// - 若无云 URL 则回退到 base64 编码（向后兼容，但同步效果差）
/// - fromJson() 先尝试读取云 URL，再尝试 base64，最后尝试字节数组
class PngEditorImage extends EditorImage {
  PngEditorImage({
    required super.id,
    required this.imageBytes,
    required this.extension,
    required super.pageIndex,
    required super.pageSize,
    this.imageUrl,
    super.newImage = true,
    super.dstRect,
    super.rotation = 0.0,
  });

  Uint8List imageBytes;
  final String extension;

  /// 云存储 URL（有此 URL 时，toJson 不再存储 imageBytes，大幅减少同步数据量）
  String? imageUrl;

  @override
  String get imageType => 'image';

  ImageProvider get imageProvider => MemoryImage(imageBytes);

  /// 上传图片到云存储并获取 URL
  /// 上传成功后 imageUrl 会被更新，后续 toJson() 会使用轻量格式
  Future<void> uploadToCloud() async {
    if (imageUrl != null && imageUrl!.startsWith('http')) {
      return; // 已上传
    }
    if (imageBytes.isEmpty) {
      return;
    }
    try {
      final ext = extension.isNotEmpty ? extension : '.png';
      final fileName = 'handwriting_${const Uuid().v4().substring(0, 8)}$ext';
      Log.info('[HandwritingImage] Uploading image: $fileName (${imageBytes.length} bytes)');
      final url = await FileUploadService.uploadFile(imageBytes, fileName);
      imageUrl = url;
      Log.info('[HandwritingImage] ✅ Image uploaded: $url');
    } catch (e) {
      Log.error('[HandwritingImage] ❌ Upload failed: $e');
    }
  }

  /// 归一化token：如果是JSON字符串则提取access_token
  static String _normalizeToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = jsonDecode(token);
        if (map is Map && map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {}
    }
    return token;
  }

  /// 从云 URL 下载图片字节（当 imageBytes 为空且有 imageUrl 时调用）
  Future<void> downloadFromCloud() async {
    if (imageBytes.isNotEmpty) return;
    if (imageUrl == null || !imageUrl!.startsWith('http')) return;

    try {
      Log.info('[HandwritingImage] Downloading from cloud: $imageUrl');
      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold((u) => u.token, (_) => '');
      final token = _normalizeToken(rawToken);

      final response = await http.get(
        Uri.parse(imageUrl!),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode == 200) {
        imageBytes = response.bodyBytes;
        Log.info('[HandwritingImage] ✅ Downloaded: ${imageBytes.length} bytes');
      } else {
        Log.error('[HandwritingImage] ❌ Download failed: ${response.statusCode}');
      }
    } catch (e) {
      Log.error('[HandwritingImage] ❌ Download error: $e');
    }
  }

  @override
  Map<String, dynamic> toJson({bool forCollab = false}) {
    final pageSizeMap = {
      'width': pageSize.width,
      'height': pageSize.height,
    };
    final dstRectMap = {
      'left': dstRect.left,
      'top': dstRect.top,
      'width': dstRect.width,
      'height': dstRect.height,
    };

    if (imageUrl != null && imageUrl!.startsWith('http')) {
      return {
        'type': imageType,
        'id': id,
        'imageUrl': imageUrl,
        'extension': extension,
        'pageIndex': pageIndex,
        'rotation': rotation,
        'pageSize': pageSizeMap,
        'dstRect': dstRectMap,
      };
    }

    // forCollab 模式下绝不包含 base64 数据，避免 Collab 同步数据过大导致 WebSocket 失败
    if (!forCollab && imageBytes.isNotEmpty) {
      final base64Str = base64Encode(imageBytes);
      return {
        'type': imageType,
        'id': id,
        'imageBase64': base64Str,
        'extension': extension,
        'pageIndex': pageIndex,
        'rotation': rotation,
        'pageSize': pageSizeMap,
        'dstRect': dstRectMap,
      };
    }

    return {
      'type': imageType,
      'id': id,
      'extension': extension,
      'pageIndex': pageIndex,
      'rotation': rotation,
      'pageSize': pageSizeMap,
      'dstRect': dstRectMap,
    };
  }

  factory PngEditorImage.fromJson(Map<String, dynamic> json) {
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

    // 优先读取云 URL
    final imageUrl = json['imageUrl'] as String?;

    // 尝试读取 base64 编码（新格式）
    Uint8List imageBytes = Uint8List(0);
    final base64Str = json['imageBase64'] as String?;
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        imageBytes = base64Decode(base64Str);
      } catch (e) {
        Log.error('[HandwritingImage] Failed to decode base64: $e');
      }
    }

    // 兼容旧格式：字节数组
    if (imageBytes.isEmpty) {
      final List<dynamic>? imageBytesList = json['imageBytes'] as List<dynamic>?;
      if (imageBytesList != null && imageBytesList.isNotEmpty) {
        imageBytes = Uint8List.fromList(imageBytesList.cast<int>());
      }
    }

    return PngEditorImage(
      id: json['id'] as String? ?? '',
      imageBytes: imageBytes,
      extension: json['extension'] as String? ?? '.png',
      pageIndex: json['pageIndex'] as int? ?? 0,
      pageSize: pageSize,
      imageUrl: imageUrl,
      dstRect: dstRect,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      newImage: false, // 从 JSON 恢复的图片不是新图片
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
  Map<String, dynamic> toJson({bool forCollab = false}) {
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
