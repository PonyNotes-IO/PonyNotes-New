import 'dart:typed_data';

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_image_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectImageFormat', () {
    test('recognizes clipboard image formats from their signatures', () {
      expect(
        detectImageFormat(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        'png',
      );
      expect(
        detectImageFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
        'jpeg',
      );
      expect(
        detectImageFormat(
          Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
        ),
        'gif',
      );
      expect(
        detectImageFormat(
          Uint8List.fromList([
            0x52,
            0x49,
            0x46,
            0x46,
            0x00,
            0x00,
            0x00,
            0x00,
            0x57,
            0x45,
            0x42,
            0x50,
          ]),
        ),
        'webp',
      );
    });

    test('rejects non-image clipboard data', () {
      expect(detectImageFormat(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  test('decodes a copied image size only when it is valid metadata', () {
    final size = decodeImageSize('{"width": 240, "height": 160}');
    expect(size?.width, 240);
    expect(size?.height, 160);
    expect(decodeImageSize('not json'), isNull);
    expect(decodeImageSize('{"width": "small"}'), isNull);
  });
}
