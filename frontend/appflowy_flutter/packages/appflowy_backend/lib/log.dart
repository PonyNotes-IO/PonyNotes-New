// ignore: import_of_legacy_library_into_null_safe
import 'dart:ffi';

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart';

import 'ffi.dart';

class Log {
  static final shared = Log();

  late Talker _logger;

  bool enableFlutterLog = true;

  // used to disable log in tests
  bool disableLog = false;

  Log() {
    _logger = Talker(
      filter: LogLevelTalkerFilter(),
    );
  }

  // Generic internal logging function to reduce code duplication
  static void _log(
    LogLevel level,
    int rustLevel,
    dynamic msg, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    // rust_log 函数在 ffi.dart 中已经处理了 iOS 兼容性问题
    // ALWAYS write to file through Rust (even in debug mode)
    // Add Flutter log marker prefix for easy identification in logs
    String levelPrefix = _getFlutterLevelPrefix(rustLevel);
    String formattedMessage = _formatMessageWithStackTrace(msg, stackTrace);
    String markedMessage = "$levelPrefix $formattedMessage";
    rust_log(rustLevel, toNativeUtf8(markedMessage));

    // Also output to Flutter console in debug mode for convenience
    if (shared.enableFlutterLog && kDebugMode) {
      shared._logger.log(msg, logLevel: level, stackTrace: stackTrace);
    }
  }

  // Get Flutter log level prefix with emoji markers
  static String _getFlutterLevelPrefix(int rustLevel) {
    switch (rustLevel) {
      case 0: return '🦋[FLUTTER-INFO]🦋';
      case 1: return '🦋[FLUTTER-DEBUG]🦋';
      case 2: return '🦋[FLUTTER-TRACE]🦋';
      case 3: return '🦋[FLUTTER-WARN]🦋';
      case 4: return '🦋[FLUTTER-ERROR]🦋';
      default: return '🦋[FLUTTER-UNKNOWN]🦋';
    }
  }

  static void info(dynamic msg, [dynamic error, StackTrace? stackTrace]) {
    if (shared.disableLog) {
      return;
    }

    _log(LogLevel.info, 0, msg, error, stackTrace);
  }

  static void debug(dynamic msg, [dynamic error, StackTrace? stackTrace]) {
    if (shared.disableLog) {
      return;
    }

    _log(LogLevel.debug, 1, msg, error, stackTrace);
  }

  static void warn(dynamic msg, [dynamic error, StackTrace? stackTrace]) {
    if (shared.disableLog) {
      return;
    }

    _log(LogLevel.warning, 3, msg, error, stackTrace);
  }

  static void trace(dynamic msg, [dynamic error, StackTrace? stackTrace]) {
    if (shared.disableLog) {
      return;
    }

    _log(LogLevel.verbose, 2, msg, error, stackTrace);
  }

  static void error(dynamic msg, [dynamic error, StackTrace? stackTrace]) {
    if (shared.disableLog) {
      return;
    }

    _log(LogLevel.error, 4, msg, error, stackTrace);
  }
}

bool isReleaseVersion() {
  return kReleaseMode;
}

// Utility to convert a message to native Utf8 (used in rust_log)
Pointer<ffi.Utf8> toNativeUtf8(dynamic msg) {
  return "$msg".toNativeUtf8();
}

String _formatMessageWithStackTrace(dynamic msg, StackTrace? stackTrace) {
  if (stackTrace != null) {
    return "$msg\nStackTrace:\n$stackTrace"; // Append the stack trace to the message
  }
  return msg.toString();
}

class LogLevelTalkerFilter implements TalkerFilter {
  @override
  bool filter(TalkerData data) {
    // filter out the debug logs in release mode
    return kDebugMode ? true : data.logLevel != LogLevel.debug;
  }
}
