import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/rust_sdk.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MemoryKeyValueStorage implements KeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

void main() {
  late Directory sandbox;
  late _MemoryKeyValueStorage keyValueStorage;

  setUp(() async {
    await getIt.reset();
    sandbox = await Directory.systemTemp.createTemp('data-migration-test-');
    keyValueStorage = _MemoryKeyValueStorage();
    getIt.registerFactory<KeyValueStorage>(() => keyValueStorage);
  });

  tearDown(() async {
    await getIt.reset();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('copies all data and switches the configured root', () async {
    final source = Directory(p.join(sandbox.path, 'source'));
    final destination = Directory(p.join(sandbox.path, 'target', 'storage'));
    final destinationRoot = p.join(sandbox.path, 'target', 'root');
    await Directory(p.join(source.path, 'nested')).create(recursive: true);
    await File(p.join(source.path, 'account.db')).writeAsString('database');
    await File(
      p.join(source.path, 'nested', 'document.bin'),
    ).writeAsString('document');
    await keyValueStorage.set(KVKeys.pathLocation, source.path);
    await keyValueStorage.set(
      KVKeys.pendingDataMigration,
      jsonEncode({
        'source': source.path,
        'destination': destination.path,
        'destination_root': destinationRoot,
      }),
    );

    await ApplicationDataStorage().applyPendingDataMigration();

    expect(
      File(p.join(destination.path, 'account.db')).readAsStringSync(),
      'database',
    );
    expect(
      File(
        p.join(destination.path, 'nested', 'document.bin'),
      ).readAsStringSync(),
      'document',
    );
    expect(source.existsSync(), isTrue);
    expect(Directory(destinationRoot).existsSync(), isTrue);
    expect(
      await keyValueStorage.get(KVKeys.pathLocation),
      destinationRoot,
    );
    expect(
      await keyValueStorage.get(KVKeys.pendingDataMigration),
      isNull,
    );
  });

  test('preserves the active cloud storage suffix at the new root', () async {
    final currentRoot = Directory(p.join(sandbox.path, 'current-root'));
    final activeCloudStorage = Directory('${currentRoot.path}_cloud');
    final selectedDirectory = p.join(sandbox.path, 'selected');
    await currentRoot.create();
    await activeCloudStorage.create();
    await keyValueStorage.set(KVKeys.pathLocation, currentRoot.path);

    final destinationRoot =
        await ApplicationDataStorage().scheduleCustomPathMigration(
      path: selectedDirectory,
      activeDataPath: activeCloudStorage.path,
    );
    final migration = jsonDecode(
      (await keyValueStorage.get(KVKeys.pendingDataMigration))!,
    ) as Map<String, dynamic>;

    expect(p.basename(destinationRoot), appFlowyDataFolder);
    expect(migration['destination'], '${p.absolute(destinationRoot)}_cloud');
  });

  test('uses the running backend path when the configured root is stale',
      () async {
    final defaultRoot = await appFlowyApplicationDataDirectory();
    final activeCloudStorage = Directory('${defaultRoot.path}_cloud');
    final staleConfiguredRoot = p.join(sandbox.path, 'stale-root');
    await Directory(staleConfiguredRoot).create(recursive: true);
    await keyValueStorage.set(KVKeys.pathLocation, staleConfiguredRoot);

    final resolvedRoot = await ApplicationDataStorage().resolveActiveRoot(
      activeCloudStorage.path,
    );

    expect(p.equals(resolvedRoot, p.absolute(defaultRoot.path)), isTrue);
  });

  test('does not switch paths when the destination contains data', () async {
    final source = Directory(p.join(sandbox.path, 'source'));
    final destination = Directory(p.join(sandbox.path, 'target'));
    final originalRoot = p.join(sandbox.path, 'original-root');
    await source.create();
    await destination.create();
    await File(p.join(source.path, 'source.db')).writeAsString('source');
    await File(p.join(destination.path, 'existing.db'))
        .writeAsString('existing');
    await keyValueStorage.set(KVKeys.pathLocation, originalRoot);
    await keyValueStorage.set(
      KVKeys.pendingDataMigration,
      jsonEncode({
        'source': source.path,
        'destination': destination.path,
        'destination_root': p.join(sandbox.path, 'new-root'),
      }),
    );

    await expectLater(
      ApplicationDataStorage().applyPendingDataMigration(),
      throwsA(isA<FileSystemException>()),
    );

    expect(await keyValueStorage.get(KVKeys.pathLocation), originalRoot);
    expect(
      await keyValueStorage.get(KVKeys.pendingDataMigration),
      isNotNull,
    );
    expect(
      File(p.join(destination.path, 'existing.db')).readAsStringSync(),
      'existing',
    );
  });
}
