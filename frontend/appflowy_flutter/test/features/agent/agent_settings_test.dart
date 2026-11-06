import 'package:appflowy/features/agent/application/agent_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'execution credentials and tool grants belong to the account/workspace scope',
      () async {
    await AgentSettings(
      scope: 'account-one-workspace',
      remoteUrl: 'wss://executor.example/agent',
      remoteToken: 'secret',
      disabledNoteTools: ['write'],
    ).save();
    expect(
      (await AgentSettings.load(scope: 'account-one-workspace')).remoteToken,
      'secret',
    );
    expect(
      (await AgentSettings.load(scope: 'account-one-workspace'))
          .disabledNoteTools,
      ['write'],
    );
    expect(
      (await AgentSettings.load(scope: 'account-two-workspace')).remoteToken,
      isEmpty,
    );
  });

  test('working directory and permission mode are stored per Agent document',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect((await AgentWorkspaceConfig.load('doc-a')).directory, isEmpty);
    expect((await AgentWorkspaceConfig.load('doc-a')).permissionMode, 'ask');
    await const AgentWorkspaceConfig(
      directory: 'D:/project',
      permissionMode: 'auto',
    ).save('doc-a');
    final a = await AgentWorkspaceConfig.load('doc-a');
    expect(a.directory, 'D:/project');
    expect(a.permissionMode, 'auto');
    expect((await AgentWorkspaceConfig.load('doc-b')).directory, isEmpty);
    expect(
      () => const AgentWorkspaceConfig(permissionMode: 'root').save('doc-a'),
      throwsArgumentError,
    );
  });
}
