import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/import_page/processor/aliyun_doc_parse_processor.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<KeyValueStorage>(DartKeyValue());
  });

  tearDown(() => getIt.reset());

  test('debug environment routes API, auth and web links to the IP server',
      () async {
    final environment = await AppFlowyCloudSharedEnv.fromEnv();
    final config = environment.appflowyCloudConfig;
    expect(config.base_url, 'http://47.94.42.183');
    final websocket = Uri.parse(config.ws_base_url);
    expect(websocket.scheme, 'ws');
    expect(websocket.host, '47.94.42.183');
    expect(websocket.port, 80);
    expect(websocket.path, '/ws/v1');
    expect(config.gotrue_url, 'http://47.94.42.183/gotrue');
    expect(config.base_web_domain, 'http://47.94.42.183');
    expect(AliyunDocParseProcessor.apiBaseUrl, 'http://47.94.42.183');
    expect(config.isValid, isTrue);
  });
}
