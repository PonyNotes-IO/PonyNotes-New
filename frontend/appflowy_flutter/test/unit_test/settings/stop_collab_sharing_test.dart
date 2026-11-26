import 'package:appflowy/features/share_tab/data/stop_collab_sharing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse(
    'https://cloud.example.com/api/workspace/owner-workspace/collab/note/sharing',
  );

  test('stops sharing in the document workspace with authentication', () async {
    await http.runWithClient(
      () => stopCollabSharing(uri, 'token'),
      () => MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url, uri);
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response('{"code":0}', 200);
      }),
    );
  });

  test('shows a readable reason for a stale share or a permission error',
      () async {
    for (final (code, message, expected) in [
      (-2, 'Record not found:Record not exist in db.', '在共享记录指定的空间中找不到这篇文档。'),
      (1012, 'owner only', '当前账号没有权限停止这篇文档的共享。'),
    ]) {
      await http.runWithClient(
        () => expectLater(
          stopCollabSharing(uri, 'token'),
          throwsA(
            isA<StopSharingFailure>()
                .having(
                  (error) => error.message,
                  'message',
                  expected,
                )
                .having(
                    (error) => error.detail, 'diagnostic', contains(message)),
          ),
        ),
        () => MockClient(
          (_) async =>
              http.Response('{"code":$code,"message":"$message"}', 200),
        ),
      );
    }
  });

  test('rejects HTTP failures and malformed success responses', () async {
    for (final response in [
      http.Response('', 500),
      http.Response('{}', 200),
      http.Response('not JSON', 200),
    ]) {
      await http.runWithClient(
        () => expectLater(stopCollabSharing(uri, 'token'), throwsException),
        () => MockClient((_) async => response),
      );
    }
  });

  test('accepts a successful empty response', () async {
    await http.runWithClient(
      () => stopCollabSharing(uri, 'token'),
      () => MockClient((_) async => http.Response('', 204)),
    );
  });
}
