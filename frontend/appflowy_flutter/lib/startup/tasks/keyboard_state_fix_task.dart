import 'dart:ui';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

import '../startup.dart';

/// 键盘状态修复任务
/// 
/// 用于解决Flutter键盘状态管理的bug：
/// "A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed"
/// 
/// 这个问题在焦点切换、页面跳转等场景中会出现，因为KeyDown和KeyUp事件不配对。
/// 这是Flutter框架本身的已知问题。
/// 
/// 解决方案：
/// 1. 设置 PlatformDispatcher.instance.onError 来捕获所有平台错误（包括断言错误）
/// 2. 设置 FlutterError.onError 来处理 Flutter 框架错误
/// 
/// 这样可以确保键盘状态相关的断言错误不会中断应用程序的正常运行。
class KeyboardStateFixTask extends LaunchTask {
  const KeyboardStateFixTask();
  
  static bool _initialized = false;
  static FlutterExceptionHandler? _originalFlutterErrorHandler;
  static ErrorCallback? _originalPlatformErrorHandler;
  
  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    
    if (_initialized) {
      return;
    }
    _initialized = true;
    
    Log.info('KeyboardStateFixTask: 注册键盘状态错误抑制处理器');
    
    // 保存原有的错误处理器
    _originalFlutterErrorHandler = FlutterError.onError;
    _originalPlatformErrorHandler = PlatformDispatcher.instance.onError;
    
    // 设置新的 FlutterError 处理器
    FlutterError.onError = _customFlutterErrorHandler;
    
    // 设置新的平台错误处理器（捕获断言错误等）
    PlatformDispatcher.instance.onError = _customPlatformErrorHandler;
  }
  
  @override
  Future<void> dispose() async {
    await super.dispose();
    
    if (_initialized) {
      // 恢复原有的错误处理器
      if (_originalFlutterErrorHandler != null) {
        FlutterError.onError = _originalFlutterErrorHandler;
      }
      if (_originalPlatformErrorHandler != null) {
        PlatformDispatcher.instance.onError = _originalPlatformErrorHandler;
      }
      _initialized = false;
      Log.info('KeyboardStateFixTask: 移除键盘状态错误抑制处理器');
    }
  }
  
  /// 平台错误处理器
  /// 
  /// 捕获断言错误等平台级错误，特别是键盘状态相关的断言错误
  static bool _customPlatformErrorHandler(Object error, StackTrace stack) {
    // 检查是否是键盘状态相关的错误
    if (_isKeyboardStateErrorFromObject(error, stack)) {
      // 静默处理键盘状态错误，返回 true 表示已处理
      // 不打印日志，避免刷屏
      return true;
    }
    
    // 对于其他错误，调用原始处理器
    if (_originalPlatformErrorHandler != null) {
      return _originalPlatformErrorHandler!(error, stack);
    }
    
    // 默认返回 false，让错误继续传播（但不会导致应用崩溃）
    return false;
  }
  
  /// 自定义 Flutter 错误处理器
  /// 
  /// 抑制键盘状态相关的已知Flutter bug错误，其他错误正常处理
  static void _customFlutterErrorHandler(FlutterErrorDetails details) {
    // 检查是否是键盘状态相关的错误
    if (_isKeyboardStateErrorFromDetails(details)) {
      // 静默处理，不打印日志
      return;
    }
    
    // 对于其他错误，调用原始处理器
    if (_originalFlutterErrorHandler != null) {
      _originalFlutterErrorHandler!(details);
    } else {
      // 如果没有原始处理器，使用默认行为
      FlutterError.presentError(details);
    }
  }
  
  /// 从错误对象检查是否是键盘状态相关的错误
  static bool _isKeyboardStateErrorFromObject(Object error, StackTrace stack) {
    final errorString = error.toString();
    final stackString = stack.toString();
    
    return _matchKeyboardStateError(errorString, stackString);
  }
  
  /// 从 FlutterErrorDetails 检查是否是键盘状态相关的错误
  static bool _isKeyboardStateErrorFromDetails(FlutterErrorDetails details) {
    final exception = details.exception;
    final exceptionString = exception.toString();
    final stackString = details.stack?.toString() ?? '';
    
    return _matchKeyboardStateError(exceptionString, stackString);
  }
  
  /// 匹配键盘状态错误的通用逻辑
  static bool _matchKeyboardStateError(String errorString, String stackString) {
    // 检查是否包含键盘状态相关的错误信息
    // "A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed"
    // "A KeyUpEvent is dispatched, but the state shows that the physical key is not pressed"
    if (errorString.contains('KeyDownEvent is dispatched') ||
        errorString.contains('KeyUpEvent is dispatched')) {
      if (errorString.contains('physical key is already pressed') ||
          errorString.contains('physical key is not pressed')) {
        return true;
      }
    }
    
    // 检查断言错误信息中的特定字符串
    if (errorString.contains('_pressedKeys.containsKey') ||
        errorString.contains('!_pressedKeys.containsKey')) {
      return true;
    }
    
    // 检查是否来自 hardware_keyboard.dart
    if (stackString.contains('hardware_keyboard.dart') &&
        (errorString.contains('KeyDownEvent') ||
         errorString.contains('KeyUpEvent'))) {
      return true;
    }
    
    // 检查是否是 HardwareKeyboard 相关的断言错误
    if (errorString.contains('HardwareKeyboard') &&
        (errorString.contains('assertion') || 
         errorString.contains('Failed assertion'))) {
      return true;
    }
    
    return false;
  }
}
