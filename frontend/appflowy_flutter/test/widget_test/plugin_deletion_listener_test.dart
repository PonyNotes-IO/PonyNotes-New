import 'package:appflowy/plugins/util.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forwards deletion notification with its view and index',
      (tester) async {
    final view = ViewPB.create()..id = 'view-a';
    final notifier = ViewPluginNotifier(view: view);
    ViewPB? deletedView;
    int? deletedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: PluginDeletionListener(
          notifier: notifier,
          onDeleted: (view, index) {
            deletedView = view;
            deletedIndex = index;
          },
          child: const SizedBox(),
        ),
      ),
    );

    notifier.isDeleted.value = DeletedViewPB.create()..index = 2;

    expect(deletedView?.id, view.id);
    expect(deletedIndex, 2);

    await tester.pumpWidget(const SizedBox());
    notifier.dispose();
  });
}
