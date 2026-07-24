import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:universal_platform/universal_platform.dart';

import 'clipboard_image_reader.dart';

// 通用类型定义
class CustomValueFormat<T> {
  const CustomValueFormat({
    required this.applicationId,
    required this.onDecode,
    required this.onEncode,
  });

  final String applicationId;
  final Future<T?> Function(Object, String) onDecode;
  final Future<Object> Function(T, String) onEncode;

  dynamic call(T value) => value;
}

const CustomValueFormat<String> inAppJsonFormat = CustomValueFormat<String>(
  applicationId: 'com.xiaomabiji.app.note.InAppJsonType',
  onDecode: _defaultDecode,
  onEncode: _defaultEncode,
);

const CustomValueFormat<String> tableJsonFormat = CustomValueFormat<String>(
  applicationId: 'com.xiaomabiji.app.note.TableJsonType',
  onDecode: _defaultDecode,
  onEncode: _defaultEncode,
);

class ClipboardServiceData {
  const ClipboardServiceData({
    this.plainText,
    this.html,
    this.image,
    this.imageSize,
    this.inAppJson,
    this.tableJson,
  });

  final String? plainText;
  final String? html;
  final (String, Uint8List?)? image;
  final ({double? width, double? height})? imageSize;
  final String? inAppJson;
  final String? tableJson;
}

class ClipboardService {
  static ClipboardServiceData? _mockData;

  @visibleForTesting
  static void mockSetData(ClipboardServiceData? data) {
    _mockData = data;
  }

  Future<void> setData(ClipboardServiceData data) async {
    if (_mockData != null) {
      return;
    }

    final image = data.image;
    if (!UniversalPlatform.isWeb &&
        image != null &&
        image.$2 != null &&
        image.$2!.isNotEmpty) {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final item = DataWriterItem();
        if (_addImage(item, image.$1, image.$2!)) {
          // Keep the original URL/text as an additional representation. This
          // lets applications that do not accept image clipboard data still
          // paste a useful value.
          if (data.plainText?.isNotEmpty == true) {
            item.add(Formats.plainText(data.plainText!));
          }
          final imageSize = data.imageSize;
          if (imageSize != null) {
            item.add(
              imageSizeClipboardFormat(
                jsonEncode({
                  'width': imageSize.width,
                  'height': imageSize.height,
                }),
              ),
            );
          }
          await clipboard.write([item]);
          return;
        }
      }
    }

    if (data.plainText != null) {
      await Clipboard.setData(ClipboardData(text: data.plainText!));
    }
  }

  Future<void> setPlainText(String text) async {
    if (_mockData != null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<ClipboardServiceData> getData() async {
    if (_mockData != null) {
      return _mockData!;
    }

    String? plainText;
    String? html;
    (String, Uint8List?)? image;
    ({double? width, double? height})? imageSize;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      plainText = data?.text;
    } catch (e) {
      Log.error('Failed to get plain text from clipboard', e);
    }

    try {
      html = await _getHtmlFromClipboard();
    } catch (e) {
      Log.error('Failed to get HTML from clipboard', e);
    }

    try {
      image = await _getImageFromClipboard();
      if (image != null) {
        imageSize = await readImageSizeFromClipboard();
      }
    } catch (e) {
      Log.error('Failed to get image from clipboard', e);
    }

    return ClipboardServiceData(
      plainText: plainText,
      html: html,
      image: image,
      imageSize: imageSize,
    );
  }

  Future<String?> _getHtmlFromClipboard() async {
    if (UniversalPlatform.isWeb) {
      return null;
    }
    try {
      final clipboardData = await Clipboard.getData('text/html');
      return clipboardData?.text;
    } catch (e) {
      Log.debug('Failed to read HTML from clipboard: $e');
    }
    return null;
  }

  Future<(String, Uint8List?)?> _getImageFromClipboard() async {
    if (UniversalPlatform.isWeb) {
      return null;
    }
    return readImageFromClipboard();
  }
}

bool _addImage(DataWriterItem item, String format, Uint8List bytes) {
  switch (format.toLowerCase()) {
    case 'png':
      item.add(Formats.png(bytes));
      return true;
    case 'jpg':
    case 'jpeg':
      item.add(Formats.jpeg(bytes));
      return true;
    case 'gif':
      item.add(Formats.gif(bytes));
      return true;
    case 'webp':
      item.add(Formats.webp(bytes));
      return true;
    default:
      Log.debug('Unsupported clipboard image format: $format');
      return false;
  }
}

// 默认函数
Future<String?> _defaultDecode(Object value, String platformType) async => null;
Future<Object> _defaultEncode(String value, String platformType) async => value;
