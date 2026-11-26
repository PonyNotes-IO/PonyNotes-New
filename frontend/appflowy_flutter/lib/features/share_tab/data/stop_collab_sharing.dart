import 'dart:convert';

import 'package:http/http.dart' as http;

class StopSharingFailure implements Exception {
  const StopSharingFailure(this.message, this.detail);

  final String message;
  final String detail;

  @override
  String toString() => '$message ($detail)';
}

Future<void> stopCollabSharing(Uri uri, String accessToken) async {
  final response = await http.delete(
    uri,
    headers: {'Authorization': 'Bearer $accessToken'},
  ).timeout(const Duration(seconds: 10));
  if (response.statusCode != 200 && response.statusCode != 204) {
    throw Exception('HTTP ${response.statusCode}');
  }
  if (response.statusCode == 204) return;
  final decoded = jsonDecode(response.body);
  if (decoded is Map<String, dynamic>) {
    final code = decoded['code'];
    final detail = 'code=$code: ${decoded['message']}';
    if (code == -2) {
      throw StopSharingFailure('在共享记录指定的空间中找不到这篇文档。', detail);
    }
    if (code == 1012) {
      throw StopSharingFailure('当前账号没有权限停止这篇文档的共享。', detail);
    }
  }
  if (decoded is! Map<String, dynamic> || decoded['code'] != 0) {
    throw Exception(
      decoded is Map ? decoded['message'] ?? '服务器返回错误' : '服务器返回错误',
    );
  }
}
