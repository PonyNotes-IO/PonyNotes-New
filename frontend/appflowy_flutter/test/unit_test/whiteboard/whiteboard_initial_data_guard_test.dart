import 'package:appflowy/plugins/whiteboard/application/whiteboard_initial_data_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new whiteboard metadata with empty scene is blank', () {
    final data = <String, dynamic>{
      'type': 'excalidraw',
      'elements': <dynamic>[],
      'appState': {'viewBackgroundColor': '#ffffff'},
      'files': <String, dynamic>{},
    };

    expect(WhiteboardInitialDataGuard.isBlankScene(data), isTrue);
    expect(
      WhiteboardInitialDataGuard.hasMeaningfulSceneChange(data),
      isFalse,
    );
  });

  test('non-empty elements are a meaningful local scene change', () {
    final data = <String, dynamic>{
      'elements': [
        {'id': 'first-image', 'type': 'image', 'width': 0, 'height': 0},
      ],
    };

    expect(WhiteboardInitialDataGuard.isBlankScene(data), isFalse);
    expect(
      WhiteboardInitialDataGuard.hasMeaningfulSceneChange(data),
      isTrue,
    );
  });

  test('non-empty image files are meaningful before elements callback arrives',
      () {
    final data = <String, dynamic>{
      'files': {
        'image-file': {'dataURL': 'data:image/png;base64,AA=='},
      },
    };

    expect(WhiteboardInitialDataGuard.isBlankScene(data), isFalse);
    expect(
      WhiteboardInitialDataGuard.hasMeaningfulSceneChange(data),
      isTrue,
    );
  });

  test('serialized empty and non-empty collections are normalized', () {
    expect(
      WhiteboardInitialDataGuard.isBlankScene({
        'elements': '[]',
        'files': '{}',
      }),
      isTrue,
    );
    expect(
      WhiteboardInitialDataGuard.hasMeaningfulSceneChange({
        'elements': '[{"id":"first-image"}]',
      }),
      isTrue,
    );
  });
}
