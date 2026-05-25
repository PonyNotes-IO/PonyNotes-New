import 'package:flutter/foundation.dart';

class PublishRefresh {
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static void ping() {
    notifier.value++;
  }
}







