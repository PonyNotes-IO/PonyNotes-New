import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('删除工作区时先关闭确认弹窗再发起删除', () {
    final source = File(
      'lib/mobile/presentation/home/workspaces/workspace_menu_bottom_sheet.dart',
    ).readAsStringSync();
    final deleteMethodStart = source.indexOf('void _deleteWorkspace(');
    final leaveMethodStart = source.indexOf('void _leaveWorkspace(');

    expect(deleteMethodStart, isNonNegative);
    expect(leaveMethodStart, greaterThan(deleteMethodStart));

    final deleteMethod = source.substring(deleteMethodStart, leaveMethodStart);
    final dismissDialog =
        deleteMethod.indexOf('Navigator.of(dialogContext).pop();');
    final dispatchDeletion =
        deleteMethod.indexOf('UserWorkspaceEvent.deleteWorkspace(');

    expect(dismissDialog, isNonNegative);
    expect(dispatchDeletion, greaterThan(dismissDialog));
  });
}
