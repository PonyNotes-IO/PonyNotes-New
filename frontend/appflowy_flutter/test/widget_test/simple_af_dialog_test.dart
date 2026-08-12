import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dialog actions do not pop the nested navigator',
      (tester) async {
    final nestedNavigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: MaterialApp(
          home: Navigator(
            key: nestedNavigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showSimpleAFDialog(
                    context: context,
                    title: '功能受限',
                    content: '云同步功能需要登录后开通会员可用。',
                    primaryAction: ('我知道了', null),
                  ),
                  child: const Text('打开弹窗'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AFGhostButton));
    await tester.pumpAndSettle();

    expect(find.text('功能受限'), findsNothing);
    expect(find.text('打开弹窗'), findsOneWidget);
    expect(nestedNavigatorKey.currentState!.canPop(), isFalse);

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    expect(find.text('功能受限'), findsNothing);
    expect(find.text('打开弹窗'), findsOneWidget);
    expect(nestedNavigatorKey.currentState!.canPop(), isFalse);
  });
}
