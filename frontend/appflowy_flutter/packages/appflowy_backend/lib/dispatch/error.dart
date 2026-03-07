import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/dart-ffi/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:flutter/foundation.dart';

class FlowyInternalError {
  late FFIStatusCode _statusCode;
  late String _error;

  FFIStatusCode get statusCode {
    return _statusCode;
  }

  String get error {
    return _error;
  }

  bool get has_error {
    return _statusCode != FFIStatusCode.Ok;
  }

  String toString() {
    return "$_statusCode: $_error";
  }

  FlowyInternalError({
    required FFIStatusCode statusCode,
    required String error,
  }) {
    _statusCode = statusCode;
    _error = error;
  }
}

class StackTraceError {
  Object error;
  StackTrace trace;
  StackTraceError(
    this.error,
    this.trace,
  );

  FlowyInternalError asFlowyError() {
    return FlowyInternalError(
        statusCode: FFIStatusCode.Err, error: this.toString());
  }

  String toString() {
    return '${error.runtimeType}. Stack trace: $trace';
  }
}

typedef void ErrorListener();

/// Receive error when Rust backend send error message back to the flutter frontend
///
class GlobalErrorCodeNotifier extends ChangeNotifier {
  // Static instance with lazy initialization
  static final GlobalErrorCodeNotifier _instance =
      GlobalErrorCodeNotifier._internal();

  FlowyError? _error;

  // Private internal constructor
  GlobalErrorCodeNotifier._internal();

  // Factory constructor to return the same instance
  factory GlobalErrorCodeNotifier() {
    return _instance;
  }

  static void receiveError(FlowyError error) {
    if (_instance._error?.code != error.code) {
      _instance._error = error;
      _instance.notifyListeners();
    }
  }

  static void receiveErrorBytes(Uint8List bytes) {
    try {
      final error = FlowyError.fromBuffer(bytes);
      if (_instance._error?.code != error.code) {
        _instance._error = error;
        _instance.notifyListeners();
      }
    } catch (e) {
      Log.error("Can not parse error bytes: $e");
    }
  }

  static ErrorListener add({
    required void Function(FlowyError error) onError,
    bool Function(FlowyError code)? onErrorIf,
  }) {
    void listener() {
      final error = _instance._error;
      if (error != null) {
        if (onErrorIf == null || onErrorIf(error)) {
          onError(error);
        }
      }
    }

    _instance.addListener(listener);
    return listener;
  }

  static void remove(ErrorListener listener) {
    _instance.removeListener(listener);
  }
}

extension FlowyErrorExtension on FlowyError {
  bool get isAIResponseLimitExceeded =>
      code == ErrorCode.AIResponseLimitExceeded;

  // 检查存储限制超出错误
  // 后端可能返回 FileStorageLimitExceeded (1028) 或 PlanLimitExceeded (1072)
  // 注意：code 是枚举类型，需要通过 .value 来获取整数进行比较
  bool get isStorageLimitExceeded =>
      code == ErrorCode.FileStorageLimitExceeded ||
      code.value == 1028 ||
      code.value == 1072;

  // 检查单文件上传大小限制超出错误
  // 后端返回 SingleUploadLimitExceeded (1037)
  bool get isSingleFileLimitExceeded =>
      code == ErrorCode.SingleUploadLimitExceeded ||
      code.value == 1037;
}
