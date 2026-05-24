import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// 通用类型定义
class CustomValueFormat<T> {
  final String applicationId;
  final Future<T?> Function(Object, String) onDecode;
  final Future<Object> Function(T, String) onEncode;

  const CustomValueFormat({
    required this.applicationId,
    required this.onDecode,
    required this.onEncode,
  });

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
    // 所有平台：只支持纯文本（为了避免 native 库问题）
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
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return ClipboardServiceData(plainText: data?.text);
  }
}

// 默认函数
Future<String?> _defaultDecode(Object value, String platformType) async => null;
Future<Object> _defaultEncode(String value, String platformType) async => value;
