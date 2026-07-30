import 'dart:async';

class Throttler {
  Throttler({
    this.duration = const Duration(milliseconds: 1000),
  });

  final Duration duration;
  Timer? _timer;

  void call(Function callback) {
    if (_timer?.isActive ?? false) return;

    // leading edge：立即执行首次调用，后续 duration 内的调用被丢弃
    callback();

    _timer = Timer(duration, () {});
  }

  void cancel() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
