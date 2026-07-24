import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy_backend/log.dart';
import 'package:cross_file/cross_file.dart';
import 'package:super_clipboard/super_clipboard.dart';

const imageSizeClipboardFormat = CustomValueFormat<String>(
  applicationId: 'com.xiaomabiji.app.note.ImageSize',
);

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
                completer.complete(await file.readAll());
              } catch (_) {
                completer.complete(null);
              } finally {
                file.close();
              }
            },
            onError: (_) => completer.complete(null),
          );

          if (progress != null) {
            final bytes = await completer.future;
            if (bytes != null && bytes.isNotEmpty) {
              final detectedFormat = detectImageFormat(bytes);
              if (detectedFormat != null) {
                return (detectedFormat, bytes);
              }
              Log.debug(
                'Ignored invalid $formatName data from the system clipboard',
              );
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

Future<({double? width, double? height})?> readImageSizeFromClipboard() async {
  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return null;
    }

    final reader = await clipboard.read();
    for (final item in reader.items) {
      if (!item.canProvide(imageSizeClipboardFormat)) {
        continue;
      }
      final value = await item.readValue(imageSizeClipboardFormat);
      if (value == null) {
        continue;
      }
      final imageSize = decodeImageSize(value);
      if (imageSize != null) {
        return imageSize;
      }
    }
  } catch (e) {
    Log.debug('Failed to read image size from clipboard: $e');
  }
  return null;
}

({double? width, double? height})? decodeImageSize(String value) {
  try {
    final json = jsonDecode(value);
    if (json is! Map) {
      return null;
    }
    final width = json['width'];
    final height = json['height'];
    if (width is! num && height is! num) {
      return null;
    }
    return (
      width: width is num ? width.toDouble() : null,
      height: height is num ? height.toDouble() : null,
    );
  } catch (_) {
    return null;
  }
}

/// Reads the original bytes when possible, so copying a document image does
/// not turn it into a screenshot with different dimensions or encoding.
Future<(String, Uint8List)?> readImageFromSource(String source) async {
  try {
    Uint8List bytes;
    if (source.startsWith('data:image/')) {
      final commaIndex = source.indexOf(',');
      if (commaIndex == -1) {
        return null;
      }
      bytes = base64Decode(source.substring(commaIndex + 1));
    } else {
      final uri = Uri.tryParse(source);
      final isNetworkImage =
          uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      if (isNetworkImage) {
        final manager = CustomImageCacheManager();
        final cached = await manager.getFileFromCache(source);
        final file = cached?.file ?? await manager.getSingleFile(source);
        bytes = await file.readAsBytes();
      } else {
        bytes = await XFile(source).readAsBytes();
      }
    }

    final format = detectImageFormat(bytes);
    return format == null ? null : (format, bytes);
  } catch (e) {
    Log.debug('Failed to read image source for clipboard: $e');
    return null;
  }
}

/// Returns a supported image format only when the bytes have a valid image
/// signature. This prevents arbitrary clipboard bytes from being saved as an
/// image merely because a clipboard provider declared an image type.
String? detectImageFormat(Uint8List data) {
  if (data.length >= 3 &&
      data[0] == 0xFF &&
      data[1] == 0xD8 &&
      data[2] == 0xFF) {
    return 'jpeg';
  }
  if (data.length >= 8 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4E &&
      data[3] == 0x47 &&
      data[4] == 0x0D &&
      data[5] == 0x0A &&
      data[6] == 0x1A &&
      data[7] == 0x0A) {
    return 'png';
  }
  if (data.length >= 6 &&
      data[0] == 0x47 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[3] == 0x38 &&
      (data[4] == 0x37 || data[4] == 0x39) &&
      data[5] == 0x61) {
    return 'gif';
  }
  if (data.length >= 12 &&
      data[0] == 0x52 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[3] == 0x46 &&
      data[8] == 0x57 &&
      data[9] == 0x45 &&
      data[10] == 0x42 &&
      data[11] == 0x50) {
    return 'webp';
  }
  return null;
}
