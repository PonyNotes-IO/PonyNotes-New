import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Log.shared.disableLog = true;
  final permissions = McpPermissions.instance;
  final tools = McpTools(endpoint: '', version: '', isAgentChannel: true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await permissions.load();
  });

  for (final preset in McpPermissionPreset.values) {
    test('$preset persists and blocks every excluded tool before execution',
        () async {
      await permissions.applyPreset(preset, tools.toolSpecs);
      await permissions.load();
      expect(permissions.presetFor(tools.toolSpecs), preset);
      for (final spec in tools.toolSpecs) {
        final allowed = switch (preset) {
          McpPermissionPreset.readOnly => spec.readOnly,
          McpPermissionPreset.safeEdit => !spec.destructive,
          McpPermissionPreset.fullControl => true,
        };
        expect(permissions.isAllowed(spec.name), allowed, reason: spec.name);
        if (!allowed) {
          final result = await tools.executeTool(spec.name, {});
          expect(result.isError, isTrue, reason: spec.name);
          expect(
            result.content.first.toJson()['text'],
            contains('permission_denied'),
          );
        }
      }
    });
  }

  test('manual exclusions are not displayed as an inaccurate preset', () async {
    await permissions.setAllowed('get_context', false);
    expect(permissions.presetFor(tools.toolSpecs), isNull);
  });
}
