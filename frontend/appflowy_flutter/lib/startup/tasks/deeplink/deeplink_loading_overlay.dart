import 'package:flutter/material.dart';

import '../app_widget.dart';

/// 深链处理过程中的全局加载浮层
class DeepLinkLoadingOverlay {
  DeepLinkLoadingOverlay._();

  static OverlayEntry? _overlayEntry;

  static bool get isShowing => _overlayEntry != null;

  static void show({String message = '正在加载，请稍候...'}) {
    if (_overlayEntry != null) {
      return;
    }

    final overlayState = AppGlobals.rootNavKey.currentState?.overlay;
    if (overlayState == null) {
      return;
    }

    _insertOverlay(overlayState, message);
  }

  /// 在应用刚被深链拉起时，overlay 可能尚未就绪。
  /// 这里做短时重试，确保加载浮层可见。
  static Future<bool> showWhenReady({
    String message = '正在加载，请稍候...',
    Duration timeout = const Duration(seconds: 2),
    Duration retryInterval = const Duration(milliseconds: 80),
  }) async {
    if (_overlayEntry != null) {
      return true;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final overlayState = AppGlobals.rootNavKey.currentState?.overlay;
      if (overlayState != null) {
        _insertOverlay(overlayState, message);
        return true;
      }
      await Future.delayed(retryInterval);
    }
    return false;
  }

  static void _insertOverlay(OverlayState overlayState, String message) {
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        return Stack(
          children: [
            ModalBarrier(
              color: Colors.black.withOpacity(0.22),
              dismissible: false,
            ),
            Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
