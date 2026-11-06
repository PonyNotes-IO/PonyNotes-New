import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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
    expect(
        (await SharedPreferences.getInstance())
            .containsKey('ai_internal.api_key'),
        isFalse);

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
  test(
      'existing model credentials migrate without changing the endpoint or model',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_internal.base_url': 'https://existing.example/v1',
      'ai_internal.model': 'existing-model',
      'ai_internal.api_key': 'legacy-key'
    });
    final loaded = await const AiProviderConfigStorage().load();
    expect(loaded.apiKey, 'legacy-key');
    expect(loaded.modelName, 'existing-model');
    expect(loaded.baseUrl, 'https://existing.example/v1');
    expect(
        (await SharedPreferences.getInstance())
            .containsKey('ai_internal.api_key'),
        false);
    expect(await const FlutterSecureStorage().read(key: 'ai_internal.api_key'),
        'legacy-key');
  });
}
