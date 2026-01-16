/// 全局键盘状态修复工具
/// 
/// 用于解决Flutter键盘状态管理的bug：
/// "A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed"
/// 
/// 问题原因：
/// Flutter的HardwareKeyboard全局跟踪所有物理按键状态，但在某些情况下（如焦点切换、页面跳转等）
/// KeyDown和KeyUp事件可能不配对，导致全局状态认为某个键还在按下状态。
/// 
/// 解决方案：
/// 在关键的键盘事件处理点添加防护代码，检测并忽略重复的KeyDown事件。

import 'package:flutter/services.dart';

/// 安全的键盘事件处理器
/// 
/// 用法：
/// ```dart
/// Focus(
///   onKeyEvent: (node, event) {
///     // 添加防护检查
///     if (!SafeKeyboardHandler.shouldProcessKeyDownEvent(event)) {
///       return KeyEventResult.ignored;
///     }
///     
///     // 你的键盘事件处理代码...
///     return KeyEventResult.ignored;
///   },
///   child: ...
/// )
/// ```
class SafeKeyboardHandler {
  /// 检查KeyDownEvent是否应该被处理
  /// 
  /// 返回false表示这是重复的KeyDown，应该被忽略
  static bool shouldProcessKeyDownEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return true; // KeyUp和KeyRepeat事件直接通过
    }
    
    try {
      final physicalKey = event.physicalKey;
      final isAlreadyPressed = HardwareKeyboard.instance.physicalKeysPressed.contains(physicalKey);
      
      if (isAlreadyPressed) {
        // 这是重复的KeyDown事件，应该被忽略
        return false;
      }
      
      return true;
    } catch (e) {
      // 如果检查失败，保守地返回true以避免阻止正常输入
      return true;
    }
  }
  
  /// 创建一个安全的Focus包装器
  /// 
  /// 用法：
  /// ```dart
  /// SafeKeyboardHandler.wrapWithFocus(
  ///   child: TextField(...),
  ///   onKeyEvent: (node, event) {
  ///     // 你的键盘事件处理代码...
  ///     return KeyEventResult.ignored;
  ///   },
  /// )
  /// ```
  static Widget wrapWithFocus({
    required Widget child,
    required KeyEventCallback? onKeyEvent,
    bool canRequestFocus = false,
    bool skipTraversal = true,
    bool includeSemantics = false,
  }) {
    return Focus(
      canRequestFocus: canRequestFocus,
      skipTraversal: skipTraversal,
      includeSemantics: includeSemantics,
      onKeyEvent: (node, event) {
        // 添加防护检查
        if (event is KeyDownEvent && !shouldProcessKeyDownEvent(event)) {
          return KeyEventResult.ignored;
        }
        
        // 调用用户的事件处理器
        if (onKeyEvent != null) {
          return onKeyEvent(node, event);
        }
        
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
  
  /// 清理键盘状态
  /// 
  /// 在页面切换或焦点丢失时调用，清理可能残留的按键状态
  /// 注意：这是一个workaround，不一定总是有效
  static void clearKeyboardState() {
    // Flutter的HardwareKeyboard不提供直接清理状态的API
    // 这里只是一个占位符，实际上无法直接清理
    // 最好的方法是避免状态不一致，而不是事后清理
  }
}

/// 为Focus组件添加键盘状态防护的扩展
extension SafeFocusExtension on Focus {
  /// 创建一个带有键盘状态防护的Focus组件
  static Focus safe({
    required Widget child,
    required KeyEventCallback onKeyEvent,
    bool canRequestFocus = false,
    bool skipTraversal = true,
    bool includeSemantics = false,
  }) {
    return Focus(
      canRequestFocus: canRequestFocus,
      skipTraversal: skipTraversal,
      includeSemantics: includeSemantics,
      onKeyEvent: (node, event) {
        // 添加防护检查
        if (event is KeyDownEvent && !SafeKeyboardHandler.shouldProcessKeyDownEvent(event)) {
          return KeyEventResult.ignored;
        }
        
        return onKeyEvent(node, event);
      },
      child: child,
    );
  }
}

