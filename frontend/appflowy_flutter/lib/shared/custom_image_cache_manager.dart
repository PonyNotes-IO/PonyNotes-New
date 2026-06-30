import 'dart:typed_data';

import 'package:appflowy/shared/appflowy_cache_manager.dart';
import 'package:appflowy/startup/tasks/prelude.dart';
import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

class CustomImageCacheManager extends CacheManager implements ICache {

  CustomImageCacheManager._()
      : super(
          Config(
            key,
            fileSystem: _LazyFileSystem(key),
            maxNrOfCacheObjects: _maxCacheObjects,
            stalePeriod: _cacheMaxAge,
          ),
        );

  factory CustomImageCacheManager() => instance;
  static CustomImageCacheManager? _instance;

  static const key = 'image_cache';

  static const _maxCacheObjects = 200;
  static const _cacheMaxAge = Duration(days: 7);

  static CustomImageCacheManager get instance {
    _instance ??= CustomImageCacheManager._();
    return _instance!;
  }

  @override
  Future<int> cacheSize() async {
    try {
      final directory = await appFlowyApplicationDataDirectory();
      final path = p.join(directory.path, key);
      const fs = LocalFileSystem();
      final dir = fs.directory(path);
      if (await dir.exists()) {
        int totalSize = 0;
        await for (final entity in dir.list()) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
        return totalSize;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> clearAll() async {
    await emptyCache();
  }
}

class _LazyFileSystem implements FileSystem {
  _LazyFileSystem(this._cacheKey);
  final String _cacheKey;
  FileSystem? _delegate;

  Future<FileSystem> _getDelegate() async {
    if (_delegate == null) {
      final baseDir = await appFlowyApplicationDataDirectory();
      final path = p.join(baseDir.path, _cacheKey);

      const fs = LocalFileSystem();
      final directory = fs.directory(path);
      await directory.create(recursive: true);
      _delegate = _RealFileSystem(directory);
    }
    return _delegate!;
  }

  @override
  Future<File> createFile(String name) async {
    final delegate = await _getDelegate();
    return delegate.createFile(name);
  }
}

class _RealFileSystem implements FileSystem {
  _RealFileSystem(this._directory);
  final Directory _directory;

  @override
  Future<File> createFile(String name) async {
    if (!(await _directory.exists())) {
      await _directory.create(recursive: true);
    }
    return _directory.childFile(name);
  }
}