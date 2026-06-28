import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('whiteboard webview container is not keyed by layout size', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("ValueKey('whiteboard_container_")));
  });

  test('whiteboard build path does not emit high-frequency logs', () {
    final source =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();

    expect(source, isNot(contains('[WhiteboardPage] build() called')));
    expect(source, isNot(contains('Creating ExcalidrawWebView')));
  });

  test('whiteboard resize notifications are throttled', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, contains('_isPostingResizeNotification'));
    expect(source, contains('_lastResizeNotificationAt'));
    expect(source, contains('const Duration(milliseconds: 250)'));
  });
}
