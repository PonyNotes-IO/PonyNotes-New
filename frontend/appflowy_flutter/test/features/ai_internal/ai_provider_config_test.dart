import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('配置独立存储，读写往返完整', () async {
    SharedPreferences.setMockInitialValues({});
    const storage = AiProviderConfigStorage();

    final empty = await storage.load();
    expect(empty.isComplete, isFalse);

    await storage.save(
      const AiProviderConfig(
        baseUrl: 'https://api.deepseek.com',
        modelName: 'deepseek-chat',
        apiKey: 'sk-test',
      ),
    );

    final loaded = await storage.load();
    expect(loaded.baseUrl, 'https://api.deepseek.com');
    expect(loaded.modelName, 'deepseek-chat');
    expect(loaded.apiKey, 'sk-test');
    expect(loaded.isComplete, isTrue);

    await storage.clear();
    expect((await storage.load()).isComplete, isFalse);
  });

  test('isComplete 要求地址、模型、Key 都非空', () {
    expect(const AiProviderConfig().isComplete, isFalse);
    expect(
      const AiProviderConfig(
        baseUrl: 'https://api.example.com',
        modelName: 'gpt-4o-mini',
      ).isComplete,
      isFalse,
    );
    expect(
      const AiProviderConfig(
        baseUrl: 'https://api.example.com',
        modelName: 'gpt-4o-mini',
        apiKey: 'sk-test',
      ).isComplete,
      isTrue,
    );
  });
}
