import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/env/env.dart';
import 'package:appflowy/plugins/import_page/processor/aliyun_doc_parse_processor.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/foundation.dart';
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

  test('build mode selects one backend for Dart, Rust, auth and sync',
      () async {
    final expectedUrl =
        kDebugMode ? 'http://47.94.42.183' : 'https://api.xiaomabiji.com';
    final expectedWebUrl = kDebugMode ? expectedUrl : 'https://xiaomabiji.com';
    expect(Env.afCloudUrl, expectedUrl);
    expect(Env.baseWebDomain, expectedWebUrl);
    expect(Env.authenticatorType, 3);
    expect(await getAppFlowyCloudUrl(), expectedUrl);
    expect(await getAppFlowyShareDomain(), expectedWebUrl);
    expect(
      await getAuthenticatorType(),
      AuthenticatorType.appflowyCloudSelfHost,
    );
    final environment = await AppFlowyCloudSharedEnv.fromEnv();
    expect(
        environment.authenticatorType, AuthenticatorType.appflowyCloudSelfHost);
    final config = environment.appflowyCloudConfig;
    expect(config.base_url, expectedUrl);
    final websocket = Uri.parse(config.ws_base_url);
    final baseUri = Uri.parse(expectedUrl);
    expect(websocket.scheme, baseUri.scheme == 'https' ? 'wss' : 'ws');
    expect(websocket.host, baseUri.host);
    expect(websocket.port, baseUri.port);
    expect(websocket.path, '/ws/v1');
    expect(config.gotrue_url, '$expectedUrl/gotrue');
    expect(config.base_web_domain, expectedWebUrl);
    expect(AliyunDocParseProcessor.apiBaseUrl, expectedWebUrl);
    expect(config.isValid, isTrue);
  });
}
