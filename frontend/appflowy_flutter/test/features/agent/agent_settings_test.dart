import 'package:appflowy/features/agent/application/agent_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
