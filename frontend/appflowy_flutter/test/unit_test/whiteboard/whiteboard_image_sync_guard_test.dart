import 'package:appflowy/plugins/whiteboard/application/whiteboard_image_sync_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects an image element whose file callback has not arrived', () {
    final elements = [
      {'id': 'image-1', 'type': 'image', 'fileId': 'file-1'},
    ];

    expect(
      WhiteboardImageSyncGuard.unresolvedFileIds(
        elements: elements,
        files: <String, dynamic>{},
      ),
      {'file-1'},
    );
  });

  test('does not defer when the referenced file is present', () {
    expect(
      WhiteboardImageSyncGuard.hasUnresolvedImageFiles(
        elements: [
          {'type': 'image', 'fileId': 'file-1'},
        ],
        files: {
          'file-1': {'dataURL': 'data:image/png;base64,AA=='},
        },
      ),
      isFalse,
    );
  });

  test('ignores non-image and deleted elements', () {
    final elements = [
      {'type': 'rectangle', 'id': 'shape-1'},
      {'type': 'image', 'fileId': 'deleted-file', 'isDeleted': true},
    ];

    expect(
      WhiteboardImageSyncGuard.collectReferencedImageFileIds(elements),
      isEmpty,
    );
    expect(
      WhiteboardImageSyncGuard.hasUnresolvedImageFiles(
        elements: elements,
        files: <String, dynamic>{},
      ),
      isFalse,
    );
  });
}
