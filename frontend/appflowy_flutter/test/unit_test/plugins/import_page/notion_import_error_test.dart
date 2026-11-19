import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_import_notion.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Notion import explains both forms of the workspace limit error', () {
    final legacy = FlowyError(
      code: ErrorCode.Internal,
      msg:
          'Workspace limit reached (Limit: 2). Please upgrade your subscription. '
          'request_id: Some("example")',
    );
    final typed = FlowyError(code: ErrorCode.WorkspaceLimitExceeded);
    final storage = FlowyError(
      code: ErrorCode.PlanLimitExceeded,
      msg: 'Storage limit exceeded',
    );

    expect(notionImportErrorMessage(legacy, languageCode: 'zh'),
        contains('客户端和服务端均支持导入到当前工作区的私有空间'));
    expect(notionImportErrorMessage(typed, languageCode: 'en'),
        contains('both the app and the server'));
    expect(notionImportErrorMessage(storage, languageCode: 'zh'), storage.msg);
  });
}
