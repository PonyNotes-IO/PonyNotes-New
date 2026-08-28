import 'dart:async';

import './douyin_platform_interface.dart';
import './model/resp.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An implementation of [DouyinPlatform] that uses method channels.
class MethodChannelDouyin extends DouyinPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  late final methodChannel = const MethodChannel('douyin')
    ..setMethodCallHandler((call) {
      return _handleMethod(call);
    });

  final StreamController<DouYinResp> _streamController =
      StreamController.broadcast();

  Future<dynamic> _handleMethod(MethodCall call) async {
    final data =
        (call.arguments as Map<dynamic, dynamic>).cast<String, dynamic>();
    switch (call.method) {
      case "onAuthorCallback":
        _streamController.add(DouYinResp.fromJson(data));
    }
  }

  @override
  Stream<DouYinResp> respStream() {
    return _streamController.stream;
  }

  @override
  Future<String> registerDouyinApp({required String apiKey}) async {
    final initState = await methodChannel.invokeMethod<String>("init", {
      "apiKey": apiKey,
    });
    return initState ?? '';
  }

  @override
  Future<String> authorLogin({required String scopeKey}) async {
    final state = await methodChannel.invokeMethod<String>("AuthorizedLogin", {
      "scope": scopeKey,
    });
    return state ?? '';
  }
}
