import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<Uint8List> downloadHandwritingPdf(
  Uri uri, {
  required Map<String, String> headers,
  required http.Client client,
}) async {
  const idleTimeout = Duration(seconds: 60);
  try {
    final request = http.Request('GET', uri)..headers.addAll(headers);
    final response = await client.send(request).timeout(idleTimeout);
    if (response.statusCode != 200) {
      throw HttpException('PDF download HTTP ${response.statusCode}');
    }
    // 大 PDF 只限制无数据的等待时间，持续传输超过 60 秒仍应完成。
    return await http.ByteStream(response.stream.timeout(idleTimeout))
        .toBytes();
  } finally {
    client.close();
  }
}
