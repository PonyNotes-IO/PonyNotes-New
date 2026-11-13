import 'package:appflowy/features/agent/application/agent_model_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('keeps every level, exposes a label for each and defaults to medium',
      () async {
    expect(AgentModelPreferences.levels, [
      'off',
      'minimal',
      'low',
      'medium',
      'high',
      'xhigh',
      'max',
    ]);
    expect(
      AgentModelPreferences.labels.length,
      AgentModelPreferences.levels.length,
    );
    expect(AgentModelPreferences.defaultLevel, 'medium');
    expect(await AgentModelPreferences.loadThinking(), 'medium');
  });

  test('stores the new extreme levels', () async {
    await AgentModelPreferences.saveThinking('xhigh');
    expect(await AgentModelPreferences.loadThinking(), 'xhigh');

    await AgentModelPreferences.saveThinking('max');
    expect(await AgentModelPreferences.loadThinking(), 'max');
  });

  test('rejects unknown levels and ignores a corrupt stored value', () async {
    expect(
      () => AgentModelPreferences.saveThinking('unlimited'),
      throwsArgumentError,
    );

    SharedPreferences.setMockInitialValues({
      'ponynotes.agent.thinking': 'unlimited',
    });
    expect(await AgentModelPreferences.loadThinking(), 'medium');
  });
}
