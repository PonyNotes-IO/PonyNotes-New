import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('whiteboard webview container is not keyed by layout size', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("ValueKey('whiteboard_container_")));
  });
}
