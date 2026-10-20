import 'dart:async';
import 'dart:io';

/// Serialize commits to one file; a failed or interrupted write keeps the last copy.
class HandwritingFileStore {
  static final Map<String, Future<void>> _writes = {};
  static int _nextWrite = 0;

  static Future<void> write(String path, List<int> bytes,
      {bool keepBackups = true}) {
    final snapshot = List<int>.of(bytes);
    final previous = _writes[path];
    late final Future<void> task;
    task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // Failure belongs to the previous caller; allow the next commit.
        }
      }
      final file = File(path);
      await file.parent.create(recursive: true);
      final temporary = File('$path.${_nextWrite++}.tmp');
      try {
        await temporary.writeAsBytes(snapshot, flush: true);
        if (keepBackups && await file.exists()) {
          final backup = File('$path.previous.tmp');
          await backup.writeAsBytes(await file.readAsBytes(), flush: true);
          await backup.rename('$path.previous');
          final legacy = File('$path.legacy');
          if (!await legacy.exists()) {
            final original = File('$path.legacy.tmp');
            await original.writeAsBytes(await file.readAsBytes(), flush: true);
            await original.rename(legacy.path);
          }
        }
        await temporary.rename(path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }()
        .whenComplete(() {
      if (identical(_writes[path], task)) _writes.remove(path);
    });
    _writes[path] = task;
    return task;
  }

  static Future<List<int>> read(String path) async {
    await _writes[path];
    final file = File(path);
    if (!await file.exists()) return <int>[];
    return file.readAsBytes();
  }
}
