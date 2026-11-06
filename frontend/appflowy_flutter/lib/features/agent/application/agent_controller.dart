import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'agent_settings.dart';
import 'agent_note_bridge.dart';
import 'agent_transport.dart';

class AgentActivity {
  AgentActivity({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  String status = 'running';
  String result = '';
  String? before;
  String? after;
}

class AgentController extends ChangeNotifier {
  AgentController({required this.chatId, AgentTransport? transport})
      : transport = transport ?? AgentTransport();
  static final _instances = <AgentController>{};
  static Future<void> revokeAll() async {
    await Future.wait(
      _instances.toList().map((controller) => controller.disconnect()),
    );
  }

  final String chatId;
  final AgentTransport transport;
  final _pending = <String, Completer<dynamic>>{};
  final messages = <Map<String, dynamic>>[];
  final activities = <String, AgentActivity>{};
  final interactions = <Map<String, dynamic>>[];
  final steps = <Map<String, dynamic>>[];
  final queuedInputs = <String>[];
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _identity;
  String? _workspaceId;
  int _epoch = 0;
  int _runEpoch = 0;
  AgentSettings? _settings;
  bool connected = false;
  int clearanceVersion = 0;
  bool connecting = false;
  bool running = false;
  bool compacting = false;
  bool _disposed = false;
  String? error;
  String streamingText = '';
  String model = '';
  String location = '本机';
  String? authorizationUrl;
  HttpServer? _oauthRelay;
  Map<String, dynamic>? contextUsage;
  List<Map<String, dynamic>> sessions = [];

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<String> identity() async {
    return AgentSettings.currentIdentity();
  }

  Future<void> connect() async {
    if (connecting || connected) return;
    connecting = true;
    error = null;
    changed();
    final epoch = ++_epoch;
    _instances.add(this);
    try {
      final currentIdentity = await identity();
      final settings = await AgentSettings.load(
        scope: const Uuid().v5(Namespace.url.value, currentIdentity),
      );
      _settings = settings;
      _workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      final provider = await const AiProviderConfigStorage().load();
      if (!provider.isComplete) {
        throw StateError('请先在「内部 AI 模型」配置模型地址、名称和 API Key');
      }
      final support = await getApplicationSupportDirectory();
      _identity = currentIdentity;
      await _subscription?.cancel();
      _subscription = transport.records.listen(
        _receive,
        onError: (Object e) {
          error = '$e';
          unawaited(disconnect(keepError: true));
        },
      );
      if (epoch != _epoch) return;
      await transport.connect(
        dataDirectory: p.join(support.path, 'agent'),
        remoteUrl: settings.remoteUrl,
        token: settings.remoteToken,
      );
      if (epoch != _epoch) {
        await transport.close();
        return;
      }
      // UUID v5 is a stable namespace identifier, not a credential or integrity check.
      final scope =
          const Uuid().v5(Namespace.url.value, '$currentIdentity|$chatId');
      final registry = McpTools(
        endpoint: 'internal-agent',
        version: '1.0.0',
        isAgentChannel: true,
        agentName: () => '小马笔记 Agent',
      );
      final base = provider.baseUrl
          .replaceAll(RegExp(r'/+$'), '')
          .replaceFirst(RegExp(r'/chat/completions$'), '');
      final data = await command('initialize', {
        'config': {
          'scope': scope,
          'workspaceId': _workspaceId,
          'baseUrl': Uri.parse(base).path.isEmpty || Uri.parse(base).path == '/'
              ? '$base/v1'
              : base,
          'model': provider.modelName,
          'apiKey': provider.apiKey,
          'directory': settings.directory,
          'allowCommands': settings.allowCommands,
          'mcpServers': settings.mcpServers,
          'mcpCredentials':
              await AgentSettings.loadMcpCredentials(settings.scope),
          'skillDirectories': settings.skillDirectories,
          'noteTools': registry.toolSpecs
              .where((spec) => !settings.disabledNoteTools.contains(spec.name))
              .map(
                (spec) => {
                  'name': spec.name,
                  'description': spec.description,
                  'inputSchema': spec.inputSchema.toJson(),
                },
              )
              .toList(),
        },
      });
      if (epoch != _epoch) return;
      _readState(Map<String, dynamic>.from(data as Map));
      connected = true;
      await listSessions();
    } catch (e) {
      if (epoch == _epoch) {
        error = '$e';
        await transport.close();
      }
    } finally {
      if (epoch == _epoch) {
        connecting = false;
        changed();
      }
    }
  }

  Future<dynamic> command(
    String type, [
    Map<String, dynamic> data = const {},
  ]) async {
    final id = const Uuid().v4();
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    try {
      transport.send({'type': type, 'id': id, ...data});
      return await completer.future
          .timeout(Duration(seconds: type == 'compact' ? 180 : 45));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> send(
    String text, {
    String behavior = 'prompt',
    List<Map<String, dynamic>> images = const [],
  }) async {
    if (!connected) await connect();
    if (!connected) return;
    if (await identity() != _identity) {
      await disconnect();
      throw StateError('账号或工作区已切换，请重新连接');
    }
    if (behavior == 'prompt') {
      ++_runEpoch;
      running = true;
      error = null;
      activities.clear();
      steps.clear();
      streamingText = '';
      messages.add({'role': 'user', 'content': text});
      changed();
    }
    try {
      final disposition = await command(
        behavior,
        {'message': text, if (images.isNotEmpty) 'images': images},
      );
      if (behavior != 'prompt' && disposition == 'queued') {
        queuedInputs.add(text);
        changed();
      }
    } catch (e) {
      error = '$e';
      if (behavior == 'prompt') running = false;
      changed();
    }
  }

  Future<void> stop() async {
    if (!connected) return;
    ++_runEpoch;
    for (final interaction in interactions.toList()) {
      respond(interaction, false);
    }
    try {
      await command('abort');
    } catch (e) {
      error = '$e';
      await disconnect(keepError: true);
    }
  }

  Future<void> compact() async {
    compacting = true;
    changed();
    try {
      await command('compact');
    } catch (e) {
      error = '$e';
    } finally {
      compacting = false;
      changed();
    }
  }

  Future<void> listSessions() async {
    final result = await command('list_sessions') as List;
    sessions = result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    changed();
  }

  Future<void> selectSession(String? id) async {
    if (running) return;
    final data = await command(
      id == null ? 'new_session' : 'switch_session',
      id == null ? {} : {'sessionId': id},
    );
    _readState(Map<String, dynamic>.from(data as Map));
    activities.clear();
    await listSessions();
    changed();
  }

  void _receive(Map<String, dynamic> record) {
    if (_disposed) return;
    switch (record['type']) {
      case 'response':
        final pending = _pending[record['id']];
        if (pending != null && !pending.isCompleted) {
          record['success'] == true
              ? pending.complete(record['data'])
              : pending.completeError(StateError('${record['error']}'));
        }
      case 'state':
        _readState(Map<String, dynamic>.from(record['data'] as Map));
      case 'settled':
        running = false;
        streamingText = '';
        interactions.clear();
        queuedInputs.clear();
        unawaited(
          listSessions().catchError((Object e) {
            error = '$e';
          }),
        );
      case 'event':
        _event(Map<String, dynamic>.from(record['event'] as Map));
      case 'approval':
      case 'select':
      case 'input':
        interactions.add(record);
      case 'note_call':
        unawaited(_noteCall(record));
      case 'plan':
        steps
          ..clear()
          ..addAll(
            (record['steps'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );
      case 'open_url':
        final uri = Uri.tryParse('${record['url']}');
        if (uri != null &&
            (uri.scheme == 'https' ||
                (uri.scheme == 'http' &&
                    ['localhost', '127.0.0.1'].contains(uri.host)))) {
          authorizationUrl = uri.toString();
          if (record['callback'] is String) {
            unawaited(_relayOAuth(record['callback'] as String));
          }
        }
      case 'notice':
        if (record['kind'] == 'error') error = '${record['message']}';
      case 'credentials_changed':
        if (_settings != null && record['value'] is String) {
          unawaited(
            AgentSettings.saveMcpCredentials(
              _settings!.scope,
              record['value'] as String,
            ).catchError((Object e) {
              error = 'MCP 凭据保存失败，请检查系统安全存储后重新登录';
              changed();
            }),
          );
        }
    }
    changed();
  }

  void _readState(Map<String, dynamic> state) {
    messages
      ..clear()
      ..addAll(
        (state['messages'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
    contextUsage = state['context'] == null
        ? null
        : Map<String, dynamic>.from(state['context'] as Map);
    model = state['model'] as String? ?? model;
    location = state['location'] as String? ?? location;
    steps
      ..clear()
      ..addAll(
        (state['steps'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map)),
      );
  }

  void _event(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message_update':
        final update = event['assistantMessageEvent'] as Map?;
        if (update?['type'] == 'text_delta') {
          streamingText += '${update?['delta'] ?? ''}';
        }
      case 'message_end':
        final message = Map<String, dynamic>.from(event['message'] as Map);
        if (message['role'] == 'user') {
          final text = message['content'] is String
              ? message['content'] as String
              : _resultText(message);
          if (queuedInputs.remove(text)) messages.add(message);
        }
        if (message['role'] == 'assistant' || message['role'] == 'toolResult') {
          messages.add(message);
          if (message['role'] == 'assistant') streamingText = '';
        }
        if (message['stopReason'] == 'error') {
          error = '${message['errorMessage'] ?? '模型请求失败'}';
        }
      case 'tool_execution_start':
        activities['${event['toolCallId']}'] = AgentActivity(
          id: '${event['toolCallId']}',
          name: '${event['toolName']}',
          arguments: Map<String, dynamic>.from(event['args'] as Map? ?? {}),
        );
      case 'tool_execution_update':
        activities['${event['toolCallId']}']?.result =
            _resultText(event['partialResult']);
      case 'tool_execution_end':
        final activity = activities['${event['toolCallId']}'];
        if (activity != null) {
          activity.status = event['isError'] == true ? 'failed' : 'completed';
          activity.result = _resultText(event['result']);
          final details = (event['result'] as Map?)?['details'] as Map?;
          activity.before = details?['before'] as String?;
          activity.after = details?['after'] as String?;
        }
      case 'auto_compaction_start':
        compacting = true;
      case 'auto_compaction_end':
        compacting = false;
    }
  }

  static String _resultText(dynamic result) =>
      (result is Map ? result['content'] as List? : null)
          ?.whereType<Map>()
          .map((c) => c['text'] ?? '')
          .join('\n') ??
      '';
  Future<void> _noteCall(Map<String, dynamic> request) async {
    final epoch = _epoch;
    final runEpoch = _runEpoch;
    CallToolResult result;
    String? before;
    String? after;
    try {
      if (!connected || await identity() != _identity) {
        throw StateError('账号或工作区已切换');
      }
      final args = Map<String, dynamic>.from(request['arguments'] as Map);
      if (args['workspace_id'] != null &&
          args['workspace_id'] != _workspaceId) {
        throw StateError('工具不属于当前工作区');
      }
      final tools = McpTools(
        endpoint: 'internal-agent',
        version: '1.0.0',
        isAgentChannel: true,
        agentName: () => '小马笔记 Agent',
        isToolAllowed: (name) =>
            !(_settings?.disabledNoteTools.contains(name) ?? true),
      );
      final bridge = AgentNoteBridge(
        tools: tools,
        workspaceId: _workspaceId!,
        isCurrent: () async =>
            epoch == _epoch &&
            runEpoch == _runEpoch &&
            connected &&
            await identity() == _identity,
        approve: (spec, args) async {
          if (args['page_id'] is String &&
              !(_settings?.disabledNoteTools.contains('get_page') ?? true)) {
            final snapshot = await tools.executeTool(
              'get_page',
              {'workspace_id': _workspaceId, 'page_id': args['page_id']},
            );
            if (!snapshot.isError) before = _resultText(snapshot.toJson());
          }
          final confirmation = Completer<bool>();
          final approval = {
            ...request,
            'type': 'note_approval',
            'title': spec.name,
            'confirmation': confirmation,
            'before': before,
          };
          interactions.add(approval);
          changed();
          final allowed = await confirmation.future
              .timeout(const Duration(seconds: 110), onTimeout: () => false);
          interactions.remove(approval);
          changed();
          if (allowed && before != null) {
            final current = await tools.executeTool(
              'get_page',
              {'workspace_id': _workspaceId, 'page_id': args['page_id']},
            );
            if (current.isError || _resultText(current.toJson()) != before) {
              throw StateError('确认期间页面已改变，请重新读取后再修改');
            }
          }
          return allowed;
        },
      );
      result = await bridge.execute('${request['name']}', args);
      if (before != null &&
          !result.isError &&
          epoch == _epoch &&
          runEpoch == _runEpoch &&
          await identity() == _identity) {
        final snapshot = await tools.executeTool(
          'get_page',
          {'workspace_id': _workspaceId, 'page_id': args['page_id']},
        );
        if (!snapshot.isError) after = _resultText(snapshot.toJson());
      }
    } catch (e) {
      result =
          CallToolResult(content: [TextContent(text: '$e')], isError: true);
    }
    if (epoch == _epoch && connected) {
      transport.send({
        'type': 'note_result',
        'id': request['id'],
        'result': {
          ...result.toJson(),
          'details': {'before': before, 'after': after},
        },
      });
    }
  }

  void respond(Map<String, dynamic> request, dynamic value) {
    interactions.remove(request);
    final confirmation = request['confirmation'];
    if (confirmation is Completer<bool>) {
      if (!confirmation.isCompleted) confirmation.complete(value == true);
    } else {
      transport.send({
        'type': 'interaction_response',
        'id': request['id'],
        'result': value,
      });
    }
    changed();
  }

  Future<void> _relayOAuth(String callback) async {
    try {
      final uri = Uri.parse(callback);
      if (uri.scheme != 'http' ||
          !['127.0.0.1', 'localhost', '::1'].contains(uri.host)) {
        throw StateError('MCP 登录回调地址无效');
      }
      await _oauthRelay?.close(force: true);
      final relay =
          await HttpServer.bind(InternetAddress.loopbackIPv4, uri.port);
      _oauthRelay = relay;
      relay.listen((request) async {
        if (request.method != 'GET' || request.uri.path != uri.path) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        try {
          await command(
            'oauth_callback',
            {'url': uri.replace(query: request.uri.query).toString()},
          );
          request.response.headers.contentType = ContentType.text;
          request.response.write('MCP 登录已完成，请返回小马笔记。');
          authorizationUrl = null;
        } catch (_) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('登录未完成，请返回小马笔记查看状态。');
        }
        await request.response.close();
        changed();
      });
    } catch (e) {
      error = '无法接收 MCP 登录回调：$e';
      authorizationUrl = null;
      changed();
    }
  }

  Future<void> disconnect({bool keepError = false}) async {
    ++clearanceVersion;
    ++_epoch;
    ++_runEpoch;
    connected = false;
    connecting = false;
    running = false;
    compacting = false;
    for (final request in interactions.toList()) {
      final confirmation = request['confirmation'];
      if (confirmation is Completer<bool> && !confirmation.isCompleted) {
        confirmation.complete(false);
      }
    }
    interactions.clear();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Agent 连接已关闭'));
      }
    }
    _pending.clear();
    await _oauthRelay?.close(force: true);
    _oauthRelay = null;
    authorizationUrl = null;
    try {
      await transport.close();
    } catch (e) {
      error = 'Agent 已撤权，执行器关闭失败：$e';
    }
    messages.clear();
    queuedInputs.clear();
    activities.clear();
    steps.clear();
    streamingText = '';
    _identity = null;
    _settings = null;
    sessions = [];
    contextUsage = null;
    model = '';
    if (!keepError) error = null;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _instances.remove(this);
    unawaited(disconnect());
    unawaited(_subscription?.cancel());
    unawaited(transport.dispose());
    super.dispose();
  }
}
