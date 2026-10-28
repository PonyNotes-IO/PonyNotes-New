import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

typedef FileUploadProgress = void Function(int sentBytes, int totalBytes);

/// Counts bytes consumed by the HTTP transport, not server acknowledgement.
class FileUploadRequest extends http.BaseRequest {
  FileUploadRequest(super.method, super.url, this.bytes, {this.onProgress}) {
    contentLength = bytes.length;
  }

  final Uint8List bytes;
  final FileUploadProgress? onProgress;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body());
  }

  Stream<List<int>> _body() async* {
    onProgress?.call(0, bytes.length);
    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < bytes.length;) {
      final end = math.min(offset + chunkSize, bytes.length);
      yield Uint8List.sublistView(bytes, offset, end);
      offset = end;
      onProgress?.call(offset, bytes.length);
    }
  }
}
