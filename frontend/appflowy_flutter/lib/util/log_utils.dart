
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LogUtils {

  static LogUtils? _instance;
  static bool _isRelease = kReleaseMode;

  /// 是否原生打印，默认false
  static bool _isXFSNativePrint = false;

  /// 一次最大打印字数，iOS以外系统用到
  static int _max = 800;

  LogUtils._();

  /// 打印工具初始化
  ///
  /// [isRelease] 是否正式环境
  /// [isXFSNative] 是否在原生打印 默认false
  static LogUtils? instance({required bool isRelease, bool isXFSNativePrint = false, int max = 800}){
    if(_instance == null){
      _instance = LogUtils._();
      _isRelease = isRelease;
      _isXFSNativePrint = isXFSNativePrint;
      _max = max;
    }
    return _instance;
  }

  static warning(Object printObj, {StackTrace? stackTrace, String? funcName}){
    _print(printObj, title: "⚠️", stackTrace: stackTrace, funcName: funcName);
  }

  static error(Object printObj, {StackTrace? stackTrace, String? funcName}){
    _print(printObj, title: "❌", stackTrace: stackTrace, funcName: funcName);
  }

  static success(Object printObj, {StackTrace? stackTrace, String? funcName}){
    _print(printObj, title: "✅️", stackTrace: stackTrace, funcName: funcName);
  }

  static info(Object printObj, {StackTrace? stackTrace, String? funcName}){
    _print(printObj, title: "🌟", stackTrace: stackTrace, funcName: funcName);
  }

  static _print(Object printObj, {StackTrace? stackTrace, String? title, String? funcName}){
    if(!_isRelease){
      List<String> components = ['$title$title ${funcName??''} $title$title'];
      String top = '┌───────────────────────────────────────────────────────$title────────────────────────────────────────────────────────────────';
      String center = '│  ${printObj.toString()}';
      String end = '└───────────────────────────────────────────────────────$title────────────────────────────────────────────────────────────────';
      components.add(top);
      components.add(center);
      if (stackTrace != null){
        components.add(stackTrace.toString());
      }
      components.add(end);

      if (_isXFSNativePrint){
        String objStr = components.join('\n');
        if (!Platform.isIOS){
          if(objStr.length > _max){
            while(objStr.length > _max){
              debugPrint(objStr.substring(0, _max));
              objStr = objStr.substring(_max);
            }
          }
        }
        debugPrint(objStr);
      } else {
        log(components.join('\n'));
      }
    }
  }

}