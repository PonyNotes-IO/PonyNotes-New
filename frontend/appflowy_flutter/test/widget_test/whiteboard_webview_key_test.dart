import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('whiteboard webview container is not keyed by layout size', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("ValueKey('whiteboard_container_")));
  });

  test(
      'whiteboard webviews bridge clipboard writes to Flutter native clipboard',
      () {
    final bridge = File(
      'lib/plugins/whiteboard/presentation/whiteboard_clipboard_bridge.dart',
    ).readAsStringSync();
    final local = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final remote = File(
      'lib/plugins/whiteboard/presentation/remote_whiteboard_page.dart',
    ).readAsStringSync();
    final mobile = File(
      'lib/plugins/whiteboard/presentation/mobile_whiteboard_body.dart',
    ).readAsStringSync();

    expect(bridge, contains("'writeWhiteboardClipboard'"));
    expect(bridge, contains('clipboard.writeText'));
    expect(local, contains('whiteboardClipboardBridgeScript'));
    expect(local, contains("handlerName: 'writeWhiteboardClipboard'"));
    expect(remote, contains('whiteboardClipboardBridgeScript'));
    expect(remote, contains("handlerName: 'writeWhiteboardClipboard'"));
    expect(mobile, contains('whiteboardClipboardBridgeScript'));
    expect(mobile, contains("handlerName: 'writeWhiteboardClipboard'"));
  });

  test('whiteboard migration blocks and observes XHR scene writes', () {
    final source = File(
      'lib/plugins/whiteboard/presentation/whiteboard_migration_script.dart',
    ).readAsStringSync();

    expect(source, contains('XMLHttpRequest'));
    expect(source, contains('__xmMigPatched'));
    expect(source, contains('已拦截未授权的 XHR room 写入'));
    expect(source, contains('state.lastPostStatus = xhr.status'));
    expect(source, contains('state.lastGetSceneVersion = isNaN(v) ? 0 : v'));
  });

  test('whiteboard import reload token reaches the platform view key', () {
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(pageSource, contains('reloadToken: _importReloadCounter'));
    expect(webViewSource, contains('final int reloadToken;'));
    expect(webViewSource, contains('widget.reloadToken'));
    expect(
      webViewSource,
      contains(
        r'inappwebview_${widget.viewId}_r${widget.reloadToken}_recovery_$_webViewRecoveryNonce',
      ),
    );
  });

  test(
    'whiteboard recreates a stale iOS platform view after loadUrl failure',
    () {
      final source = File(
        'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
      ).readAsStringSync();

      expect(source, contains('on MissingPluginException catch'));
      expect(source, contains('_controller = null'));
      expect(source, contains('_webViewCreated = false'));
      expect(source, contains('_webViewRecoveryNonce++'));
    },
  );

  test('local whiteboard server URL matches its IPv4 listener', () {
    final source = File(
      'lib/plugins/whiteboard/application/local_asset_server.dart',
    ).readAsStringSync();

    expect(source, contains("'http://127.0.0.1:\$_port'"));
    expect(source, contains('InternetAddress.loopbackIPv4'));
    expect(source, contains('_lifecycleLock.synchronized'));
    expect(source, contains('Future<bool> _isHealthy()'));
    expect(source, contains("requestPath == '__health'"));
    expect(source, contains('await _stopUnlocked()'));
  });

  test('local whiteboard main-frame connection errors restart asset server',
      () {
    final source = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(source, contains('onReceivedError:'));
    expect(source, contains('request.isForMainFrame == false'));
    expect(source, contains('_recoverLocalAssetServer(message)'));
    expect(source, contains('await _assetServer.restart()'));
  });

  test('whiteboard import uses the full JS restoration path', () {
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();

    expect(bridgeSource, contains('_initPayload = data || {};'));
    expect(bridgeSource, contains('await _restoreWhiteboardData(api);'));
    expect(pageSource, isNot(contains('Duration(milliseconds: 80)')));
  });

  test('late scene restoration waits for JS and preserves local edits', () {
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(webViewSource, contains('await evaluateAsyncJavascript('));
    expect(webViewSource, contains('await window.loadExcalidrawData'));
    expect(
      bridgeSource,
      contains('Preserved local edits while applying initial data'),
    );
    expect(bridgeSource, contains('_reconcileElements('));
    expect(bridgeSource, contains('_mergeRemoteElements('));
    expect(
      bridgeSource,
      contains('const merged = _mergeRemoteElements(current, data.value);'),
    );
    expect(bridgeSource, contains("'whiteboardImageSceneSnapshot'"));
    expect(bridgeSource, contains('direct image scene delivered'));
    expect(bridgeSource, contains('_ponynotesWaitForUsableAPI()'));
    expect(
        bridgeSource, contains('typeof candidate.addFiles === \'function\''));
    expect(bridgeSource,
        contains('typeof candidate.getSceneElements === \'function\''));
    expect(bridgeSource, contains('await window.waitForWhiteboardDataReady();'));
  });

  test('initial whiteboard readiness waits for bridge scene restoration', () {
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(
      bridgeSource,
      contains('const _initialDataRestoreGate = new Promise'),
    );
    expect(
      bridgeSource,
      contains('window.waitForWhiteboardDataReady = async function'),
    );
    expect(bridgeSource, contains('_initialDataRestoreGateResolve?.()'));
    expect(
      webViewSource,
      contains('await window.waitForWhiteboardDataReady();'),
    );
    expect(
      webViewSource.indexOf('await window.waitForWhiteboardDataReady();'),
      lessThan(webViewSource.indexOf('await _initializeExcalidraw();')),
    );
  });

  test('private whiteboard blocks editing until initial data is ready', () {
    final source =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();

    expect(source, contains('final interactiveView = _isLoadingData'));
    expect(source, contains('IgnorePointer(child: excalidrawView)'));
  });

  test('whiteboard import invalidates stale initial data load', () {
    final source = File(
      'lib/plugins/whiteboard/whiteboard.dart',
    ).readAsStringSync();

    expect(source, contains('_initialDataLoadGeneration++'));
    expect(
        source, contains('final loadGeneration = _initialDataLoadGeneration'));
    expect(source, contains('loadGeneration != _initialDataLoadGeneration'));
  });

  test('whiteboard lifecycle resume does not consume the import reload token',
      () {
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();

    expect(
      pageSource,
      isNot(contains('_importReloadCounter++; // 强制重建 WebView')),
    );
  });

  test(
      'whiteboard reloads imported and late initial data through the restore path',
      () {
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(
      webViewSource,
      contains('oldWidget.reloadToken != widget.reloadToken'),
    );
    expect(
      webViewSource,
      contains('!oldWidget.initialDataLoaded && widget.initialDataLoaded'),
    );
    expect(
      webViewSource,
      contains('widget.initialData!,'),
    );
    expect(
      webViewSource,
      contains('dataArrivedLate && !reloadTokenChanged'),
    );
    expect(
      webViewSource,
      contains('preserveLocalSceneForBlankData:'),
    );
  });

  test('late blank initial data preserves an already edited local scene', () {
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(
      pageSource,
      contains('_hasMeaningfulLocalChangeDuringInitialLoad'),
    );
    expect(
      pageSource,
      contains('WhiteboardInitialDataGuard.isBlankScene(data)'),
    );
    expect(
      bridgeSource,
      contains('options.preserveLocalSceneForBlankData === true'),
    );
    expect(bridgeSource, contains('isBlankScenePayload(data)'));
    expect(bridgeSource, contains('currentElements.length > 0'));
    expect(
      bridgeSource,
      contains('Preserved local scene from late blank initial data'),
    );
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

  test(
      'whiteboard startup gates local cloud sync until data and webview are ready',
      () {
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();
    final adapterSource = File(
      'lib/plugins/whiteboard/application/whiteboard_collab_adapter.dart',
    ).readAsStringSync();
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(adapterSource, contains('holdAutoSyncUntilReady'));
    expect(adapterSource, contains('markInitialDataReadyForAutoSync'));
    expect(adapterSource, contains('markWebViewReadyForAutoSync'));
    expect(adapterSource, contains('Auto sync blocked by startup gate'));
    expect(adapterSource, contains('holdAutoSyncUntilReady();'));
    expect(
      pageSource,
      contains('_collabAdapter?.markInitialDataReadyForAutoSync();'),
    );
    expect(pageSource, contains('onInitialReady: _onWhiteboardInitialReady'));
    expect(webViewSource, contains('final VoidCallback? onInitialReady;'));
    expect(webViewSource, contains('_notifyInitialReadyOnce();'));
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

  test('iOS image bridge atomically delivers the first image scene', () {
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();

    expect(bridgeSource, contains('queueIOSImageSceneSync(elements, files);'));
    expect(bridgeSource, contains("'whiteboardImageSceneSnapshot'"));
    expect(bridgeSource,
        contains('await window.flutter_inappwebview.callHandler'));
    expect(bridgeSource, contains('iOS image scene delivered'));
    expect(bridgeSource, contains('_iosImageSceneSyncInFlight'));
    expect(bridgeSource, contains('_iosImageSceneSyncInFlightPromise'));
    expect(bridgeSource, contains('scheduleIOSImageSceneSyncFlush'));
    expect(webViewSource, contains("'whiteboardImageSceneSnapshot'"));
    expect(webViewSource, contains("'elements': List<dynamic>.from(elements)"));
    expect(
        webViewSource, contains("'files': Map<String, dynamic>.from(files)"));
  });

  test('image insertion waits for a usable canvas and repairs zero-size images',
      () {
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();
    final bundledEditor = File(
      'assets/excalidraw/assets/index-D9TGhlVV.js',
    ).readAsStringSync();

    expect(bridgeSource, contains('needsDimensionRepair'));
    expect(bridgeSource, contains('zero-size image repaired'));
    expect(bundledEditor, contains('performance.now()+1500'));
    expect(
      bundledEditor,
      contains(
          'this.state.height||this.excalidrawContainerRef.current?.clientHeight'),
    );
  });

  test('whiteboard storage bridge confirms delivery before deduplication', () {
    final source =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();
    final sendIndex = source.indexOf("'localStorageOnSet'");
    final acknowledgeIndex = source.indexOf(
      'lastSentFlutterStorageValues.set(key, value);',
      sendIndex,
    );

    expect(sendIndex, greaterThanOrEqualTo(0));
    expect(acknowledgeIndex, greaterThan(sendIndex));
    expect(source, contains('pendingFlutterStorageSyncs.set(key, payload);'));
    expect(source, contains('syncFilesFromScene(pendingFilesSyncKey, true)'));
  });

  test('whiteboard forces host theme and disables internal theme switching',
      () {
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(webViewSource, contains('officialUpdateScene'));
    expect(webViewSource, contains('_hostThemeRuntimeScript'));
    expect(webViewSource, contains('__ponynotesRuntimeThemeWatchdog'));
    expect(webViewSource, contains('canvas.static, canvas.interactive'));
    expect(webViewSource, contains('__ponynotesApplyReactTheme'));
    expect(webViewSource, contains('__ponynotesSetHostTheme'));
    expect(webViewSource, contains('ponynotes-host-theme-style'));
    expect(webViewSource,
        contains('html.dark #root .excalidraw canvas.excalidraw__canvas'));
    expect(bridgeSource, contains('window.setHostTheme = function'));
    expect(bridgeSource, contains('_forcedHostTheme'));
    expect(bridgeSource, contains('initialHostTheme'));
    expect(
        bridgeSource, contains('appStateToRestore.theme = _forcedHostTheme'));
    expect(
      bridgeSource,
      contains("appStateToRestore.viewBackgroundColor ="),
    );
    expect(bridgeSource, contains('api.updateScene'));
    expect(bridgeSource, contains('syncExcalidrawReactTheme'));
    expect(bridgeSource, contains('__ponynotesSetHostTheme'));
    expect(bridgeSource, contains('__ponynotesHostTheme'));
    expect(bridgeSource, contains('ponynotes-host-theme-style'));
    expect(bridgeSource,
        contains('html.dark #root .excalidraw canvas.excalidraw__canvas'));
    expect(bridgeSource, contains('enforceHostTheme'));
    // 深色主题由 Excalidraw 的 canvas 反色滤镜渲染，宿主桥接只更新
    // theme；旧版本写入的 #121212 背景需要迁移回白色基准。
    expect(
        bridgeSource, contains('const appState = { theme: normalizedTheme };'));
    expect(bridgeSource, contains('legacyDarkBackground'));
    expect(
      bridgeSource,
      contains("appState.viewBackgroundColor = '#ffffff'"),
    );
    expect(webViewSource, contains("canvas.style.backgroundColor = '';"));
    expect(bridgeSource, contains('_ponynotesHostThemeWatchdog'));
    expect(bridgeSource, isNot(contains('KeyboardEvent')));
    expect(bridgeSource, contains("classList.toggle('theme--dark'"));
    expect(webViewSource, contains('toggle-dark-mode'));
    expect(webViewSource, contains('text.includes(\'system mode\')'));
    expect(webViewSource, contains('Theme.of(context).brightness'));
    expect(pageSource, contains('_whiteboardCanvasDarkColor'));
    expect(pageSource, contains('canvasFallbackColor'));
    expect(pageSource, contains('didChangePlatformBrightness'));
    expect(pageSource, contains('_brightnessPollTimer'));
    expect(pageSource, contains('Timer.periodic'));
    expect(pageSource, contains('_syncSystemBrightness'));
    expect(pageSource, contains('_themeSyncGeneration'));
    expect(pageSource, contains('generation != _themeSyncGeneration'));
    expect(
      pageSource,
      contains('主题同步由 didChangeDependencies、didChangePlatformBrightness 和轮询'),
    );
    final indexSource = File('assets/excalidraw/index.html').readAsStringSync();
    expect(indexSource, contains('getSystemTheme'));
    expect(indexSource, contains('getInitialTheme'));
    expect(webViewSource, contains('hostTheme'));
    expect(webViewSource, contains('ponynotes-whiteboard-v9'));
    expect(indexSource,
        contains('localStorage.setItem("excalidraw-theme", theme)'));
    expect(indexSource, contains('initialTheme'));
    expect(indexSource, contains('syncThemeFromSystem'));
    expect(indexSource, contains('systemThemeQuery.addEventListener'));
    expect(
        webViewSource, contains('var hostThemeSetter = window.setHostTheme'));
    expect(webViewSource, contains('__ponynotesSystemThemeListenerInstalled'));
    expect(
        webViewSource, contains("matchMedia('(prefers-color-scheme: dark)')"));
    expect(indexSource,
        contains('html.dark #root .excalidraw canvas.excalidraw__canvas'));
    // 带有初始 hostTheme 时也必须保留系统外观监听，覆盖白板驻留期间的切换。
    expect(indexSource, contains('systemThemeQuery.addEventListener'));
    final remoteSource = File(
      'lib/plugins/whiteboard/presentation/remote_whiteboard_page.dart',
    ).readAsStringSync();
    expect(remoteSource, contains('hostTheme'));
    expect(remoteSource, contains('__ponynotesApplyTheme'));
    expect(remoteSource, contains('didChangeDependencies'));
    expect(remoteSource, contains('_currentSystemBrightness'));
    expect(remoteSource, contains('Theme.of(context).brightness'));
    expect(remoteSource, contains('WidgetsBindingObserver'));
    expect(remoteSource, contains('_brightnessPollTimer'));
    expect(remoteSource, contains('window.setHostTheme'));
    expect(remoteSource, contains('Timer.periodic'));
    expect(remoteSource, contains('_syncSystemBrightness'));
    expect(remoteSource, contains('_themeSyncGeneration'));
    expect(remoteSource, contains('__ponynotesSetHostTheme'));
    expect(remoteSource, contains('canvas.static, canvas.interactive'));
    expect(remoteSource, contains('ponynotes-host-theme-style'));
    expect(
      remoteSource,
      contains('html.dark #root .excalidraw canvas.excalidraw__canvas'),
    );
    expect(remoteSource, contains('Dart host theme applied'));
    expect(remoteSource, isNot(contains('new KeyboardEvent')));

    // 移动端 /whiteboard 路由仍使用 MobileWhiteboardBody，必须与协作空间
    // RemoteWhiteboardPage 共用同一套系统主题同步链路。
    final mobileSource = File(
      'lib/plugins/whiteboard/presentation/mobile_whiteboard_body.dart',
    ).readAsStringSync();
    expect(mobileSource, contains('WidgetsBindingObserver'));
    expect(mobileSource, contains('didChangeDependencies'));
    expect(mobileSource, contains('_currentSystemBrightness'));
    expect(mobileSource, contains('Theme.of(context).brightness'));
    expect(mobileSource, contains('_brightnessPollTimer'));
    expect(mobileSource, contains('window.setHostTheme'));
    expect(mobileSource, contains('_syncSystemBrightness'));
    expect(mobileSource, contains('_themeSyncGeneration'));
    expect(mobileSource, contains('hostTheme'));
    expect(mobileSource, contains('__ponynotesApplyTheme'));
    expect(mobileSource, contains('__ponynotesSetHostTheme'));
    expect(mobileSource, contains('canvas.static, canvas.interactive'));
    expect(mobileSource, contains('ponynotes-host-theme-style'));
    expect(
      mobileSource,
      contains('html.dark #root .excalidraw canvas.excalidraw__canvas'),
    );
    expect(mobileSource, contains('Dart host theme applied'));
    expect(mobileSource, isNot(contains('new KeyboardEvent')));
    expect(mobileSource, contains('UserScriptInjectionTime.AT_DOCUMENT_START'));
    expect(
      mobileSource,
      contains('source: _mobileWhiteboardReadinessScript'),
    );
    expect(mobileSource, contains('_waitForWhiteboardReady'));
    expect(mobileSource, contains('state.isLoading === false'));
    expect(mobileSource, contains('portal.socketInitialized !== true'));
    expect(mobileSource, contains('loadGeneration != _pageLoadGeneration'));
    expect(mobileSource, contains('AbsorbPointer'));
    expect(mobileSource, contains('request.isForMainFrame == false'));
    expect(mobileSource, contains('LocaleKeys.error_loadingViewError.tr()'));
    expect(mobileSource, contains('LocaleKeys.button_retry.tr()'));
    expect(
      mobileSource.indexOf('_waitForWhiteboardReady('),
      lessThan(mobileSource.indexOf('_isLoading = false;', 0)),
    );
  });

  test('whiteboard theme follows the effective app theme in real time', () {
    final pageSource =
        File('lib/plugins/whiteboard/whiteboard.dart').readAsStringSync();
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final mobileSource = File(
      'lib/plugins/whiteboard/presentation/mobile_whiteboard_body.dart',
    ).readAsStringSync();
    expect(pageSource, contains('didChangeDependencies'));
    expect(pageSource, contains('_currentSystemBrightness'));
    expect(pageSource, contains('Theme.of(context).brightness'));
    expect(webViewSource, contains('_currentSystemBrightness'));
    expect(webViewSource, contains('didChangeDependencies'));
    expect(webViewSource, contains('_lastObservedHostTheme'));
    expect(webViewSource, contains('Theme.of(context).brightness'));
    expect(mobileSource, contains('didChangeDependencies'));
    expect(mobileSource, contains('_currentSystemBrightness'));
    expect(mobileSource, contains('Theme.of(context).brightness'));
    expect(
      pageSource,
      contains('final currentBrightness = _currentSystemBrightness();'),
    );
  });

  test('whiteboard uses memory storage only on macOS', () {
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final bridgeSource =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(webViewSource, contains('TargetPlatform.macOS'));
    expect(webViewSource, contains("'memory'"));
    expect(webViewSource, contains("'persistent'"));
    expect(webViewSource, contains('storageMode=\$storageMode'));
    expect(bridgeSource, contains("urlParams.get('storageMode') === 'memory'"));
    expect(bridgeSource, contains('const memoryStorage = new Map();'));
    expect(bridgeSource, contains('memoryStorage.set(key, String(value));'));
    expect(bridgeSource, contains('window.flutter_inappwebview.callHandler'));
  });

  test('whiteboard bridge exposes pending storage flush for page teardown', () {
    final source =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(source, contains('window.__ponynotesFlushStorageSyncs'));
    expect(source, contains('async function flushAllFlutterStorageSyncs()'));
    expect(source, contains('await Promise.allSettled(pending)'));
    expect(source, contains('syncFilesFromScene(pendingFilesSyncKey)'));
  });

  test('whiteboard bridge recovers iOS image decode and stale viewport', () {
    final source =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(source, contains('installIOSImageDecodeRefresh'));
    expect(source, contains("element.type !== 'image'"));
    expect(source, contains("element.status !== 'pending'"));
    expect(source, contains('decodedFileIds.has(element.fileId)'));
    expect(source, contains("file.dataURL.startsWith('data:image/')"));
    expect(source, contains("typeof image.decode === 'function'"));
    expect(source, contains('api.onChange((elements, appState, files)'));
    expect(source, contains('getImageViewportSnapshot'));
    expect(source, contains("window.dispatchEvent(new Event('resize'))"));
    expect(source, contains('iOS zero-size image repaired'));
    expect(source, contains("typeof api.mutateElement === 'function'"));
    expect(source, contains('!snapshot.isVisible'));
    expect(source, contains('snapshot.width > 0'));
    expect(source, contains('snapshot.viewportWidth > 0'));
    expect(source, contains('api.scrollToContent(latestElement'));
    expect(source, contains("fitToContent: false"));
    expect(source, contains('requestAnimationFrame(() => api.refresh())'));
    expect(source, isNot(contains('api.resetScene()')));

    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    expect(webViewSource, contains("message.contains('iOS image decoded')"));
    expect(
      webViewSource,
      contains("message.contains('iOS image decode fallback')"),
    );
    expect(
      webViewSource,
      contains("message.contains('iOS image viewport')"),
    );
    expect(
      webViewSource,
      contains("'iOS inserted image cache rebuilt'"),
    );
    expect(
      webViewSource,
      contains(".contains('iOS zero-size image repaired')"),
    );
  });

  test('bundled Excalidraw decodes images and uses live picker viewport', () {
    final indexHtml = File('assets/excalidraw/index.html').readAsStringSync();
    final webViewSource = File(
      'lib/plugins/whiteboard/presentation/excalidraw_webview.dart',
    ).readAsStringSync();
    final bundle = Directory('assets/excalidraw/assets')
        .listSync()
        .whereType<File>()
        .firstWhere(
          (file) =>
              file.path.endsWith('.js') &&
              file.readAsStringSync().contains(
                    'Only images can be added to ImageCache',
                  ),
        )
        .readAsStringSync();

    expect(indexHtml, contains('ponynotes-whiteboard-v9'));
    expect(webViewSource, contains('ponynotes-whiteboard-v9'));

    expect(
      bundle,
      contains(
        's=/iPad|iPhone|iPod/.test(navigator.userAgent)||navigator.platform==="MacIntel"',
      ),
    );
    expect(bundle, contains('await Promise.race([i.decode()'));
    expect(bundle, contains('setTimeout(r,2e3)'));

    const pickerCall =
        'const n=await xT({description:"Image",extensions:Object.keys(Nh),multiple:!0})';
    const layoutSettle =
        'await new Promise(i=>{const s=performance.now()+1500,r=()=>{this.updateDOMRect();if(this.state.width>0&&this.state.height>0)';
    const liveViewport =
        'i=this.state.width/2+this.state.offsetLeft,s=this.state.height/2+this.state.offsetTop';
    expect(bundle, contains(pickerCall));
    expect(bundle, contains(layoutSettle));
    expect(bundle, contains(liveViewport));
    expect(bundle, contains('rebuildImageCacheForInsertedImages'));
    expect(bundle, contains('iOS inserted image cache rebuilt'));
    expect(bundle.indexOf(pickerCall), lessThan(bundle.indexOf(layoutSettle)));
    expect(
        bundle.indexOf(layoutSettle), lessThan(bundle.indexOf(liveViewport)));
    expect(
      bundle,
      contains('if((r<=0||o<=0)&&c>0&&u>0){n&&n();return}'),
    );
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
    expect(source, contains('Duration(milliseconds: 900)'));
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
