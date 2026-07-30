import 'dart:convert';

import 'package:appflowy/features/share_tab/data/collab_workspace_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('preferred document workspace wins without HTTP', () async {
    var requestCount = 0;
    final resolver = _resolver(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('', 500);
      }),
    );

    final result = await resolver.resolve(
      viewId: 'view-1',
      preferredWorkspaceId: ' workspace-w1 ',
    );

    expect(result.status, CollabWorkspaceResolutionStatus.resolved);
    expect(result.workspaceId, 'workspace-w1');
    expect(result.canProceed, isTrue);
    expect(requestCount, 0);
  });

  test('share-info owner workspace is canonical', () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    final resolver = _resolver(
      client: MockClient((request) async {
        requestedUri = request.url;
        requestedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'data': {'owner_workspace_id': 'workspace-w1'},
          }),
          200,
        );
      }),
    );

    final result = await resolver.resolve(viewId: 'view-1');

    expect(result.status, CollabWorkspaceResolutionStatus.resolved);
    expect(result.workspaceId, 'workspace-w1');
    expect(requestedUri?.path, '/api/collab/share-info');
    expect(requestedUri?.queryParameters, {'view_id': 'view-1'});
    expect(requestedHeaders?['authorization'], 'Bearer token');
  });

  test('404 permits first-share fallback to current workspace', () async {
    final resolver = _resolver(
      client: MockClient((_) async => http.Response('', 404)),
    );

    final result = await resolver.resolve(viewId: 'view-1');

    expect(result.status, CollabWorkspaceResolutionStatus.notShared);
    expect(result.workspaceId, 'workspace-w2');
    expect(result.canProceed, isTrue);
  });

  test('server and network failures fail closed', () async {
    final serverFailure = _resolver(
      client: MockClient((_) async => http.Response('', 500)),
    );
    final networkFailure = _resolver(
      client: MockClient((_) async => throw Exception('offline')),
    );

    final serverResult = await serverFailure.resolve(viewId: 'view-1');
    final networkResult = await networkFailure.resolve(viewId: 'view-2');

    expect(serverResult.status, CollabWorkspaceResolutionStatus.unavailable);
    expect(serverResult.workspaceId, isNull);
    expect(serverResult.canProceed, isFalse);
    expect(networkResult.status, CollabWorkspaceResolutionStatus.unavailable);
    expect(networkResult.workspaceId, isNull);
  });

  test('malformed successful response fails closed', () async {
    final resolver = _resolver(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {'owner_workspace_id': null},
          }),
          200,
        ),
      ),
    );

    final result = await resolver.resolve(viewId: 'view-1');

    expect(result.status, CollabWorkspaceResolutionStatus.unavailable);
    expect(result.canProceed, isFalse);
  });

  test('empty access token fails closed without HTTP', () async {
    var requestCount = 0;
    final resolver = _resolver(
      accessTokenProvider: () async => '',
      client: MockClient((_) async {
        requestCount++;
        return http.Response('', 200);
      }),
    );

    final result = await resolver.resolve(viewId: 'view-1');

    expect(result.status, CollabWorkspaceResolutionStatus.unavailable);
    expect(requestCount, 0);
  });

  test('successful share-info resolution is cached per view', () async {
    var requestCount = 0;
    final resolver = _resolver(
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'data': {'owner_workspace_id': 'workspace-w1'},
          }),
          200,
        );
      }),
    );

    final first = await resolver.resolve(viewId: 'view-1');
    final second = await resolver.resolve(viewId: 'view-1');

    expect(first.workspaceId, 'workspace-w1');
    expect(second.workspaceId, 'workspace-w1');
    expect(requestCount, 1);
  });
}

HttpCollabWorkspaceResolver _resolver({
  required http.Client client,
  Future<String> Function()? accessTokenProvider,
}) =>
    HttpCollabWorkspaceResolver(
      client: client,
      baseUrlProvider: () => 'https://cloud.example.com',
      accessTokenProvider: accessTokenProvider ?? () async => 'token',
      currentWorkspaceIdProvider: () async => 'workspace-w2',
    );
