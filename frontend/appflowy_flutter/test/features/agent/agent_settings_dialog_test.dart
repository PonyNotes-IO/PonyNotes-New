import 'package:appflowy/features/agent/application/agent_settings.dart';
import 'package:appflowy/features/agent/presentation/agent_settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../widget_test/widget_test_wrapper.dart';

void main() {
  testWidgets(
      'remote file authorization names the remote task directory instead of selecting phone paths',
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
    expect(find.text('允许访问远端任务目录'), findsOneWidget);
    expect(find.byTooltip('选择目录'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
