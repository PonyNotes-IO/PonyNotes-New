import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_listener.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

enum WhiteboardSyncStatus { idle, syncing, success, error }

class WhiteboardCollabAdapter {
  WhiteboardCollabAdapter({
    required this.viewId,
    required this.onDataChanged,
    this.traceId,
    this.sessionId,
  }) {
    _service = WhiteboardDataService();
    _listener = WhiteboardListener(id: viewId);
    _listener.start(onRemoteUpdate: _onRemoteUpdate);
    Log.info('[WBCollab][WhiteboardCollabAdapter] Listener started for view: $viewId');
  }

  final String viewId;
  final Function(Map<String, dynamic>) onDataChanged;
  final String? traceId;
  final String? sessionId;

  late final WhiteboardDataService _service;
  late final WhiteboardListener _listener;

  static const _debounceDuration = Duration(milliseconds: 50);
  static const DeepCollectionEquality _deepEquality = DeepCollectionEquality();
  static const Set<String> _stableAppStateKeys = {
    'gridModeEnabled',
    'gridSize',
    'theme',
    'viewBackgroundColor',
    'zoom',
    'zenModeEnabled',
  };

  static const int _filesSizeWarningBytes = 5 * 1024 * 1024;

  bool _disposed = false;
  bool _isSyncing = false;
  bool _hasUnsavedChanges = false;
  bool _isPulling = false;
  bool _hasQueuedSync = false;

  WhiteboardSyncStatus _syncStatus = WhiteboardSyncStatus.idle;
  final StreamController<WhiteboardSyncStatus> _syncStatusController =
      StreamController<WhiteboardSyncStatus>.broadcast();

  Stream<WhiteboardSyncStatus> get syncStatusStream => _syncStatusController.stream;
  WhiteboardSyncStatus get syncStatus => _syncStatus;

  final Map<String, dynamic> _pendingData = {};
  String _pendingType = '';
  final Map<String, dynamic> _syncData = {};
  String _syncType = '';
  Timer? _debounceTimer;
  final Map<String, dynamic> _fullData = {};
  final Map<String, dynamic> _pendingFiles = {};
  final Map<String, dynamic> _syncFiles = {};

  void setInitialData(Map<String, dynamic>? data) {
    if (data != null) {
      final normalized = _normalizeKeys(data);
      _fullData.addAll(normalized);
      if (normalized.containsKey('files') && normalized['files'] is Map) {
        _fullData['files'] =
            Map<String, dynamic>.from(normalized['files'] as Map);
      }
    }
  }

  Map<String, dynamic> _normalizeKeys(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'excalidraw' || key.endsWith('_excalidraw')) {
        if (!normalized.containsKey('elements')) {
          normalized['elements'] = value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'excalidraw-state' || key.endsWith('_excalidraw-state')) {
        if (!normalized.containsKey('appState')) {
          normalized['appState'] = _sanitizeAppState(value is String ? _tryParseJson(value) : value);
        }
      } else if (key == 'excalidraw-files' || key.endsWith('_excalidraw-files')) {
        if (!normalized.containsKey('files')) {
          normalized['files'] = value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'elements' || key == 'appState' || key == 'files') {
        normalized[key] = _sanitizeWhiteboardValue(key, value is String ? _tryParseJson(value) : value);
      } else {
        normalized[key] = value;
      }
    }
    return normalized;
  }

  dynamic _tryParseJson(String value) {
    try {
      return jsonDecode(value);
    } catch (e) {
      return value;
    }
  }

  dynamic _sanitizeWhiteboardValue(String key, dynamic value) {
    if (key == 'appState') return _sanitizeAppState(value);
    if (key == 'files' && value is Map) return Map<String, dynamic>.from(value);
    return value;
  }

  Map<String, dynamic> _sanitizeAppState(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    final source = Map<String, dynamic>.from(value);
    final sanitized = <String, dynamic>{};
    for (final key in _stableAppStateKeys) {
      if (source.containsKey(key)) sanitized[key] = source[key];
    }
    return sanitized;
  }

  void onWhiteboardDataChanged(String type, Map<String, dynamic> data) {
    if (_disposed) return;
    data.forEach((key, value) {
      final sanitizedValue = _sanitizeWhiteboardValue(key, value);
      if (key == 'files' && value is Map) {
        _fullData[key] = _mergeFiles(
            _fullData[key] as Map<String, dynamic>?, value as Map<String, dynamic>);
        _pendingFiles.addAll(value);
      } else {
        _fullData[key] = sanitizedValue;
      }
    });
    _hasUnsavedChanges = true;
    _pendingData.addAll(
      data.map((key, value) => MapEntry(key, _sanitizeWhiteboardValue(key, value))),
    );
    _pendingType = type;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _syncImmediately();
    });
  }

  Map<String, dynamic> _mergeFiles(
      Map<String, dynamic>? existing, Map<String, dynamic> newFiles) {
    final result = <String, dynamic>{};
    if (existing != null) result.addAll(existing);
    newFiles.forEach((fileId, newData) {
      if (newData is Map && result.containsKey(fileId) && result[fileId] is Map) {
        final existingData = Map<String, dynamic>.from(result[fileId] as Map);
        final newFileMap = Map<String, dynamic>.from(newData as Map);
        if (!newFileMap.containsKey('dataURL') && existingData.containsKey('dataURL')) {
          newFileMap['dataURL'] = existingData['dataURL'];
          Log.info('[WBCollab][WhiteboardCollabAdapter] Preserving local dataURL for $fileId during merge');
        }
        result[fileId] = newFileMap;
      } else {
        result[fileId] = newData;
      }
    });
    return result;
  }

  Future<void> _syncImmediately() async {
    if (!_hasUnsavedChanges || _disposed) return;
    if (_isSyncing) {
      _hasQueuedSync = true;
      return;
    }
    _isSyncing = true;
    _hasUnsavedChanges = false;
    _syncData.addAll(_pendingData);
    _syncType = _pendingType;
    _pendingType = '';
    _pendingData.clear();
    _syncFiles.addAll(_pendingFiles);
    _pendingFiles.clear();

    _syncStatus = WhiteboardSyncStatus.syncing;
    _syncStatusController.add(_syncStatus);

    try {
      var success = false;
      if (_syncType == 'update') {
        if (_syncFiles.isNotEmpty) {
          _fullData['files'] = _mergeFiles(
              _fullData['files'] as Map<String, dynamic>?, _syncFiles);
        }

        if (_fullData.containsKey('files') && _fullData['files'] is Map) {
          final files = _fullData['files'] as Map<String, dynamic>;
          Log.info('[WBCollab][WhiteboardCollabAdapter] Files count: ${files.length}');
          try {
            final filesBytes = utf8.encode(jsonEncode(files)).length;
            if (filesBytes > _filesSizeWarningBytes) {
              Log.warn('[WBCollab][WhiteboardCollabAdapter] Files payload exceeds 5 MB ($filesBytes bytes)');
            }
          } catch (_) {}
        }

        Map<String, dynamic>? dataToSend;
        final elements = _fullData['elements'];
        if (elements is List && elements.length > 0) {
          dataToSend = Map<String, dynamic>.from(_fullData);
        }

        if (dataToSend != null) {
          Log.info('[WBCollab][WhiteboardCollabAdapter] Saving whiteboard data, fullData keys: ${_fullData.keys.toList()}');
          success = await _service.saveWhiteboardData(viewId, dataToSend);
        }

        if (success && _fullData['elements'] is List) {
          // Full sync completed successfully
        }
      } else {
        success = await _service.deleteWhiteboardData(viewId, _syncData);
      }

      if (!success) {
        _hasUnsavedChanges = true;
        _pendingData.addAll(_syncData);
        _pendingFiles.addAll(_syncFiles);
        _syncStatus = WhiteboardSyncStatus.error;
        _syncStatusController.add(_syncStatus);
        Log.warn('[WBCollab][WhiteboardCollabAdapter] Sync failed, will retry');
      } else {
        _syncStatus = WhiteboardSyncStatus.success;
        _syncStatusController.add(_syncStatus);
        Log.info('[WBCollab][WhiteboardCollabAdapter] Sync completed: saved to server');
      }
    } catch (e) {
      _hasUnsavedChanges = true;
      _pendingData.addAll(_syncData);
      _pendingFiles.addAll(_syncFiles);
      _syncStatus = WhiteboardSyncStatus.error;
      _syncStatusController.add(_syncStatus);
      Log.error('[WBCollab][WhiteboardCollabAdapter] Sync error: $e');
    } finally {
      _isSyncing = false;
      _syncData.clear();
      _syncFiles.clear();
    }

    if (_hasQueuedSync && !_disposed) {
      _hasQueuedSync = false;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () => _syncImmediately());
    } else if (_hasUnsavedChanges && !_disposed) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () {
        _syncImmediately();
      });
    }
  }

  /// 从 Collab 后端拉取完整白板数据（公开方法，供页面恢复时调用）
  Future<void> pullFromCollab() async {
    if (_disposed || _isPulling) return;
    _isPulling = true;
    try {
      final data = await _service.loadWhiteboardData(viewId);
      if (data.isNotEmpty && !_disposed) {
        _fullData.clear();
        _fullData.addAll(_normalizeKeys(data));
        onDataChanged(_fullData);
        Log.info('[WBCollab] Pulled full data from collab: ${_fullData.keys.toList()}');
      }
    } catch (e) {
      Log.error('[WBCollab] Pull from collab failed: $e');
    } finally {
      _isPulling = false;
    }
  }

  void _onRemoteUpdate(Map<String, dynamic> payload) {
    if (_disposed) return;
    try {
      final key = payload['key'] as String?;
      if (key == null) return;
      final isRemote = payload['is_remote'] == true;
      final isLargeData = payload['large_data'] == true;
      Log.info('[WBCollab][WhiteboardCollabAdapter] Notification update: key=$key, isRemote=$isRemote, largeData=$isLargeData');
      if (!isRemote) {
        Log.debug('[WBCollab][WhiteboardCollabAdapter] Skip local echo notification for key=$key');
        return;
      }
      if (isLargeData) {
        Log.info('[WBCollab][WhiteboardCollabAdapter] Large data notification for key=$key - pulling full state from collab');
        pullFromCollab();
        return;
      }
      var parsedValue = payload['value'];
      if (parsedValue is String) {
        parsedValue = _tryParseJson(parsedValue);
      }
      parsedValue = _sanitizeWhiteboardValue(key, parsedValue);
      if (key == 'files' && parsedValue is Map) {
        _fullData[key] = _mergeFiles(
          _fullData[key] as Map<String, dynamic>?,
          Map<String, dynamic>.from(parsedValue),
        );
      } else {
        if (_deepEquality.equals(_fullData[key], parsedValue)) {
          Log.debug('[WBCollab][WhiteboardCollabAdapter] Skip echoed remote update for key=$key');
          return;
        }
        _fullData[key] = parsedValue;
      }
      onDataChanged({key: parsedValue});
      Log.info('[WBCollab][WhiteboardCollabAdapter] Pushed to WebView: key=$key');
    } catch (e) {
      Log.error('[WBCollab][WhiteboardCollabAdapter] Failed to process remote update: $e');
    }
  }

  Future<void> forceSync() async {
    if (_disposed) return;
    _debounceTimer?.cancel();
    int attempts = 0;
    while (_isSyncing && !_disposed && attempts < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }
    if (_hasUnsavedChanges && !_disposed) {
      await _syncImmediately();
    }
  }

  void dispose() {
    _disposed = true;
    _listener.stop();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingData.clear();
    _syncData.clear();
    _fullData.clear();
    _pendingFiles.clear();
    _syncFiles.clear();
    _syncStatusController.close();
  }
}
