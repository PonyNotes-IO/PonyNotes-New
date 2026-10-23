import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/editor_transaction_adapter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart'
    hide quoteNode;
import 'package:appflowy/plugins/trash/application/trash_service.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/command_palette/search_service.dart';
import 'package:appflowy/workspace/application/permission/workspace_permission_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:appflowy/features/mcp/application/mcp_audit_log.dart';
import 'package:appflowy/features/mcp/application/mcp_permissions.dart';
import 'package:nanoid/nanoid.dart';
import 'package:uuid/uuid.dart';

/// 单个工具的定义：名称、描述、参数 schema 与处理函数。
///
/// MCP 传输层用它注册到 Server，内部 AI 用它构造 OpenAI `tools` 声明并执行。
class McpToolSpec {
  const McpToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.readOnly = false,
    this.destructive = false,
  });

  final String name;
  final String description;
  final JsonObject inputSchema;
  final bool readOnly;

  /// 破坏性写操作（移入回收站、删除块）。与其余可逆写操作区分开，
  /// 避免 MCP 侧对这类工具下发 `destructiveHint: false` 的错误暗示。
  final bool destructive;

  /// 处理函数。参数是原始 JSON 对象，返回值直接作为工具结果。
  final Future<CallToolResult> Function(Map<String, dynamic> args) handler;

  /// MCP 侧的提示语义。三种状态各自对应一种注解，与逐个注册时期的形态一致。
  ToolAnnotations get annotations => readOnly
      ? const ToolAnnotations(readOnlyHint: true)
      : destructive
          ? const ToolAnnotations()
          : const ToolAnnotations(destructiveHint: false);
}

/// MCP 工具注册与处理。所有工具复用客户端现有业务服务，只读工具不修改内容。
class McpTools {
  McpTools({
    required this.endpoint,
    required this.version,
    this.isAgentChannel = false,
    this.agentName,
  });

  final String endpoint;
  final String version;

  /// 是否为外部 Agent 通道（MCP Server）。为 true 时按权限表过滤工具，
  /// 并把每次调用写入审计日志；内部 AI 走 `executeTool`，不受权限开关限制。
  final bool isAgentChannel;

  /// 当前连接的 Agent 名称，来自 MCP initialize 上报的 clientInfo。
  final String Function()? agentName;

  static const int _defaultPageLimit = 100;
  static const int _defaultBlockLimit = 200;
  static const int _maxLimit = 500;
  static const int _maxTextChars = 20000;
  static const int _maxBlockChars = 2000;
  static const Duration _searchTimeout = Duration(seconds: 8);
  static const Duration _writeTimeout = Duration(seconds: 10);
  static const Duration _toolTimeout = Duration(seconds: 60);

  static const JsonObject _noArgsSchema =
      JsonObject(additionalProperties: false);

  static const JsonObject _listPagesSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'parent_id': JsonString(description: '父空间或父页面 ID；省略时列出工作区根级视图'),
      'limit': JsonInteger(
        description: '返回数量上限，默认 100，最大 500',
        minimum: 1,
        maximum: _maxLimit,
      ),
      'offset': JsonInteger(description: '跳过前 N 项，默认 0', minimum: 0),
    },
    required: ['workspace_id'],
    additionalProperties: false,
  );

  static const JsonObject _pageIdSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
    },
    required: ['workspace_id', 'page_id'],
    additionalProperties: false,
  );

  static const JsonObject _listBlocksSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
      'parent_block_id': JsonString(description: '父块 ID；省略时从页面根块开始'),
      'limit': JsonInteger(
        description: '返回数量上限，默认 200，最大 500',
        minimum: 1,
        maximum: _maxLimit,
      ),
      'offset': JsonInteger(description: '跳过前 N 项，默认 0', minimum: 0),
    },
    required: ['workspace_id', 'page_id'],
    additionalProperties: false,
  );

  static const JsonObject _searchSchema = JsonObject(
    properties: {
      'query': JsonString(description: '检索关键词'),
      'workspace_id': JsonString(description: '可选，限定到指定工作区'),
      'limit': JsonInteger(
        description: '返回数量上限，默认 20，最大 50',
        minimum: 1,
        maximum: 50,
      ),
    },
    required: ['query'],
    additionalProperties: false,
  );

  static const JsonObject _createWorkspaceSchema = JsonObject(
    properties: {
      'name': JsonString(description: '工作区名称'),
    },
    required: ['name'],
    additionalProperties: false,
  );

  static const JsonObject _openWorkspaceSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '要切换到的目标工作区 ID'),
    },
    required: ['workspace_id'],
    additionalProperties: false,
  );

  static const JsonObject _createPageSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'parent_id': JsonString(description: '父空间或父页面 ID'),
      'title': JsonString(description: '页面标题'),
      'markdown': JsonString(description: '可选，页面初始正文（Markdown）'),
    },
    required: ['workspace_id', 'parent_id', 'title'],
    additionalProperties: false,
  );

  static const JsonObject _renamePageSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
      'title': JsonString(description: '新的页面标题'),
    },
    required: ['workspace_id', 'page_id', 'title'],
    additionalProperties: false,
  );

  static const JsonObject _movePageSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '要移动的页面 ID'),
      'new_parent_id': JsonString(description: '新的父空间或父页面 ID'),
    },
    required: ['workspace_id', 'page_id', 'new_parent_id'],
    additionalProperties: false,
  );

  static const JsonObject _appendContentSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
      'markdown': JsonString(description: '要追加到页面末尾的 Markdown 内容'),
    },
    required: ['workspace_id', 'page_id', 'markdown'],
    additionalProperties: false,
  );

  static const JsonObject _insertBlockSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
      'parent_block_id': JsonString(description: '父块 ID；省略时插入到页面根块'),
      'after_block_id': JsonString(description: '插入到该块之后；省略时追加到父块末尾'),
      'block_type': JsonString(
        description: '块类型，见枚举；不同块类型使用对应可选字段',
        enumValues: [
          'paragraph',
          'heading1',
          'heading2',
          'heading3',
          'bulleted_list',
          'numbered_list',
          'todo_list',
          'quote',
          'divider',
          'toggle_list',
          'toggle_heading1',
          'toggle_heading2',
          'toggle_heading3',
          'code',
          'callout',
          'math_equation',
          'image',
          'video',
          'file',
          'gallery',
          'link_preview',
          'sub_page',
          'columns',
          'table',
          'grid',
          'board',
          'calendar',
          'date',
        ],
      ),
      'text': JsonString(description: '块文本；divider、image、video、file 忽略该字段'),
      'checked': JsonBoolean(description: 'todo_list 是否勾选，默认 false'),
      'collapsed': JsonBoolean(description: 'toggle 类块是否折叠，默认 false'),
      'language': JsonString(description: 'code 块语言，如 dart、python'),
      'icon': JsonString(description: 'callout 块图标 emoji，默认 📌'),
      'formula': JsonString(description: 'math_equation 的 LaTeX 公式；为空时使用 text'),
      'url': JsonString(description: 'image、video、file、link_preview 的资源地址（必填）'),
      'file_name': JsonString(description: 'file 块显示名称，可选'),
      'image_urls': JsonArray(
        items: JsonString(),
        description: 'gallery 的图片地址列表（必填）',
      ),
      'page_id_ref': JsonString(description: 'sub_page 指向的页面 ID（必填，会自动创建子页面）'),
      'column_count': JsonInteger(
        description: 'columns 的列数，默认 2，范围 2~4',
        minimum: 2,
        maximum: 4,
      ),
      'rows': JsonArray(
        items: JsonArray(items: JsonString()),
        description: 'table 的单元格文本，按行给出；每行列数需一致，首行作为表头',
      ),
      'header_row': JsonBoolean(description: 'table 是否启用表头行，暂不支持'),
      'database_id': JsonString(
        description: 'database_id 可以是数据库 ID 或数据库视图 ID；传入视图 ID 会自动解析',
      ),
      'date': JsonString(
        description: 'date 的日期（ISO 8601）；省略时使用当前时间',
      ),
      'include_time': JsonBoolean(description: 'date 是否带时间，默认 false'),
      'reminder': JsonString(
        description: 'date 的提醒时间；省略表示不创建提醒',
        enumValues: [
          'at_time_of_event',
          'five_mins_before',
          'ten_mins_before',
          'fifteen_mins_before',
          'thirty_mins_before',
          'one_hour_before',
          'two_hours_before',
          'on_day_of_event',
          'one_day_before',
          'two_days_before',
          'one_week_before',
          'custom',
        ],
      ),
      'reminder_minutes': JsonInteger(
        description: 'reminder=custom 时提前的分钟数，默认 30',
        minimum: 1,
        maximum: 60 * 24 * 30,
      ),
    },
    required: ['workspace_id', 'page_id', 'block_type'],
    additionalProperties: false,
  );

  static const JsonObject _updateBlockSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
      'block_id': JsonString(description: '要更新的块 ID'),
      'text': JsonString(description: '新的块文本，空字符串表示清空'),
      'checked': JsonBoolean(description: 'todo_list 新的勾选状态，可选'),
      'collapsed': JsonBoolean(description: 'toggle 类块新的折叠状态，可选'),
    },
    required: ['workspace_id', 'page_id', 'block_id', 'text'],
    additionalProperties: false,
  );

  static const JsonObject _deleteBlockSchema = JsonObject(
    properties: {
      'workspace_id': JsonString(description: '工作区 ID，必须是客户端当前工作区'),
      'page_id': JsonString(description: '页面 ID'),
      'block_id': JsonString(description: '要删除的块 ID，会同时删除其所有子块'),
    },
    required: ['workspace_id', 'page_id', 'block_id'],
    additionalProperties: false,
  );

  /// 工具注册表：MCP 传输层与内部 AI 共用同一份定义与处理函数。
  ///
  /// 内部 AI 通过 [executeTool] 调用，不经过 MCP 协议，但走完全相同的业务逻辑，
  /// 避免两套入口各自实现笔记操作。
  List<McpToolSpec> get toolSpecs => _toolSpecs;

  /// 17 个工具的唯一来源。新增工具只需在此追加一条，MCP 与内部 AI 同时生效。
  late final List<McpToolSpec> _toolSpecs = [
    McpToolSpec(
      name: 'get_context',
      description: '返回当前登录账号标识、当前工作区和客户端状态，不返回登录凭据。',
      inputSchema: _noArgsSchema,
      readOnly: true,
      handler: (_) => _getContext(),
    ),
    McpToolSpec(
      name: 'list_workspaces',
      description: '列出当前账号可访问的工作区，包含 ID、名称、类型和当前工作区标记。',
      inputSchema: _noArgsSchema,
      readOnly: true,
      handler: (_) => _listWorkspaces(),
    ),
    McpToolSpec(
      name: 'list_pages',
      description: '列出当前工作区中指定父级下的直接子视图（空间、页面或数据库）。'
          '省略 parent_id 时返回工作区根级视图；用返回的 page_id 继续向下展开。',
      inputSchema: _listPagesSchema,
      readOnly: true,
      handler: _listPages,
    ),
    McpToolSpec(
      name: 'get_page',
      description: '读取文档页面的元信息、正文文本和可定位的内容块 ID。'
          '非文档页面只返回元信息并标记 content_supported=false。',
      inputSchema: _pageIdSchema,
      readOnly: true,
      handler: _getPage,
    ),
    McpToolSpec(
      name: 'list_blocks',
      description: '按深度优先顺序读取页面或父块下的结构化内容块，包含块 ID、类型、文本、父块和层级。',
      inputSchema: _listBlocksSchema,
      readOnly: true,
      handler: _listBlocks,
    ),
    McpToolSpec(
      name: 'search_notes',
      description: '检索笔记，返回页面 ID、标题、命中摘要和工作区。'
          '结果有数量上限和超时；complete=false 表示检索未在超时前结束。',
      inputSchema: _searchSchema,
      readOnly: true,
      handler: _searchNotes,
    ),
    McpToolSpec(
      name: 'create_workspace',
      description: '按名称创建一个与当前工作区同类型的工作区，返回新工作区 ID；不会自动切换。',
      inputSchema: _createWorkspaceSchema,
      handler: _createWorkspace,
    ),
    McpToolSpec(
      name: 'open_workspace',
      description: '切换客户端当前工作区。该操作会改变用户界面上下文，成功后在返回结果中给出实际上下文。',
      inputSchema: _openWorkspaceSchema,
      handler: _openWorkspace,
    ),
    McpToolSpec(
      name: 'create_page',
      description: '在指定空间或页面下创建文档页面，可选携带初始 Markdown 内容；不会自动打开页面。',
      inputSchema: _createPageSchema,
      handler: _createPage,
    ),
    McpToolSpec(
      name: 'rename_page',
      description: '修改页面标题。',
      inputSchema: _renamePageSchema,
      handler: _renamePage,
    ),
    McpToolSpec(
      name: 'move_page',
      description: '将页面移动到另一个空间或页面下，会检查目标层级是否合法并拒绝形成循环。',
      inputSchema: _movePageSchema,
      handler: _movePage,
    ),
    McpToolSpec(
      name: 'delete_page',
      description: '将页面移入回收站（不永久删除）。',
      inputSchema: _pageIdSchema,
      destructive: true,
      handler: _deletePage,
    ),
    McpToolSpec(
      name: 'restore_page',
      description: '从回收站恢复页面。',
      inputSchema: _pageIdSchema,
      handler: _restorePage,
    ),
    McpToolSpec(
      name: 'append_content',
      description: '将 Markdown 内容追加到文档页面末尾，返回新增块的 ID。',
      inputSchema: _appendContentSchema,
      handler: _appendContent,
    ),
    McpToolSpec(
      name: 'insert_block',
      description: '在指定父块下插入一个内容块，可指定插入到某个块之后。',
      inputSchema: _insertBlockSchema,
      handler: _insertBlock,
    ),
    McpToolSpec(
      name: 'update_block',
      description: '按块 ID 替换文本块的文本内容；不支持修改块类型。',
      inputSchema: _updateBlockSchema,
      handler: _updateBlock,
    ),
    McpToolSpec(
      name: 'delete_block',
      description: '删除指定块及其所有子块。',
      inputSchema: _deleteBlockSchema,
      destructive: true,
      handler: _deleteBlock,
    ),
  ];

  /// 按名称执行工具，内部 AI 使用。未知工具名返回带 isError 的结果，不抛异常。
  Future<CallToolResult> executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final spec = toolSpecs.where((s) => s.name == name).firstOrNull;
    if (spec == null) {
      return _error('unknown_tool', '未知工具：$name');
    }
    return _instrument(name, args, spec.handler);
  }

  /// 把 [toolSpecs] 注册到 MCP Server。新增工具只改 [toolSpecs]，
  /// 这里不需要再逐条登记，避免两处定义漂移。
  ///
  /// Agent 通道会跳过被用户关掉的工具：不对外声明，Agent 也就看不到。
  void registerAll(McpServer server) {
    for (final spec in toolSpecs) {
      if (isAgentChannel && !McpPermissions.instance.isAllowed(spec.name)) {
        continue;
      }
      server.registerTool(
        spec.name,
        description: spec.description,
        inputSchema: spec.inputSchema,
        annotations: spec.annotations,
        callback: (args, extra) => _instrument(spec.name, args, spec.handler),
      );
    }
  }

  /// 记录工具名、目标 ID、耗时和结果；不记录正文、Markdown 或 Token。
  Future<CallToolResult> _instrument(
    String name,
    Map<String, dynamic> args,
    Future<CallToolResult> Function(Map<String, dynamic> args) handler,
  ) async {
    final stopwatch = Stopwatch()..start();
    final target = _targetIds(args);
    try {
      final result = await handler(args).timeout(_toolTimeout);
      Log.info(
        '[MCP] tool=$name target=[$target] ok=${!result.isError} '
        'ms=${stopwatch.elapsedMilliseconds}',
      );
      _recordAudit(name, target, result.isError, stopwatch);
      return result;
    } on TimeoutException {
      Log.error('[MCP] tool=$name target=[$target] timeout');
      _recordAudit(name, target, true, stopwatch);
      return _error('tool_timeout', '工具执行超时，请稍后查询确认结果，不要直接重试写入。');
    } catch (e, st) {
      Log.error(
        '[MCP] tool=$name target=[$target] error=$e ms=${stopwatch.elapsedMilliseconds}\n$st',
      );
      _recordAudit(name, target, true, stopwatch);
      return _error('internal', '工具执行异常：$e');
    }
  }

  /// 只给外部 Agent 通道写审计，内部 AI 的调用不进 Agent 日志。
  void _recordAudit(
    String tool,
    String target,
    bool isError,
    Stopwatch stopwatch,
  ) {
    if (!isAgentChannel) return;
    McpAuditLog.instance.record(
      McpAuditEntry(
        at: DateTime.now(),
        tool: tool,
        agent: _resolveAgentName(),
        target: target,
        isError: isError,
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  String _resolveAgentName() {
    final name = agentName?.call().trim() ?? '';
    return name.isEmpty ? '未识别客户端' : name;
  }

  String _targetIds(Map<String, dynamic> args) {
    const keys = [
      'workspace_id',
      'page_id',
      'parent_id',
      'new_parent_id',
      'parent_block_id',
      'block_id',
    ];
    final parts = <String>[];
    for (final key in keys) {
      final value = args[key];
      if (value is String && value.isNotEmpty) {
        parts.add('$key=$value');
      }
    }
    return parts.join(',');
  }

  Future<CallToolResult> _getContext() async {
    final profile = await _currentProfile();
    if (profile == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    final workspace = await _currentWorkspace();
    return _ok({
      'user': {
        'id': profile.id.toString(),
        'name': profile.name,
        'email': profile.email,
      },
      'current_workspace': workspace == null
          ? null
          : {'workspace_id': workspace.id, 'name': workspace.name},
      'server': {'endpoint': endpoint, 'version': version},
    });
  }

  Future<CallToolResult> _listWorkspaces() async {
    final profile = await _currentProfile();
    if (profile == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    final result = await UserBackendService(userId: profile.id).getWorkspaces();
    final workspaces = result.fold((items) => items, (error) {
      Log.error('[MCP] list_workspaces failed: $error');
      return null;
    });
    if (workspaces == null) {
      return _error('internal', '读取工作区列表失败。');
    }
    final current = await _currentWorkspace();
    return _ok({
      'workspaces': workspaces.take(100).map((workspace) {
        return {
          'workspace_id': workspace.workspaceId,
          'name': workspace.name,
          'type': workspace.workspaceType.name,
          'is_current': workspace.workspaceId == current?.id,
        };
      }).toList(),
    });
  }

  Future<CallToolResult> _listPages(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id');
    if (workspaceId == null || workspaceId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id。');
    }
    final contextError = await _validateWorkspace(workspaceId);
    if (contextError != null) return contextError;

    final parentId = _stringArg(args, 'parent_id')?.trim() ?? '';
    final limit = _intArg(args, 'limit', _defaultPageLimit, 1, _maxLimit);
    final offset = _intArg(args, 'offset', 0, 0, 1 << 30);
    final effectiveParent = parentId.isEmpty ? workspaceId : parentId;

    if (effectiveParent != workspaceId) {
      final parent = await _view(effectiveParent);
      if (parent == null) {
        return _error('not_found', '父页面不存在或无权访问。');
      }
      if (parent.workspaceId.isNotEmpty && parent.workspaceId != workspaceId) {
        return _error('workspace_mismatch', '父页面不属于指定工作区。');
      }
    }

    final result =
        await ViewBackendService.getChildViews(viewId: effectiveParent);
    final views = result.fold((views) => views, (error) {
      Log.error('[MCP] list_pages failed: $error');
      return null;
    });
    if (views == null) {
      return _error('not_found', '无法读取该父级下的页面。');
    }

    final page = views.skip(offset).take(limit).map(_viewToJson).toList();
    return _ok({
      'workspace_id': workspaceId,
      'parent_id': effectiveParent,
      'pages': page,
      'total': views.length,
      'has_more': offset + page.length < views.length,
    });
  }

  Future<CallToolResult> _getPage(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id');
    final pageId = _stringArg(args, 'page_id');
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        pageId == null ||
        pageId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id 或 page_id。');
    }
    final contextError = await _validateWorkspace(workspaceId);
    if (contextError != null) return contextError;

    final view = await _view(pageId);
    if (view == null) {
      return _error('not_found', '页面不存在或无权访问。');
    }
    if (view.workspaceId.isNotEmpty && view.workspaceId != workspaceId) {
      return _error('workspace_mismatch', '页面不属于指定工作区。');
    }
    if (view.isSpace || view.layout != ViewLayoutPB.Document) {
      return _ok({
        'page': _viewToJson(view),
        'content_supported': false,
        'reason': view.isSpace ? '空间是页面容器，不提供正文' : '仅文档页面支持读取正文',
        'text': '',
        'blocks': <Map<String, dynamic>>[],
      });
    }

    final data = await _readDocument(pageId, workspaceId);
    if (data == null) {
      return _error('document_unavailable', '无法读取页面正文，文档可能尚未同步到本机。');
    }
    final document = data.toDocument();
    if (document == null) {
      return _error('document_unavailable', '无法解析页面正文。');
    }
    final blocks = _flattenDocument(document.root);
    final text = blocks
        .map((block) => block.text)
        .where((text) => text.isNotEmpty)
        .join('\n');
    final truncated = text.length > _maxTextChars;
    return _ok({
      'page': _viewToJson(view),
      'content_supported': true,
      'text': truncated ? text.substring(0, _maxTextChars) : text,
      'text_truncated': truncated,
      'blocks': blocks.take(_defaultPageLimit).map(_blockToJson).toList(),
      'block_count': blocks.length,
      'blocks_truncated': blocks.length > _defaultPageLimit,
    });
  }

  Future<CallToolResult> _listBlocks(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id');
    final pageId = _stringArg(args, 'page_id');
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        pageId == null ||
        pageId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id 或 page_id。');
    }
    final contextError = await _validateWorkspace(workspaceId);
    if (contextError != null) return contextError;

    final view = await _view(pageId);
    if (view == null) {
      return _error('not_found', '页面不存在或无权访问。');
    }
    if (view.workspaceId.isNotEmpty && view.workspaceId != workspaceId) {
      return _error('workspace_mismatch', '页面不属于指定工作区。');
    }
    if (view.isSpace || view.layout != ViewLayoutPB.Document) {
      return _error('unsupported_layout', '仅文档页面支持读取内容块。');
    }

    final data = await _readDocument(pageId, workspaceId);
    if (data == null) {
      return _error('document_unavailable', '无法读取页面正文，文档可能尚未同步到本机。');
    }
    final document = data.toDocument();
    if (document == null) {
      return _error('document_unavailable', '无法解析页面正文。');
    }
    final parentBlockId = _stringArg(args, 'parent_block_id')?.trim() ?? '';
    final start = parentBlockId.isEmpty || parentBlockId == pageId
        ? document.root
        : _findNode(document, parentBlockId);
    if (start == null) {
      return _error('not_found', '父块不存在。');
    }

    final limit = _intArg(args, 'limit', _defaultBlockLimit, 1, _maxLimit);
    final offset = _intArg(args, 'offset', 0, 0, 1 << 30);
    final blocks = _flattenDocument(start);
    final page = blocks.skip(offset).take(limit).map(_blockToJson).toList();
    return _ok({
      'page_id': pageId,
      'parent_block_id': parentBlockId.isEmpty ? null : parentBlockId,
      'blocks': page,
      'total': blocks.length,
      'has_more': offset + page.length < blocks.length,
    });
  }

  Future<CallToolResult> _searchNotes(Map<String, dynamic> args) async {
    final query = _stringArg(args, 'query')?.trim();
    if (query == null || query.isEmpty) {
      return _error('invalid_params', '缺少 query。');
    }
    if (await _currentProfile() == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    if (workspaceId.isNotEmpty) {
      final contextError = await _validateWorkspace(workspaceId);
      if (contextError != null) return contextError;
    }
    final limit = _intArg(args, 'limit', 20, 1, 50);

    final searchResult =
        await SearchBackendService.performSearch(query, limit: limit * 3);
    final stream = searchResult.fold((stream) => stream, (error) {
      Log.error('[MCP] search_notes failed: $error');
      return null;
    });
    if (stream == null) {
      return _error('internal', '启动检索失败。');
    }

    final items = <String, Map<String, dynamic>>{};
    final finished = Completer<void>();
    stream.listen(
      onServerItems: (serverItems, _, __, ___) {
        for (final item in serverItems) {
          if (item.id.isEmpty) continue;
          items[item.id] = _serverSearchItem(item);
        }
      },
      onSummaries: null,
      onLocalItems: (localItems, _) {
        for (final item in localItems) {
          if (item.id.isEmpty) continue;
          items.putIfAbsent(item.id, () => _localSearchItem(item));
        }
      },
      onFinished: (_) {
        if (!finished.isCompleted) finished.complete();
      },
    );

    var complete = true;
    try {
      await finished.future.timeout(_searchTimeout);
    } on TimeoutException {
      complete = false;
    } finally {
      await stream.dispose();
    }

    final results = items.values
        .where(
          (item) =>
              workspaceId.isEmpty ||
              (item['workspace_id'] as String).isEmpty ||
              item['workspace_id'] == workspaceId,
        )
        .take(limit)
        .toList();
    return _ok({'query': query, 'complete': complete, 'results': results});
  }

  Map<String, dynamic> _serverSearchItem(SearchResponseItemPB item) {
    return {
      'page_id': item.id,
      'title': item.displayName,
      'snippet': item.content,
      'workspace_id': item.workspaceId,
    };
  }

  Map<String, dynamic> _localSearchItem(LocalSearchResponseItemPB item) {
    return {
      'page_id': item.id,
      'title': item.displayName,
      'snippet': null,
      'workspace_id': item.workspaceId,
    };
  }

  Future<CallToolResult> _createWorkspace(Map<String, dynamic> args) async {
    final name = _stringArg(args, 'name')?.trim() ?? '';
    if (name.isEmpty) {
      return _error('invalid_params', '缺少 name。');
    }
    final profile = await _currentProfile();
    if (profile == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    final result = await UserBackendService(userId: profile.id)
        .createUserWorkspace(name, profile.workspaceType);
    FlowyError? failure;
    final workspace = result.fold((workspace) => workspace, (error) {
      failure = error;
      return null;
    });
    if (workspace == null) {
      return _error('internal', '创建工作区失败：${failure?.msg ?? '未知错误'}');
    }
    return _ok({
      'workspace_id': workspace.workspaceId,
      'name': workspace.name,
      'type': workspace.workspaceType.name,
      'is_current': false,
    });
  }

  Future<CallToolResult> _openWorkspace(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    if (workspaceId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id。');
    }
    final profile = await _currentProfile();
    if (profile == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    final target = await _workspaceById(profile, workspaceId);
    if (target == null) {
      return _error('not_found', '工作区不存在或无权访问。');
    }
    final current = await _currentWorkspace();
    if (current?.id == workspaceId) {
      return _ok({
        'workspace_id': current!.id,
        'name': current.name,
        'type': target.workspaceType.name,
        'switched': false,
      });
    }

    final result = await UserBackendService(userId: profile.id)
        .openWorkspace(workspaceId, target.workspaceType);
    FlowyError? failure;
    final opened = result.fold((_) => true, (error) {
      failure = error;
      return false;
    });
    if (!opened) {
      return _error('internal', '切换工作区失败：${failure?.msg ?? '未知错误'}');
    }
    final after = await _currentWorkspace();
    if (after?.id != workspaceId) {
      return _error('write_unconfirmed', '切换未生效，请用 get_context 确认当前工作区。');
    }
    return _ok({
      'workspace_id': after!.id,
      'name': after.name,
      'type': target.workspaceType.name,
      'switched': true,
    });
  }

  Future<CallToolResult> _createPage(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final parentId = _stringArg(args, 'parent_id')?.trim() ?? '';
    final title = _stringArg(args, 'title')?.trim() ?? '';
    if (workspaceId.isEmpty || parentId.isEmpty || title.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id、parent_id 或 title。');
    }
    final accessError = await _requireWriteAccess(workspaceId);
    if (accessError != null) return accessError;

    final parent = await _view(parentId);
    if (parent == null) {
      return _error('not_found', '父页面不存在或无权访问。');
    }
    if (parent.workspaceId.isNotEmpty && parent.workspaceId != workspaceId) {
      return _error('workspace_mismatch', '父页面不属于指定工作区。');
    }
    if (!parent.isSpace && parent.layout != ViewLayoutPB.Document) {
      return _error('invalid_parent', '父级必须是空间或文档页面。');
    }

    List<int>? initialBytes;
    String? viewId;
    final markdown = _stringArg(args, 'markdown');
    if (markdown != null && markdown.trim().isNotEmpty) {
      viewId = const Uuid().v4();
      final document = customMarkdownToDocument(markdown, tableWidth: 250.0);
      final data = DocumentDataPBFromTo.fromDocument(document);
      if (data == null) {
        return _error('internal', 'Markdown 转换失败。');
      }
      // 让初始文档的根块 ID 与新页面 ID 一致，避免根块 ID 是随机 nanoid
      _rebindDocumentRoot(data, viewId);
      initialBytes = data.writeToBuffer();
    }

    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentId,
      name: title,
      openAfterCreate: false,
      initialDataBytes: initialBytes,
      viewId: viewId,
    );
    FlowyError? failure;
    final view = result.fold((view) => view, (error) {
      failure = error;
      return null;
    });
    if (view == null) {
      return _error('internal', '创建页面失败：${failure?.msg ?? '未知错误'}');
    }
    final confirmed = await _view(view.id);
    if (confirmed == null) {
      return _error('write_unconfirmed', '页面已提交创建但未能确认；请用 list_pages 查询。');
    }
    return _ok({
      'page': _viewToJson(confirmed),
      'content_included': initialBytes != null,
    });
  }

  Future<CallToolResult> _renamePage(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    final title = _stringArg(args, 'title')?.trim() ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty || title.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id、page_id 或 title。');
    }
    final accessError = await _requireWriteAccess(workspaceId);
    if (accessError != null) return accessError;
    final view = await _view(pageId);
    if (view == null) {
      return _error('not_found', '页面不存在或无权访问。');
    }
    if (view.workspaceId.isNotEmpty && view.workspaceId != workspaceId) {
      return _error('workspace_mismatch', '页面不属于指定工作区。');
    }
    if (view.isLocked) {
      return _error('page_locked', '页面已锁定，无法修改。');
    }

    final result = await ViewBackendService.updateView(
      viewId: pageId,
      name: title,
    );
    FlowyError? failure;
    final renamed = result.fold((_) => true, (error) {
      failure = error;
      return false;
    });
    if (!renamed) {
      return _error('internal', '重命名失败：${failure?.msg ?? '未知错误'}');
    }
    // 该事件不返回更新后的视图，重新读取确认
    final confirmed = await _view(pageId);
    if (confirmed == null || confirmed.name != title) {
      return _error('write_unconfirmed', '重命名已提交但未能确认；请用 list_pages 查询。');
    }
    return _ok({'page': _viewToJson(confirmed)});
  }

  Future<CallToolResult> _movePage(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    final newParentId = _stringArg(args, 'new_parent_id')?.trim() ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty || newParentId.isEmpty) {
      return _error(
        'invalid_params',
        '缺少 workspace_id、page_id 或 new_parent_id。',
      );
    }
    final accessError = await _requireWriteAccess(workspaceId);
    if (accessError != null) return accessError;

    final page = await _view(pageId);
    final target = await _view(newParentId);
    if (page == null || target == null) {
      return _error('not_found', '页面或目标父级不存在、无权访问。');
    }
    for (final view in [page, target]) {
      if (view.workspaceId.isNotEmpty && view.workspaceId != workspaceId) {
        return _error('workspace_mismatch', '页面或目标父级不属于指定工作区。');
      }
    }
    if (page.isSpace) {
      return _error('unsupported', '空间不支持通过 MCP 移动。');
    }
    if (page.isLocked) {
      return _error('page_locked', '页面已锁定，无法移动。');
    }
    if (!target.isSpace && target.layout != ViewLayoutPB.Document) {
      return _error('invalid_parent', '目标父级必须是空间或文档页面。');
    }
    if (target.id == page.id) {
      return _error('invalid_params', '不能把页面移动到自身下面。');
    }
    final ancestors = await ViewBackendService.getViewAncestors(target.id);
    final ancestorsList = ancestors.fold((items) => items, (_) => null);
    if (ancestorsList != null &&
        ancestorsList.items.any((view) => view.id == pageId)) {
      return _error('invalid_params', '不能把页面移动到它自己的子页面下。');
    }

    final result = await ViewBackendService.moveViewV2(
      viewId: pageId,
      newParentId: newParentId,
      prevViewId: null,
    );
    FlowyError? failure;
    final moved = result.fold((_) => true, (error) {
      failure = error;
      return false;
    });
    if (!moved) {
      return _error('internal', '移动失败：${failure?.msg ?? '未知错误'}');
    }
    final after = await _view(pageId);
    if (after?.parentViewId != newParentId) {
      return _error('write_unconfirmed', '移动已提交但未能确认；请用 list_pages 查询。');
    }
    return _ok({'page': _viewToJson(after!), 'new_parent_id': newParentId});
  }

  Future<CallToolResult> _deletePage(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id 或 page_id。');
    }
    final accessError = await _requireWriteAccess(workspaceId);
    if (accessError != null) return accessError;
    final view = await _view(pageId);
    if (view == null) {
      return _error('not_found', '页面不存在或无权访问。');
    }
    if (view.workspaceId.isNotEmpty && view.workspaceId != workspaceId) {
      return _error('workspace_mismatch', '页面不属于指定工作区。');
    }
    if (view.isSpace) {
      return _error('unsupported', '空间不支持通过 MCP 删除。');
    }
    if (view.isLocked) {
      return _error('page_locked', '页面已锁定，无法删除。');
    }

    await ViewBackendService.deleteView(viewId: pageId);
    final trashed = await _findTrashItem(pageId);
    if (trashed == null) {
      return _error('write_unconfirmed', '删除已提交但未能确认；请用 list_pages 查询。');
    }
    return _ok({
      'page_id': pageId,
      'title': view.name,
      'trashed': true,
    });
  }

  Future<CallToolResult> _restorePage(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id 或 page_id。');
    }
    final accessError = await _requireWriteAccess(workspaceId);
    if (accessError != null) return accessError;

    final trashed = await _findTrashItem(pageId);
    if (trashed == null) {
      return _error('not_found', '该页面不在回收站中。');
    }
    final result = await TrashService.putback(pageId);
    FlowyError? failure;
    final restored = result.fold((_) => true, (error) {
      failure = error;
      return false;
    });
    if (!restored) {
      return _error('internal', '恢复失败：${failure?.msg ?? '未知错误'}');
    }
    final stillTrashed = await _findTrashItem(pageId);
    if (stillTrashed != null) {
      return _error('write_unconfirmed', '恢复已提交但未能确认；请再次查询回收站。');
    }
    return _ok({'page_id': pageId, 'title': trashed.name, 'restored': true});
  }

  Future<CallToolResult> _appendContent(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    final markdown = _stringArg(args, 'markdown') ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty || markdown.trim().isEmpty) {
      return _error('invalid_params', '缺少 workspace_id、page_id 或 markdown。');
    }
    final pageError = await _requireWritableDocument(workspaceId, pageId);
    if (pageError != null) return pageError;

    final state = await _loadEditorState(pageId, workspaceId);
    if (state == null) {
      return _error('document_unavailable', '无法读取页面正文，文档可能尚未同步到本机。');
    }
    final content = customMarkdownToDocument(markdown, tableWidth: 250.0);
    final contentNodes = content.root.children.toList();
    if (contentNodes.isEmpty) {
      state.dispose();
      return _error('invalid_params', 'Markdown 未解析出任何内容。');
    }

    final root = state.document.root;
    final last = root.children.isEmpty ? null : root.children.last;
    final lastIsEmpty =
        last != null && last.children.isEmpty && (last.delta?.isEmpty ?? true);
    final nodes = <Node>[
      if (last != null && !lastIsEmpty) paragraphNode(),
      ...contentNodes,
      paragraphNode(),
    ];
    final leadingSeparator = last != null && !lastIsEmpty ? 1 : 0;
    final path = last == null ? const [0] : last.path.next;
    final transaction = state.transaction..insertNodes(path, nodes);
    // insertNodes 会深拷贝节点并生成新 ID，必须从操作中取实际写入的块 ID
    final insertedNodes = transaction.operations
        .whereType<InsertOperation>()
        .expand((operation) => operation.nodes)
        .skip(leadingSeparator)
        .take(contentNodes.length)
        .map((node) => node.id)
        .toList();

    try {
      final error = await _persistDocument(
        pageId: pageId,
        workspaceId: workspaceId,
        state: state,
        transaction: transaction,
        verify: (document) =>
            insertedNodes.every((id) => document.blocks.containsKey(id)),
      );
      if (error != null) return error;
    } finally {
      state.dispose();
    }
    return _ok({
      'page_id': pageId,
      'appended_block_ids': insertedNodes,
      'appended_count': insertedNodes.length,
    });
  }

  Future<CallToolResult> _insertBlock(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    final blockType = _stringArg(args, 'block_type')?.trim() ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty || blockType.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id、page_id 或 block_type。');
    }
    String? subPageViewId;
    if (blockType == 'sub_page') {
      // 子页面块需要真实的视图，先在当前页面下创建子页面
      final subPageError = await _requireWriteAccess(workspaceId);
      if (subPageError != null) return subPageError;
      final title = _stringArg(args, 'text')?.trim() ?? '';
      if (title.isEmpty) {
        return _error('invalid_params', 'sub_page 需要通过 text 提供子页面标题。');
      }
      final created = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: pageId,
        name: title,
        openAfterCreate: false,
      );
      FlowyError? failure;
      subPageViewId = created.fold((view) => view.id, (error) {
        failure = error;
        return null;
      });
      if (subPageViewId == null) {
        return _error('internal', '创建子页面失败：${failure?.msg ?? '未知错误'}');
      }
      args = {...args, 'page_id_ref': subPageViewId};
    }
    String? databaseViewId;
    String? databaseId;
    if (const {'grid', 'board', 'calendar'}.contains(blockType)) {
      final databaseError = await _requireWriteAccess(workspaceId);
      if (databaseError != null) return databaseError;
      final layout = switch (blockType) {
        'grid' => ViewLayoutPB.Grid,
        'board' => ViewLayoutPB.Board,
        _ => ViewLayoutPB.Calendar,
      };
      // database_id 兼容数据库 ID 或数据库视图 ID
      final databaseRef = _stringArg(args, 'database_id')?.trim() ?? '';
      databaseId =
          databaseRef.isEmpty ? null : await _resolveDatabaseId(databaseRef);
      if (databaseId != null) {
        // 引用已有数据库：在页面下建一个关联该数据库的视图
        final name = _stringArg(args, 'text')?.trim() ?? '';
        final reference = await ViewBackendService.createDatabaseLinkedView(
          parentViewId: pageId,
          databaseId: databaseId,
          layoutType: layout,
          name: name.isNotEmpty ? name : blockType,
        );
        FlowyError? failure;
        databaseViewId = reference.fold((view) => view.id, (error) {
          failure = error;
          return null;
        });
        if (databaseViewId == null) {
          return _error('internal', '引用数据库失败：${failure?.msg ?? '未知错误'}');
        }
        args = {...args, 'parent_view_id': pageId};
      } else {
        // 独立视图：与界面插入行内数据库一致，先建视图再插入块
        final name = _stringArg(args, 'text')?.trim() ?? '';
        final created = await ViewBackendService.createView(
          parentViewId: pageId,
          name: name.isNotEmpty ? name : blockType,
          layoutType: layout,
          openAfterCreate: false,
        );
        FlowyError? failure;
        final view = created.fold((view) => view, (error) {
          failure = error;
          return null;
        });
        if (view == null) {
          return _error('internal', '创建数据库视图失败：${failure?.msg ?? '未知错误'}');
        }
        databaseViewId = view.id;
        args = {...args, 'parent_view_id': pageId};
      }
      args = {...args, 'view_id_ref': databaseViewId};
    }
    // date 是行内元素，需要在已加载的文档里定位承载块后再构造
    final node = blockType == 'date' ? null : createBlockNode(blockType, args);
    if (node == null && blockType != 'date') {
      final urlRequired =
          const {'image', 'video', 'file', 'link_preview'}.contains(blockType);
      return _error(
        'invalid_params',
        urlRequired
            ? 'block_type=$blockType 需要 url。'
            : switch (blockType) {
                'gallery' => 'block_type=gallery 需要 image_urls。',
                'table' => 'block_type=table 需要 rows。',
                'ai_writer' => 'AI 写作块只在编辑器会话内有效，无法通过 MCP 持久化插入。',
                _ => '不支持的 block_type：$blockType。',
              },
      );
    }
    final text = _stringArg(args, 'text') ?? '';
    final pageError = await _requireWritableDocument(workspaceId, pageId);
    if (pageError != null) return pageError;

    final state = await _loadEditorState(pageId, workspaceId);
    if (state == null) {
      return _error('document_unavailable', '无法读取页面正文，文档可能尚未同步到本机。');
    }
    final parentBlockId = _stringArg(args, 'parent_block_id')?.trim() ?? '';
    final afterBlockId = _stringArg(args, 'after_block_id')?.trim() ?? '';
    final parent = parentBlockId.isEmpty || parentBlockId == pageId
        ? state.document.root
        : _findNode(state.document, parentBlockId);
    if (parent == null) {
      state.dispose();
      return _error('not_found', '父块不存在。');
    }
    Node? after;
    if (afterBlockId.isNotEmpty) {
      after = _findNode(state.document, afterBlockId);
      if (after == null) {
        state.dispose();
        return _error('not_found', 'after_block_id 指向的块不存在。');
      }
      if (after.parent?.id != parent.id) {
        state.dispose();
        return _error('invalid_params', 'after_block_id 不是父块的直接子块。');
      }
    }

    if (blockType == 'date') {
      try {
        return await _appendDateMention(
          pageId: pageId,
          workspaceId: workspaceId,
          state: state,
          parent: parent,
          after: after,
          args: args,
        );
      } finally {
        state.dispose();
      }
    }

    final path = after != null
        ? after.path.next
        : parent.path.child(parent.children.length);
    final blockNode = node!;
    final transaction = state.transaction..insertNode(path, blockNode);
    // insertNode 会深拷贝节点并生成新 ID，必须从操作中取实际写入的块 ID
    final nodeId = transaction.operations
        .whereType<InsertOperation>()
        .first
        .nodes
        .first
        .id;

    try {
      final error = await _persistDocument(
        pageId: pageId,
        workspaceId: workspaceId,
        state: state,
        transaction: transaction,
        verify: (document) => document.blocks.containsKey(nodeId),
      );
      if (error != null) return error;
    } finally {
      state.dispose();
    }
    return _ok({
      'block_id': nodeId,
      'parent_id': parent.id,
      'type': blockNode.type,
      'text': text,
      if (subPageViewId != null) 'sub_page_id': subPageViewId,
      if (databaseViewId != null) 'database_view_id': databaseViewId,
      if (databaseId != null) 'database_id': databaseId,
    });
  }

  Future<CallToolResult> _appendDateMention({
    required String pageId,
    required String workspaceId,
    required EditorState state,
    required Node parent,
    required Node? after,
    required Map<String, dynamic> args,
  }) async {
    final reminderValue = _stringArg(args, 'reminder')?.trim() ?? '';
    ReminderOption? reminderOption;
    if (reminderValue.isNotEmpty) {
      reminderOption = parseReminderOption(reminderValue);
      if (reminderOption == null || reminderOption == ReminderOption.none) {
        return _error('invalid_params', '不支持的 reminder：$reminderValue。');
      }
    }
    final rawDate = _stringArg(args, 'date')?.trim() ?? '';
    final date = rawDate.isEmpty ? DateTime.now() : DateTime.tryParse(rawDate);
    if (date == null) {
      return _error('invalid_params', 'date 不是合法的 ISO 8601 时间。');
    }

    // 日期是行内元素：优先写到 after_block_id 指定的文本块，
    // 否则写到父块最后一个可编辑的文本块，都没有时新建一个段落承载。
    Node? host = after;
    if (host == null) {
      for (final child in parent.children.reversed) {
        if (child.delta != null) {
          host = child;
          break;
        }
      }
    }
    final transaction = state.transaction;
    if (host == null || host.delta == null) {
      final path = after != null
          ? after.path.next
          : parent.path.child(parent.children.length);
      transaction.insertNode(path, paragraphNode());
      host =
          transaction.operations.whereType<InsertOperation>().first.nodes.first;
    }
    final hostId = host.id;

    String? reminderId;
    if (reminderOption != null) {
      reminderId = nanoid();
      final minutes = _intArg(
        args,
        'reminder_minutes',
        ReminderOption.customMinutes,
        1,
        60 * 24 * 30,
      );
      final scheduledAt = reminderOption == ReminderOption.custom
          ? date.subtract(Duration(minutes: minutes))
          : reminderOption.getNotificationDateTime(date);
      // 与编辑器写入日期提醒时的字段保持一致
      getIt<ReminderBloc>().add(
        ReminderEvent.addById(
          reminderId: reminderId,
          objectId: pageId,
          scheduledAt: Int64(
            scheduledAt.millisecondsSinceEpoch ~/ 1000,
          ),
          meta: {
            ReminderMetaKeys.includeTime:
                (args['include_time'] == true).toString(),
            ReminderMetaKeys.blockId: hostId,
            ReminderMetaKeys.notificationType: 'reminder',
          },
        ),
      );
    }

    final node = _mentionDateNode({
      ...args,
      'date': date.toIso8601String(),
      'host_block_id': hostId,
      'host_delta': host.delta!.toJson(),
      if (reminderId != null) 'reminder_id': reminderId,
      if (reminderOption != null) 'reminder_option': reminderOption.name,
    });
    if (node == null) {
      if (reminderId != null) {
        getIt<ReminderBloc>().add(
          ReminderEvent.removeReminder(reminderId: reminderId),
        );
      }
      return _error('invalid_params', '无法构造日期元素。');
    }
    transaction.updateNode(host, {
      blockComponentDelta: node.attributes[blockComponentDelta],
    });
    final error = await _persistDocument(
      pageId: pageId,
      workspaceId: workspaceId,
      state: state,
      transaction: transaction,
      verify: (document) {
        final parsed = document.toDocument();
        final updated = parsed == null ? null : _findNode(parsed, hostId);
        final delta = updated?.delta;
        return delta != null &&
            delta.toJson().any(
                  (op) =>
                      op is Map &&
                      op['attributes'] is Map &&
                      (op['attributes'] as Map)[MentionBlockKeys.mention]
                          is Map,
                );
      },
    );
    if (error != null) {
      // 文档写入未确认时撤销刚创建的提醒，避免留下孤立提醒
      if (reminderId != null) {
        getIt<ReminderBloc>().add(
          ReminderEvent.removeReminder(reminderId: reminderId),
        );
      }
      return error;
    }
    return _ok({
      'block_id': hostId,
      'type': 'date',
      'text': '',
      if (reminderId != null) 'reminder_id': reminderId,
      if (reminderOption != null) 'reminder_option': reminderOption.name,
    });
  }

  @visibleForTesting
  static ReminderOption? parseReminderOption(String value) {
    return switch (value) {
      'at_time_of_event' => ReminderOption.atTimeOfEvent,
      'five_mins_before' => ReminderOption.fiveMinsBefore,
      'ten_mins_before' => ReminderOption.tenMinsBefore,
      'fifteen_mins_before' => ReminderOption.fifteenMinsBefore,
      'thirty_mins_before' => ReminderOption.thirtyMinsBefore,
      'one_hour_before' => ReminderOption.oneHourBefore,
      'two_hours_before' => ReminderOption.twoHoursBefore,
      'on_day_of_event' => ReminderOption.onDayOfEvent,
      'one_day_before' => ReminderOption.oneDayBefore,
      'two_days_before' => ReminderOption.twoDaysBefore,
      'one_week_before' => ReminderOption.oneWeekBefore,
      'custom' => ReminderOption.custom,
      _ => null,
    };
  }

  Future<CallToolResult> _updateBlock(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    final blockId = _stringArg(args, 'block_id')?.trim() ?? '';
    final text = _stringArg(args, 'text') ?? '';
    final hasChecked = args['checked'] is bool;
    final hasCollapsed = args['collapsed'] is bool;
    if (workspaceId.isEmpty || pageId.isEmpty || blockId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id、page_id 或 block_id。');
    }
    final pageError = await _requireWritableDocument(workspaceId, pageId);
    if (pageError != null) return pageError;

    final state = await _loadEditorState(pageId, workspaceId);
    if (state == null) {
      return _error('document_unavailable', '无法读取页面正文，文档可能尚未同步到本机。');
    }
    final node = _findNode(state.document, blockId);
    if (node == null) {
      state.dispose();
      return _error('not_found', '块不存在。');
    }
    if (node.id == state.document.root.id) {
      state.dispose();
      return _error('invalid_params', '不能通过 update_block 修改页面根块。');
    }
    final attributes = <String, Object?>{};
    if (node.delta != null) {
      attributes[blockComponentDelta] = (Delta()..insert(text)).toJson();
    }
    if (hasChecked) {
      if (node.type != TodoListBlockKeys.type) {
        state.dispose();
        return _error('invalid_params', 'checked 仅适用于 todo_list 块。');
      }
      attributes[TodoListBlockKeys.checked] = args['checked'];
    }
    if (hasCollapsed) {
      if (!node.type.startsWith('toggle')) {
        state.dispose();
        return _error('invalid_params', 'collapsed 仅适用于 toggle 类块。');
      }
      attributes[ToggleListBlockKeys.collapsed] = args['collapsed'];
    }
    if (attributes.isEmpty) {
      state.dispose();
      return _error('unsupported_block', '该块不是可编辑的文本块。');
    }
    final transaction = state.transaction..updateNode(node, attributes);
    // 整段文本被替换时，原来的日期 mention 也会消失，需要同步清理提醒
    final reminderIds = attributes.containsKey(blockComponentDelta)
        ? _reminderIdsIn(node)
        : const <String>{};

    try {
      final error = await _persistDocument(
        pageId: pageId,
        workspaceId: workspaceId,
        state: state,
        transaction: transaction,
        verify: (document) {
          final parsed = document.toDocument();
          final updated = parsed == null ? null : _findNode(parsed, blockId);
          if (updated == null) return false;
          if (attributes.containsKey(blockComponentDelta) &&
              (updated.delta?.toPlainText() ?? '') != text) {
            return false;
          }
          if (hasChecked &&
              updated.attributes[TodoListBlockKeys.checked] !=
                  args['checked']) {
            return false;
          }
          if (hasCollapsed &&
              updated.attributes[ToggleListBlockKeys.collapsed] !=
                  args['collapsed']) {
            return false;
          }
          return true;
        },
      );
      if (error != null) return error;
    } finally {
      state.dispose();
    }
    _removeReminders(reminderIds);
    return _ok({
      'block_id': blockId,
      if (attributes.containsKey(blockComponentDelta)) 'text': text,
      if (hasChecked) 'checked': args['checked'],
      if (hasCollapsed) 'collapsed': args['collapsed'],
    });
  }

  Future<CallToolResult> _deleteBlock(Map<String, dynamic> args) async {
    final workspaceId = _stringArg(args, 'workspace_id')?.trim() ?? '';
    final pageId = _stringArg(args, 'page_id')?.trim() ?? '';
    final blockId = _stringArg(args, 'block_id')?.trim() ?? '';
    if (workspaceId.isEmpty || pageId.isEmpty || blockId.isEmpty) {
      return _error('invalid_params', '缺少 workspace_id、page_id 或 block_id。');
    }
    final pageError = await _requireWritableDocument(workspaceId, pageId);
    if (pageError != null) return pageError;

    final state = await _loadEditorState(pageId, workspaceId);
    if (state == null) {
      return _error('document_unavailable', '无法读取页面正文，文档可能尚未同步到本机。');
    }
    final node = _findNode(state.document, blockId);
    if (node == null) {
      state.dispose();
      return _error('not_found', '块不存在。');
    }
    final parent = node.parent;
    if (node.id == state.document.root.id || parent == null) {
      state.dispose();
      return _error('invalid_params', '不能删除页面根块。');
    }

    final deletedIds = _subtreeIds(node);
    final reminderIds = _reminderIdsIn(node);
    final transaction = state.transaction;
    if (parent.children.length == 1) {
      transaction.insertNode(node.path.next, paragraphNode());
    }
    transaction.deleteNode(node);

    try {
      final error = await _persistDocument(
        pageId: pageId,
        workspaceId: workspaceId,
        state: state,
        transaction: transaction,
        verify: (document) =>
            deletedIds.every((id) => !document.blocks.containsKey(id)),
      );
      if (error != null) return error;
    } finally {
      state.dispose();
    }
    _removeReminders(reminderIds);
    return _ok({
      'page_id': pageId,
      'deleted_block_ids': deletedIds,
      'deleted_count': deletedIds.length,
    });
  }

  Future<CallToolResult?> _requireWriteAccess(String workspaceId) async {
    final contextError = await _validateWorkspace(workspaceId);
    if (contextError != null) return contextError;
    final profile = await _currentProfile();
    if (profile == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    // 本地工作区由本机账号直接管理，不存在只读成员
    if (profile.workspaceType == WorkspaceTypePB.LocalW) return null;
    final role = await WorkspacePermissionService.getCurrentUserRole(
      workspaceId: workspaceId,
      userId: profile.id.toInt(),
    );
    if (role == null) {
      // 无法确认角色时拒绝写入，不能沿用界面层的默认放行
      return _error('permission_denied', '无法确认当前账号在该工作区的角色，已拒绝写入。');
    }
    if (role == AFRolePB.Guest) {
      return _error('permission_denied', '只读成员无法通过 MCP 修改内容。');
    }
    return null;
  }

  Future<CallToolResult?> _requireWritableDocument(
    String workspaceId,
    String pageId,
  ) async {
    final accessError = await _requireWriteAccess(workspaceId);
    if (accessError != null) return accessError;
    final view = await _view(pageId);
    if (view == null) {
      return _error('not_found', '页面不存在或无权访问。');
    }
    if (view.workspaceId.isNotEmpty && view.workspaceId != workspaceId) {
      return _error('workspace_mismatch', '页面不属于指定工作区。');
    }
    if (view.isSpace || view.layout != ViewLayoutPB.Document) {
      return _error('unsupported_layout', '仅文档页面支持内容修改。');
    }
    if (view.isLocked) {
      return _error('page_locked', '页面已锁定，无法修改。');
    }
    return null;
  }

  Future<UserWorkspacePB?> _workspaceById(
    UserProfilePB profile,
    String workspaceId,
  ) async {
    final result = await UserBackendService(userId: profile.id).getWorkspaces();
    final workspaces = result.fold((items) => items, (_) => null);
    if (workspaces == null) return null;
    for (final workspace in workspaces) {
      if (workspace.workspaceId == workspaceId) return workspace;
    }
    return null;
  }

  Future<TrashPB?> _findTrashItem(String viewId) async {
    final result = await TrashService().readTrash();
    final items = result.fold((trash) => trash.items, (_) => null);
    if (items == null) return null;
    for (final item in items) {
      if (item.id == viewId) return item;
    }
    return null;
  }

  Future<EditorState?> _loadEditorState(
    String pageId,
    String workspaceId,
  ) async {
    // ApplyAction 要求文档处于打开状态，写入期间保持打开，
    // 完成后由 _persistDocument 按需关闭。
    final service = DocumentService();
    final opened = await service.openDocument(
      documentId: pageId,
      workspaceId: workspaceId,
    );
    final data = opened.fold((document) => document, (error) {
      Log.error('[MCP] open document $pageId failed: $error');
      return null;
    });
    final document = data?.toDocument();
    if (document == null) return null;
    return EditorState(document: document);
  }

  /// 先提交到业务层，再更新本地状态，最后重新读取确认保存结果。
  Future<CallToolResult?> _persistDocument({
    required String pageId,
    required String workspaceId,
    required EditorState state,
    required Transaction transaction,
    required bool Function(DocumentDataPB document) verify,
  }) async {
    final adapter = TransactionAdapter(
      documentId: pageId,
      documentService: DocumentService(),
    );
    try {
      await adapter.apply(transaction, state).timeout(_writeTimeout);
    } on TimeoutException {
      return _error(
        'write_timeout',
        '写入超时，无法确认是否已保存；请用 get_page 或 list_blocks 查询确认，不要直接重试创建。',
      );
    } catch (e, st) {
      Log.error('[MCP] persist document $pageId failed: $e\n$st');
      return _error('internal', '写入失败：$e');
    }
    try {
      await state.apply(transaction);
    } catch (e, st) {
      Log.error('[MCP] apply local transaction for $pageId failed: $e\n$st');
      return _error(
        'write_unconfirmed',
        '写入已提交但本地状态更新失败；请用 get_page 或 list_blocks 查询确认。',
      );
    }
    final fresh = await _freshDocument(pageId, workspaceId, state);
    if (fresh == null || !verify(fresh)) {
      return _error(
        'write_unconfirmed',
        '写入已提交但未能确认保存结果；请用 get_page 或 list_blocks 查询确认。',
      );
    }
    // 界面没有打开该文档时，写入确认后关闭，避免长期占用内存
    if (DocumentBloc.findOpen(pageId) == null) {
      await DocumentService().closeDocument(viewId: pageId);
    }
    return null;
  }

  Node? _findNode(Document document, String id) {
    Node? found;
    void walk(Node node) {
      if (found != null) return;
      if (node.id == id) {
        found = node;
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(document.root);
    return found;
  }

  List<String> _subtreeIds(Node node) {
    final ids = <String>[];
    void walk(Node node) {
      ids.add(node.id);
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(node);
    return ids;
  }

  /// 收集块及其子块里所有日期 mention 关联的提醒 ID。
  Set<String> _reminderIdsIn(Node node) {
    final ids = <String>{};
    void walk(Node node) {
      final delta = node.delta;
      if (delta != null) {
        for (final operation in delta.toJson()) {
          if (operation is! Map) continue;
          final attributes = operation['attributes'];
          final mention =
              attributes is Map ? attributes[MentionBlockKeys.mention] : null;
          if (mention is! Map ||
              mention[MentionBlockKeys.type] != MentionType.date.name) {
            continue;
          }
          final reminderId = mention[MentionBlockKeys.reminderId];
          if (reminderId is String && reminderId.isNotEmpty) {
            ids.add(reminderId);
          }
        }
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(node);
    return ids;
  }

  void _removeReminders(Set<String> reminderIds) {
    for (final reminderId in reminderIds) {
      getIt<ReminderBloc>().add(
        ReminderEvent.removeReminder(reminderId: reminderId),
      );
    }
  }

  /// 按 block_type 和参数构造编辑器的块节点，覆盖斜杠菜单可插入的全部块类型。
  @visibleForTesting
  static Node? createBlockNode(String type, Map<String, dynamic> args) {
    final text = args['text'] is String ? args['text'] as String : '';
    final checked = args['checked'] == true;
    final collapsed = args['collapsed'] == true;
    switch (type) {
      case 'paragraph':
        return paragraphNode(text: text);
      case 'heading1':
        return headingNode(level: 1, text: text);
      case 'heading2':
        return headingNode(level: 2, text: text);
      case 'heading3':
        return headingNode(level: 3, text: text);
      case 'bulleted_list':
        return bulletedListNode(text: text);
      case 'numbered_list':
        return numberedListNode(delta: Delta()..insert(text));
      case 'todo_list':
        return todoListNode(checked: checked, text: text);
      case 'quote':
        return quoteNode(delta: Delta()..insert(text));
      case 'divider':
        return dividerNode();
      case 'toggle_list':
        return toggleListBlockNode(
          text: text,
          collapsed: collapsed,
          children: [paragraphNode()],
        );
      case 'toggle_heading1':
        return toggleHeadingNode(
          text: text,
          collapsed: collapsed,
          children: [paragraphNode()],
        );
      case 'toggle_heading2':
        return toggleHeadingNode(
          level: 2,
          text: text,
          collapsed: collapsed,
          children: [paragraphNode()],
        );
      case 'toggle_heading3':
        return toggleHeadingNode(
          level: 3,
          text: text,
          collapsed: collapsed,
          children: [paragraphNode()],
        );
      case 'code':
        final language = args['language'];
        return codeBlockNode(
          delta: Delta()..insert(text),
          language: language is String && language.isNotEmpty ? language : null,
        );
      case 'callout':
        final icon = args['icon'];
        return calloutNode(
          delta: Delta()..insert(text),
          emoji: EmojiIconData.emoji(
            icon is String && icon.isNotEmpty ? icon : '📌',
          ),
          defaultColor: Colors.transparent,
        );
      case 'math_equation':
        final formula = args['formula'];
        return mathEquationNode(
          formula: formula is String && formula.isNotEmpty ? formula : text,
        );
      case 'image':
      case 'video':
      case 'file':
        final url = args['url'];
        if (url is! String || url.isEmpty) return null;
        if (type == 'image') {
          return imageNode(url: url);
        }
        if (type == 'video') {
          return Node(
            type: VideoBlockKeys.type,
            attributes: {VideoBlockKeys.url: url},
          );
        }
        final fileName = args['file_name'];
        return fileNode(
          url: url,
          type: FileUrlType.network,
          name: fileName is String && fileName.isNotEmpty ? fileName : null,
        );
      case 'gallery':
        final urls = args['image_urls'];
        if (urls is! List || urls.isEmpty) return null;
        final images = urls
            .whereType<String>()
            .where((url) => url.isNotEmpty)
            .map(
              (url) => ImageBlockData(
                url: url,
                type: CustomImageType.external,
              ),
            )
            .toList();
        return images.isEmpty ? null : multiImageNode(images: images);
      case 'link_preview':
        final url = args['url'];
        if (url is! String || url.isEmpty) return null;
        return linkPreviewNode(url: url);
      case 'sub_page':
        final ref = args['page_id_ref'];
        if (ref is! String || ref.isEmpty) return null;
        return subPageNode(viewId: ref);
      case 'columns':
        final columnCount = args['column_count'];
        return simpleColumnsNode(
          columnCount: columnCount is int ? columnCount.clamp(2, 4) : 2,
        );
      case 'table':
        final rows = args['rows'];
        if (rows is! List || rows.isEmpty) return null;
        final cells = rows
            .map(
              (row) => row is List
                  ? row.map((cell) => '${cell ?? ''}').toList()
                  : <String>[],
            )
            .where((row) => row.isNotEmpty)
            .toList();
        if (cells.isEmpty) return null;
        final columnCount = cells.map((row) => row.length).reduce(min);
        return createSimpleTableBlockNode(
          columnCount: columnCount,
          rowCount: cells.length,
          contentBuilder: (rowIndex, columnIndex) =>
              cells[rowIndex][columnIndex],
        );
      case 'grid':
      case 'board':
      case 'calendar':
        // 需要先创建或定位数据库视图，由 _insertBlock 预先解析出 view_id
        final viewId = args['view_id_ref'];
        if (viewId is! String || viewId.isEmpty) return null;
        final parentId = args['parent_view_id'];
        return Node(
          type: switch (type) {
            'grid' => DatabaseBlockKeys.gridType,
            'board' => DatabaseBlockKeys.boardType,
            _ => DatabaseBlockKeys.calendarType,
          },
          attributes: {
            DatabaseBlockKeys.parentID: parentId is String ? parentId : '',
            DatabaseBlockKeys.viewID: viewId,
          },
        );
      case 'ai_writer':
        // AI 写作块只在编辑器会话内有效（编辑器以 inMemoryUpdate 插入），无法持久化
        return null;
      case 'date':
        return _mentionDateNode(args);
    }
    return null;
  }

  /// 日期是行内元素：在承载块 delta 末尾追加一个带 mention 属性的零宽字符。
  static Node? _mentionDateNode(Map<String, dynamic> args) {
    final hostBlockId = args['host_block_id'];
    if (hostBlockId is! String || hostBlockId.isEmpty) return null;
    final hostDelta = args['host_delta'];
    final delta = Delta.fromJson(hostDelta is List ? hostDelta : const []);
    final dateText = args['date'];
    final date = dateText is String && dateText.isNotEmpty
        ? dateText
        : DateTime.now().toIso8601String();
    final reminderId = args['reminder_id'];
    final reminderOption = args['reminder_option'];
    String? reminderOptionName;
    if (reminderOption is String && reminderOption.isNotEmpty) {
      for (final option in ReminderOption.values) {
        if (option.name == reminderOption) {
          reminderOptionName = option.name;
          break;
        }
      }
      reminderOptionName ??= parseReminderOption(reminderOption)?.name;
    }
    delta.insert(
      '​',
      attributes: MentionBlockKeys.buildMentionDateAttributes(
        date: date,
        reminderId:
            reminderId is String && reminderId.isNotEmpty ? reminderId : null,
        reminderOption: reminderOptionName,
        includeTime: args['include_time'] == true,
      ),
    );
    return Node(
      id: hostBlockId,
      type: ParagraphBlockKeys.type,
      attributes: {blockComponentDelta: delta.toJson()},
    );
  }

  /// 把 Markdown 文档的随机根块 ID 重映射为页面 ID。
  void _rebindDocumentRoot(DocumentDataPB data, String viewId) {
    final oldRoot = data.pageId;
    if (oldRoot.isEmpty || oldRoot == viewId) return;
    final root = data.blocks.remove(oldRoot);
    if (root == null) return;
    root.id = viewId;
    root.childrenId = viewId;
    data.blocks[viewId] = root;
    data.pageId = viewId;
    final children = data.meta.childrenMap.remove(oldRoot);
    if (children != null) {
      data.meta.childrenMap[viewId] = children;
    }
    for (final block in data.blocks.values) {
      if (block.parentId == oldRoot) {
        block.parentId = viewId;
      }
    }
  }

  /// database_id 参数既可以是数据库 ID，也可以是数据库视图 ID；
  /// 传入视图 ID 时通过数据库服务解析出真正的数据库 ID。
  Future<String?> _resolveDatabaseId(String ref) async {
    final asView =
        await DatabaseViewBackendService(viewId: ref).getDatabaseId();
    final databaseId = asView.fold((value) => value, (_) => null);
    return databaseId ?? ref;
  }

  Future<CallToolResult?> _validateWorkspace(String workspaceId) async {
    final profile = await _currentProfile();
    if (profile == null) {
      return _error('not_logged_in', '客户端未登录，请先在小马笔记中登录账号。');
    }
    final current = await _currentWorkspace();
    if (current == null) {
      return _error('not_logged_in', '客户端尚未打开任何工作区。');
    }
    if (workspaceId != current.id) {
      return _error(
        'workspace_mismatch',
        '请求的工作区不是客户端当前工作区，请使用 get_context 获取当前工作区。',
      );
    }
    return null;
  }

  Future<ViewPB?> _view(String viewId) async {
    final result = await ViewBackendService.getView(viewId);
    return result.fold((view) => view, (_) => null);
  }

  Future<DocumentDataPB?> _readDocument(
    String pageId,
    String workspaceId,
  ) async {
    final service = DocumentService();
    final local = await service.getDocument(
      documentId: pageId,
      workspaceId: workspaceId,
    );
    final localDocument = local.fold((document) => document, (_) => null);
    if (localDocument != null && localDocument.blocks.isNotEmpty) {
      return localDocument;
    }

    // 未打开的云端文档通过 getDocument 只会得到一个空实例，
    // 必须走 openDocument 触发同步，这与编辑器打开页面的路径一致。
    final opened = await service.openDocument(
      documentId: pageId,
      workspaceId: workspaceId,
    );
    final openedDocument = opened.fold((document) => document, (error) {
      Log.error('[MCP] open document $pageId failed: $error');
      return null;
    });
    if (openedDocument != null && openedDocument.blocks.isNotEmpty) {
      // 界面没有打开该文档时，读取后关闭，避免长期占用内存
      if (DocumentBloc.findOpen(pageId) == null) {
        await service.closeDocument(viewId: pageId);
      }
      return openedDocument;
    }
    Log.warn(
      '[MCP] read document $pageId empty: getDocument=${localDocument?.blocks.length} '
      'openDocument=${openedDocument?.blocks.length}',
    );

    final cloud = await service.getCloudDocument(
      documentId: pageId,
      workspaceId: workspaceId,
    );
    return cloud.fold((document) => document, (error) {
      Log.error('[MCP] read document $pageId failed: $error');
      return null;
    });
  }

  /// 重新读取并确认刚落库的内容：本地数据未刷新时合并内存中的编辑器状态。
  Future<DocumentDataPB?> _freshDocument(
    String pageId,
    String workspaceId,
    EditorState state,
  ) async {
    final fresh = await _readDocument(pageId, workspaceId);
    if (fresh == null) return null;
    final freshIds = fresh.blocks.keys.toSet();
    final memoryIds =
        state.document.root.copyWith().children.map((node) => node.id).toSet();
    if (memoryIds.difference(freshIds).isEmpty) return fresh;
    // 本地文档的增量写入可能还在异步落库，确认时以内存中的编辑器状态为准
    final merged = DocumentDataPBFromTo.fromDocument(state.document);
    if (merged == null) return fresh;
    if (merged.pageId != fresh.pageId) {
      // 页面根块可能沿用随机 ID，合并时需要与磁盘数据保持同一个根
      final oldRoot = merged.pageId;
      final root = merged.blocks.remove(oldRoot);
      if (root != null) {
        root.id = fresh.pageId;
        root.childrenId = fresh.pageId;
        merged.blocks[fresh.pageId] = root;
        final children = merged.meta.childrenMap.remove(oldRoot);
        if (children != null) merged.meta.childrenMap[fresh.pageId] = children;
        for (final block in merged.blocks.values) {
          if (block.parentId == oldRoot) block.parentId = fresh.pageId;
        }
        merged.pageId = fresh.pageId;
      }
    }
    return merged;
  }

  /// 用编辑器同一套转换构建块树，确保外部长文本也能提取。
  List<_McpBlock> _flattenDocument(Node parent) {
    final blocks = <_McpBlock>[];
    void walk(Node node, int depth) {
      for (final child in node.children) {
        final delta = child.delta;
        blocks.add(
          _McpBlock(child, depth, delta == null ? '' : deltaText(delta)),
        );
        walk(child, depth + 1);
      }
    }

    walk(parent, 0);
    return blocks;
  }

  /// Delta 纯文本；日期 mention 渲染成可读日期而不是零宽字符。
  @visibleForTesting
  static String deltaText(Delta delta) {
    final buffer = StringBuffer();
    for (final operation in delta.toJson()) {
      if (operation is! Map) continue;
      final attributes = operation['attributes'];
      final mention =
          attributes is Map ? attributes[MentionBlockKeys.mention] : null;
      if (mention is Map &&
          mention[MentionBlockKeys.type] == MentionType.date.name) {
        final rawDate = mention[MentionBlockKeys.date];
        final date = rawDate is String ? DateTime.tryParse(rawDate) : null;
        if (date != null) {
          final local = date.toLocal();
          final day = '${local.year}/${local.month}/${local.day}';
          final current = buffer.toString();
          if (current.isNotEmpty && !current.endsWith(' ')) {
            buffer.write(' ');
          }
          if (mention[MentionBlockKeys.includeTime] == true) {
            final hour = local.hour.toString().padLeft(2, '0');
            final minute = local.minute.toString().padLeft(2, '0');
            buffer.write('$day $hour:$minute');
          } else {
            buffer.write(day);
          }
          continue;
        }
      }
      final insert = operation['insert'];
      if (insert is String) buffer.write(insert);
    }
    return buffer.toString();
  }

  Map<String, dynamic> _blockToJson(_McpBlock block) {
    final truncated = block.text.length > _maxBlockChars;
    final node = block.node;
    final checked = node.attributes[TodoListBlockKeys.checked];
    final attributes = blockAttributes(node);
    final url = attributes['url'];
    final images = attributes[MultiImageBlockKeys.images];
    final imageUrls = images is List
        ? images
            .whereType<Map>()
            .map((image) => image['url'])
            .whereType<String>()
            .toList()
        : null;
    return {
      'block_id': node.id,
      'parent_id': node.parent?.id ?? '',
      'type': node.type,
      'text': truncated ? block.text.substring(0, _maxBlockChars) : block.text,
      'text_truncated': truncated,
      'depth': block.depth,
      if (checked is bool) 'checked': checked,
      if (url is String && url.isNotEmpty) 'url': url,
      if (imageUrls != null && imageUrls.isNotEmpty) 'image_urls': imageUrls,
      if (attributes.isNotEmpty) 'attributes': attributes,
    };
  }

  /// 资源类块（图片、视频、文件、相册、链接预览等）的业务属性。
  /// 去掉 delta，避免与 text 字段重复；相册的 images 是 JSON 字符串，这里解析成列表。
  @visibleForTesting
  static Map<String, dynamic> blockAttributes(Node node) {
    final result = <String, dynamic>{};
    for (final entry in node.attributes.entries) {
      if (entry.key == blockComponentDelta) continue;
      final value = entry.value;
      if (value == null) continue;
      if (entry.key == MultiImageBlockKeys.images && value is String) {
        try {
          result[entry.key] = jsonDecode(value);
        } catch (_) {
          result[entry.key] = value;
        }
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  Map<String, dynamic> _viewToJson(ViewPB view) {
    return {
      'page_id': view.id,
      'title': view.name,
      'layout': view.layout.name,
      'parent_id': view.parentViewId,
      'is_document': view.layout == ViewLayoutPB.Document,
      'is_space': view.isSpace,
      'last_edited': view.lastEdited.toInt(),
    };
  }

  /// 提取块的纯文本；长文本块的内容保存在 meta.textMap 中。
  @visibleForTesting
  static String blockText(BlockPB block, MetaPB? meta) {
    final text = _parseText(block.data);
    if (text.isNotEmpty) return text;
    if (meta != null &&
        block.externalType == 'text' &&
        block.externalId.isNotEmpty) {
      final delta = meta.textMap[block.externalId];
      if (delta != null) return _parseText(delta);
    }
    return '';
  }

  static String _parseText(String raw) {
    if (raw.isEmpty) return '';
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        final delta = data['delta'];
        if (delta is List) {
          final buffer = StringBuffer();
          for (final operation in delta) {
            if (operation is Map && operation['insert'] is String) {
              buffer.write(operation['insert']);
            }
          }
          return buffer.toString();
        }
        final text = data['text'];
        if (text is String) return text;
      }
    } catch (_) {
      // 无法解析的块保留原始数据，不阻断整页读取
    }
    return '';
  }

  Future<UserProfilePB?> _currentProfile() async {
    final result = await UserBackendService.getCurrentUserProfile();
    return result.fold((profile) => profile, (_) => null);
  }

  Future<WorkspacePB?> _currentWorkspace() async {
    final result = await FolderEventReadCurrentWorkspace().send();
    return result.fold((workspace) => workspace, (_) => null);
  }

  String? _stringArg(Map<String, dynamic> args, String key) {
    final value = args[key];
    return value is String ? value : null;
  }

  int _intArg(
    Map<String, dynamic> args,
    String key,
    int defaultValue,
    int min,
    int max,
  ) {
    final value = args[key];
    final parsed = value is int ? value : int.tryParse('$value');
    if (parsed == null) return defaultValue;
    return parsed.clamp(min, max);
  }

  CallToolResult _ok(Map<String, dynamic> data) {
    return CallToolResult(content: [TextContent(text: jsonEncode(data))]);
  }

  CallToolResult _error(String code, String message) {
    final body = jsonEncode({
      'error': {'code': code, 'message': message},
    });
    return CallToolResult(
      isError: true,
      content: [TextContent(text: body)],
    );
  }
}

class _McpBlock {
  const _McpBlock(this.node, this.depth, this.text);

  final Node node;
  final int depth;
  final String text;
}
