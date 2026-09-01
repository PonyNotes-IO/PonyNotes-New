/// WebView 剪贴板写入桥接，统一 WKWebView 和 Android WebView 的复制行为。
const String whiteboardClipboardBridgeScript = r'''
(function () {
  if (window.__ponynotesClipboardBridgeInstalled) return;
  function install() {
    if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) return false;
    var clipboard = navigator.clipboard;
    if (!clipboard) {
      clipboard = {};
      try { Object.defineProperty(navigator, 'clipboard', { configurable: true, value: clipboard }); }
      catch (_) { return false; }
    }
    var originalWrite = clipboard.write && clipboard.write.bind(clipboard);
    function bytesToBase64(bytes) {
      var binary = '';
      for (var i = 0; i < bytes.length; i += 0x8000) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      }
      return btoa(binary);
    }
    async function readItems(items) {
      var payload = {};
      for (var i = 0; i < (items || []).length; i++) {
        var item = items[i];
        for (var j = 0; j < (item.types || []).length; j++) {
          var type = item.types[j];
          var blob = await item.getType(type);
          if (type === 'image/svg+xml') {
            payload.plainText = await blob.text();
          } else if (type.indexOf('image/') === 0) {
            payload.imageBase64 = bytesToBase64(new Uint8Array(await blob.arrayBuffer()));
            payload.imageMimeType = type;
          } else if (type === 'text/html') {
            payload.html = await blob.text();
          } else if (type === 'text/plain') {
            payload.plainText = await blob.text();
          }
        }
      }
      return payload;
    }
    var nativeWrite = async function (items) {
      var payload = await readItems(items);
      if (!payload.imageBase64 && !payload.plainText && !payload.html) {
        if (originalWrite) return originalWrite(items);
        return;
      }
      return window.flutter_inappwebview.callHandler('writeWhiteboardClipboard', payload);
    };
    var nativeWriteText = function (text) {
      return window.flutter_inappwebview.callHandler(
        'writeWhiteboardClipboard', { plainText: String(text) },
      );
    };
    try {
      Object.defineProperty(clipboard, 'write', { configurable: true, writable: true, value: nativeWrite });
      Object.defineProperty(clipboard, 'writeText', { configurable: true, writable: true, value: nativeWriteText });
    } catch (_) {
      try { clipboard.write = nativeWrite; clipboard.writeText = nativeWriteText; }
      catch (ignored) { return false; }
    }
    window.__ponynotesClipboardBridgeInstalled = true;
    return true;
  }
  if (!install()) { setTimeout(install, 100); setTimeout(install, 500); setTimeout(install, 1500); }
})();
''';

String? whiteboardClipboardImageFormat(String? mimeType) {
  final value = mimeType?.toLowerCase() ?? '';
  if (value == 'image/jpeg' || value == 'image/jpg') return 'jpeg';
  if (value == 'image/gif') return 'gif';
  if (value == 'image/webp') return 'webp';
  if (value == 'image/png') return 'png';
  return null;
}
