import 'package:appflowy/features/ai_internal/application/internal_ai_chat_store.dart';
import 'package:appflowy/features/ai_internal/presentation/ai_chat_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/widget_test_wrapper.dart';

void main() {
  setUp(() => InternalAiChatStore.instance.reset());

  testWidgets('未配置模型时显示提示，输入框与发送按钮可用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WidgetTestWrapper(child: AiChatView()));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有配置模型'), findsOneWidget);
    expect(find.text('内部 AI 对话'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
  });

  testWidgets('已配置时不再显示未配置提示', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_internal.base_url': 'https://api.example.com',
      'ai_internal.model': 'gpt-4o-mini',
      'ai_internal.api_key': 'sk-test',
    });
    await tester.pumpWidget(const WidgetTestWrapper(child: AiChatView()));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有配置模型'), findsNothing);
    expect(find.textContaining('可以试试'), findsOneWidget);
  });
}
