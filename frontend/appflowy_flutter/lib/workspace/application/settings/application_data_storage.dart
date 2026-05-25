import 'dart:io';

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

  Future<void> setPath(String path) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      Log.info('LocalFileStorage is not supported on this platform.');
      return;
    }

    await getIt<KeyValueStorage>().set(KVKeys.pathLocation, path);
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

      // if the path is not exists means the path is invalid, so we should clear the kv store
      try {
        if (!Directory(path).existsSync()) {
          await getIt<KeyValueStorage>().clear();
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
