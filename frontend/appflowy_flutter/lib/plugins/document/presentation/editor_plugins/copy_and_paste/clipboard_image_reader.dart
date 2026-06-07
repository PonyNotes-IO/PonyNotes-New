import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:super_clipboard/super_clipboard.dart';

Future<(String, Uint8List?)?> readImageFromClipboard() async {
  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      Log.debug('Clipboard API is not available on this platform');
      return null;
    }

    final reader = await clipboard.read();
    for (final item in reader.items) {
      final imageFormats = [
        (Formats.png, 'png'),
        (Formats.jpeg, 'jpeg'),
        (Formats.gif, 'gif'),
        (Formats.webp, 'webp'),
      ];

      for (final (format, formatName) in imageFormats) {
        if (item.canProvide(format)) {
          final completer = Completer<Uint8List?>();
          final progress = item.getFile(
            format,
            (file) async {
              try {
                final bytes = await file.readAll();
                completer.complete(bytes);
              } catch (e) {
                completer.complete(null);
              } finally {
                file.close();
              }
            },
            onError: (error) {
              completer.complete(null);
            },
          );

          if (progress != null) {
            final bytes = await completer.future;
            if (bytes != null && bytes.isNotEmpty) {
              return (formatName, bytes);
            }
          }
        }
      }
    }
  } catch (e) {
    Log.debug('Failed to read image from clipboard: $e');
  }
  return null;
}

String _detectImageFormat(Uint8List data) {
  if (data.length < 4) {
    return 'png';
  }
  if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
    return 'jpeg';
  } else if (data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4E &&
      data[3] == 0x47) {
    return 'png';
  } else if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) {
    return 'gif';
  }
  return 'png';
}