import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ffi.dart' as ffi;

export 'package:async/async.dart';

enum ExceptionType {
  AppearanceSettingsIsEmpty,
}

class FlowySDKException implements Exception {
  ExceptionType type;
  FlowySDKException(this.type);
}

class FlowySDK {
  static const MethodChannel _channel = MethodChannel('appflowy_backend');
  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  FlowySDK();

  Future<void> dispose() async {
    ffi.dispose_sdk();
  }

  void forceSync({Duration timeout = const Duration(milliseconds: 1500)}) {
    ffi.force_sync(timeout.inMilliseconds);
  }

  Future<void> init(String configuration) async {
    ffi.set_stream_port(RustStreamReceiver.shared.port);
    ffi.store_dart_post_cobject(NativeApi.postCObject);

    // On iOS, VSCode can't print logs from Rust, so we need to use a different method to print logs.
    // So we use a shared port to receive logs from Rust and print them using the logger. In release mode, we don't print logs.
    if (Platform.isIOS && kDebugMode) {
      ffi.set_log_stream_port(RustLogStreamReceiver.logShared.port);
    }

    // init_sdk blocks until Rust has restored the workspace, including cloud
    // requests. Keep Linux's UI isolate free to paint the startup window.
    final code = Platform.isLinux
        ? await compute(_initializeSDK, configuration)
        : _initializeSDK(configuration);
    if (code != 0) {
      throw Exception('Failed to initialize the SDK');
    }
  }
}

int _initializeSDK(String configuration) {
  final nativeConfiguration = configuration.toNativeUtf8();
  try {
    return ffi.init_sdk(0, nativeConfiguration);
  } finally {
    malloc.free(nativeConfiguration);
  }
}

class RustLogStreamReceiver {
  static RustLogStreamReceiver logShared = RustLogStreamReceiver._internal();
  late RawReceivePort _ffiPort;
  late StreamController<Uint8List> _streamController;
  late StreamSubscription<Uint8List> _subscription;
  int get port => _ffiPort.sendPort.nativePort;

  RustLogStreamReceiver._internal() {
    _ffiPort = RawReceivePort();
    _streamController = StreamController();
    _ffiPort.handler = _streamController.add;

    _subscription = _streamController.stream.listen((data) {
      String decodedString = utf8.decode(data);
      Log.info(decodedString);
    });
  }

  factory RustLogStreamReceiver() {
    return logShared;
  }

  Future<void> dispose() async {
    await _streamController.close();
    await _subscription.cancel();
    _ffiPort.close();
  }
}
