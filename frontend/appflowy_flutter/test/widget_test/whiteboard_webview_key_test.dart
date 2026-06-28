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

  test('whiteboard layout changes do not actively refresh the webview', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Future<void> notifyContainerResized()')));
    expect(source, isNot(contains('_installResizeGuard')));
    expect(source, isNot(contains('_ponynotesResizeObserver')));
    expect(source, isNot(contains('api.refresh')));
    expect(source, isNot(contains('_api.refresh')));
  });

  test('whiteboard platform view resize is settled before applying', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, contains('_stableWebViewSize'));
    expect(source, contains('_pendingWebViewSize'));
    expect(source, contains('_webViewResizeSettleTimer'));
    expect(source, contains('_webViewResizeSettleDuration'));
    expect(source, contains('ClipRect'));
    expect(source, contains('Alignment.topLeft'));
  });

  test('whiteboard webview dispose releases controller handlers', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, contains('_javaScriptHandlerNames'));
    expect(source, contains('controller.removeJavaScriptHandler'));
    expect(source, contains('controller.dispose()'));
    expect(source, contains('_isDisposed = true'));
  });

  test('whiteboard adapter stops listener before dispose completes', () {
    final source = File(
      'lib/plugins/whiteboard/application/whiteboard_collab_adapter.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> forceSyncAndDispose()'));
    expect(source, contains('await _listener.stop()'));
    expect(source, contains('dispose();'));
  });

  test('closing tabs disposes removed page managers', () {
    final source = File(
      'lib/workspace/application/tabs/tabs_bloc.dart',
    ).readAsStringSync();

    expect(source, contains('_disposePageManagersRemovedFrom'));
    expect(source, contains('manager.dispose();'));
  });

  test('whiteboard storage bridge batches high frequency drawing sync', () {
    final source =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(source, contains('pendingFlutterStorageSyncs'));
    expect(source, contains('scheduleFlutterStorageSync'));
    expect(source, contains('flushFlutterStorageSync'));
    expect(source, contains('flutterStorageSyncDelays'));
    expect(
        source,
        isNot(contains(
          "window.flutter_inappwebview.callHandler('localStorageOnSet', { key: key, value: valueForSync });",
        )));
  });

  test('whiteboard collab adapter does not save on every pen frame', () {
    final source = File(
      'lib/plugins/whiteboard/application/whiteboard_collab_adapter.dart',
    ).readAsStringSync();
    final dataServiceSource = File(
      'lib/plugins/whiteboard/application/whiteboard_data_service.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains('_debounceDuration = Duration(milliseconds: 50)')),
    );
    expect(source, contains('Duration(milliseconds: 650)'));
    expect(source, isNot(contains('Saving whiteboard data, fullData keys')));
    expect(source, isNot(contains('Files count:')));
    expect(source, isNot(contains('Notification update: key=')));
    expect(source, isNot(contains('Pushed to WebView: key=')));
    expect(
      dataServiceSource,
      isNot(contains('Log.info(\'[WBCollab][WhiteboardDataService] Saving')),
    );
  });

  test('current user profile requests are coalesced during rebuild storms', () {
    final source =
        File('lib/user/application/user_service.dart').readAsStringSync();

    expect(source, contains('_currentUserProfileInFlight'));
    expect(source, contains('_currentUserProfileCacheTtl'));
    expect(source, contains('_cachedCurrentUserProfile'));
    expect(
      source,
      contains('final inFlight = _currentUserProfileInFlight;'),
    );
  });
}
