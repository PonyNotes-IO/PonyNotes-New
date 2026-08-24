import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('选择移动目标后关闭更多菜单和移动到二级弹层', (tester) async {
    var closeResult = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppFlowyPopover(
              popupBuilder: (_) => SizedBox(
                key: const ValueKey('more-menu'),
                width: 160,
                height: 100,
                child: AppFlowyPopover(
                  popupBuilder: (movePopoverContext) => TextButton(
                    key: const ValueKey('move-target'),
                    onPressed: () {
                      closeResult = closeMovePagePopovers(movePopoverContext);
                    },
                    child: const Text('私有空间目标'),
                  ),
                  child: const SizedBox(
                    key: ValueKey('move-to-button'),
                    width: 100,
                    height: 40,
                    child: Text('移动到'),
                  ),
                ),
              ),
              child: const SizedBox(
                key: ValueKey('more-button'),
                width: 40,
                height: 40,
                child: Text('更多'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('more-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-menu')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('move-to-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-target')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('move-target')));
    await tester.pumpAndSettle();

    expect(closeResult, isTrue);
    expect(find.byKey(const ValueKey('move-target')), findsNothing);
    expect(find.byKey(const ValueKey('more-menu')), findsNothing);
  });
}
