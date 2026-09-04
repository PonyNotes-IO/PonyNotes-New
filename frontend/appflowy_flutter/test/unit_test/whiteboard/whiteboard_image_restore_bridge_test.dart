import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('白板图片恢复只注入图片 dataURL 并在解码后刷新画布', () {
    final bridge =
        File('assets/excalidraw/flutter_bridge.js').readAsStringSync();

    expect(
      bridge,
      contains("candidateDataURL.startsWith('data:image/')"),
    );
    expect(
      bridge,
      contains("candidateDataURL.startsWith('http')"),
    );
    expect(
      bridge,
      contains('await _awaitImageDecodeAndRefresh(api, toAdd)'),
    );
    expect(
      bridge,
      contains('await _awaitImageDecodeAndRefresh(api, downloaded)'),
    );
    expect(bridge, contains("typeof image.decode === 'function'"));
    expect(bridge, contains('requestAnimationFrame(resolve)'));
  });
}
