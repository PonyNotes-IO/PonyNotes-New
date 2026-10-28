import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/import_page/file_upload_request.dart';
import 'package:appflowy/plugins/import_page/file_upload_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-handwriting-saber/entities.pb.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show ValueChanged, ValueNotifier, visibleForTesting;

import 'handwriting_file_store.dart';
import 'handwriting_saber_data_service.dart';

class HandwritingUploadProgress {
  const HandwritingUploadProgress({
    this.sentBytes = 0,
    this.totalBytes = 0,
    this.isSaving = false,
  });

  final int sentBytes;
  final int totalBytes;
  final bool isSaving;

  double? get fraction => totalBytes == 0 ? null : sentBytes / totalBytes;
}

/// Tasks retain captured identity and files, never a live Widget.
class HandwritingAssetSync {
  HandwritingAssetSync._()
      : _upload = ((bytes, name, workspace, onProgress) =>
            FileUploadService.uploadFile(
              bytes,
              name,
              workspaceId: workspace,
              onProgress: onProgress,
            )),
        _commit = ((payload) async {
          final result =
              await HandwritingSaberEventSaveHandwritingSaber(payload).send();
          result.fold((_) {}, (e) => throw StateError(e.msg));
        }),
        _session = HandwritingSaberDataService.currentSession;

  @visibleForTesting
  HandwritingAssetSync.forTesting({
    required Future<String> Function(
      Uint8List,
      String,
      String,
      FileUploadProgress,
    ) upload,
    required Future<void> Function(SaveHandwritingSaberPayloadPB) commit,
    required Future<HandwritingSession> Function() session,
  })  : _upload = upload,
        _commit = commit,
        _session = session;

  final Future<String> Function(Uint8List, String, String, FileUploadProgress)
      _upload;
  final Future<void> Function(SaveHandwritingSaberPayloadPB) _commit;
  final Future<HandwritingSession> Function() _session;
  static final _worker = HandwritingAssetSync._();
  final Map<String, Future<bool>> _tasks = {};
  final Set<String> _dirty = {};
  final Map<String, ValueNotifier<HandwritingUploadProgress>> _progress = {};

  static Future<bool> resume({
    required String viewId,
    required String path,
    required String workspaceId,
    required String userId,
    ValueChanged<HandwritingUploadProgress>? onProgress,
  }) =>
      _worker.sync(
        viewId: viewId,
        path: path,
        workspaceId: workspaceId,
        userId: userId,
        onProgress: onProgress,
      );

  @visibleForTesting
  Future<bool> sync({
    required String viewId,
    required String path,
    required String workspaceId,
    required String userId,
    ValueChanged<HandwritingUploadProgress>? onProgress,
  }) async {
    final progress = _progress.putIfAbsent(
      path,
      () => ValueNotifier(const HandwritingUploadProgress()),
    );
    void notify() => onProgress?.call(progress.value);
    progress.addListener(notify);
    notify();
    _dirty.add(path);
    try {
      return await _tasks.putIfAbsent(path, () async {
        var changed = false;
        try {
          while (_dirty.remove(path)) {
            changed = await _sync(
                  viewId: viewId,
                  path: path,
                  workspaceId: workspaceId,
                  userId: userId,
                  onProgress: (value) => progress.value = value,
                ) ||
                changed;
          }
          return changed;
        } finally {
          unawaited(_tasks.remove(path));
          _dirty.remove(path);
          _progress.remove(path);
          progress.dispose();
        }
      });
    } finally {
      progress.removeListener(notify);
    }
  }

  Future<bool> _sync({
    required String viewId,
    required String path,
    required String workspaceId,
    required String userId,
    required ValueChanged<HandwritingUploadProgress> onProgress,
  }) async {
    final journal = '$path.assets.pending';
    final identity = (userId: userId, workspaceId: workspaceId);
    Future<void> checkSession() async {
      if (await _session() != identity) {
        throw StateError('Asset session changed');
      }
    }

    try {
      await checkSession();
      final bytes = await HandwritingFileStore.read(path);
      if (bytes.isEmpty) throw StateError('Handwriting data is unavailable');
      await HandwritingFileStore.write(
        journal,
        utf8.encode(
          jsonEncode({
            'viewId': viewId,
            'workspaceId': workspaceId,
            'userId': userId,
          }),
        ),
        keepBackups: false,
      );
      final base = HandwritingSaberDataService.normalizeLegacy(viewId, bytes);
      final document = jsonDecode(utf8.decode(base)) as Map<String, dynamic>;
      final cached = await HandwritingFileStore.read('$path.assets');
      final urls = cached.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(cached)) as Map<String, dynamic>;
      Future<String> upload(Uint8List bytes, String extension) async {
        await checkSession();
        final suffix = extension.startsWith('.') ? extension : '.$extension';
        final name = 'handwriting_${sha256.convert(bytes)}$suffix';
        final key = '$workspaceId/$name';
        if (urls[key] is String) return urls[key] as String;
        onProgress(HandwritingUploadProgress(totalBytes: bytes.length));
        final url = await _upload(bytes, name, workspaceId, (sent, total) {
          onProgress(
            HandwritingUploadProgress(sentBytes: sent, totalBytes: total),
          );
        });
        await checkSession();
        urls[key] = url;
        // Keep successful uploads even if a later upload/reference commit fails.
        await HandwritingFileStore.write(
          '$path.assets',
          utf8.encode(jsonEncode(urls)),
          keepBackups: false,
        );
        return url;
      }

      var changed = false;
      Object? pendingError;
      final pdfUploads = <String, Future<String>>{};
      final failedPdfs = <String>{};
      for (final page in document['pages'] as List) {
        for (final image in page['images'] as List? ?? []) {
          if ((image['imageUrl'] as String? ?? '').startsWith('http')) continue;
          if (image['type'] == 'svg' || image.containsKey('svgString')) {
            continue;
          }
          try {
            final encoded = image['imageBase64'] as String?;
            final imageBytes = encoded != null
                ? base64Decode(encoded)
                : Uint8List.fromList(
                    (image['imageBytes'] as List? ?? []).cast<int>(),
                  );
            if (imageBytes.isEmpty) {
              throw StateError('Handwriting image data is unavailable');
            }
            image['imageUrl'] = await upload(
              imageBytes,
              image['extension'] as String? ?? '.png',
            );
            changed = true;
          } catch (e) {
            Log.warn('[HandwritingAssets] Image pending: $e');
            pendingError ??= e;
          }
        }
        final background = page['backgroundImage'] as Map<String, dynamic>?;
        if (background == null ||
            (background['pdfUrl'] as String? ?? '').startsWith('http')) {
          continue;
        }
        final pdfPath = background['pdfFilePath'] as String? ?? '';
        if (failedPdfs.contains(pdfPath)) continue;
        try {
          if (pdfPath.startsWith('http')) {
            background['pdfUrl'] = pdfPath;
            changed = true;
          } else if (pdfPath.isNotEmpty && await File(pdfPath).exists()) {
            background['pdfUrl'] = await pdfUploads.putIfAbsent(
              pdfPath,
              () async => upload(await File(pdfPath).readAsBytes(), '.pdf'),
            );
            changed = true;
          } else {
            throw StateError('The original handwriting PDF is unavailable');
          }
        } catch (e) {
          Log.warn('[HandwritingAssets] PDF pending: $e');
          failedPdfs.add(pdfPath);
          pendingError ??= e;
        }
      }
      if (changed) {
        await checkSession();
        onProgress(const HandwritingUploadProgress(isSaving: true));
        await _commit(
          SaveHandwritingSaberPayloadPB()
            ..viewId = viewId
            ..userId = userId
            ..workspaceId = workspaceId
            ..baseSbn2Bytes = base
            ..sbn2Bytes = utf8.encode(jsonEncode(document)),
        );
      }
      if (pendingError != null) throw pendingError;
      if (await File(journal).exists()) await File(journal).delete();
      return changed;
    } catch (e) {
      // shortcut: retry on note open/save; add an app-wide worker if background retry is needed.
      Log.warn('[HandwritingAssets] Upload pending: $e');
      rethrow;
    }
  }
}
