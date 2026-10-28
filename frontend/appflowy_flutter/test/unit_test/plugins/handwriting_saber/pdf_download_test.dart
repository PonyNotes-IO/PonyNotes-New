import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_pdf_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class _Client extends Mock implements http.Client {}

void main() {
  final uri = Uri.parse('https://example.com/document.pdf');
  late _Client client;

  setUpAll(() => registerFallbackValue(http.Request('GET', uri)));
  setUp(() => client = _Client());

  Future<List<int>> download() => downloadHandwritingPdf(
        uri,
        headers: {'Authorization': 'Bearer test-token'},
        client: client,
      );

  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('持续传输超过60秒的PDF可以完整下载并关闭连接', (tester) async {
    final body = StreamController<List<int>>();
    when(() => client.send(any())).thenAnswer((invocation) async {
      final request = invocation.positionalArguments.single as http.BaseRequest;
      expect(request.url, uri);
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.StreamedResponse(body.stream, 200);
    });
    List<int>? downloaded;
    unawaited(download().then((bytes) => downloaded = bytes));
    await flush(tester);
    expect(body.hasListener, isTrue);
    for (final chunk in ['%PDF-1.7\n', 'page data\n', '%%EOF']) {
      await tester.pump(const Duration(seconds: 40));
      body.add(utf8.encode(chunk));
      await flush(tester);
      expect(body.hasListener, isTrue);
      expect(downloaded, isNull);
      verifyNever(client.close);
    }
    unawaited(body.close());
    await flush(tester);
    expect(downloaded, isNotNull);
    expect(utf8.decode(downloaded!), '%PDF-1.7\npage data\n%%EOF');
    verify(client.close).called(1);
  });

  testWidgets('响应体连续60秒无数据会超时并关闭连接', (tester) async {
    final body = StreamController<List<int>>();
    when(() => client.send(any()))
        .thenAnswer((_) async => http.StreamedResponse(body.stream, 200));
    Object? error;
    unawaited(
      download().then<void>(
        (_) => fail('A stalled download must fail'),
        onError: (Object e) => error = e,
      ),
    );
    await flush(tester);
    body.add(utf8.encode('%PDF-'));
    await flush(tester);
    await tester.pump(const Duration(seconds: 60));
    await flush(tester);
    expect(error, isA<TimeoutException>());
    verify(client.close).called(1);
    unawaited(body.close());
    await flush(tester);
  });

  testWidgets('等待响应头超时会关闭连接', (tester) async {
    final response = Completer<http.StreamedResponse>();
    when(() => client.send(any())).thenAnswer((_) => response.future);
    Object? error;
    unawaited(
      download().then<void>(
        (_) => fail('Waiting for headers must time out'),
        onError: (Object e) => error = e,
      ),
    );
    await flush(tester);
    await tester.pump(const Duration(seconds: 60));
    await flush(tester);
    expect(error, isA<TimeoutException>());
    verify(client.close).called(1);
    response.complete(http.StreamedResponse(const Stream.empty(), 200));
  });

  test('HTTP错误保留状态码并关闭连接', () async {
    when(() => client.send(any())).thenAnswer(
      (_) async => http.StreamedResponse(const Stream.empty(), 404),
    );
    await expectLater(
      download(),
      throwsA(
        isA<HttpException>()
            .having((e) => e.message, 'status', contains('404')),
      ),
    );
    verify(client.close).called(1);
  });

  test('传输中断不能返回不完整PDF并关闭连接', () async {
    when(() => client.send(any())).thenAnswer(
      (_) async => http.StreamedResponse(
        Stream.error(const HttpException('connection lost')),
        200,
      ),
    );
    await expectLater(download(), throwsA(isA<HttpException>()));
    verify(client.close).called(1);
  });
}
