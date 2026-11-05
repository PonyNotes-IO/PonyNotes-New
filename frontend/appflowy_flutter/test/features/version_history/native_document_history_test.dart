import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sdk = FlowySDK();
  late Directory data;

  setUpAll(() async {
    Log.shared.disableLog = true;
    data = Directory.systemTemp.createTempSync('ponynotes-history-dispatch-');
    await sdk.init(
      jsonEncode(
        AppFlowyConfiguration(
          root: data.path,
          app_version: '1.0.0',
          custom_app_path: data.path,
          origin_app_path: data.path,
          device_id: 'history-dispatch-test',
          platform: Platform.operatingSystem,
          authenticator_type: AuthTypePB.Local.value,
          appflowy_cloud_config: AppFlowyCloudConfiguration.defaultConfig(),
          envs: {},
        ).toJson(),
      ),
    );
  });

  tearDownAll(() async {
    await sdk.dispose();
    data.deleteSync(recursive: true);
  });

  test('native history events reach handlers and return protobuf errors',
      () async {
    final query = DocumentHistoryQueryPB(documentId: 'invalid-document-id');
    // Invalid IDs stop inside each real handler before storage or cloud access.
    final results = [
      await DocumentEventListDocumentVersions(query).send(),
      await DocumentEventGetDocumentVersion(query).send(),
      await DocumentEventSaveDocumentVersion(query).send(),
      await DocumentEventRestoreDocumentVersion(query).send(),
    ];
    for (final result in results) {
      result.fold(
        (_) => fail('Invalid document ID must be rejected'),
        (error) => expect(error.code, ErrorCode.InvalidParams),
      );
    }
  });
}
