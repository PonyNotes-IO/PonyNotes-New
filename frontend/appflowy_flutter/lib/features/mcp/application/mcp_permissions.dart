import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外部 Agent 可使用的工具白名单（默认全开，只记录被关掉的工具）。
///
/// 只作用于 MCP 通道：内部 AI 直接走 [McpTools.executeTool]，不受这里的开关影响。
class McpPermissions extends ChangeNotifier {
  McpPermissions._();

  static final McpPermissions instance = McpPermissions._();

  static const String _prefsKey = 'mcp_disabled_tools';

  final Set<String> _disabled = <String>{};

  Set<String> get disabledTools => Set.unmodifiable(_disabled);

  bool isAllowed(String tool) => !_disabled.contains(tool);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    _disabled
      ..clear()
      ..addAll(stored);
    notifyListeners();
  }

  Future<void> setAllowed(String tool, bool allowed) async {
    final changed = allowed ? _disabled.remove(tool) : _disabled.add(tool);
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _disabled.toList()..sort());
  }

  Future<void> allowAll() async {
    if (_disabled.isEmpty) return;
    _disabled.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
