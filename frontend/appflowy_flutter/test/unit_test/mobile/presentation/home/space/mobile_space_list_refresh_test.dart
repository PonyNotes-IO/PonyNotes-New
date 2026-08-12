import 'package:appflowy/mobile/presentation/home/space/mobile_space_list_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android keeps the loaded document sequence while switching documents',
      () {
    expect(
      mobileSpaceKeepsDocumentListCached(isAndroid: true),
      isTrue,
    );
  });

  test('non-Android clients keep the existing refresh behavior', () {
    expect(
      mobileSpaceKeepsDocumentListCached(isAndroid: false),
      isFalse,
    );
  });
}
