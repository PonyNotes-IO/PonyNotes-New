import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('移动端白板顶部不显示分享按钮', () {
    final source = File(
      'lib/mobile/presentation/base/mobile_view_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_MobileWhiteboardShareButton')));
    expect(source, isNot(contains('whiteboard_share_')));
    expect(
      source,
      contains('if (view.layout != ViewLayoutPB.Whiteboard &&'),
    );
    expect(source, contains('view.layout != ViewLayoutPB.Board)'));
  });

  test('移动端看板顶部不显示分享按钮', () {
    final source = File(
      'lib/mobile/presentation/base/mobile_view_page.dart',
    ).readAsStringSync();

    expect(source, contains('view.layout != ViewLayoutPB.Board)'));
  });
}
