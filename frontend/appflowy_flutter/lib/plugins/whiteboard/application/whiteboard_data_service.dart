import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-whiteboard/entities.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:path/path.dart' as p;

import 'whiteboard_image_upload_service.dart';

class WhiteboardDataService {
  Future<String> _getWhiteboardDirectory() async {
    final basePath = await getIt<ApplicationDataStorage>().getPath();
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userId = userProfileResult.fold(
      (profile) => profile.id.toString(),
      (error) {
        Log.error('[WBCollab][WhiteboardDataService] Failed to get user profile: ${error.msg}');
        return '';
      },
    );

    final whiteboardPath = userId.isNotEmpty
        ? p.join(basePath, userId, 'whiteboards')
        : p.join(basePath, 'whiteboards');

    final directory = Directory(whiteboardPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      Log.info('[WBCollab][WhiteboardDataService] Created directory: $whiteboardPath');
    }

    return whiteboardPath;
  }

  Future<String> _getWhiteboardFilePath(String viewId) async {
    final directory = await _getWhiteboardDirectory();
    return p.join(directory, '$viewId.json');
  }

  Future<FlowyResult<void, FlowyError>> createWhiteboard({
    required String viewId,
    Map<String, dynamic>? initialData,
  }) async {
    try {
      final payload = CreateWhiteboardPayloadPB()..viewId = viewId;

      if (initialData != null) {
        payload.initialData = jsonEncode(initialData);
      }

      return await WhiteboardEventCreateWhiteboard(payload).send();
    } catch (e, stackTrace) {
      Log.error('[WBCollab][WhiteboardDataService] Exception in createWhiteboard: $e\n$stackTrace');
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to create whiteboard: $e'),
      );
    }
  }

  Future<FlowyResult<void, FlowyError>> openWhiteboard({
    required String viewId,
  }) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventOpenWhiteboard(payload).send();
      return result;
    } catch (e, stackTrace) {
      Log.error('[WBCollab][WhiteboardDataService] Exception in openWhiteboard: $e\n$stackTrace');
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to open whiteboard: $e'),
      );
    }
  }

  Future<bool> saveWhiteboardData(
    String viewId,
    Map<String, dynamic> data, {
    String? traceId,
    String? sessionId,
    String source = 'collab-adapter',
  }) async {
    final stopwatch = Stopwatch()..start();
    logDiagnosticEvent(
      'WhiteboardLoad',
      'data_save_start',
      {
        'traceId': traceId,
        'sessionId': sessionId,
        'viewId': viewId,
        'source': source,
        'elementsCount': _countElements(data),
        'filesCount': _countFiles(data),
        'payloadBytes': _estimatePayloadBytes(data),
      },
    );

    if (data.containsKey('files') && data['files'] is Map) {
      final files = data['files'] as Map<String, dynamic>;
      if (files.isNotEmpty) {
        try {
          final processedFiles =
              await WhiteboardImageUploadService.processFilesForUpload(
            files,
          );
          data['files'] = processedFiles;
        } catch (e) {
          Log.warn('[WBCollab][WhiteboardDataService] Image upload failed: $e');
        }
      }
    }

    final collabData = _stripDataURLsForCollab(data);
    final collabPayloadBytes = _estimatePayloadBytes(collabData);

    Log.info('[WBCollab][WhiteboardDataService] Saving whiteboard to collab: $viewId');
    final collabSuccess = await _saveToCollab(
      viewId,
      jsonEncode({'type': 'update', 'data': jsonEncode(collabData)}),
    );
    if (collabSuccess) {
      logDiagnosticEvent(
        'WhiteboardLoad',
        'collab_sync_done',
        {
          'traceId': traceId,
          'sessionId': sessionId,
          'viewId': viewId,
          'source': source,
          'storage': 'collab',
          'durationMs': stopwatch.elapsedMilliseconds,
          'elementsCount': _countElements(data),
          'filesCount': _countFiles(data),
          'payloadBytes': collabPayloadBytes,
          'fullPayloadBytes': _estimatePayloadBytes(data),
        },
      );
      return true;
    }

    Log.warn('[WBCollab][WhiteboardDataService] ⚠️ Collab save failed, falling back to file system');
    logDiagnosticEvent(
      'WhiteboardLoad',
      'collab_sync_fallback',
      {
        'traceId': traceId,
        'sessionId': sessionId,
        'viewId': viewId,
        'source': source,
        'durationMs': stopwatch.elapsedMilliseconds,
        'fallback': 'file',
        'elementsCount': _countElements(data),
        'filesCount': _countFiles(data),
        'payloadBytes': collabPayloadBytes,
      },
      warning: true,
    );
    final fileSuccess = await _saveToFile(viewId, data);
    logDiagnosticEvent(
      'WhiteboardLoad',
      'collab_sync_done',
      {
        'traceId': traceId,
        'sessionId': sessionId,
        'viewId': viewId,
        'source': source,
        'storage': fileSuccess ? 'file_fallback' : 'file_failed',
        'durationMs': stopwatch.elapsedMilliseconds,
        'elementsCount': _countElements(data),
        'filesCount': _countFiles(data),
        'payloadBytes': _estimatePayloadBytes(data),
      },
      warning: !fileSuccess,
    );
    return fileSuccess;
  }

  /// Save dirty elements using merge_elements type (element-level incremental merge)
  /// Only sends changed elements, server merges by element id + version
  Future<bool> saveWhiteboardElements(
    String viewId,
    Map<String, dynamic> data, {
    String? traceId,
    String? sessionId,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Process files if present
    if (data.containsKey('files') && data['files'] is Map) {
      final files = data['files'] as Map<String, dynamic>;
      if (files.isNotEmpty) {
        try {
          final processedFiles =
              await WhiteboardImageUploadService.processFilesForUpload(files);
          data['files'] = processedFiles;
        } catch (e) {
          Log.warn('[WBCollab][WhiteboardDataService] Image upload failed: $e');
        }
      }
    }

    final collabData = _stripDataURLsForCollab(data);
    Log.info(
        '[WBCollab][WhiteboardDataService] Saving whiteboard elements (merge): $viewId, '
        'elements count: ${(collabData['elements'] as List?)?.length ?? 0}');

    final collabSuccess = await _saveToCollab(
      viewId,
      jsonEncode({'type': 'merge_elements', 'data': jsonEncode(collabData)}),
    );

    if (collabSuccess) {
      Log.info(
          '[WBCollab][WhiteboardDataService] Merge elements saved in ${stopwatch.elapsedMilliseconds}ms');
      return true;
    }

    Log.warn('[WBCollab][WhiteboardDataService] Merge elements save failed');
    return false;
  }

  Map<String, dynamic> _stripDataURLsForCollab(Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);

    if (result.containsKey('files') && result['files'] is Map) {
      final files = result['files'] as Map<String, dynamic>;
      final slimFiles = <String, dynamic>{};

      for (final entry in files.entries) {
        final fileId = entry.key;
        final fileData = entry.value;

        if (fileData is! Map) {
          slimFiles[fileId] = fileData;
          continue;
        }

        final fileDataMap = Map<String, dynamic>.from(fileData as Map);
        final hasCloudUrl = fileDataMap.containsKey('url') &&
            fileDataMap['url'] is String &&
            (fileDataMap['url'] as String).startsWith('http');

        if (hasCloudUrl) {
          fileDataMap.remove('dataURL');
        }
        slimFiles[fileId] = fileDataMap;
      }

      result['files'] = slimFiles;
    }

    return result;
  }

  Future<bool> deleteWhiteboardData(
    String viewId,
    Map<String, dynamic> data,
  ) async {
    Log.info(
        '[WBCollab][WhiteboardDataService] =====================================================');
    Log.info('[WBCollab][WhiteboardDataService] deleteWhiteboardData() called');
    Log.info('[WBCollab][WhiteboardDataService] ViewID: $viewId');
    Log.info(
        '[WBCollab][WhiteboardDataService] =====================================================');

    Log.info('[WBCollab][WhiteboardDataService] Step 1: Trying to save to Collab backend...');
    final collabSuccess = await _saveToCollab(
      viewId,
      jsonEncode({'type': 'delete', 'data': jsonEncode(data)}),
    );
    if (collabSuccess) {
      Log.info(
          '[WBCollab][WhiteboardDataService] Saved delete event to Collab successfully: $viewId');
      return true;
    }

    return false;
  }

  Future<bool> _saveToCollab(String viewId, String data) async {
    try {
      final payload = UpdateWhiteboardPayloadPB()
        ..viewId = viewId
        ..jsonData = data;

      final result = await WhiteboardEventUpdateWhiteboard(payload).send();

      return result.fold(
        (_) => true,
        (error) {
          Log.error('[WBCollab][WhiteboardDataService] _saveToCollab failed: ${error.msg}');
          return false;
        },
      );
    } catch (e, stackTrace) {
      Log.error('[WBCollab][WhiteboardDataService] _saveToCollab exception: $e\n$stackTrace');
      return false;
    }
  }

  Future<bool> _saveToFile(String viewId, Map<String, dynamic> data) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);
      final dataWithMeta = {
        ...data,
        'savedAt': DateTime.now().toIso8601String(),
        'viewId': viewId,
      };

      await file.writeAsString(
        jsonEncode(dataWithMeta),
        flush: true,
      );

      Log.info('[WBCollab][WhiteboardDataService] Saved to file: $viewId');
      return true;
    } catch (e) {
      Log.error('[WBCollab][WhiteboardDataService] Failed to save to file: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> loadWhiteboardData(
    String viewId, {
    String? traceId,
    String? sessionId,
    String source = 'page-load',
  }) async {
    final stopwatch = Stopwatch()..start();
    logDiagnosticEvent(
      'WhiteboardLoad',
      'data_load_start',
      {
        'traceId': traceId,
        'sessionId': sessionId,
        'viewId': viewId,
        'source': source,
      },
    );

    await openWhiteboard(viewId: viewId);

    final collabData = await _loadFromCollab(viewId);
    if (collabData != null) {
      logDiagnosticEvent(
        'WhiteboardLoad',
        'data_load_done',
        {
          'traceId': traceId,
          'sessionId': sessionId,
          'viewId': viewId,
          'source': source,
          'storage': 'collab',
          'durationMs': stopwatch.elapsedMilliseconds,
          'elementsCount': _countElements(collabData),
          'filesCount': _countFiles(collabData),
          'payloadBytes': _estimatePayloadBytes(collabData),
        },
      );
      return collabData;
    }

    print('[WBCollab][WhiteboardDataService] Collab not found, trying file system');
    final fileData = await _loadFromFile(viewId);

    await _saveToCollab(
      viewId,
      jsonEncode({'type': 'update', 'data': fileData}),
    );

    logDiagnosticEvent(
      'WhiteboardLoad',
      'data_load_done',
      {
        'traceId': traceId,
        'sessionId': sessionId,
        'viewId': viewId,
        'source': source,
        'storage': 'file_fallback',
        'durationMs': stopwatch.elapsedMilliseconds,
        'elementsCount': _countElements(fileData),
        'filesCount': _countFiles(fileData),
        'payloadBytes': _estimatePayloadBytes(fileData),
      },
      warning: true,
    );
    return fileData;
  }

  Future<Map<String, dynamic>?> _loadFromCollab(String viewId) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventGetWhiteboardData(payload).send();

      return result.fold(
        (data) {
          if (data.jsonData.isEmpty) {
            return null;
          }
          return jsonDecode(data.jsonData) as Map<String, dynamic>;
        },
        (error) {
          return null;
        },
      );
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadFromFile(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);

      if (!file.existsSync()) {
        Log.info('[WBCollab][WhiteboardDataService] File not found, returning empty: $viewId');
        return _createEmptyWhiteboardData();
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      Log.info('[WBCollab][WhiteboardDataService] Loaded from file: $viewId');
      return data;
    } catch (e) {
      Log.error('[WBCollab][WhiteboardDataService] Failed to load from file: $e');
      return _createEmptyWhiteboardData();
    }
  }

  Future<FlowyResult<void, FlowyError>> closeWhiteboard({
    required String viewId,
  }) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      return await WhiteboardEventCloseWhiteboard(payload).send();
    } catch (e, stackTrace) {
      Log.error('[WBCollab][WhiteboardDataService] Exception in closeWhiteboard: $e\n$stackTrace');
      return FlowyResult.failure(
        FlowyError(msg: 'Failed to close whiteboard: $e'),
      );
    }
  }

  Future<bool> deleteWhiteboard(String viewId) async {
    try {
      final payload = ViewIdPB()..value = viewId;
      final result = await WhiteboardEventDeleteWhiteboard(payload).send();

      final success = result.fold(
        (_) => true,
        (error) {
          Log.error('[WBCollab][WhiteboardDataService] Failed to delete from Collab: ${error.msg}');
          return false;
        },
      );

      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);

      if (file.existsSync()) {
        await file.delete();
        Log.info('[WBCollab][WhiteboardDataService] File data deleted: $viewId');
      }

      return success;
    } catch (e) {
      Log.error('[WBCollab][WhiteboardDataService] Failed to delete whiteboard data: $e');
      return false;
    }
  }

  Future<bool> whiteboardDataExists(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      return File(filePath).existsSync();
    } catch (e) {
      Log.error('Failed to check whiteboard data existence: $e');
      return false;
    }
  }

  Future<bool> exportToJson(String viewId, String exportPath) async {
    try {
      final data = await loadWhiteboardData(viewId);
      final file = File(exportPath);

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );

      Log.info('Whiteboard exported to JSON: $exportPath');
      return true;
    } catch (e) {
      Log.error('Failed to export whiteboard to JSON: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> importFromJson(
    String viewId,
    String importPath,
  ) async {
    try {
      final file = File(importPath);
      if (!file.existsSync()) {
        Log.error('Import file not found: $importPath');
        return null;
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (!_isValidExcalidrawData(data)) {
        Log.error('Invalid Excalidraw data format');
        return null;
      }

      await saveWhiteboardData(viewId, data);

      Log.info('Whiteboard imported from JSON: $importPath');
      return data;
    } catch (e) {
      Log.error('Failed to import whiteboard from JSON: $e');
      return null;
    }
  }

  Future<List<String>> listAllWhiteboards() async {
    try {
      final directory = await _getWhiteboardDirectory();
      final dir = Directory(directory);

      if (!dir.existsSync()) {
        return [];
      }

      final files = dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();

      return files
          .map((file) => p.basenameWithoutExtension(file.path))
          .toList();
    } catch (e) {
      Log.error('Failed to list whiteboards: $e');
      return [];
    }
  }

  Map<String, dynamic> _createEmptyWhiteboardData() {
    return {
      'type': 'excalidraw',
      'version': 2,
      'source': 'https://excalidraw.com',
      'elements': [],
      'appState': {
        'gridSize': null,
        'viewBackgroundColor': '#ffffff',
      },
      'files': {},
    };
  }

  bool _isValidExcalidrawData(Map<String, dynamic> data) {
    return data.containsKey('type') &&
        data['type'] == 'excalidraw' &&
        data.containsKey('elements') &&
        data['elements'] is List;
  }

  int _countElements(Map<String, dynamic> data) {
    final elements = data['elements'];
    return elements is List ? elements.length : 0;
  }

  int _countFiles(Map<String, dynamic> data) {
    final files = data['files'];
    return files is Map ? files.length : 0;
  }

  int _estimatePayloadBytes(Map<String, dynamic> data) {
    try {
      return utf8.encode(jsonEncode(data)).length;
    } catch (_) {
      return -1;
    }
  }

  Future<int?> getWhiteboardDataSize(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);

      if (!file.existsSync()) {
        return null;
      }

      return file.lengthSync();
    } catch (e) {
      Log.error('Failed to get whiteboard data size: $e');
      return null;
    }
  }

  Future<DateTime?> getWhiteboardLastModified(String viewId) async {
    try {
      final filePath = await _getWhiteboardFilePath(viewId);
      final file = File(filePath);

      if (!file.existsSync()) {
        return null;
      }

      return file.lastModifiedSync();
    } catch (e) {
      Log.error('Failed to get whiteboard last modified time: $e');
      return null;
    }
  }
}
