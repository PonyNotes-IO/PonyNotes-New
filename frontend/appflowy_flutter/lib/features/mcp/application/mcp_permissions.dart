import 'package:appflowy/features/mcp/application/mcp_tools.dart'
    show McpToolSpec, McpTools;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外部 Agent 工具白名单：保留旧工具选择，扩展工具需要显式启用。
///
/// 只作用于 MCP 通道：内部 AI 直接走 [McpTools.executeTool]，不受这里的开关影响。
class McpPermissions extends ChangeNotifier {
  McpPermissions._();

  static final McpPermissions instance = McpPermissions._();

  static const String _prefsKey = 'mcp_disabled_tools';
  static const String _enabledKey = 'mcp_enabled_extended_tools';
  static const Set<String> legacyTools = {
    'get_context',
    'list_workspaces',
    'list_pages',
    'get_page',
    'list_blocks',
    'query_database',
    'create_database_row',
    'update_database_cell',
    'delete_database_row',
    'create_database_field',
    'update_database_field',
    'delete_database_field',
    'search_notes',
    'get_backlinks',
    'get_workspace_links_graph',
    'reindex_page_links',
    'create_workspace',
    'open_workspace',
    'create_page',
    'rename_page',
    'move_page',
    'delete_page',
    'list_trash',
    'duplicate_page',
    'restore_page',
    'append_content',
    'insert_block',
    'update_block',
    'delete_block',
    'move_block',
    'insert_note_reference',
    'remove_note_reference',
    'get_reference_context',
    'open_note_reference',
    'get_note_graph',
    'open_note_graph',
  };

  final Set<String> _disabled = <String>{};
  final Set<String> _enabled = <String>{};

  Set<String> get disabledTools => Set.unmodifiable(_disabled);

  bool isAllowed(String tool) =>
      !_disabled.contains(tool) &&
      (legacyTools.contains(tool) || _enabled.contains(tool));

  McpPermissionPreset? presetFor(List<McpToolSpec> tools) {
    for (final preset in McpPermissionPreset.values) {
      if (tools.every((tool) => isAllowed(tool.name) == preset.allows(tool))) {
        return preset;
      }
    }
    return null;
  }

  Future<void> applyPreset(
    McpPermissionPreset preset,
    List<McpToolSpec> tools,
  ) async {
    _disabled
      ..clear()
      ..addAll(tools.where((tool) => !preset.allows(tool)).map((t) => t.name));
    _enabled
      ..clear()
      ..addAll(tools.where(preset.allows).map((t) => t.name));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _disabled.toList()..sort());
    await prefs.setStringList(_enabledKey, _enabled.toList()..sort());
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    _enabled
      ..clear()
      ..addAll(prefs.getStringList(_enabledKey) ?? const []);
    _disabled
      ..clear()
      ..addAll(stored);
    notifyListeners();
  }

  Future<void> setAllowed(String tool, bool allowed) async {
    final previous = isAllowed(tool);
    if (allowed) {
      _disabled.remove(tool);
      _enabled.add(tool);
    } else {
      _disabled.add(tool);
      _enabled.remove(tool);
    }
    final changed = previous != isAllowed(tool);
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _disabled.toList()..sort());
    await prefs.setStringList(_enabledKey, _enabled.toList()..sort());
  }

  Future<void> allowAll() async {
    _disabled.clear();
    _enabled.addAll(
      McpTools(endpoint: '', version: '').toolSpecs.map((tool) => tool.name),
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.setStringList(_enabledKey, _enabled.toList()..sort());
  }
}

enum McpPermissionPreset {
  readOnly,
  safeEdit,
  fullControl;

  bool allows(McpToolSpec tool) => switch (this) {
        readOnly => tool.readOnly,
        safeEdit => !tool.destructive,
        fullControl => true,
      };
}
