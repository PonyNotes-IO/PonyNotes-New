import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/mcp/application/mcp_audit_log.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_server_service.dart';
import 'package:appflowy/features/mcp/presentation/mcp_settings_view.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await McpAuditLog.instance.clear();
    await McpServerService.instance.restore();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    double width = 620,
    bool dark = false,
    double textScale = 1,
    bool guide = true,
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
    if (guide) {
      await tester.tap(find.text('查看完整设置指南'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('recent client opens live details and preserves unknown history',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'mcp_clients': jsonEncode([
        McpClientConnection(
          name: 'status-test-client',
          firstConnectedAt: DateTime(2026, 10, 23, 14, 18, 30),
          lastUsedAt: DateTime(2026, 10, 26, 10, 20, 15),
        ).toJson(),
      ]),
      'mcp_audit_log': jsonEncode([
        McpAuditEntry(
          at: DateTime(2026, 10, 22),
          tool: 'get_context',
          agent: 'legacy-client',
          target: '',
          isError: false,
          durationMs: 1,
        ).toJson(),
      ]),
    });
    await McpServerService.instance.restore();
    await pumpSettings(tester, width: 320, dark: true, textScale: 1.3);
    await tester.tap(find.text('status-test-client'));
    await tester.pumpAndSettle();
    expect(find.text('连接状态'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('首次连接时间'), findsOneWidget);
    expect(find.text('2026/10/23 14:18:30'), findsOneWidget);
    expect(find.text('上次使用时间'), findsOneWidget);
    expect(find.text('2026/10/26 10:20:15'), findsOneWidget);
    McpAuditLog.instance.record(
      McpAuditEntry(
        at: DateTime(2026, 10, 26, 11, 30, 45),
        tool: 'get_context',
        agent: 'status-test-client',
        target: '',
        isError: false,
        durationMs: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026/10/26 11:30:45'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('legacy-client'));
    await tester.pumpAndSettle();
    expect(find.text('未知（历史记录未保存）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(find.text('连接 Codex'), findsNothing);
    expect(find.text('MCP 完整设置指南'), findsOneWidget);
    final disconnect = find.widgetWithText(TextButton, '断开所有连接');
    await tester.ensureVisible(disconnect);
    expect(tester.widget<TextButton>(disconnect).onPressed, isNull);
    final buttonRect = tester.getRect(disconnect);
    final descriptionRect = tester.getRect(find.text('解除所有与小马笔记 MCP 的连接'));
    expect(buttonRect.overlaps(descriptionRect), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled MCP hides permissions and connection credentials',
      (tester) async {
    await pumpSettings(tester, guide: false);
    expect(find.text('MCP服务器配置'), findsOneWidget);
    expect(find.text('启用MCP服务器'), findsOneWidget);
    expect(find.text('权限控制'), findsNothing);
    expect(find.byTooltip('复制 MCP 配置'), findsNothing);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'enabled presets control tools; copy includes the real credential',
      (tester) async {
    final service = McpServerService.instance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'mcp_token_hash',
      McpServerService.hashToken('ui-test-token'),
    );
    await prefs.setString('mcp_token_plain', 'ui-test-token');
    await prefs.setString('mcp_token_created_at', '2026-10-31T16:44:00');
    await service.restore();
    await tester.runAsync(
      () => IOOverrides.runWithIOOverrides(
        service.start,
        _EphemeralMcpPort(),
      ),
    );
    expect(service.isRunning, isTrue);
    addTearDown(() async => service.shutdown());
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpSettings(tester, width: 960, guide: false);
    expect(find.text('权限控制'), findsOneWidget);
    expect(find.text('创建时间：2026/10/31 16:44'), findsOneWidget);
    expect(find.text('最后使用：—'), findsOneWidget);
    await tester.tap(find.text('只读模式'));
    await tester.pumpAndSettle();
    expect(McpPermissions.instance.isAllowed('get_page'), isTrue);
    expect(McpPermissions.instance.isAllowed('update_block'), isFalse);
    await tester.tap(find.text('安全编辑'));
    await tester.pumpAndSettle();
    expect(McpPermissions.instance.isAllowed('update_block'), isTrue);
    expect(McpPermissions.instance.isAllowed('delete_page'), isFalse);
    await tester.tap(find.text('完全控制'));
    await tester.pumpAndSettle();
    expect(McpPermissions.instance.disabledTools, isEmpty);
    await tester.tap(find.byTooltip('复制 MCP 配置'));
    await tester.pumpAndSettle();
    final config = jsonDecode(copied!) as Map<String, dynamic>;
    expect(config['mcpServers']['ponynotes']['url'], service.endpoint);
    expect(
      config['mcpServers']['ponynotes']['headers']['Authorization'],
      'Bearer ui-test-token',
    );
    expect(find.textContaining('ui-test-token'), findsNothing);

    // 在比默认设置内容区更窄的 396px 下，三个权限档位仍需并排。
    await pumpSettings(tester, width: 396, guide: false);
    final presetButtons = ['只读模式', '安全编辑', '完全控制']
        .map(
          (label) => find.widgetWithText(TextButton, label),
        )
        .toList();
    final rowTop = tester.getTopLeft(presetButtons.first).dy;
    for (final button in presetButtons) {
      expect(tester.getTopLeft(button).dy, rowTop);
      expect(
        tester.getSize(button).height,
        tester.getSize(presetButtons.first).height,
      );
      expect(tester.getTopLeft(button).dx, greaterThanOrEqualTo(0));
      expect(tester.getBottomRight(button).dx, lessThanOrEqualTo(396));
    }
    await tester.tap(presetButtons[0]);
    await tester.pumpAndSettle();
    expect(McpPermissions.instance.isAllowed('update_block'), isFalse);
    expect(tester.takeException(), isNull);
    await pumpSettings(
      tester,
      width: 320,
      dark: true,
      textScale: 1.3,
      guide: false,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(TextButton, '安全编辑')).dy,
      greaterThan(
        tester.getTopLeft(find.widgetWithText(TextButton, '只读模式')).dy,
      ),
    );
    await tester.ensureVisible(find.text('安全编辑'));
    await tester.tap(find.text('安全编辑'));
    await tester.pumpAndSettle();
    expect(McpPermissions.instance.isAllowed('delete_page'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(CupertinoSwitch));
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(service.isRunning, isFalse);
    expect(find.text('权限控制'), findsNothing);
    expect(service.token, 'ui-test-token');
    await tester.pumpWidget(const SizedBox());
  });
}

// UI tests only need a running service; leave the desktop client's port alone.
class _EphemeralMcpPort extends IOOverrides {
  @override
  Future<ServerSocket> serverSocketBind(
    dynamic address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) =>
      super.serverSocketBind(
        address,
        0,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      );
}
