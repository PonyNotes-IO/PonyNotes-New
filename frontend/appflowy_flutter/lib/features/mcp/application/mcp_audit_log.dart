import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次外部 Agent 的工具调用记录。
///
/// 只记工具名、目标 ID、耗时与成败，不记正文、Markdown 或 Token。
class McpAuditEntry {
  const McpAuditEntry({
    required this.at,
    required this.tool,
    required this.agent,
    required this.target,
    required this.isError,
    required this.durationMs,
  });

  factory McpAuditEntry.fromJson(Map<String, dynamic> json) {
    return McpAuditEntry(
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      tool: json['tool'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      target: json['target'] as String? ?? '',
      isError: json['isError'] as bool? ?? false,
      durationMs: json['durationMs'] as int? ?? 0,
    );
  }

  final DateTime at;
  final String tool;

  /// Agent 在 initialize 时上报的客户端名，例如 `Cursor`、`claude-ai`。
  final String agent;
  final String target;
  final bool isError;
  final int durationMs;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'tool': tool,
        'agent': agent,
        'target': target,
        'isError': isError,
        'durationMs': durationMs,
      };
}

/// 审计日志：内存环形缓冲 + 本地持久化，供设置页展示。
class McpAuditLog extends ChangeNotifier {
  McpAuditLog._();

  static final McpAuditLog instance = McpAuditLog._();

  static const int maxEntries = 200;
  static const String _prefsKey = 'mcp_audit_log';

  final List<McpAuditEntry> _entries = <McpAuditEntry>[];

  /// 最新在前。
  List<McpAuditEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(
          list.map((e) => McpAuditEntry.fromJson(e as Map<String, dynamic>)),
        );
      notifyListeners();
    } catch (e) {
      debugPrint('[MCP] audit log load failed: $e');
    }
  }

  /// 记录一次调用。内存里立即生效，落盘异步。
  void record(McpAuditEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
  }
}
