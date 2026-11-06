import 'package:appflowy/features/agent/application/agent_settings.dart';
import 'package:appflowy/features/agent/presentation/agent_settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../widget_test/widget_test_wrapper.dart';

void main() {
  testWidgets(
      'global settings no longer pick directories; those belong to each document',
      (tester) async {
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: AgentSettingsDialog(
          settings: AgentSettings(
            scope: 'test',
            remoteUrl: 'wss://executor.example/agent',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('允许访问远端任务目录'), findsNothing);
    expect(find.text('允许请求执行命令'), findsNothing);
    expect(find.byTooltip('选择目录'), findsNothing);
    expect(find.textContaining('工作目录和权限模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
