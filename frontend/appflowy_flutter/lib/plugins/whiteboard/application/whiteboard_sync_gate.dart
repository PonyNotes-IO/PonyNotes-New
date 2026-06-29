import 'dart:async';

enum WhiteboardSyncGateOpenReason {
  ready,
  fallbackTimeout,
  manual,
}

class WhiteboardSyncGate {
  WhiteboardSyncGate({
    this.fallbackTimeout = const Duration(seconds: 10),
  });

  final Duration fallbackTimeout;
  void Function(WhiteboardSyncGateOpenReason reason)? onOpened;

  Timer? _fallbackTimer;
  bool _isHeld = false;
  bool _initialDataReady = false;
  bool _webViewReady = false;
  WhiteboardSyncGateOpenReason? _openReason;

  bool get canAutoSync => !_isHeld;
  WhiteboardSyncGateOpenReason? get openReason => _openReason;

  void hold() {
    _fallbackTimer?.cancel();
    _isHeld = true;
    _initialDataReady = false;
    _webViewReady = false;
    _openReason = null;
    _fallbackTimer = Timer(fallbackTimeout, () {
      release(WhiteboardSyncGateOpenReason.fallbackTimeout);
    });
  }

  void markInitialDataReady() {
    _initialDataReady = true;
    _releaseIfReady();
  }

  void markWebViewReady() {
    _webViewReady = true;
    _releaseIfReady();
  }

  void release([
    WhiteboardSyncGateOpenReason reason = WhiteboardSyncGateOpenReason.manual,
  ]) {
    if (!_isHeld) {
      return;
    }

    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _isHeld = false;
    _openReason = reason;
    onOpened?.call(reason);
  }

  void dispose() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  void _releaseIfReady() {
    if (_isHeld && _initialDataReady && _webViewReady) {
      release(WhiteboardSyncGateOpenReason.ready);
    }
  }
}
