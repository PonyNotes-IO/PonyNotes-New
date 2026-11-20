import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_folder.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private sidebar lists synced root notes alongside spaces', () {
    Localization.load(const Locale('en'), translations: Translations({}));
    final space = ViewPB(id: 'space')..isSpace = true;
    final pendingSpace = ViewPB(id: 'pending')..isSpace = true;
    final syncedNote = ViewPB(id: 'synced', layout: ViewLayoutPB.Document);

    final section = PrivateSectionFolder(
      spaces: [space, pendingSpace],
      privateViews: [space, syncedNote],
    );

    expect(section.views, [space, pendingSpace, syncedNote]);
  });
}
