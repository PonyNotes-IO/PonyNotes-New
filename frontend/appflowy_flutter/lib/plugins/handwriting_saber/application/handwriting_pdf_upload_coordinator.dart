import 'dart:async';

import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy_backend/log.dart';
import 'package:get_it/get_it.dart';

/// Upload boundary used by [HandwritingPdfUploadCoordinator].
///
/// Keeping the backend behind this interface makes the single-flight policy
/// testable without starting the native storage stream in a Flutter test.
abstract interface class HandwritingPdfUploadBackend {
  /// Returns the URL only after the remote upload has actually finished.
  /// Returns null for both enqueue/upload errors and permanent HTTP errors.
  Future<String?> uploadAndWait({
    required String localPdfPath,
    required String parentDir,
  });
}

/// Coalesces concurrent uploads of the same PDF.
///
/// The key deliberately contains the workspace, parent directory and local
/// path. A PDF can be used by several handwriting pages, but it must only be
/// copied, hashed and queued once for a given cloud namespace.
class HandwritingPdfUploadCoordinator {
  HandwritingPdfUploadCoordinator({
    HandwritingPdfUploadBackend? backend,
  }) : _backend = backend ?? const _AppFlowyHandwritingPdfUploadBackend();

  static final shared = HandwritingPdfUploadCoordinator();

  final HandwritingPdfUploadBackend _backend;
  final Map<(String, String, String), Future<String?>> _inFlight = {};

  Future<String?> upload({
    required String workspaceId,
    required String parentDir,
    required String localPdfPath,
  }) {
    final key = (workspaceId, parentDir, localPdfPath);
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final future = _runUpload(
      key: key,
      localPdfPath: localPdfPath,
      parentDir: parentDir,
    );
    _inFlight[key] = future;
    future.then<void>(
      (_) => _removeIfCurrent(key, future),
      onError: (_, __) => _removeIfCurrent(key, future),
    );
    return future;
  }

  Future<String?> _runUpload({
    required (String, String, String) key,
    required String localPdfPath,
    required String parentDir,
  }) async {
    try {
      return await _backend.uploadAndWait(
        localPdfPath: localPdfPath,
        parentDir: parentDir,
      );
    } catch (error, stackTrace) {
      Log.error(
        '[HandwritingPdfUploadCoordinator] upload failed for '
        '${key.$3}: $error\n$stackTrace',
      );
      return null;
    }
  }

  void _removeIfCurrent(
    (String, String, String) key,
    Future<String?> future,
  ) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }
}

class _AppFlowyHandwritingPdfUploadBackend
    implements HandwritingPdfUploadBackend {
  const _AppFlowyHandwritingPdfUploadBackend();

  @override
  Future<String?> uploadAndWait({
    required String localPdfPath,
    required String parentDir,
  }) async {
    final result = await DocumentService().uploadFile(
      localFilePath: localPdfPath,
      documentId: parentDir,
    );
    final url = result.fold<String?>(
      (uploaded) => uploaded.url.isEmpty ? null : uploaded.url,
      (error) {
        Log.error(
          '[HandwritingPdfUploadCoordinator] enqueue failed: ${error.msg}',
        );
        return null;
      },
    );
    if (url == null) {
      return null;
    }

    final storage = GetIt.instance<FileStorageService>();
    final notifier = storage.onFileProgress(fileUrl: url);
    final initial = notifier.value;
    if (initial.error?.isNotEmpty == true) {
      Log.error(
        '[HandwritingPdfUploadCoordinator] upload failed: ${initial.error}',
      );
      return null;
    }
    if (initial.progress >= 1.0) {
      return url;
    }

    final completed = Completer<bool>();
    void onProgress() {
      final progress = notifier.value;
      if (progress.error?.isNotEmpty == true) {
        if (!completed.isCompleted) completed.complete(false);
      } else if (progress.progress >= 1.0) {
        if (!completed.isCompleted) completed.complete(true);
      }
    }

    notifier.addListener(onProgress);
    try {
      // A missed native event should not leave the handwriting page waiting
      // forever. This is a timeout, not a retry; the caller can explicitly
      // retry later if desired.
      final success = await completed.future.timeout(
        const Duration(minutes: 15),
        onTimeout: () => false,
      );
      if (!success) {
        Log.error(
          '[HandwritingPdfUploadCoordinator] upload did not complete: $url',
        );
        return null;
      }
      return url;
    } finally {
      notifier.removeListener(onProgress);
    }
  }
}
