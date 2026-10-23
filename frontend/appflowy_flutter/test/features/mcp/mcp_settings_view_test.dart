import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/presentation/mcp_settings_view.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    double width = 620,
    bool dark = false,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppFlowyTheme(
        data: dark
            ? AppFlowyDefaultTheme().dark()
            : AppFlowyDefaultTheme().light(),
        child: MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const Scaffold(body: McpSettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('client discovery, search, setup dialog and address copying',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpSettings(tester);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Codex')).dy,
      tester.getTopLeft(find.text('Claude Desktop')).dy,
    );
    expect(
      tester.getTopLeft(find.text('Codex')).dx,
      lessThan(tester.getTopLeft(find.text('Claude Desktop')).dx),
    );

    await tester.tap(find.byTooltip('复制连接地址'));
    await tester.pumpAndSettle();
    expect(copied, McpServerService.instance.endpoint);

    await tester.tap(find.byTooltip('搜索客户端'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'CURSOR');
    await tester.pumpAndSettle();
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
    await tester.enterText(find.byType(TextField), 'no-such-client');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的客户端，试试其他关键词。'), findsOneWidget);

    await tester.tap(find.byTooltip('收起搜索'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Codex'));
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(find.text('连接 Codex'), findsOneWidget);
    expect(find.text('开启本机服务'), findsOneWidget);
    expect(McpServerService.instance.isRunning, isFalse);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(find.text('连接与权限'));
    await tester.tap(find.text('连接与权限'));
    await tester.pumpAndSettle();
    final disconnect = find.widgetWithText(TextButton, '断开所有连接');
    await tester.ensureVisible(disconnect);
    expect(tester.widget<TextButton>(disconnect).onPressed, isNull);
    expect(
      tester.getTopLeft(disconnect).dx,
      greaterThan(
        tester.getTopLeft(find.text('解除所有与小马笔记 MCP 的连接')).dx,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow dark layout wraps clients and keeps permissions usable',
      (tester) async {
    await pumpSettings(tester, width: 320, dark: true, textScale: 1.3);
    expect(
      tester.getTopLeft(find.text('Codex')).dy,
      lessThan(tester.getTopLeft(find.text('Claude Desktop')).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Codex'));
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(find.text('连接 Codex'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('连接与权限'));
    await tester.tap(find.text('连接与权限'));
    await tester.pumpAndSettle();
    expect(find.text('连接凭证'), findsOneWidget);
    expect(find.text('工具权限'), findsOneWidget);
    final disconnect = find.widgetWithText(TextButton, '断开所有连接');
    await tester.ensureVisible(disconnect);
    expect(
      tester.getTopLeft(disconnect).dy,
      greaterThan(
        tester.getBottomLeft(find.text('解除所有与小马笔记 MCP 的连接')).dy,
      ),
    );
    expect(tester.takeException(), isNull);
    final tool = find.text('get_context');
    await tester.ensureVisible(tool);
    await tester.pumpAndSettle();
    final toggle = find.descendant(
      of: find.ancestor(of: tool, matching: find.byType(Row)).first,
      matching: find.byType(Switch),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(McpPermissions.instance.isAllowed('get_context'), isFalse);
    await McpPermissions.instance.allowAll();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
