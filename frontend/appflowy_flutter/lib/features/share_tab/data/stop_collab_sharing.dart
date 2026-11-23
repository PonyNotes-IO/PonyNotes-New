import 'dart:convert';

import 'package:http/http.dart' as http;

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
  if (decoded is! Map<String, dynamic> || decoded['code'] != 0) {
    throw Exception(
      decoded is Map ? decoded['message'] ?? '服务器返回错误' : '服务器返回错误',
    );
  }
}
