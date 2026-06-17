import 'package:flutter/foundation.dart';
import 'package:appflowy_backend/log.dart';

/// 全窗口显示控制器：
/// - 通过 [isFullWindow] 暴露当前是否处于全窗口模式
/// - 所有需要控制/响应全窗口的地方都应使用此控制器，避免状态不一致
/// 
/// 该控制器用于管理应用内的全屏模式（非系统级全屏），主要影响：
/// - 侧边栏的显示/隐藏
/// - 顶部工具栏的显示/隐藏  
/// - 编辑面板的显示/隐藏
/// - 整体布局的重新排列
class FullWindowController {
  static final ValueNotifier<bool> isFullWindow = ValueNotifier<bool>(false);
  
  /// 防止状态在短时间内频繁切换的保护标志
  static bool _isTransitioning = false;
  
  /// 最小状态切换间隔（毫秒）
  static const _minTransitionIntervalMs = 200;
  
  /// 上次状态切换时间
  static DateTime? _lastTransitionTime;

  static void enter() {
    if (!_canTransition()) {
      return;
    }
    
    try {
      if (!isFullWindow.value) {
        _markTransitionStart();
        isFullWindow.value = true;
        _markTransitionEnd();
        Log.info('[FullWindowController] entered full window mode');
      }
    } catch (error, stackTrace) {
      _markTransitionEnd();
      Log.error('[FullWindowController] failed to enter full window: $error', error, stackTrace);
    }
  }

  static void exit() {
    if (!_canTransition()) {
      return;
    }
    
    try {
      if (isFullWindow.value) {
        _markTransitionStart();
        isFullWindow.value = false;
        _markTransitionEnd();
        Log.info('[FullWindowController] exited full window mode');
      }
    } catch (error, stackTrace) {
      _markTransitionEnd();
      Log.error('[FullWindowController] failed to exit full window: $error', error, stackTrace);
    }
  }

  static void toggle() {
    if (!_canTransition()) {
      return;
    }
    
    try {
      _markTransitionStart();
      isFullWindow.value = !isFullWindow.value;
      _markTransitionEnd();
      Log.info('[FullWindowController] toggled full window mode: ${isFullWindow.value}');
    } catch (error, stackTrace) {
      _markTransitionEnd();
      Log.error('[FullWindowController] failed to toggle full window: $error', error, stackTrace);
    }
  }
  
  /// 检查是否可以进行状态切换
  static bool _canTransition() {
    // 检查是否正在切换中
    if (_isTransitioning) {
      Log.warn('[FullWindowController] transition in progress, ignoring request');
      return false;
    }
    
    // 检查时间间隔
    final now = DateTime.now();
    if (_lastTransitionTime != null) {
      final elapsed = now.difference(_lastTransitionTime!).inMilliseconds;
      if (elapsed < _minTransitionIntervalMs) {
        Log.warn('[FullWindowController] transition too frequent, ignoring request');
        return false;
      }
    }
    
    return true;
  }
  
  /// 标记状态切换开始
  static void _markTransitionStart() {
    _isTransitioning = true;
  }
  
  /// 标记状态切换结束
  static void _markTransitionEnd() {
    _isTransitioning = false;
    _lastTransitionTime = DateTime.now();
  }
}


