import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/trash/application/trash_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sdk = FlowySDK();
  late Directory data;
  late String workspaceId;
  late String pageId;
  const resourceTypes = ['sub_page', 'grid', 'board', 'calendar'];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Log.shared.disableLog = true;
    data = Directory.systemTemp.createTempSync('ponynotes-mcp-write-test-');
    await sdk.init(
      jsonEncode(
        AppFlowyConfiguration(
          root: data.path,
          app_version: '1.0.0',
          custom_app_path: data.path,
          origin_app_path: data.path,
          device_id: 'mcp-write-test',
          platform: Platform.operatingSystem,
          authenticator_type: AuthTypePB.Local.value,
          appflowy_cloud_config: AppFlowyCloudConfiguration.defaultConfig(),
          envs: {},
        ).toJson(),
      ),
    );
    await UserEventSignUp(
      SignUpPayloadPB(
        name: 'MCP regression test',
        email: 'mcp-test@localhost',
        password: 'test-password',
        authType: AuthTypePB.Local,
        deviceId: 'mcp-write-test',
      ),
    ).send().getOrThrow();
    UserBackendService.clearCurrentUserProfileCache();
    workspaceId =
        (await FolderEventReadCurrentWorkspace().send().getOrThrow()).id;
  });

  tearDownAll(() async {
    UserBackendService.clearCurrentUserProfileCache();
    await sdk.dispose();
    data.deleteSync(recursive: true);
  });

  setUp(() async {
    pageId = (await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: workspaceId,
      name: 'MCP test page',
      openAfterCreate: false,
    ).getOrThrow())
        .id;
  });

  McpTools tools([DocumentService? service]) => McpTools(
        endpoint: 'test',
        version: 'test',
        documentService: service,
      );
  Future<CallToolResult> insert(
    McpTools registry,
    String type, [
    Map<String, dynamic> extra = const {},
  ]) =>
      registry.executeTool('insert_block', {
        'workspace_id': workspaceId,
        'page_id': pageId,
        'block_type': type,
        'text': 'test resource',
        ...extra,
      });
  Future<Set<String>> children() async =>
      (await ViewBackendService.getChildViews(viewId: pageId).getOrThrow())
          .map((v) => v.id)
          .toSet();
  Map<String, dynamic> body(CallToolResult result) =>
      jsonDecode((result.content.single as TextContent).text)
          as Map<String, dynamic>;

  test('disconnecting rotates persisted credentials while keeping service off',
      () async {
    final service = McpServerService.instance;
    addTearDown(service.revoke);
    final previous = await service.generateToken();
    final current = await service.resetToken();
    expect(current, isNot(previous));
    expect(service.token, current);
    expect(service.isRunning, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mcp_token_plain'), current);
    expect(
      prefs.getString('mcp_token_hash'),
      McpServerService.hashToken(current),
    );
    expect(
      prefs.getString('mcp_token_hash'),
      isNot(McpServerService.hashToken(previous)),
    );
    expect(prefs.getBool('mcp_server_enabled'), isNot(true));
  });

  test('successful inserts confirm backend data for every resource type',
      () async {
    final registry = tools();
    for (final type in resourceTypes) {
      final result = await insert(registry, type);
      expect(result.isError, isFalse, reason: body(result).toString());
      final inserted = body(result);
      final viewId =
          inserted[type == 'sub_page' ? 'sub_page_id' : 'database_view_id']
              as String;
      expect(await children(), contains(viewId));
      final saved = await DocumentService()
          .openDocument(documentId: pageId, workspaceId: workspaceId)
          .getOrThrow();
      expect(saved.blocks.containsKey(inserted['block_id']), isTrue);
      await DocumentService().closeDocument(viewId: pageId).getOrThrow();
    }
  });

  test('invalid insertion locations and locked pages create no resources',
      () async {
    final before = await children();
    for (final type in resourceTypes) {
      for (final key in ['parent_block_id', 'after_block_id']) {
        final result = await insert(tools(), type, {key: 'missing-block'});
        expect(result.isError, isTrue);
        expect(body(result)['error']['code'], 'not_found');
        expect(await children(), before);
      }
    }
    await ViewBackendService.lockView(pageId).getOrThrow();
    for (final type in resourceTypes) {
      final result = await insert(tools(), type);
      expect(body(result)['error']['code'], 'page_locked');
      expect(await children(), before);
    }
  });

  test('rejected writes roll back each newly created resource', () async {
    final before = await children();
    final trashBefore = (await TrashService().readTrash().getOrThrow())
        .items
        .map((t) => t.id)
        .toSet();
    for (final type in resourceTypes) {
      final service = _ControlledDocumentService()..failBlocks = true;
      final result = await insert(tools(service), type);
      expect(result.isError, isTrue);
      expect(body(result)['error']['code'], 'write_failed');
      expect(await children(), before);
      expect(service.closeCalls, greaterThan(0));
    }
    final trashAfter = (await TrashService().readTrash().getOrThrow())
        .items
        .map((t) => t.id)
        .toSet();
    expect(trashAfter.difference(trashBefore).length, resourceTypes.length);
  });

  test('unconfirmed writes retain referenced resources and return recovery IDs',
      () async {
    final service = _ControlledDocumentService()..staleReads = true;
    final result = await insert(tools(service), 'sub_page');
    expect(result.isError, isTrue);
    final error = body(result)['error'];
    expect(error['code'], 'insert_unconfirmed');
    final viewId = error['details']['created_view_id'] as String;
    final blockId = error['details']['block_id'] as String;
    expect(await children(), contains(viewId));
    final saved = await DocumentService()
        .openDocument(documentId: pageId, workspaceId: workspaceId)
        .getOrThrow();
    expect(saved.blocks.containsKey(blockId), isTrue);
    expect(jsonDecode(saved.blocks[blockId]!.data)['view_id'], viewId);
    await DocumentService().closeDocument(viewId: pageId).getOrThrow();
  });

  test('a backend error after saving does not delete the referenced resource',
      () async {
    final service = _ControlledDocumentService()..failAfterWrite = true;
    final result = await insert(tools(service), 'sub_page');
    final error = body(result)['error'];
    expect(result.isError, isTrue);
    expect(error['code'], 'insert_unconfirmed');
    expect(await children(), contains(error['details']['created_view_id']));
    final saved = await DocumentService()
        .openDocument(documentId: pageId, workspaceId: workspaceId)
        .getOrThrow();
    expect(saved.blocks.containsKey(error['details']['block_id']), isTrue);
    await DocumentService().closeDocument(viewId: pageId).getOrThrow();
  });

  test(
      'rollback failure reports the remaining resource instead of claiming cleanup',
      () async {
    final service = _ControlledDocumentService()..failBlocks = true;
    service.beforeWrite = () async {
      final created = (await children()).single;
      await ViewBackendService.lockView(created).getOrThrow();
    };
    final result = await insert(tools(service), 'sub_page');
    final error = body(result)['error'];
    expect(result.isError, isTrue);
    expect(error['code'], 'insert_unconfirmed');
    expect(await children(), contains(error['details']['created_view_id']));
  });

  test('rolling back a linked database view preserves the original database',
      () async {
    final original = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Grid,
      parentViewId: workspaceId,
      name: 'existing database',
      openAfterCreate: false,
    ).getOrThrow();
    final service = _ControlledDocumentService()..failBlocks = true;
    final result =
        await insert(tools(service), 'grid', {'database_id': original.id});
    expect(body(result)['error']['code'], 'write_failed');
    expect(await children(), isEmpty);
    expect(
      (await ViewBackendService.getView(original.id).getOrThrow()).id,
      original.id,
    );
    final trash = (await TrashService().readTrash().getOrThrow()).items;
    expect(trash.any((item) => item.id == original.id), isFalse);
  });
}

class _ControlledDocumentService extends DocumentService {
  bool failBlocks = false;
  bool failAfterWrite = false;
  bool staleReads = false;
  int closeCalls = 0;
  DocumentDataPB? snapshot;
  Future<void> Function()? beforeWrite;

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> openDocument({
    required String documentId,
    String? workspaceId,
  }) async {
    final result = await super
        .openDocument(documentId: documentId, workspaceId: workspaceId);
    snapshot = result.fold((value) => value.deepCopy(), (_) => null);
    return result;
  }

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
    String? workspaceId,
  }) async {
    if (staleReads && snapshot != null) return FlowyResult.success(snapshot!);
    return super.getDocument(documentId: documentId, workspaceId: workspaceId);
  }

  @override
  Future<FlowyResult<void, FlowyError>> applyAction({
    required String documentId,
    required Iterable<BlockActionPB> actions,
  }) async {
    await beforeWrite?.call();
    if (failBlocks) {
      return FlowyResult.failure(FlowyError(msg: 'injected write rejection'));
    }
    final result =
        await super.applyAction(documentId: documentId, actions: actions);
    if (failAfterWrite) {
      return FlowyResult.failure(FlowyError(msg: 'injected error after save'));
    }
    return result;
  }

  @override
  Future<FlowyResult<void, FlowyError>> closeDocument({
    required String viewId,
  }) {
    closeCalls++;
    return super.closeDocument(viewId: viewId);
  }
}
