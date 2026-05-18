import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/startup/tasks/rust_sdk.dart';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../startup.dart';

class AutoExportDebugLogsTask extends LaunchTask {
  AutoExportDebugLogsTask();

  static const _sessionFolderName = 'PonyNotes-DebugLogs';
  static const _exportInterval = Duration(seconds: 20);
  static const _moduleLogsRootName = '模块化日志';
  static const _moduleReadmeFolderName = '00-导出说明';
  static const _moduleEnvironmentFolderName = '01-应用与环境';
  static const _moduleGeneralFolderName = '02-通用运行日志';
  static const _moduleWhiteboardFolderName = '03-白板详细日志';
  static const _moduleTableFolderName = '04-表格问题详细日志';
  static const _moduleRawIndexFolderName = '99-原始文件索引';

  Timer? _exportTimer;
  Directory? _sessionDirectory;
  bool _isExporting = false;

  static Future<Directory> exportOnce({String reason = 'manual'}) async {
    final exporter = AutoExportDebugLogsTask();
    final sessionDirectory = await exporter._resolveSessionDirectory();
    await sessionDirectory.create(recursive: true);
    await exporter._exportSnapshotToDirectory(
      sessionDirectory: sessionDirectory,
      reason: reason,
    );
    return sessionDirectory;
  }

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    if (!ponyNotesDiagnosticBuildEnabled) {
      return;
    }

    final sessionRoot = await _resolveSessionDirectory();
    await sessionRoot.create(recursive: true);
    _sessionDirectory = sessionRoot;

    logDiagnosticMessage(
      'export.bootstrap',
      'sessionDir=${sessionRoot.path} label=$ponyNotesDiagnosticBuildLabel',
    );

    await _exportSnapshot(reason: 'startup');
    _exportTimer = Timer.periodic(
      _exportInterval,
      (_) => unawaited(_exportSnapshot(reason: 'periodic')),
    );
  }

  @override
  Future<void> dispose() async {
    _exportTimer?.cancel();
    if (ponyNotesDiagnosticBuildEnabled) {
      await _exportSnapshot(reason: 'dispose');
    }
    await super.dispose();
  }

  Future<Directory> _resolveSessionDirectory() async {
    final timestamp = _formatTimestamp(DateTime.now());
    final configuredDirectory = _resolveConfiguredExportRoot();
    if (configuredDirectory != null) {
      return Directory(
        p.join(
          configuredDirectory.path,
          'session-$timestamp',
        ),
      );
    }

    final desktopDirectory = _resolveDesktopDirectory();
    if (desktopDirectory != null) {
      return Directory(
        p.join(
          desktopDirectory.path,
          _sessionFolderName,
          'session-$timestamp',
        ),
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(
      p.join(
        supportDirectory.path,
        _sessionFolderName,
        'session-$timestamp',
      ),
    );
  }

  Directory? _resolveConfiguredExportRoot() {
    final candidates = <String>[
      ponyNotesDebugLogExportDir,
      Platform.environment['PONYNOTES_DEBUG_LOG_EXPORT_DIR'] ?? '',
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeConfiguredPath(candidate);
      if (normalized != null) {
        return Directory(normalized);
      }
    }

    return null;
  }

  String? _normalizeConfiguredPath(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    var expanded = _expandConfiguredPath(trimmed);
    if (expanded.startsWith('~')) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (home.isNotEmpty) {
        expanded = p.join(home, expanded.substring(1));
      }
    }

    return p.normalize(p.absolute(expanded));
  }

  String _expandConfiguredPath(String value) {
    var expanded = value;
    for (final entry in Platform.environment.entries) {
      expanded = expanded.replaceAll('%${entry.key}%', entry.value);
    }
    return expanded;
  }

  Directory? _resolveDesktopDirectory() {
    final candidates = <String?>[
      Platform.environment['USERPROFILE'] != null
          ? p.join(Platform.environment['USERPROFILE']!, 'Desktop')
          : null,
      Platform.environment['HOME'] != null
          ? p.join(Platform.environment['HOME']!, 'Desktop')
          : null,
    ];

    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) {
        continue;
      }

      final directory = Directory(candidate);
      if (directory.existsSync()) {
        return directory;
      }
    }

    return null;
  }

  Future<void> _exportSnapshot({required String reason}) async {
    final sessionDirectory = _sessionDirectory;
    if (sessionDirectory == null || _isExporting) {
      return;
    }

    _isExporting = true;
    final stopwatch = Stopwatch()..start();
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final dataDirectory = await appFlowyApplicationDataDirectory();
      await _exportSnapshotToDirectory(
        sessionDirectory: sessionDirectory,
        reason: reason,
        supportDirectory: supportDirectory,
        dataDirectory: dataDirectory,
      );
    } finally {
      _isExporting = false;
    }
  }

  Future<void> _exportSnapshotToDirectory({
    required Directory sessionDirectory,
    required String reason,
    Directory? supportDirectory,
    Directory? dataDirectory,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final resolvedSupportDirectory =
          supportDirectory ?? await getApplicationSupportDirectory();
      final resolvedDataDirectory =
          dataDirectory ?? await appFlowyApplicationDataDirectory();
      final candidates = <_DiagnosticExportCandidate>[
        ..._collectExportCandidates(
          rootDirectory: resolvedSupportDirectory,
          rootLabel: 'support',
        ),
        if (p.normalize(resolvedDataDirectory.path) !=
            p.normalize(resolvedSupportDirectory.path))
          ..._collectExportCandidates(
            rootDirectory: resolvedDataDirectory,
            rootLabel: 'data',
          ),
      ];
      final exportedFiles = <String>[];

      await sessionDirectory.create(recursive: true);

      for (final candidate in candidates) {
        final exported = await _copyDiagnosticFile(
          candidate: candidate,
          targetDirectory: sessionDirectory,
        );
        if (exported != null) {
          exportedFiles.add(exported);
        }
      }

      final windowPrefs = await _loadWindowPreferences(
        resolvedSupportDirectory,
        resolvedDataDirectory,
      );
      final syncTraceEnabled = await getSyncLogEnabled();
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final manifestSummary = <String, dynamic>{
        'reason': reason,
        'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'sessionDirectory': sessionDirectory.path,
        'supportDirectory': resolvedSupportDirectory.path,
        'dataDirectory': resolvedDataDirectory.path,
        'configuredExportDirectory': ponyNotesDebugLogExportDir,
        'environmentExportDirectory':
            Platform.environment['PONYNOTES_DEBUG_LOG_EXPORT_DIR'],
        'diagnosticBuildEnabled': ponyNotesDiagnosticBuildEnabled,
        'diagnosticBuildLabel': ponyNotesDiagnosticBuildLabel,
        'applicationVersion': ApplicationInfo.applicationVersion,
        'buildNumber': ApplicationInfo.buildNumber,
        'os': ApplicationInfo.os,
        'architecture': ApplicationInfo.architecture,
        'deviceId': ApplicationInfo.deviceId,
        'pid': pid,
        'resolvedExecutable': Platform.resolvedExecutable,
        'cloudBaseUrl': cloudEnv.appflowyCloudConfig.base_url,
        'authenticatorType': cloudEnv.authenticatorType.name,
        'syncTraceEnabled': syncTraceEnabled,
        'windowPreferences': windowPrefs,
        'exportedFiles': exportedFiles,
      };
      final moduleExports = await _buildModuleExports(
        sessionDirectory: sessionDirectory,
        exportedFiles: exportedFiles,
        manifestSummary: manifestSummary,
      );
      final manifest = <String, dynamic>{
        'manifestVersion': 2,
        ...manifestSummary,
        'moduleExports': moduleExports,
      };

      final manifestPath =
          p.join(sessionDirectory.path, 'session_manifest.json');
      await File(
        manifestPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

      logDiagnosticMessage(
        'export.snapshot',
        'reason=$reason durationMs=${stopwatch.elapsedMilliseconds} '
            'files=${exportedFiles.length} manifest=$manifestPath',
      );
    } catch (error, stackTrace) {
      Log.error(
        '[PonyNotesDiag][export.snapshot] failed: $error',
        error,
        stackTrace,
      );
    }
  }

  List<_DiagnosticExportCandidate> _collectExportCandidates({
    required Directory rootDirectory,
    required String rootLabel,
  }) {
    if (!rootDirectory.existsSync()) {
      return const [];
    }

    final fileNames = <String>{
      'shared_preferences.json',
      'window_manager.json',
    };
    final files = <_DiagnosticExportCandidate>[];

    for (final entity in rootDirectory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      final name = p.basename(entity.path);
      final isDiagnosticLog = name.startsWith('log.') ||
          name.startsWith('log.sync.') ||
          name.startsWith('LOG');
      final isKnownConfig = fileNames.contains(name);
      if (isDiagnosticLog || isKnownConfig) {
        final relativePath = p.relative(
          entity.path,
          from: rootDirectory.path,
        );
        files.add(
          _DiagnosticExportCandidate(
            source: entity,
            relativePath: p.join(rootLabel, relativePath),
          ),
        );
      }
    }

    return files;
  }

  Future<String?> _copyDiagnosticFile({
    required _DiagnosticExportCandidate candidate,
    required Directory targetDirectory,
  }) async {
    try {
      final source = candidate.source;
      if (!await source.exists()) {
        return null;
      }

      final relativePath = p.normalize(candidate.relativePath);
      final targetPath = p.join(targetDirectory.path, relativePath);
      final bytes = await source.readAsBytes();
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsBytes(bytes, flush: true);
      return relativePath;
    } catch (error) {
      Log.warn(
        '[PonyNotesDiag][export.copy] skip ${candidate.source.path}: $error',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadWindowPreferences(
    Directory supportDirectory,
    Directory dataDirectory,
  ) async {
    final sharedPreferencesCandidates = <String>[
      p.join(supportDirectory.path, 'shared_preferences.json'),
      p.join(dataDirectory.path, 'shared_preferences.json'),
    ];

    for (final candidate in sharedPreferencesCandidates) {
      final file = File(candidate);
      if (!await file.exists()) {
        continue;
      }

      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          return {
            'source': candidate,
            'flutter.windowMaximized': decoded['flutter.windowMaximized'],
            'flutter.windowPosition': decoded['flutter.windowPosition'],
            'flutter.windowSize': decoded['flutter.windowSize'],
          };
        }
      } catch (error) {
        Log.warn(
          '[PonyNotesDiag][export.windowPrefs] failed to parse $candidate: $error',
        );
      }
    }

    return const {};
  }

  Future<Map<String, dynamic>> _buildModuleExports({
    required Directory sessionDirectory,
    required List<String> exportedFiles,
    required Map<String, dynamic> manifestSummary,
  }) async {
    final moduleRootDirectory =
        Directory(p.join(sessionDirectory.path, _moduleLogsRootName));
    await moduleRootDirectory.create(recursive: true);

    final readmeRelativePath = await _writeModuleTextFile(
      sessionDirectory: sessionDirectory,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleReadmeFolderName,
        'README.txt',
      ),
      content: _buildModuleReadmeText(),
    );
    final exportedIndexRelativePath = await _writeModuleTextFile(
      sessionDirectory: sessionDirectory,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleRawIndexFolderName,
        'exported-files.txt',
      ),
      content: exportedFiles.join('\n'),
    );

    final appLogRelativePath = await _writeAggregatedModuleLog(
      sessionDirectory: sessionDirectory,
      exportedFiles: exportedFiles,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleGeneralFolderName,
        'app.log',
      ),
      matcher: (_, relativePath) => _isAppRuntimeLogRelativePath(relativePath),
    );
    final syncLogRelativePath = await _writeAggregatedModuleLog(
      sessionDirectory: sessionDirectory,
      exportedFiles: exportedFiles,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleGeneralFolderName,
        'sync.log',
      ),
      matcher: (_, relativePath) => _isSyncRuntimeLogRelativePath(relativePath),
    );
    final whiteboardLogRelativePath = await _writeAggregatedModuleLog(
      sessionDirectory: sessionDirectory,
      exportedFiles: exportedFiles,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleWhiteboardFolderName,
        'whiteboard.log',
      ),
      matcher: (line, _) => _matchesWhiteboardLogLine(line),
    );
    final tableLogRelativePath = await _writeAggregatedModuleLog(
      sessionDirectory: sessionDirectory,
      exportedFiles: exportedFiles,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleTableFolderName,
        'table.log',
      ),
      matcher: (line, _) => _matchesTableLogLine(line),
    );

    final manifestViewRelativePath = await _writeModuleJsonFile(
      sessionDirectory: sessionDirectory,
      relativePath: p.join(
        _moduleLogsRootName,
        _moduleEnvironmentFolderName,
        'manifest-view.json',
      ),
      json: {
        'applicationVersion': manifestSummary['applicationVersion'],
        'buildNumber': manifestSummary['buildNumber'],
        'os': manifestSummary['os'],
        'architecture': manifestSummary['architecture'],
        'deviceId': manifestSummary['deviceId'],
        'pid': manifestSummary['pid'],
        'reason': manifestSummary['reason'],
        'exportedAtUtc': manifestSummary['exportedAtUtc'],
        'diagnosticBuildEnabled': manifestSummary['diagnosticBuildEnabled'],
        'diagnosticBuildLabel': manifestSummary['diagnosticBuildLabel'],
        'syncTraceEnabled': manifestSummary['syncTraceEnabled'],
        'windowPreferences': manifestSummary['windowPreferences'],
        'rawLogCount': exportedFiles.length,
      },
    );

    final sharedPreferencesRelativePath = await _copyFirstMatchingExportedFile(
      sessionDirectory: sessionDirectory,
      exportedFiles: exportedFiles,
      sourceCandidates: const [
        'support/shared_preferences.json',
        'data/shared_preferences.json',
      ],
      destinationRelativePath: p.join(
        _moduleLogsRootName,
        _moduleEnvironmentFolderName,
        'shared_preferences.json',
      ),
    );

    return {
      'enabled': true,
      'root': _moduleLogsRootName,
      'artifacts': [
        readmeRelativePath,
        manifestViewRelativePath,
        if (sharedPreferencesRelativePath != null)
          sharedPreferencesRelativePath,
        if (appLogRelativePath != null) appLogRelativePath,
        if (syncLogRelativePath != null) syncLogRelativePath,
        if (whiteboardLogRelativePath != null) whiteboardLogRelativePath,
        if (tableLogRelativePath != null) tableLogRelativePath,
        exportedIndexRelativePath,
      ],
      'modules': [
        {
          'id': 'general',
          'label': '通用运行日志',
          'directory': p.join(_moduleLogsRootName, _moduleGeneralFolderName),
          'outputs': [
            if (appLogRelativePath != null) appLogRelativePath,
            if (syncLogRelativePath != null) syncLogRelativePath,
          ],
        },
        {
          'id': 'whiteboard',
          'label': '白板详细日志',
          'directory': p.join(_moduleLogsRootName, _moduleWhiteboardFolderName),
          'outputs': [
            if (whiteboardLogRelativePath != null) whiteboardLogRelativePath,
          ],
        },
        {
          'id': 'table',
          'label': '表格问题详细日志',
          'directory': p.join(_moduleLogsRootName, _moduleTableFolderName),
          'outputs': [
            if (tableLogRelativePath != null) tableLogRelativePath,
          ],
        },
      ],
      'rawFiles': exportedFiles,
    };
  }

  Future<String> _writeModuleTextFile({
    required Directory sessionDirectory,
    required String relativePath,
    required String content,
  }) async {
    final absolutePath = p.join(sessionDirectory.path, relativePath);
    await Directory(p.dirname(absolutePath)).create(recursive: true);
    await File(absolutePath).writeAsString(content, flush: true);
    return relativePath;
  }

  Future<String> _writeModuleJsonFile({
    required Directory sessionDirectory,
    required String relativePath,
    required Map<String, dynamic> json,
  }) async {
    return _writeModuleTextFile(
      sessionDirectory: sessionDirectory,
      relativePath: relativePath,
      content: const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  Future<String?> _writeAggregatedModuleLog({
    required Directory sessionDirectory,
    required List<String> exportedFiles,
    required String relativePath,
    required bool Function(String line, String relativePath) matcher,
  }) async {
    final buffer = <String>[];
    for (final exportedFile in exportedFiles) {
      final absolutePath = p.join(sessionDirectory.path, exportedFile);
      final sourceFile = File(absolutePath);
      if (!await sourceFile.exists() || !_looksLikeTextLogFile(exportedFile)) {
        continue;
      }

      final content = await _readTextLogFile(sourceFile);
      if (content == null || content.trim().isEmpty) {
        continue;
      }

      final matchingLines = const LineSplitter()
          .convert(content)
          .where((line) => matcher(line, exportedFile))
          .toList();
      if (matchingLines.isEmpty) {
        continue;
      }

      if (buffer.isNotEmpty) {
        buffer.add('');
      }
      buffer.add('===== $exportedFile =====');
      buffer.addAll(matchingLines);
    }

    if (buffer.isEmpty) {
      return null;
    }

    await _writeModuleTextFile(
      sessionDirectory: sessionDirectory,
      relativePath: relativePath,
      content: buffer.join('\n'),
    );
    return relativePath;
  }

  Future<String?> _copyFirstMatchingExportedFile({
    required Directory sessionDirectory,
    required List<String> exportedFiles,
    required List<String> sourceCandidates,
    required String destinationRelativePath,
  }) async {
    for (final candidate in sourceCandidates) {
      if (!exportedFiles.contains(candidate)) {
        continue;
      }

      final sourceFile = File(p.join(sessionDirectory.path, candidate));
      if (!await sourceFile.exists()) {
        continue;
      }

      final destinationPath =
          p.join(sessionDirectory.path, destinationRelativePath);
      await Directory(p.dirname(destinationPath)).create(recursive: true);
      await sourceFile.copy(destinationPath);
      return destinationRelativePath;
    }

    return null;
  }

  Future<String?> _readTextLogFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeTextLogFile(String relativePath) {
    final name = p.basename(relativePath).toLowerCase();
    return name.startsWith('log.') || name.startsWith('log.sync.');
  }

  bool _isAppRuntimeLogRelativePath(String relativePath) {
    final name = p.basename(relativePath).toLowerCase();
    return name.startsWith('log.') && !name.startsWith('log.sync.');
  }

  bool _isSyncRuntimeLogRelativePath(String relativePath) {
    final name = p.basename(relativePath).toLowerCase();
    return name.startsWith('log.sync.');
  }

  bool _matchesWhiteboardLogLine(String line) {
    if (ponyNotesDiagnosticModuleFromMessage(line) == 'whiteboard') {
      return true;
    }

    final lower = line.toLowerCase();
    return lower.contains('[whiteboard') ||
        lower.contains('excalidrawwebview') ||
        lower.contains('localassetserver') ||
        lower.contains('whiteboardcollabadapter') ||
        lower.contains('whiteboard.') ||
        lower.contains('assets/excalidraw/');
  }

  bool _matchesTableLogLine(String line) {
    if (ponyNotesDiagnosticModuleFromMessage(line) == 'table') {
      return true;
    }

    final lower = line.toLowerCase();
    return lower.contains('simple_table') ||
        lower.contains('gridrefresh') ||
        lower.contains('gridbloc') ||
        lower.contains('databasecontroller') ||
        lower.contains('rowmeta is null') ||
        lower.contains('cell_reload') ||
        lower.contains('grid_rows_changed') ||
        lower.contains('doc_rebuild_reason') ||
        lower.contains('table_');
  }

  String _buildModuleReadmeText() {
    return [
      '本目录是诊断日志的中文整理视图，不替代原始日志文件。',
      '原始日志仍保留在 session 根目录下的 data/ 和 support/ 中。',
      '02-通用运行日志：应用运行日志与同步日志的聚合视图。',
      '03-白板详细日志：筛出白板加载、WebView、资源服务、协作同步相关日志。',
      '04-表格问题详细日志：筛出 Grid、Database、Simple Table 相关日志。',
      '99-原始文件索引：列出本次导出的原始文件相对路径。',
    ].join('\n');
  }

  String _formatTimestamp(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}'
        '${twoDigits(value.month)}'
        '${twoDigits(value.day)}-'
        '${twoDigits(value.hour)}'
        '${twoDigits(value.minute)}'
        '${twoDigits(value.second)}';
  }
}

class _DiagnosticExportCandidate {
  const _DiagnosticExportCandidate({
    required this.source,
    required this.relativePath,
  });

  final File source;
  final String relativePath;
}
