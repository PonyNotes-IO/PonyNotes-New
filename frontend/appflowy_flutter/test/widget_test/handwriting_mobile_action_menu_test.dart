import 'package:appflowy/plugins/handwriting_saber/presentation/handwriting_export_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile handwriting menu separates export and import actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HandwritingExportAction(
            view: ViewPB()
              ..id = 'handwriting-view'
              ..name = '手写笔记',
            mobile: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.text('导出'), findsOneWidget);
    expect(find.text('导出为 PDF'), findsOneWidget);
    expect(find.text('导出为源文件(.ponynhw)'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('导入源文件(.ponynhw)'), findsOneWidget);
  });
}
