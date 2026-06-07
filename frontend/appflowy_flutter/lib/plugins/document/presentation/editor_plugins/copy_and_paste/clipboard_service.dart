import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    this.inAppJson,
    this.tableJson,
  });

  final String? plainText;
  final String? html;
  final (String, Uint8List?)? image;
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
    } catch (e) {
      Log.error('Failed to get image from clipboard', e);
    }

    return ClipboardServiceData(
      plainText: plainText,
      html: html,
      image: image,
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

// 默认函数
Future<String?> _defaultDecode(Object value, String platformType) async => null;
Future<Object> _defaultEncode(String value, String platformType) async => value;
