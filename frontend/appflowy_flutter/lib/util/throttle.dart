import 'dart:async';

class Throttler {
  Throttler({
    this.duration = const Duration(milliseconds: 1000),
    this.trailing = false,
  });

  final Duration duration;

  /// When enabled, also run the latest call received during each cooldown.
  final bool trailing;
  Timer? _timer;
  void Function()? _pending;

  void call(void Function() callback) {
    if (_timer?.isActive ?? false) {
      if (trailing) {
        _pending = callback;
      }
      return;
    }

    _timer = Timer(duration, () {
      final pending = _pending;
      _pending = null;
      if (pending != null) {
        call(pending);
      }
    });
    callback();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void dispose() => cancel();
}
