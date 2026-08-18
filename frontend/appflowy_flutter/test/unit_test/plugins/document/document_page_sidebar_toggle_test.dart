import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DocumentPage does not render a second shared sidebar toggle', () {
    final source =
        File('lib/plugins/document/document_page.dart').readAsStringSync();

    expect(source, isNot(contains('shouldShowSidebarExpandButton')));
  });

  test('DocumentPage hides the mobile private-space share action', () {
    final source =
        File('lib/plugins/document/document_page.dart').readAsStringSync();

    expect(source, contains('_buildDocumentShareAction()'));
    expect(source, contains('_isDocumentInPrivateSpace()'));
    expect(source, contains('future: _isPrivateSpace'));
    expect(source, contains('snapshot.data == true'));
    expect(source.split('ShareButton('), hasLength(2));
  });
}
