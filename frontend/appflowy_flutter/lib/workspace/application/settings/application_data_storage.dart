import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/shared/patterns/common_patterns.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;

import '../../../startup/tasks/prelude.dart';

const appFlowyDataFolder = "AppFlowyDataDoNotRename";

class ApplicationDataStorage {
  ApplicationDataStorage();

  static Object? lastMigrationError;

  String? _cachePath;

  /// Set the custom path to store the data.
  /// If the path is not exists, the path will be created.
  /// If the path is invalid, the path will be set to the default path.
  Future<void> setCustomPath(String path) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      Log.info('LocalFileStorage is not supported on this platform.');
      return;
    }

    if (Platform.isMacOS) {
      // remove the prefix `/Volumes/*`
      path = path.replaceFirst(macOSVolumesRegex, '');
    } else if (Platform.isWindows) {
      path = path.replaceAll('/', '\\');
    }

    // If the path is not ends with `AppFlowyData`, we will append the
    // `AppFlowyData` to the path. If the path is ends with `AppFlowyData`,
    // which means the path is the custom path.
    if (p.basename(path) != appFlowyDataFolder) {
      path = p.join(path, appFlowyDataFolder);
    }

    // create the directory if not exists.
    final directory = Directory(path);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    await setPath(path);
  }

  /// Schedules the current data directory to be migrated after the running
  /// backend has been disposed. The migration is applied by [InitRustSDKTask]
  /// before the backend is initialized again.
  Future<String> scheduleCustomPathMigration({
    required String path,
    required String activeDataPath,
  }) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      throw UnsupportedError(
        'Custom local data directories are not supported on this platform.',
      );
    }
    final destinationRoot = _normalizeCustomPath(path);
    return schedulePathMigration(
      destinationRoot: destinationRoot,
      activeDataPath: activeDataPath,
    );
  }

  Future<String> schedulePathMigration({
    required String destinationRoot,
    required String activeDataPath,
  }) async {
    destinationRoot = p.normalize(p.absolute(destinationRoot));
    final currentRoot = await getPath();
    final defaultRoot = (await appFlowyApplicationDataDirectory()).path;
    final suffix = _storageSuffix(
      activeDataPath: activeDataPath,
      currentRoot: currentRoot,
      defaultRoot: defaultRoot,
    );
    final destinationDataPath = '$destinationRoot$suffix';

    final source = p.normalize(p.absolute(activeDataPath));
    final destination = p.normalize(p.absolute(destinationDataPath));
    if (!Directory(source).existsSync()) {
      throw FileSystemException(
        'The current data directory does not exist.',
        source,
      );
    }
    if (p.equals(source, destination)) {
      await setPath(destinationRoot);
      await getIt<KeyValueStorage>().remove(KVKeys.pendingDataMigration);
      return destinationRoot;
    }
    if (p.isWithin(source, destination) || p.isWithin(destination, source)) {
      throw ArgumentError(
        'The new data directory must not be inside the current directory.',
      );
    }
    final destinationDirectory = Directory(destination);
    if (destinationDirectory.existsSync() &&
        destinationDirectory.listSync(followLinks: false).isNotEmpty) {
      throw FileSystemException(
        'The destination data directory is not empty.',
        destination,
      );
    }

    await getIt<KeyValueStorage>().set(
      KVKeys.pendingDataMigration,
      jsonEncode({
        'source': source,
        'destination': destination,
        'destination_root': destinationRoot,
      }),
    );
    return destinationRoot;
  }

  /// Returns the configured root that actually owns [activeDataPath].
  ///
  /// The preference can contain a destination from an interrupted migration,
  /// so the running backend path remains the source of truth.
  Future<String> resolveActiveRoot(String activeDataPath) async {
    final configuredRoot = p.normalize(p.absolute(await getPath()));
    final defaultRoot = p
        .normalize(p.absolute((await appFlowyApplicationDataDirectory()).path));
    final activePath = p.normalize(p.absolute(activeDataPath));

    for (final root in [configuredRoot, defaultRoot]) {
      if (_isRootOf(activePath: activePath, root: root)) {
        return root;
      }
    }
    return activePath;
  }

  /// Applies a scheduled migration while the backend is stopped.
  ///
  /// Data is copied into a temporary sibling directory first and renamed only
  /// after every entry has been copied. The source is intentionally retained as
  /// a recovery copy.
  Future<void> applyPendingDataMigration() async {
    final value =
        await getIt<KeyValueStorage>().get(KVKeys.pendingDataMigration);
    if (value == null) {
      return;
    }

    final migration = jsonDecode(value) as Map<String, dynamic>;
    final source = Directory(migration['source'] as String);
    final destination = Directory(migration['destination'] as String);
    final destinationRoot = migration['destination_root'] as String;

    if (!source.existsSync()) {
      throw FileSystemException(
        'The current data directory does not exist.',
        source.path,
      );
    }
    if (destination.existsSync() &&
        destination.listSync(followLinks: false).isNotEmpty) {
      throw FileSystemException(
        'The destination data directory is not empty.',
        destination.path,
      );
    }

    final temporary = Directory(
      '${destination.path}.migration-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await _copyDirectory(source, temporary);
      await destination.parent.create(recursive: true);
      if (destination.existsSync()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
      await Directory(destinationRoot).create(recursive: true);
      await setPath(destinationRoot);
      await getIt<KeyValueStorage>().remove(KVKeys.pendingDataMigration);
    } catch (_) {
      if (temporary.existsSync()) {
        await temporary.delete(recursive: true);
      }
      rethrow;
    }
  }

  String _normalizeCustomPath(String path) {
    if (Platform.isMacOS) {
      path = path.replaceFirst(macOSVolumesRegex, '');
    } else if (Platform.isWindows) {
      path = path.replaceAll('/', '\\');
    }
    if (p.basename(path) != appFlowyDataFolder) {
      path = p.join(path, appFlowyDataFolder);
    }
    return p.normalize(p.absolute(path));
  }

  String _storageSuffix({
    required String activeDataPath,
    required String currentRoot,
    required String defaultRoot,
  }) {
    for (final root in [currentRoot, defaultRoot]) {
      final normalizedRoot = p.normalize(p.absolute(root));
      final normalizedActivePath = p.normalize(p.absolute(activeDataPath));
      if (p.equals(normalizedActivePath, normalizedRoot)) {
        return '';
      }
      // Cloud environments append "_<host>" to the configured root. This is
      // intentionally a sibling path rather than a child directory.
      if (_pathStartsWith(normalizedActivePath, '${normalizedRoot}_')) {
        return normalizedActivePath.substring(normalizedRoot.length);
      }
    }
    throw StateError(
      'Unable to relate the active data directory to its configured root.',
    );
  }

  bool _isRootOf({
    required String activePath,
    required String root,
  }) =>
      p.equals(activePath, root) || _pathStartsWith(activePath, '${root}_');

  bool _pathStartsWith(String path, String prefix) {
    if (Platform.isWindows) {
      return path.toLowerCase().startsWith(prefix.toLowerCase());
    }
    return path.startsWith(prefix);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Link) {
        await Link(targetPath).create(await entity.target());
      }
    }
  }

  Future<void> setPath(String path) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      Log.info('LocalFileStorage is not supported on this platform.');
      return;
    }

    final storage = getIt<KeyValueStorage>();
    await storage.set(KVKeys.pathLocation, path);
    final persistedPath = await storage.get(KVKeys.pathLocation);
    if (persistedPath == null || !p.equals(persistedPath, path)) {
      throw FileSystemException(
        'Unable to persist the new data directory.',
        path,
      );
    }
    // clear the cache path, and not set the cache path to the new path because the set path may be invalid
    _cachePath = null;
  }

  Future<String> getPath() async {
    if (_cachePath != null) {
      return _cachePath!;
    }

    try {
      final response = await getIt<KeyValueStorage>().get(KVKeys.pathLocation);

      String path;
      if (response == null) {
        try {
          final directory = await appFlowyApplicationDataDirectory();
          path = directory.path;
        } catch (e) {
          Log.error('Failed to get application data directory: $e');
          // 使用默认路径
          path = './data';
        }
      } else {
        path = response;
      }
      _cachePath = path;

      // If the configured path no longer exists, clear only that setting.
      try {
        if (!Directory(path).existsSync()) {
          await getIt<KeyValueStorage>().remove(KVKeys.pathLocation);
          try {
            final directory = await appFlowyApplicationDataDirectory();
            path = directory.path;
          } catch (e) {
            Log.error('Failed to get application data directory: $e');
            // 使用默认路径
            path = './data';
          }
        }
      } catch (e) {
        Log.error('Failed to check directory existence: $e');
        // 继续使用当前路径
      }

      return path;
    } catch (e) {
      Log.error('Failed to get application data path: $e');
      // 使用默认路径
      return './data';
    }
  }
}

class MockApplicationDataStorage extends ApplicationDataStorage {
  MockApplicationDataStorage();

  // this value will be clear after setup
  // only for the initial step
  @visibleForTesting
  static String? initialPath;

  @override
  Future<String> getPath() async {
    final path = initialPath;
    if (path != null) {
      initialPath = null;
      await super.setPath(path);
      return Future.value(path);
    }
    return super.getPath();
  }
}
