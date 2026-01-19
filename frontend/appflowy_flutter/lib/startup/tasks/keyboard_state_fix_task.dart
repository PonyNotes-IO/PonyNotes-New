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
/// 解决方案：通过自定义FlutterError处理器来抑制这个特定的错误，
/// 避免它在控制台中显示并影响用户体验。键盘输入会继续正常工作。
class KeyboardStateFixTask extends LaunchTask {
  const KeyboardStateFixTask();
  
  static bool _initialized = false;
  static FlutterExceptionHandler? _originalErrorHandler;
  
  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    
    if (_initialized) {
      return;
    }
    _initialized = true;
    
    Log.info('KeyboardStateFixTask: 注册键盘状态错误抑制处理器');
    
    // 保存原有的错误处理器
    _originalErrorHandler = FlutterError.onError;
    
    // 设置新的错误处理器
    FlutterError.onError = _customErrorHandler;
  }
  
  @override
  Future<void> dispose() async {
    await super.dispose();
    
    if (_initialized) {
      // 恢复原有的错误处理器
      if (_originalErrorHandler != null) {
        FlutterError.onError = _originalErrorHandler;
      }
      _initialized = false;
      Log.info('KeyboardStateFixTask: 移除键盘状态错误抑制处理器');
    }
  }
  
  /// 自定义错误处理器
  /// 
  /// 抑制键盘状态相关的已知Flutter bug错误，其他错误正常处理
  static void _customErrorHandler(FlutterErrorDetails details) {
    // 检查是否是键盘状态相关的错误
    if (_isKeyboardStateError(details)) {
      // 只在调试模式下记录日志，避免在生产环境中产生过多日志
      if (kDebugMode) {
        Log.trace(
          'KeyboardStateFixTask: 抑制键盘状态错误 (Flutter已知bug) - '
          '${details.exception}'
        );
      }
      // 不调用原始处理器，从而抑制这个错误
      return;
    }
    
    // 对于其他错误，调用原始处理器
    if (_originalErrorHandler != null) {
      _originalErrorHandler!(details);
    } else {
      // 如果没有原始处理器，使用默认行为
      FlutterError.presentError(details);
    }
  }
  
  /// 检查是否是键盘状态相关的错误
  static bool _isKeyboardStateError(FlutterErrorDetails details) {
    final exception = details.exception;
    final exceptionString = exception.toString();
    
    // 检查是否包含键盘状态相关的错误信息
    // "A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed"
    // "A KeyUpEvent is dispatched, but the state shows that the physical key is not pressed"
    if (exceptionString.contains('KeyDownEvent is dispatched') ||
        exceptionString.contains('KeyUpEvent is dispatched')) {
      if (exceptionString.contains('physical key is already pressed') ||
          exceptionString.contains('physical key is not pressed')) {
        return true;
      }
    }
    
    // 检查断言错误信息中的特定字符串
    if (exceptionString.contains('_pressedKeys.containsKey') ||
        exceptionString.contains('!_pressedKeys.containsKey')) {
      return true;
    }
    
    // 检查是否来自 hardware_keyboard.dart
    final stackTrace = details.stack?.toString() ?? '';
    if (stackTrace.contains('hardware_keyboard.dart') &&
        (exceptionString.contains('KeyDownEvent') ||
         exceptionString.contains('KeyUpEvent'))) {
      return true;
    }
    
    return false;
  }
}
