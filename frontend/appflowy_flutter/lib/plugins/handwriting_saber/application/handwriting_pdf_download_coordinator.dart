import 'dart:async';

/// Download boundary used by [HandwritingPdfDownloadCoordinator].
abstract interface class HandwritingPdfDownloadBackend {
  /// Returns the persistent local cache path after a successful download.
  /// Returns null for HTTP errors, including 404, and other download errors.
  Future<String?> downloadAndCache({required String pdfUrl});
}

/// Coalesces page-level downloads of the same cloud PDF.
///
/// A PDF background is represented by one image per page. Without this
/// coordinator every page can issue the same GET independently. Failed URLs
/// are temporarily suppressed so a 404 cannot turn into one retry storm per
/// page while the document remains open.
class HandwritingPdfDownloadCoordinator {
  HandwritingPdfDownloadCoordinator({
    required HandwritingPdfDownloadBackend backend,
    this.failureCooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  })  : _backend = backend,
        _now = now ?? DateTime.now;

  final HandwritingPdfDownloadBackend _backend;
  final Duration failureCooldown;
  final DateTime Function() _now;
  final Map<String, Future<String?>> _inFlight = {};
  final Map<String, DateTime> _failedUntil = {};

  Future<String?> download({required String pdfUrl}) {
    final inFlight = _inFlight[pdfUrl];
    if (inFlight != null) {
      return inFlight;
    }

    final failedUntil = _failedUntil[pdfUrl];
    if (failedUntil != null && _now().isBefore(failedUntil)) {
      return Future<String?>.value(null);
    }

    final future = _run(pdfUrl);
    _inFlight[pdfUrl] = future;
    future.then<void>(
      (path) {
        if (path == null) {
          _failedUntil[pdfUrl] = _now().add(failureCooldown);
        } else {
          _failedUntil.remove(pdfUrl);
        }
        _removeIfCurrent(pdfUrl, future);
      },
      onError: (_, __) {
        _failedUntil[pdfUrl] = _now().add(failureCooldown);
        _removeIfCurrent(pdfUrl, future);
      },
    );
    return future;
  }

  Future<String?> _run(String pdfUrl) async {
    try {
      return await _backend.downloadAndCache(pdfUrl: pdfUrl);
    } catch (_) {
      return null;
    }
  }

  void _removeIfCurrent(String pdfUrl, Future<String?> future) {
    if (identical(_inFlight[pdfUrl], future)) {
      _inFlight.remove(pdfUrl);
    }
  }
}
