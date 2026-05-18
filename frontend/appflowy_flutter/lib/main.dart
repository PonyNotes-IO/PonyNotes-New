import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:scaled_app/scaled_app.dart';

import 'startup/startup.dart';

// Stores the initial deep link passed from the native runner.
String? _initialDeepLink;

String get _lockFilePath {
  final appData =
      Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'] ?? '.';
  return '$appData\\PonyNotes\\instance.lock';
}

Future<void> _cleanupLegacyLockFile() async {
  final lockFile = File(_lockFilePath);
  try {
    if (await lockFile.exists()) {
      await lockFile.delete();
      Log.info('Single instance: Deleted legacy Dart lock file');
    }
  } catch (e) {
    Log.error('Single instance: Error deleting legacy Dart lock file: $e');
  }
}

Future<void> main(List<String> args) async {
  if (Platform.isWindows) {
    Log.info('DeepLink: ==== App started with args: $args ====');

    final envUrl = Platform.environment['APP_URI'];
    if (envUrl != null) {
      Log.info('DeepLink: Got URL from environment: $envUrl');
    }

    // Windows single-instance handling already lives in the native runner
    // via PonyNotesMutex and deep_link.txt forwarding. Remove the legacy
    // Dart lock file so stale crash leftovers do not force exit(0).
    await _cleanupLegacyLockFile();
  }

  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );

  if (args.isNotEmpty) {
    final url = args.first;
    if (url.startsWith('ponynotes://')) {
      Log.info('DeepLink: Received initial URL from command line: $url');
      _initialDeepLink = url;
    }
  }

  await runAppFlowy();
}

String? getInitialDeepLink() => _initialDeepLink;
