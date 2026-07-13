import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DocumentPage does not render a second shared sidebar toggle', () {
    final source = File('lib/plugins/document/document_page.dart').readAsStringSync();

    expect(source, isNot(contains('shouldShowSidebarExpandButton')));
  });
}
