import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_listener.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_image_sync_guard.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_sync_gate.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_version_lock.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// WhiteboardCollabAdapter
///
/// 完全模仿 TransactionAdapter 的实现
/// 立即同步白板数据变更到 Collab 后端（不使用定时器）
///
/// 核心思路：
/// 1. 监听白板数据变更（模仿 DocumentBloc 的 transactionStream）
/// 2. **立即调用** WhiteboardDataService.saveWhiteboardData()（模仿 TransactionAdapter.apply()）
/// 3. 使用防抖机制避免过于频繁的调用
/// 4. 提供强制同步方法（用于手动保存）
/// 5. ✅ 关键修复：在 Widget 销毁前强制同步，确保数据不丢失
class WhiteboardCollabAdapter {
  WhiteboardCollabAdapter({
    required this.viewId,
    required this.onDataChanged,
    this.traceId,
    this.sessionId,
  }) {
    _service = WhiteboardDataService();
    _listener = WhiteboardListener(id: viewId);
    _syncGate.onOpened = _handleSyncGateOpened;
    holdAutoSyncUntilReady();
    _listener.start(onRemoteUpdate: _onRemoteUpdate);
    Log.info(
      '[WBCollab][WhiteboardCollabAdapter] Listener started for view: $viewId',
    );
  }

  final String viewId;
  final Function(Map<String, dynamic>) onDataChanged;
  final String? traceId;
  final String? sessionId;

  late final WhiteboardDataService _service;
  late final WhiteboardListener _listener;

  // 防抖窗口：合并快速连续的绘制/拖动，减少 save 频率（尤其 Windows：每次 save 都要
  // 大字符串 FFI 编组 + 逐元素 CRDT 合并 + 写 RocksDB）。650ms → 900ms 明显减少高频
  // 拖拽时的 save 次数，又不至于让停笔后落库明显延迟。销毁/切换前有 forceSync 兜底，
  // 加大窗口不会丢数据。
  static const _debounceDuration = Duration(milliseconds: 900);
  static const whiteboardElementsDeltaKey = '__whiteboard_elements_delta';
  static const DeepCollectionEquality _deepEquality = DeepCollectionEquality();
  // scrollX/scrollY 已从稳定键中移除：
  // 原因：resize 反馈循环会持续调整 scrollX 并触发保存，
  // 导致每次会话中画布不断向左漂移且漂移量被持久化到后端
  static const Set<String> _stableAppStateKeys = {
    'gridModeEnabled',
    'gridSize',
    'theme',
    'viewBackgroundColor',
    // 【P2修复】移除 'zoom'：缩放/视口应是每个客户端的本地状态，不应跨端同步。
    // 此前同步 zoom 却不同步 scrollX/scrollY，远程改 zoom 会让本地视口绕不同中心
    // 缩放、把内容推出可视区——用户会误以为“缩放把笔画弄丢了”（实际只是移出视野，
    // 非真丢数据）。协同白板里每人本就应各自控制自己的缩放与视口。
    'zenModeEnabled',
  };

  bool _disposed = false;
  bool _isSyncing = false;
  bool _hasUnsavedChanges = false;
  bool _hasNonEmptyInitialData = false;

  // 待同步的数据（增量）
  final Map<String, dynamic> _pendingData = {};
  String _pendingType = "";

  // 正在同步的数据（增量）
  final Map<String, dynamic> _syncData = {};
  String _syncType = "";

  Timer? _debounceTimer;
  Timer? _imageSyncGuardTimer;
  static const _imageSyncGuardTimeout = Duration(milliseconds: 1800);
  // 缓存完整白板数据（全量状态）
  final Map<String, dynamic> _fullData = {};
  final WhiteboardSyncGate _syncGate = WhiteboardSyncGate();
  final WhiteboardVersionLock _versionLock = WhiteboardVersionLock();

  // ✅ 修复：添加待处理的 files 数据
  final Map<String, dynamic> _pendingFiles = {};
  final Map<String, dynamic> _syncFiles = {};
  int? _pendingRevision;

  // 【增量保存】出问题时置 false 回退到"每次全量发送整个场景"的旧路径。
  static const bool _incrementalSaveEnabled = true;

  // 【增量保存】已成功保存到 Rust 的元素 version 快照（elementId -> version）。
  // 只把相对该快照有变化的元素（新增 / version 增大 / 删除墓碑）经 FFI 发给 Rust，
  // 未变元素不再重复传输。空快照 => 本次保存退化为全量（首次打开 / 保存失败后的兜底）。
  // 正确性：Rust update_elements_map 本就按元素级 version 合并（incoming < existing 才跳过），
  // 所以"只发变更元素"与"全量发送"在 Rust 端产生完全相同的结果，union 语义与逐元素排序不变。
  final Map<String, int> _lastSentElementVersions = {};

  void holdAutoSyncUntilReady() {
    _syncGate.hold();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    Log.info(
      '[WBCollab][WhiteboardCollabAdapter] Auto sync gate held for startup: $viewId',
    );
  }

  void markInitialDataReadyForAutoSync() {
    _syncGate.markInitialDataReady();
    _flushPendingAfterGateIfOpen();
  }

  void markWebViewReadyForAutoSync() {
    _syncGate.markWebViewReady();
    _flushPendingAfterGateIfOpen();
  }

  void releaseAutoSyncGate({
    WhiteboardSyncGateOpenReason reason = WhiteboardSyncGateOpenReason.manual,
  }) {
    _syncGate.release(reason);
    _flushPendingAfterGateIfOpen();
  }

  void _handleSyncGateOpened(WhiteboardSyncGateOpenReason reason) {
    Log.info(
      '[WBCollab][WhiteboardCollabAdapter] Auto sync gate opened for $viewId, reason: $reason',
    );
    _flushPendingAfterGateIfOpen();
  }

  void _flushPendingAfterGateIfOpen() {
    if (!_syncGate.canAutoSync || !_hasUnsavedChanges || _disposed) {
      return;
    }

    Log.info(
      '[WBCollab][WhiteboardCollabAdapter] Flushing pending sync after gate opened for $viewId, reason: ${_syncGate.openReason}',
    );
    _scheduleSync();
  }

  /// 设置初始数据
  /// ✅ 关键修复：标准化键名，避免 localStorage 原始键名和标准键名共存导致数据混乱
  bool setInitialData(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }

    // 标准化键名后再设置
    final normalized = _normalizeKeys(data);
    final incomingRevision = _tryParseRevision(normalized['revision']) ?? 0;
    if (!_versionLock.shouldAccept(
      incomingRevision,
      sourceRank: WhiteboardSourceRank.authority,
    )) {
      Log.info(
        '[WBCollab][WhiteboardCollabAdapter] Dropping stale initial payload for $viewId: incomingRevision=$incomingRevision currentRevision=${_versionLock.revision}',
      );
      return false;
    }

    _seedRevision(
      incomingRevision,
      sourceRank: WhiteboardSourceRank.authority,
    );
    if (_hasMeaningfulSceneChange(normalized)) {
      _hasNonEmptyInitialData = true;
    }
    // 【数据丢失根因修复】保持"全量缓存中 elements 永不为空数组"的不变式：
    // 空 elements([]) 只来自异常路径，不纳入缓存，避免后续被当作权威状态回写服务器。
    if (_isBlankElementsValue(normalized['elements'])) {
      normalized.remove('elements');
    }
    _fullData.addAll(normalized);
    _fullData['revision'] = incomingRevision;
    // 同时初始化 files 数据
    if (normalized.containsKey('files') && normalized['files'] is Map) {
      _fullData['files'] =
          Map<String, dynamic>.from(normalized['files'] as Map);
    }
    return true;
  }

  /// ✅ 标准化键名：将 localStorage 原始键名转换为标准键名
  /// excalidraw -> elements, excalidraw-state -> appState, excalidraw-files -> files
  Map<String, dynamic> _normalizeKeys(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key == 'excalidraw' || key.endsWith('_excalidraw')) {
        if (!normalized.containsKey('elements')) {
          normalized['elements'] =
              value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'excalidraw-state' ||
          key.endsWith('_excalidraw-state')) {
        if (!normalized.containsKey('appState')) {
          normalized['appState'] = _sanitizeAppState(
            value is String ? _tryParseJson(value) : value,
          );
        }
      } else if (key == 'excalidraw-files' ||
          key.endsWith('_excalidraw-files')) {
        if (!normalized.containsKey('files')) {
          normalized['files'] = value is String ? _tryParseJson(value) : value;
        }
      } else if (key == 'elements' || key == 'appState' || key == 'files') {
        // 标准键名优先（不覆盖已有的标准键名数据）
        normalized[key] = _sanitizeWhiteboardValue(
          key,
          value is String ? _tryParseJson(value) : value,
        );
      } else if (key == 'revision') {
        final parsedRevision = _tryParseRevision(value);
        if (parsedRevision != null) {
          normalized[key] = parsedRevision;
        }
      } else {
        normalized[key] = value;
      }
    }

    return normalized;
  }

  /// 尝试解析 JSON 字符串，失败则返回原始值
  dynamic _tryParseJson(String value) {
    try {
      return jsonDecode(value);
    } catch (e) {
      return value;
    }
  }

  /// 白板数据变更回调（模仿 DocumentBloc 的 transactionStream）
  ///
  /// 关键：立即同步到后端（模仿 TransactionAdapter.apply()）
  dynamic _sanitizeWhiteboardValue(String key, dynamic value) {
    if (key == 'appState') {
      return _sanitizeAppState(value);
    }
    if (key == 'files' && value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return value;
  }

  int? _tryParseRevision(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _seedRevision(
    dynamic revision, {
    WhiteboardSourceRank sourceRank = WhiteboardSourceRank.session,
  }) {
    final parsed = _tryParseRevision(revision);
    if (parsed == null) {
      return;
    }
    _versionLock.seed(parsed, sourceRank: sourceRank);
    _pendingRevision = parsed;
  }

  void _ensurePendingRevision() {
    if (_pendingRevision != null) {
      _fullData['revision'] = _pendingRevision;
      return;
    }

    final nextRevision = _versionLock.bump();
    _pendingRevision = nextRevision;
    _fullData['revision'] = nextRevision;
  }

  Map<String, dynamic> _sanitizeAppState(dynamic value) {
    if (value is! Map) {
      return <String, dynamic>{};
    }

    final source = Map<String, dynamic>.from(value);
    final sanitized = <String, dynamic>{};
    for (final key in _stableAppStateKeys) {
      if (source.containsKey(key)) {
        sanitized[key] = source[key];
      }
    }
    return sanitized;
  }

  /// 判断某个值是否是“空 elements”（长度为 0 的列表）。
  ///
  /// 【数据丢失根因修复】同步用的 elements 由 JS 端 getSceneElementsIncludingDeleted()
  /// 采集：用户真实删除会保留 isDeleted 墓碑（数组非空），因此真正的空 [] 只可能来自
  /// WebView 重新初始化 / 页面重载 / 远程空值回声等异常路径。当前 App 未接入任何会产生
  /// 合法空数组的“清空画布”功能（window.clearCanvas 未定义、宿主也未调用），所以空 []
  /// 一律视为异常，必须在本地写入、同步、远程推送三处丢弃，杜绝“某人网络抖动 → 空 []
  /// 被持久化并广播 → 全体协作用户白板瞬间清空”。若将来接入真正的清空功能，应通过显式
  /// 意图标志放行，而非放开此守卫。
  bool _isBlankElementsValue(dynamic value) => value is List && value.isEmpty;

  /// 返回移除了“空 elements([])”键后的数据副本（其它键原样保留）。
  Map<String, dynamic> _withoutBlankElements(Map<String, dynamic> data) {
    if (!data.containsKey('elements') ||
        !_isBlankElementsValue(data['elements'])) {
      return data;
    }
    Log.warn(
      '[WBCollab][WhiteboardCollabAdapter] Dropped blank elements([]) local write for $viewId (spurious clear guard; existing content kept)',
    );
    final copy = Map<String, dynamic>.from(data);
    copy.remove('elements');
    return copy;
  }

  void onWhiteboardDataChanged(String type, Map<String, dynamic> data) {
    if (_disposed) {
      return;
    }

    // 【回退修复 2026-07-01】本地用户编辑一律放行，绝不按 revision 门控。
    // 原因：这个回调只处理“用户在本机 WebView 上的实时绘制”（Excalidraw onChange →
    // localStorageOnSet）。上游 version-lock 用 revision 门控本地编辑存在两个致命问题：
    //   ① setInitialData 以 authority(rank=2) 锁定初始 revision 后，session 级本地编辑在相等
    //      revision 上永远通不过 shouldAccept，revision 卡在 0，编辑全部被丢（344 次 0 保存）；
    //   ② 即便放宽到“仅丢严格更旧”，本地 onChange 携带的 revision 是上一次推给 WebView 的
    //      陈旧回声值，天然滞后于 _ensurePendingRevision 递增后的当前 HEAD（实测
    //      incomingRevision=3 < currentRevision=4），连续绘制仍被成批丢弃、切换即丢。
    // revision 只应服务于“对外保存的排序”（由 _ensurePendingRevision 赋值，Rust 侧只挡严格
    // 更旧的跨端更新），绝不能用来拦截用户本机的实时绘制。空画布式清空由下方
    // _withoutBlankElements 守卫拦截，不依赖 version-lock。

    // 【数据丢失根因修复】剔除清空画布式的空 elements([]) 写入，绝不写入全量缓存与
    // 待同步队列（详见 _isBlankElementsValue 说明）。仅对 'update' 生效，'delete' 走
    // 独立的删除路径，不受影响。
    final sceneData = Map<String, dynamic>.from(data)..remove('revision');
    final effectiveData =
        type == 'update' ? _withoutBlankElements(sceneData) : sceneData;
    if (effectiveData.isEmpty) {
      return;
    }

    // 更新全量数据缓存
    effectiveData.forEach((key, value) {
      final sanitizedValue = _sanitizeWhiteboardValue(key, value);
      if (key == 'files' && value is Map) {
        _fullData[key] = _mergeFiles(_fullData[key] as Map<String, dynamic>?,
            value as Map<String, dynamic>);
        _pendingFiles.addAll(value);
      } else {
        _fullData[key] = sanitizedValue;
      }
    });

    _hasUnsavedChanges = true;
    _pendingData.addAll(
      effectiveData.map(
        (key, value) => MapEntry(key, _sanitizeWhiteboardValue(key, value)),
      ),
    );
    _pendingType = type;
    _ensurePendingRevision();

    if (!_syncGate.canAutoSync) {
      // 每次编辑（gate 关闭期间）都会触发，降为 debug 以减少 Windows 日志开销。
      Log.debug(
        '[WBCollab][WhiteboardCollabAdapter] Auto sync blocked by startup gate: $viewId, keys: ${data.keys.join(',')}',
      );
      return;
    }

    // Excalidraw writes elements and files through separate bridge debounce
    // windows. Do not let an image element reach local Collab alone: the
    // resulting remote echo can replace the image before its file cache is
    // available in the WebView. The files callback normally releases this
    // guard within 900ms; the timeout is only a bounded fallback for a broken
    // or delayed bridge callback.
    if (_hasUnresolvedImageFiles()) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _scheduleImageSyncGuard();
      Log.info(
        '[WBCollab][WhiteboardCollabAdapter] Delaying image sync for $viewId; missing file ids: ${_missingImageFileIds().join(',')}',
      );
      return;
    }

    _imageSyncGuardTimer?.cancel();
    _imageSyncGuardTimer = null;
    _scheduleSync();
  }

  Set<String> _missingImageFileIds() {
    return WhiteboardImageSyncGuard.unresolvedFileIds(
      elements: _fullData['elements'],
      files: _fullData['files'],
    );
  }

  bool _hasUnresolvedImageFiles() => _missingImageFileIds().isNotEmpty;

  void _scheduleImageSyncGuard() {
    _imageSyncGuardTimer?.cancel();
    _imageSyncGuardTimer = Timer(_imageSyncGuardTimeout, () {
      _imageSyncGuardTimer = null;
      if (_disposed || !_hasUnsavedChanges || !_syncGate.canAutoSync) {
        return;
      }
      Log.warn(
        '[WBCollab][WhiteboardCollabAdapter] Image sync guard timed out for $viewId; saving with missing file ids: ${_missingImageFileIds().join(',')}',
      );
      _syncImmediately(allowUnresolvedImages: true);
    });
  }

  void _scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _syncImmediately();
    });
  }

  /// 合并 files 数据（智能合并，保护 dataURL）
  Map<String, dynamic> _mergeFiles(
      Map<String, dynamic>? existing, Map<String, dynamic> newFiles) {
    final result = <String, dynamic>{};
    if (existing != null) {
      result.addAll(existing);
    }

    // 遍历新文件，如果本地已有该文件且包含 dataURL，而新数据没有，则保留本地的 dataURL
    newFiles.forEach((fileId, newData) {
      if (newData is Map &&
          result.containsKey(fileId) &&
          result[fileId] is Map) {
        final existingData = Map<String, dynamic>.from(result[fileId] as Map);
        final newFileMap = Map<String, dynamic>.from(newData as Map);

        // 如果新数据没有 dataURL 但本地有，则保留本地的
        if (!newFileMap.containsKey('dataURL') &&
            existingData.containsKey('dataURL')) {
          newFileMap['dataURL'] = existingData['dataURL'];
        }

        // 【存储爆炸修复 2026-07-02】必须同样保留已有的云 url 及上传元数据：
        // JS 侧同步来的 files 永远只有 dataURL、不带 url，旧逻辑用它整条替换会把上一次
        // 上传写回的 url 冲掉 → processFilesForUpload 的 skip 判断(有 url 才跳过)失效 →
        // 协作期间每次保存(约 3-4 秒一次)把画板上所有图片全部重新上传。配合“每次上传都
        // 生成新文件名”，单账号一天就泄漏了 12 万个文件/110GB 云存储。
        for (final key in const ['url', 'fileName', 'fileSize', 'uploadedAt']) {
          if (!newFileMap.containsKey(key) && existingData.containsKey(key)) {
            newFileMap[key] = existingData[key];
          }
        }

        result[fileId] = newFileMap;
      } else {
        result[fileId] = newData;
      }
    });

    return result;
  }

  /// 立即同步到 Collab 后端（模仿 TransactionAdapter.apply()）
  Future<void> _syncImmediately({bool allowUnresolvedImages = false}) async {
    if (!_hasUnsavedChanges || _isSyncing || _disposed) {
      return;
    }

    if (!_syncGate.canAutoSync) {
      Log.info(
        '[WBCollab][WhiteboardCollabAdapter] Immediate sync skipped by startup gate: $viewId',
      );
      return;
    }

    if (!allowUnresolvedImages && _hasUnresolvedImageFiles()) {
      _scheduleImageSyncGuard();
      return;
    }

    _isSyncing = true;
    _hasUnsavedChanges = false;
    _syncData.addAll(_pendingData);
    _syncType = _pendingType;
    _pendingType = "";
    _pendingData.clear();

    _syncFiles.addAll(_pendingFiles);
    _pendingFiles.clear();
    final revision = _pendingRevision ?? _versionLock.revision;
    _fullData['revision'] = revision;

    try {
      var success = false;

      if (_syncType == 'update') {
        if (_syncFiles.isNotEmpty) {
          _fullData['files'] = _mergeFiles(
              _fullData['files'] as Map<String, dynamic>?, _syncFiles);
        }

        // 【数据丢失根因修复】兜底守卫：即便上游守卫全部失效，也绝不把空 elements([])
        // 作为权威全量状态持久化到 Collab（会广播清空所有协作端）。
        if (_isBlankElementsValue(_fullData['elements'])) {
          _fullData.remove('elements');
          Log.warn(
            '[WBCollab][WhiteboardCollabAdapter] Stripped blank elements([]) before collab save for $viewId',
          );
        }

        // 【增量保存】构造本次要发送的 payload：默认拷贝全量缓存，再把 elements 替换为
        // "自上次成功保存以来的变更元素"。files/appState/revision 等仍随全量发送
        //（files 在 Rust 端 union 合并、appState 很小，无需增量）。
        final payload = Map<String, dynamic>.from(_fullData);
        List<Map<String, dynamic>>? sentElements;
        if (_incrementalSaveEnabled && _fullData['elements'] is List) {
          final delta = _computeElementsDelta(_fullData['elements'] as List);
          if (delta.isEmpty) {
            // 本次没有元素变化：不发送 elements 键，避免重复经 FFI 传全量场景。
            payload.remove('elements');
            // 同时剥掉空 files({})，否则会触发 Rust 的"空场景覆盖非空场景"守卫，
            // 连带把本次的 appState 变更一起丢弃。
            final files = payload['files'];
            if (files is Map && files.isEmpty) {
              payload.remove('files');
            }
          } else {
            payload['elements'] = delta;
          }
          sentElements = delta;
        }

        success = await _service.saveWhiteboardData(
          viewId,
          payload,
          revision: revision,
        );

        // saveWhiteboardData 会把上传后带回云 url 的 files 重新赋值到传入 map 上；
        // 写回全量缓存，保持"图片已有 url 才跳过重传"的防存储爆炸逻辑（与旧路径一致）。
        if (payload['files'] is Map) {
          _fullData['files'] = payload['files'];
        }

        // 仅在保存成功后推进"已发送 version 快照"；失败则保持不变，下次自动重发这些变更。
        if (success && sentElements != null) {
          _commitSentElementVersions(sentElements);
        }
      } else {
        success = await _service.deleteWhiteboardData(viewId, _syncData);
      }

      if (!success) {
        _hasUnsavedChanges = true;
        _pendingData.addAll(_syncData);
        _pendingFiles.addAll(_syncFiles);
        _pendingRevision = revision;
        Log.warn(
            '[WBCollab][WhiteboardCollabAdapter] ⚠️ Sync failed, will retry');
      } else {
        _versionLock.seed(revision);
        _pendingRevision = null;
        Log.debug(
            '[WBCollab][WhiteboardCollabAdapter] Sync completed: saved to server');
      }
    } catch (e) {
      _hasUnsavedChanges = true;
      _pendingData.addAll(_syncData);
      _pendingFiles.addAll(_syncFiles);
      _pendingRevision = revision;
      Log.error('[WBCollab][WhiteboardCollabAdapter] ❌ Sync error: $e');
    } finally {
      _isSyncing = false;
      _syncData.clear();
      _syncFiles.clear();
    }

    // 同步期间如果有新变更积累，安排下一次同步
    if (_hasUnsavedChanges && !_disposed) {
      _scheduleSync();
    }
  }

  /// 强制立即同步（用于手动保存和 Widget 销毁前）
  /// 会等待正在进行的同步完成，然后如果有未保存的变更则再次同步
  Future<void> forceSync() async {
    if (_disposed) {
      return;
    }

    _debounceTimer?.cancel();
    _imageSyncGuardTimer?.cancel();
    _imageSyncGuardTimer = null;

    // 等待正在进行的同步完成（最多等待 5 秒）
    int attempts = 0;
    while (_isSyncing && !_disposed && attempts < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }

    if (_hasUnsavedChanges && !_disposed) {
      if (!_syncGate.canAutoSync && !_shouldForceSyncWhileGateHeld()) {
        Log.warn(
          '[WBCollab][WhiteboardCollabAdapter] Force sync skipped by startup blank guard: $viewId, keys: ${_pendingData.keys.join(',')}, reason: ${_syncGate.openReason}',
        );
        return;
      }
      releaseAutoSyncGate();
      await _syncImmediately(allowUnresolvedImages: true);
    }
  }

  bool _shouldForceSyncWhileGateHeld() {
    if (_hasNonEmptyInitialData || _pendingType == 'delete') {
      return true;
    }

    return _hasMeaningfulSceneChange(_pendingData);
  }

  bool _hasMeaningfulSceneChange(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key == 'elements') {
        if (value is List && value.isNotEmpty) {
          return true;
        }
        if (value is! List) {
          return true;
        }
        continue;
      }

      if (key == whiteboardElementsDeltaKey && value is Map) {
        final changed = value['changed'];
        if (changed is List && changed.isNotEmpty) {
          return true;
        }
        continue;
      }

      if (key == 'files') {
        if (value is Map && value.isNotEmpty) {
          return true;
        }
        if (value is! Map) {
          return true;
        }
        continue;
      }

      if (_isNonSceneMetadataKey(key)) {
        continue;
      }

      return true;
    }

    return false;
  }

  bool _isNonSceneMetadataKey(String key) {
    return key == 'appState' ||
        key == 'type' ||
        key == 'version' ||
        key == 'source' ||
        key == 'savedAt' ||
        key == 'viewId';
  }

  Future<void> forceSyncAndDispose() async {
    if (_disposed) {
      return;
    }

    try {
      await _listener.stop();
      await forceSync();
    } finally {
      dispose();
    }
  }

  /// 处理来自实时通知的更新
  /// 由 WhiteboardListener 回调，payload 已在 Listener 中从 JSON 解析完毕
  void _onRemoteUpdate(String key, dynamic value, bool isRemote, int? revision) {
    if (_disposed) return;

    try {
      // 本地写入回声不再推回 WebView，避免自触发循环
      if (!isRemote) {
        return;
      }

      final remoteRevision = _tryParseRevision(revision);
      if (remoteRevision != null) {
        if (!_versionLock.shouldAccept(
          remoteRevision,
          sourceRank: WhiteboardSourceRank.authority,
        )) {
          Log.info(
            '[WBCollab][WhiteboardCollabAdapter] Dropping stale remote payload for $viewId: incomingRevision=$remoteRevision currentRevision=${_versionLock.revision}',
          );
          return;
        }
        _seedRevision(
          remoteRevision,
          sourceRank: WhiteboardSourceRank.authority,
        );
        _fullData['revision'] = remoteRevision;
      } else if (key == 'revision') {
        return;
      }

      // 解析值（如果是字符串 JSON 则解析）
      dynamic parsedValue = value;
      if (value is String) {
        parsedValue = _tryParseJson(value);
      }
      parsedValue = _sanitizeWhiteboardValue(key, parsedValue);

      if (key == 'elements' &&
          parsedValue is Map &&
          parsedValue['changed'] is List) {
        final changed = List<dynamic>.from(parsedValue['changed'] as List);
        if (changed.isEmpty) {
          return;
        }

        final mergedElements = _mergeElementsDelta(_fullData[key], changed);
        _fullData[key] = mergedElements;
        onDataChanged({
          whiteboardElementsDeltaKey: {
            'changed': changed,
            'elements': mergedElements,
          },
        });
        return;
      }

      // 【根因B修复】到这里说明 elements 不是合法的增量(delta)更新。
      // 非增量的 elements 值若不是合法的元素列表（如 Rust 旧数据迁移/边缘条件产生的
      // null、字符串或其它非 List），绝不能透传给 WebView——
      // updateScene({elements: null/非法}) 会把整块画板瞬间清空（“无操作即清空”路径）。
      // 直接丢弃这种值，等正常的增量/全量 List 元素再同步。
      if (key == 'elements' && parsedValue is! List) {
        return;
      }

      // 【数据丢失根因修复】远程送来的“整块空 elements([])”绝不能推给 WebView：
      // updateScene({elements: []}) 会把本地画板瞬间清空，随后本地 onChange 回声又把空
      // 状态经本地同步路径持久化，形成“一人网络抖动 → 清空所有人”的放大回路。空 [] 只
      // 来自异常端，直接丢弃，等正常的非空元素再同步。
      if (key == 'elements' &&
          parsedValue is List &&
          parsedValue.isEmpty) {
        Log.warn(
          '[WBCollab][WhiteboardCollabAdapter] Ignored remote blank elements([]) for $viewId (spurious clear guard)',
        );
        return;
      }

      // 更新全量数据
      if (key == 'files' && parsedValue is Map) {
        _fullData[key] = _mergeFiles(
          _fullData[key] as Map<String, dynamic>?,
          Map<String, dynamic>.from(parsedValue),
        );
      } else {
        if (_deepEquality.equals(_fullData[key], parsedValue)) {
          return;
        }
        _fullData[key] = parsedValue;
      }

      // 通知 WebView 更新
      onDataChanged({key: parsedValue});
    } catch (e) {
      Log.error(
          '[WBCollab][WhiteboardCollabAdapter] ❌ Failed to process remote update: $e');
    }
  }

  List<dynamic> _mergeElementsDelta(dynamic existing, List<dynamic> changed) {
    final byId = <String, dynamic>{};
    if (existing is List) {
      for (final element in existing) {
        if (element is Map && element['id'] is String) {
          byId[element['id'] as String] = element;
        }
      }
    }

    for (final change in changed) {
      if (change is! Map || change['id'] is! String) {
        continue;
      }

      final id = change['id'] as String;
      final remoteElement = change['element'];
      final localElement = byId[id];
      if (remoteElement is! Map) {
        // 【元素丢失根因修复 2026-07-01】远程 delta 里 element 为 null，只可能来自 Rust
        // observe_deep 读到“键被移除/值不可解析”的异常态。当前 union-only 模型下元素键从不
        // 删除，合法删除一律是 isDeleted:true 的“非空 Map”。因此绝不能据 null 把本地存活元素
        // 标记删除——这正是“多端协作时别人写的元素莫名消失”的真凶。保留本地，跳过。
        if (localElement is Map && localElement['isDeleted'] != true) {
          Log.warn(
            '[WBLoss] Ignored spurious null-element delete for id=$id (kept local element)',
          );
        }
        continue;
      }

      if (localElement is! Map) {
        byId[id] = remoteElement;
        continue;
      }

      final localVersion = _elementVersion(localElement);
      final remoteVersion = _elementVersion(remoteElement);
      if (remoteVersion > localVersion ||
          (remoteVersion == localVersion &&
              _elementVersionNonce(remoteElement) >
                  _elementVersionNonce(localElement))) {
        // 【埋点】记录“存活元素被远程标记删除”的事件，便于定位非 null 路径的删除来源。
        if (localElement['isDeleted'] != true && remoteElement['isDeleted'] == true) {
          Log.warn(
            '[WBLoss] element $id marked deleted by remote delta: localV=$localVersion remoteV=$remoteVersion',
          );
        }
        byId[id] = remoteElement;
      }
    }

    return byId.values.toList(growable: false);
  }

  /// 【增量保存】计算相对"上次成功保存"的变更元素集合。
  ///
  /// 输入为 JS 端 getSceneElementsIncludingDeleted() 采集的完整场景（含删除墓碑）。
  /// 返回需要发送给 Rust 的元素：
  /// - 新增元素（快照里没有该 id）；
  /// - version 增大的元素（Excalidraw 每次改动都会递增 version）；
  /// - 删除墓碑（删除会保留 isDeleted:true 且 version 递增的元素，天然落入"version 增大"）。
  /// 未变元素不返回，避免重复经 FFI 传给 Rust。删除通过墓碑发送、绝不靠"漏发"，符合正确性红线。
  List<Map<String, dynamic>> _computeElementsDelta(List<dynamic> fullElements) {
    final delta = <Map<String, dynamic>>[];
    for (final element in fullElements) {
      if (element is! Map) {
        continue;
      }
      final id = element['id'];
      if (id is! String) {
        continue;
      }
      final version = _elementVersion(element);
      final lastVersion = _lastSentElementVersions[id];
      if (lastVersion == null || version > lastVersion) {
        delta.add(Map<String, dynamic>.from(element));
      }
    }
    return delta;
  }

  /// 【增量保存】保存成功后，把本次已持久化到 Rust 的元素 version 记入快照，供下次增量比对。
  void _commitSentElementVersions(List<Map<String, dynamic>> sentElements) {
    for (final element in sentElements) {
      final id = element['id'];
      if (id is String) {
        _lastSentElementVersions[id] = _elementVersion(element);
      }
    }
  }

  int _elementVersion(Map element) {
    final version = element['version'];
    return version is int ? version : 0;
  }

  int _elementVersionNonce(Map element) {
    final nonce = element['versionNonce'];
    return nonce is int ? nonce : 0;
  }

  /// 销毁适配器
  void dispose() {
    _disposed = true;
    _listener.stop();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _imageSyncGuardTimer?.cancel();
    _imageSyncGuardTimer = null;
    _pendingData.clear();
    _syncData.clear();
    _fullData.clear();
    _pendingFiles.clear();
    _syncFiles.clear();
    _lastSentElementVersions.clear();
    _syncGate.dispose();
  }
}
