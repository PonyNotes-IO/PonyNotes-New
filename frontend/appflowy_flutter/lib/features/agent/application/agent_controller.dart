import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:flutter/foundation.dart';
import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'agent_artifacts.dart';
import 'agent_credits.dart';
import 'agent_internal_service.dart';
import 'agent_model_preferences.dart';
import 'agent_service.dart';
import 'agent_reference.dart';
import 'agent_note_bridge.dart';
import 'agent_permissions.dart';
import 'agent_prompt.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';

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
  AgentController({
    required this.chatId,
    AgentService? service,
    AgentInternalService? internalService,
    Future<String?> Function()? workspaceId,
    this.mode = 'smart-reasoning',
    this.documentName = '',
    this.independent = false,
    this.initialThinking,
    AgentArtifacts? artifacts,
    Map<String, dynamic> cloudArtifacts = const {},
  })  : service = service ?? AgentService(),
        internalService = internalService ?? AgentInternalService(),
        artifacts = artifacts ?? AgentArtifacts(),
        cloudArtifacts = Map<String, dynamic>.from(cloudArtifacts),
        _workspace = workspaceId ?? AIChatViewService.getCurrentWorkspaceId;
  static final _instances = <AgentController>{};
  static final accountClearance = ValueNotifier(0);
  static Future<void> revokeAll() async {
    accountClearance.value++;
    await Future.wait(
      _instances.toList().map((controller) => controller.disconnect()),
    );
  }

  final String chatId;
  final String documentName;
  final bool independent;
  final String? initialThinking;
  final AgentService service;
  final AgentInternalService internalService;
  final Future<String?> Function() _workspace;
  final AgentArtifacts artifacts;
  final Map<String, dynamic> cloudArtifacts;
  String mode;
  bool _modeSelected = false;
  bool cloudSync = false;
  bool savingArtifacts = false;
  bool _saveArtifactsAgain = false;
  String? artifactError;
  final artifactFiles = <String, File>{};
  String get _storageKey => 'ponynotes.agent.artifacts.$_identity|$chatId';
  final messages = <Map<String, dynamic>>[];
  final activities = <String, AgentActivity>{};
  final sources = <String, Map<String, dynamic>>{};
  final references = <Map<String, dynamic>>[];
  final queuedInputs = <String>[];
  final _answerSegments = <String, String>{};
  final permissions = AgentPermissions();
  final interactions = <Map<String, dynamic>>[];
  final prompts = <String, AgentPrompt>{};
  String progressText = '';
  bool preparingNotes = false;
  final _handledCalls = <String>{};
  String _clientId = const Uuid().v4();
  Timer? _toolTimer;
  bool _pollingTools = false;
  int _toolEpoch = 0;
  bool _acceptNoteCalls = false;
  McpTools get noteTools => McpTools(
        endpoint: 'internal-agent',
        version: '1.0.0',
        isAgentChannel: true,
        agentName: () => '小马 Agent',
        isToolAllowed: (name) => !permissions.disabledTools.contains(name),
      );
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _workspaceId;
  String? _identity;
  String? activeMessageId;
  int _epoch = 0;
  int _run = 0;
  bool _disposed = false;
  bool _streamOpen = false;
  bool connected = false;
  bool connecting = false;
  bool running = false;
  int clearanceVersion = 0;
  String? error;
  String? notice;
  String streamingText = '';
  String model = '';
  String thinkingLevel = AgentModelPreferences.defaultLevel;
  bool webSearch = false;
  AiProviderConfig? providerConfig;
  AgentCredits? credits;
  String? creditsError;
  bool _creditsInFlight = false;
  bool _creditsRefreshAgain = false;
  Map<String, dynamic>? sessionTokens;
  Timer? _attachmentPoll;
  int _attachmentPollTicks = 0;
  Map<String, dynamic>? _pendingRetry;

  /// Tests shorten this to observe polling without waiting for real parses.
  @visibleForTesting
  Duration attachmentPollInterval = const Duration(seconds: 3);

  /// True when the last submission was rejected before WeKnora accepted it, so
  /// the original bytes are still in memory and the message can be re-sent.
  bool get canRetryUpload => _pendingRetry != null && !running;

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _isCurrent() async =>
      _workspaceId != null &&
      await _workspace() == _workspaceId &&
      await service.identity(_workspaceId!) == _identity;

  Future<void> connect() async {
    if (connecting || connected) return;
    connecting = true;
    error = null;
    changed();
    final epoch = ++_epoch;
    _instances.add(this);
    try {
      final workspace = await _workspace();
      if (workspace == null) throw StateError('请先打开工作区');
      _workspaceId = workspace;
      _identity = await service.identity(workspace);
      cloudSync =
          (await SharedPreferences.getInstance()).getBool(_storageKey) ?? false;
      await permissions.load(_identity!, chatId);
      _clientId = const Uuid().v4();
      if (mode == 'smart-reasoning') await _registerNoteTools();
      _startHeartbeat();
      thinkingLevel =
          initialThinking ?? await AgentModelPreferences.loadThinking();
      final data = await service.request('GET', workspace, chatId, '');
      if (epoch != _epoch) return;
      if (!await _isCurrent()) throw StateError('账号或工作区已切换');
      _history(data);
      _answerSegments.clear();
      streamingText = '';
      connected = true;
      unawaited(saveArtifacts());
      if (activeMessageId != null) {
        _listen(
          service.stream(
            'GET',
            workspace,
            chatId,
            '/stream?message_id=$activeMessageId',
          ),
          epoch,
        );
      }
      final selected = providerConfig ?? await internalService.preferred();
      if (epoch != _epoch || !await _isCurrent()) return;
      providerConfig = selected;
      model = selected.modelName;
      unawaited(refreshCredits());
    } catch (e) {
      if (epoch == _epoch) error = '$e';
    } finally {
      if (epoch == _epoch) {
        connecting = false;
        changed();
      }
    }
  }

  void _history(Map<String, dynamic> data) {
    if (data['cloud_artifacts'] is Map) {
      cloudArtifacts
          .addAll(Map<String, dynamic>.from(data['cloud_artifacts'] as Map));
    }
    // History reports the last submitted mode, not the user's next-turn choice.
    if (!_modeSelected &&
        ['quick-answer', 'smart-reasoning'].contains(data['mode'])) {
      mode = data['mode'] as String;
    }
    messages
      ..clear()
      ..addAll(
        (data['messages'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
    activities.clear();
    prompts.clear();
    for (final message in messages) {
      for (final value in [
        ...message['prompt_history'] as List? ?? [],
        if (message['pending_prompt'] is Map) message['pending_prompt'],
      ].whereType<Map>()) {
        final prompt = AgentPrompt.fromJson(
          value,
          '${message['id']}',
        );
        if (prompt.open && !prompt.expired) prompts[prompt.id] = prompt;
      }
    }
    for (final entry in cloudArtifacts.entries) {
      final file = Map<String, dynamic>.from(entry.value as Map);
      final id = file['message_id'] as String;
      final message = messages.where((m) => m['id'] == id).firstOrNull;
      final target = message ?? {'id': id, 'role': 'assistant', 'content': ''};
      final files = (target['artifacts'] as List? ?? []).toList();
      files.removeWhere((f) => f is Map && f['index'] == file['index']);
      files.add(file);
      target['artifacts'] = files;
      if (message == null) messages.add(target);
    }
    _sources(data['sources']);
    activeMessageId = data['active_message_id'] as String?;
    // ContinueStream replays this message from its beginning.
    if (activeMessageId != null) {
      messages.removeWhere((message) => message['id'] == activeMessageId);
    }
    running = activeMessageId != null;
    queuedInputs.removeWhere(
      (text) => messages.any(
        (message) => message['role'] == 'user' && message['content'] == text,
      ),
    );
    if (data['scope_changed'] == true) {
      notice = '可访问的笔记范围已变化，下一次提问将使用新会话；原会话仍保留在服务端。';
    }
    references.clear();
    for (final message in messages) {
      if (message['role'] == 'assistant') {
        references.addAll(
          (message['knowledge_references'] as List? ?? [])
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r)),
        );
      }
    }
  }

  void _sources(dynamic value) {
    if (value is! Map) return;
    sources
      ..clear()
      ..addAll(
        value.map(
          (key, value) =>
              MapEntry('$key', Map<String, dynamic>.from(value as Map)),
        ),
      );
  }

  Future<List<AgentReference>> loadReferences() async {
    final version = clearanceVersion;
    final workspace = await _workspace();
    if (workspace == null) throw StateError('请先打开工作区');
    if (_identity != null && !await _isCurrent()) throw StateError('账号或工作区已切换');
    final items = await service.references(workspace);
    if (_disposed ||
        version != clearanceVersion ||
        await _workspace() != workspace ||
        (_identity != null && !await _isCurrent())) {
      throw StateError('账号或工作区已切换，请重新选择引用');
    }
    return items;
  }

  Future<Map<String, dynamic>> loadReferenceFile(String id, int page) async {
    if (!await _isCurrent()) throw StateError('账号或工作区已切换');
    final version = clearanceVersion;
    final data = await service.request(
      'GET',
      _workspaceId!,
      '',
      '/references/${Uri.encodeComponent(id)}?page=$page',
    );
    if (_disposed || version != clearanceVersion || !await _isCurrent()) {
      throw StateError('账号或工作区已切换');
    }
    return data;
  }

  Future<bool> send(
    String text, {
    String behavior = 'prompt',
    List<Map<String, dynamic>> images = const [],
    List<Map<String, dynamic>> attachments = const [],
    List<AgentReference> contextReferences = const [],
    String? initialRequest,
  }) async {
    if (!connected) await connect();
    if (!connected) return false;
    if (!await _isCurrent()) {
      await disconnect();
      throw StateError('账号或工作区已切换，请重新打开文档');
    }
    if (running) {
      if (behavior == 'prompt' || activeMessageId == null) {
        throw StateError('当前回答尚未结束');
      }
      if (images.isNotEmpty ||
          attachments.isNotEmpty ||
          contextReferences.isNotEmpty) {
        throw StateError('请等待当前回答结束后发送附件或引用');
      }
      await service.request('POST', _workspaceId!, chatId, '/steer', {
        'query': text,
        'client_id': _clientId,
        'delivery': behavior == 'follow_up' ? 'after' : 'inject',
        'expected_assistant_message_id': activeMessageId,
      });
      queuedInputs.add(text);
      changed();
      return true;
    }
    final config = providerConfig;
    if (config == null) {
      error = '请先选择可用模型；已有文件仍可打开';
      changed();
      return false;
    }
    if (mode == 'smart-reasoning') await _registerNoteTools();
    final run = ++_run;
    final epoch = _epoch;
    await _subscription?.cancel();
    final accepted = Completer<bool>();
    running = true;
    error = null;
    activities.clear();
    references.clear();
    progressText = mode == 'quick-answer' ? '正在检索小马笔记' : '正在准备资料';
    notice = null;
    _answerSegments.clear();
    streamingText = '';
    final question = <String, dynamic>{
      'role': 'user',
      'content': text,
      if (attachments.isNotEmpty)
        'attachments': attachments
            .map(
              (file) => {
                'file_name': file['file_name'],
                'file_size': file['file_size'],
                'status': 'uploading',
                'uploaded': 0,
              },
            )
            .toList(),
      if (images.isNotEmpty)
        'images': images
            .map((image) => {'file_name': image['file_name'] ?? '图片'})
            .toList(),
      if (contextReferences.isNotEmpty)
        'mentioned_items': contextReferences
            .map((r) => {...r.toJson(), 'name': r.name})
            .toList(),
    };
    messages.add(question);
    changed();
    var noteContext = <Map<String, dynamic>>[];
    var noteSearchStatus = '';
    if (mode == 'quick-answer') {
      preparingNotes = true;
      final retrieved = await _quickNotes(text, epoch, run);
      if (epoch != _epoch || run != _run || _disposed) {
        if (epoch == _epoch && !_disposed) {
          messages.remove(question);
          changed();
        }
        return false;
      }
      if (!await _isCurrent()) {
        await disconnect();
        return false;
      }
      preparingNotes = false;
      noteContext = retrieved.$1;
      noteSearchStatus = retrieved.$2;
      progressText = '正在检索知识库';
      changed();
    }
    final body = <String, dynamic>{
      'query': text,
      'client_id': _clientId,
      'mode': mode,
      'model': {
        'model_name': config.modelName,
        'is_internal': config.isInternal,
        if (!config.isInternal) 'base_url': config.baseUrl,
        if (!config.isInternal) 'api_key': config.apiKey,
        'supports_reasoning': config.supportsReasoning,
      },
      'reasoning_effort': thinkingLevel,
      'web_search': webSearch,
      if (mode == 'quick-answer') ...{
        'note_context': noteContext,
        'note_search_status': noteSearchStatus,
      },
      'initial_request': initialRequest != null,
      'images': images
          .map(
            (image) =>
                {'data': 'data:${image['mimeType']};base64,${image['data']}'},
          )
          .toList(),
      'attachments': attachments,
      if (contextReferences.isNotEmpty)
        'references': contextReferences.map((r) => r.toJson()).toList(),
    };
    _listen(
      attachments.isEmpty
          ? service.stream('POST', _workspaceId!, chatId, '/messages', body)
          : service.streamWithProgress(
              'POST',
              _workspaceId!,
              chatId,
              '/messages',
              body,
              onProgress: (sent, total) =>
                  _trackUploadProgress(epoch, body, question, sent, total),
            ),
      epoch,
      accepted: accepted,
    );
    final sent = await accepted.future;
    if (!sent && epoch == _epoch) {
      for (final file
          in (question['attachments'] as List? ?? []).whereType<Map>()) {
        file['status'] = 'unconfirmed';
      }
      // Keep the original bytes so the user can re-send without re-picking.
      _pendingRetry = {
        'text': text,
        'question': question,
        'attachments': attachments,
        'references': contextReferences,
        'images': images,
      };
      changed();
    } else if (sent && epoch == _epoch) {
      _pendingRetry = null;
      if (attachments.isNotEmpty) _startAttachmentPoll(epoch);
    }
    return sent;
  }

  /// Re-sends a submission WeKnora never accepted, dropping the failed bubble
  /// first so the conversation does not keep a duplicate question.
  Future<bool> retryUpload() async {
    final pending = _pendingRetry;
    if (pending == null || running) return false;
    _pendingRetry = null;
    final question = pending['question'] as Map<String, dynamic>;
    final index = messages.indexWhere((message) => identical(message, question));
    if (index >= 0) messages.removeAt(index);
    changed();
    return send(
      pending['text'] as String,
      attachments: (pending['attachments'] as List)
          .whereType<Map<String, dynamic>>()
          .toList(),
      contextReferences: (pending['references'] as List<AgentReference>),
      images: (pending['images'] as List<Map<String, dynamic>>),
    );
  }

  static bool _settled(String? status) =>
      const {'ready', 'failed', 'expired'}.contains(status);

  /// Maps transported body bytes back onto the individual attachments so each
  /// file shows its own progress instead of one shared percentage.
  void _trackUploadProgress(
    int epoch,
    Map<String, dynamic> body,
    Map<String, dynamic> question,
    int sent,
    int total,
  ) {
    if (_disposed || epoch != _epoch) return;
    final spans = attachmentSpans(body);
    final files =
        (question['attachments'] as List? ?? []).whereType<Map>().toList();
    for (var index = 0; index < files.length && index < spans.length; index++) {
      final (start, end) = spans[index];
      if (end <= start) continue;
      final fraction = ((sent - start) / (end - start)).clamp(0.0, 1.0);
      files[index]['uploaded'] = (fraction * 100).round();
    }
    changed();
  }

  /// UTF-8 byte ranges of each attachment payload inside the serialized body.
  /// Base64 is ASCII, but the surrounding body is not, so UTF-16 indices from
  /// [String.indexOf] must be converted before they line up with byte counts.
  static List<(int, int)> attachmentSpans(Map<String, dynamic> body) {
    final payloads = (body['attachments'] as List? ?? [])
        .whereType<Map>()
        .map((file) => file['data'] as String? ?? '')
        .toList();
    if (payloads.isEmpty) return const [];
    final encoded = jsonEncode(body);
    final spans = <(int, int)>[];
    var cursor = 0;
    var bytesBefore = 0;
    var unitsBefore = 0;
    for (final payload in payloads) {
      if (payload.isEmpty) {
        spans.add((0, 0));
        continue;
      }
      final index = encoded.indexOf(payload, cursor);
      if (index < 0) {
        spans.add((0, 0));
        continue;
      }
      // Scan the gap once; attachments are ordered, so this stays linear.
      bytesBefore += _utf8Bytes(encoded, unitsBefore, index);
      unitsBefore = index;
      spans.add((bytesBefore, bytesBefore + payload.length));
      bytesBefore += payload.length;
      unitsBefore += payload.length;
      cursor = index + payload.length;
    }
    return spans;
  }

  static int _utf8Bytes(String text, int start, int end) {
    var bytes = 0;
    for (var index = start; index < end; index++) {
      final unit = text.codeUnitAt(index);
      if (unit < 0x80) {
        bytes += 1;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < end) {
        bytes += 4;
        index++;
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }

  /// Upload only proves WeKnora stored the file; parsing finishes later, so poll
  /// until every attachment reaches a terminal state instead of showing
  /// "processing" forever.
  void _startAttachmentPoll(int epoch) {
    _attachmentPoll?.cancel();
    _attachmentPollTicks = 0;
    _attachmentPoll = Timer.periodic(attachmentPollInterval, (timer) async {
      _attachmentPollTicks++;
      if (_disposed || epoch != _epoch) {
        timer.cancel();
        _attachmentPoll = null;
        return;
      }
      if (_attachmentPollTicks > 20) {
        timer.cancel();
        _attachmentPoll = null;
        return;
      }
      if (await _refreshAttachmentStatus(epoch) && timer.isActive) {
        timer.cancel();
        _attachmentPoll = null;
      }
    });
  }

  /// Returns true once no attachment is still pending.
  Future<bool> _refreshAttachmentStatus(int epoch) async {
    try {
      final statuses = await service.attachmentStatus(_workspaceId!, chatId);
      if (_disposed || epoch != _epoch) return true;
      final byId = {
        for (final status in statuses)
          if (status['id'] is String) status['id'] as String: status,
      };
      var pending = false;
      for (final message in messages) {
        for (final file
            in (message['attachments'] as List? ?? []).whereType<Map>()) {
          final status = byId[file['id']];
          if (status == null) continue;
          file['status'] = status['status'];
          if (status['error_message'] is String) {
            file['error_message'] = status['error_message'];
          }
          if (!_settled(status['status'] as String?)) pending = true;
        }
      }
      changed();
      return !pending;
    } catch (_) {
      // A transient failure is retried on the next tick.
      return false;
    }
  }

  Future<(List<Map<String, dynamic>>, String)> _quickNotes(
    String query,
    int epoch,
    int run,
  ) async {
    final notes = <Map<String, dynamic>>[];
    if (permissions.disabledTools.contains('search_notes') ||
        permissions.disabledTools.contains('get_page')) {
      notice = '笔记检索已关闭，本轮将检索知识库';
      return (notes, 'disabled');
    }
    final bridge = AgentNoteBridge(
      tools: noteTools,
      workspaceId: _workspaceId!,
      isCurrent: () async =>
          epoch == _epoch && run == _run && await _isCurrent(),
      approve: (_, __) async => false,
    );
    try {
      final found = await bridge.execute(
        'search_notes',
        {'workspace_id': _workspaceId, 'query': query, 'limit': 5},
      );
      if (found.isError) throw StateError('笔记检索未完成');
      final data = jsonDecode(_resultText(found)) as Map;
      var partial = data['complete'] == false;
      for (final item
          in (data['results'] as List? ?? []).whereType<Map>().take(5)) {
        if (epoch != _epoch || run != _run || !await _isCurrent()) {
          return (<Map<String, dynamic>>[], 'canceled');
        }
        final id = '${item['page_id'] ?? ''}';
        if (!Uuid.isValidUUID(fromString: id)) continue;
        final page = await bridge
            .execute('get_page', {'workspace_id': _workspaceId, 'page_id': id});
        if (epoch != _epoch || run != _run || !await _isCurrent()) {
          return (<Map<String, dynamic>>[], 'canceled');
        }
        if (page.isError) {
          partial = true;
          continue;
        }
        final body = jsonDecode(_resultText(page)) as Map;
        if (body['content_supported'] != true ||
            '${body['text'] ?? ''}'.trim().isEmpty) {
          continue;
        }
        final title =
            String.fromCharCodes('${item['title'] ?? '笔记'}'.runes.take(300));
        notes.add({
          'page_id': id,
          'title': title,
          'content': String.fromCharCodes('${body['text']}'.runes.take(4000)),
        });
        sources['note:$id'] = {
          'title': title,
          'url': 'ponynotes://open?viewId=$id&workspaceId=$_workspaceId',
        };
      }
      if (partial) notice = '部分笔记暂未读取完成，已使用可读取的笔记继续检索';
      return (
        notes,
        partial
            ? 'partial'
            : notes.isEmpty
                ? 'empty'
                : 'complete'
      );
    } catch (_) {
      if (epoch == _epoch && run == _run) notice = '笔记检索暂不可用，本轮将检索知识库；可重新连接后再试';
      return (notes, 'unavailable');
    }
  }

  void _listen(
    Stream<Map<String, dynamic>> stream,
    int epoch, {
    Completer<bool>? accepted,
  }) {
    var completed = false;
    _streamOpen = true;
    _subscription = stream.listen(
      (event) {
        if (epoch != _epoch || _disposed) return;
        if (event['response_type'] == 'scope' &&
            accepted?.isCompleted == false) {
          accepted!.complete(true);
        }
        if (event['response_type'] == 'complete') completed = true;
        receive(event);
      },
      onError: (Object e) {
        if (accepted?.isCompleted == false) accepted!.complete(false);
        if (epoch != _epoch || _disposed) return;
        _streamOpen = false;
        _cancelApprovals();
        error = agentDisplayText('$e');
        connected = false;
        running = false;
        changed();
      },
      onDone: () {
        if (accepted?.isCompleted == false) accepted!.complete(false);
        if (epoch != _epoch || _disposed) return;
        _streamOpen = false;
        if (!completed) {
          error ??= '回答连接已断开，重新连接可恢复；请勿重复提交问题';
          connected = false;
        }
        running = false;
        changed();
        if (completed) unawaited(_reloadHistory());
      },
      cancelOnError: true,
    );
  }

  @visibleForTesting
  void receive(Map<String, dynamic> event) {
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : <String, dynamic>{};
    activeMessageId =
        event['assistant_message_id'] as String? ?? activeMessageId;
    switch (event['response_type']) {
      case 'scope':
        _sources(data['sources']);
        final question = messages.where((m) => m['role'] == 'user').lastOrNull;
        if (question != null &&
            data['attachments'] is List &&
            (data['attachments'] as List).isNotEmpty) {
          question['attachments'] = data['attachments'];
        }
      case 'progress':
        _answerSegments.remove('${data['event_id'] ?? event['id']}');
        streamingText = _answerSegments.values.join();
        progressText = '${event['content'] ?? ''}';
      case 'agent_prompt_required':
      case 'tool_approval_required':
        if (activeMessageId != null) {
          final prompt = AgentPrompt.fromJson(data, activeMessageId!);
          prompts.putIfAbsent(prompt.id, () => prompt);
          progressText = prompt.kind == 'ask_user' ? '等待你的回答' : '等待你的确认';
        }
      case 'agent_prompt_resolved':
      case 'tool_approval_resolved':
        prompts.remove('${data['pending_id']}');
        progressText = '继续处理';
      case 'answer':
        final id = '${data['event_id'] ?? event['id'] ?? 'answer'}';
        final text = '${event['content'] ?? ''}';
        _answerSegments[id] = data['replace'] == true
            ? text
            : '${_answerSegments[id] ?? ''}$text';
        streamingText = _answerSegments.values.join();
      case 'tool_call':
        _answerSegments.clear();
        streamingText = '';
        final id = '${data['tool_call_id']}';
        activities[id] = AgentActivity(
          id: id,
          name: '${data['tool_name']}',
          arguments: data['arguments'] is Map
              ? Map<String, dynamic>.from(data['arguments'] as Map)
              : {},
        );
      case 'tool_result':
        final id = '${data['tool_call_id']}';
        final activity = activities.putIfAbsent(
          id,
          () => AgentActivity(
            id: id,
            name: '${data['tool_name']}',
            arguments: {},
          ),
        );
        activity.status = data['success'] == true ? 'completed' : 'failed';
        activity.result = '${event['content'] ?? data['error'] ?? ''}';
      case 'references':
        references
          ..clear()
          ..addAll(
            (data['references'] as List? ??
                    event['knowledge_references'] as List? ??
                    [])
                .whereType<Map>()
                .map((r) => Map<String, dynamic>.from(r)),
          );
      case 'user_message_injected':
        final text = '${data['query'] ?? event['content'] ?? ''}';
        queuedInputs.remove(text);
        if (text.isNotEmpty) messages.add({'role': 'user', 'content': text});
      case 'context_compacted':
        notice = '较早的对话已自动压缩';
      case 'error':
        error = agentDisplayText('${event['content'] ?? '小马 Agent 执行失败'}');
      case 'complete':
        if (data['final_content'] is String) {
          streamingText = data['final_content'] as String;
        }
        sessionTokens = event['usage'] is Map
            ? Map<String, dynamic>.from(event['usage'] as Map)
            : data['usage'] is Map
                ? Map<String, dynamic>.from(data['usage'] as Map)
                : null;
        if (streamingText.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'content': streamingText,
            'knowledge_references': references.toList(),
            'local_activities': activities.values.toList(),
          });
          activities.clear();
        }
        streamingText = '';
        _answerSegments.clear();
        activeMessageId = null;
        running = false;
        progressText = '';
        unawaited(refreshCredits());
    }
    changed();
  }

  Future<void> _reloadHistory() async {
    final epoch = _epoch;
    final run = _run;
    try {
      final data = await service.request('GET', _workspaceId!, chatId, '');
      if (epoch == _epoch && run == _run && await _isCurrent()) {
        _history(data);
        unawaited(saveArtifacts());
        if (activeMessageId != null && !_streamOpen && connected) {
          _answerSegments.clear();
          streamingText = '';
          _listen(
            service.stream(
              'GET',
              _workspaceId!,
              chatId,
              '/stream?message_id=$activeMessageId',
            ),
            epoch,
          );
        }
        changed();
      }
    } catch (e) {
      if (epoch == _epoch && run == _run) {
        error = '回答已结束，但历史刷新失败：$e';
        changed();
      }
    }
  }

  Future<void> answerPrompt(
    AgentPrompt prompt,
    Map<String, dynamic> response,
  ) async {
    if (prompt.submitting ||
        !prompt.open ||
        !connected ||
        !await _isCurrent()) {
      return;
    }
    final epoch = _epoch;
    prompt.submitting = true;
    prompt.error = null;
    changed();
    try {
      final result = await service
          .request('POST', _workspaceId!, chatId, '/prompt-response', {
        'pending_id': prompt.id,
        'message_id': prompt.messageId,
        'kind': prompt.kind,
        'response': response,
      });
      if (epoch != _epoch || !await _isCurrent()) return;
      prompt.status = 'answered';
      prompt.response = response;
      prompts.remove(prompt.id);
      progressText = '继续处理';
      if (result['resumed'] == true || !_streamOpen) {
        ++_run;
        service.closeStream();
        await _subscription?.cancel();
        _answerSegments.clear();
        streamingText = '';
        messages.removeWhere((m) => m['id'] == prompt.messageId);
        activeMessageId = prompt.messageId;
        running = true;
        _listen(
          service.stream(
            'GET',
            _workspaceId!,
            chatId,
            '/stream?message_id=${Uri.encodeComponent(prompt.messageId)}${result['resumed'] == true ? '&resume_pending_id=${Uri.encodeComponent(prompt.id)}' : ''}',
          ),
          epoch,
        );
      }
    } catch (e) {
      if (epoch == _epoch) {
        prompt.error = '回答未提交成功，请重试：${agentDisplayText('$e')}';
      }
    } finally {
      prompt.submitting = false;
      if (epoch == _epoch) changed();
    }
  }

  Future<void> stop() async {
    if (!connected || (!running && prompts.isEmpty)) return;
    if (preparingNotes) {
      ++_run;
      preparingNotes = false;
      running = false;
      progressText = '';
      notice = '检索已停止，问题尚未发送';
      changed();
      return;
    }
    try {
      _acceptNoteCalls = false;
      _cancelApprovals();
      if (!await _isCurrent()) throw StateError('账号或工作区已切换');
      await service.request('POST', _workspaceId!, chatId, '/stop', {});
      service.closeStream();
      await _subscription?.cancel();
      running = false;
      await _reloadHistory();
    } catch (e) {
      error = '$e';
      changed();
    }
  }

  Future<void> configureModel(AiProviderConfig config, String thinking) async {
    if (running || connecting) throw StateError('请等待当前回答结束后切换模型');
    providerConfig = config;
    model = config.modelName;
    thinkingLevel = thinking;
    error = null;
    credits = null;
    changed();
    if (connected) unawaited(refreshCredits());
  }

  void configureMode(bool smart) {
    _modeSelected = true;
    mode = smart ? 'smart-reasoning' : 'quick-answer';
    changed();
  }

  Future<void> configureCloudSync(bool enabled) async {
    if (_identity == null) return;
    cloudSync = enabled;
    await (await SharedPreferences.getInstance()).setBool(_storageKey, enabled);
    changed();
    await saveArtifacts();
  }

  String artifactKey(String message, int index) => '$message/$index';

  List<AgentArtifact> get savedArtifacts => [
        for (final message in messages)
          for (final artifact
              in (message['artifacts'] as List? ?? []).whereType<Map>())
            if (artifactFiles[
                    artifactKey('${message['id']}', artifact['index'] as int)]
                case final file?)
              AgentArtifact(
                document: chatId,
                message: '${message['id']}',
                index: artifact['index'] as int,
                name: '${artifact['file_name']}',
                size: artifact['file_size'] as int,
                file: file,
                createdAt: DateTime.tryParse('${artifact['created_at']}') ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                documentName: documentName,
                independent: independent,
                cloudUrl: artifact['cloud_url'] as String?,
              ),
      ];

  Future<void> saveArtifacts() async {
    if (savingArtifacts) {
      _saveArtifactsAgain = true;
      return;
    }
    if (!connected || _identity == null) return;
    final epoch = _epoch;
    final identity = _identity!;
    final workspace = _workspaceId!;
    savingArtifacts = true;
    artifactError = null;
    changed();
    try {
      final history =
          messages.map((m) => Map<String, dynamic>.from(m)).toList();
      if (history.isEmpty) return;
      for (final message in history) {
        for (final artifact
            in (message['artifacts'] as List? ?? []).whereType<Map>()) {
          if (epoch != _epoch || !await _isCurrent()) return;
          final value = Map<String, dynamic>.from(artifact);
          final id = message['id'] as String;
          final index = value['index'] as int;
          final key = artifactKey(id, index);
          final file = await artifacts.save(
            identity: identity,
            document: chatId,
            message: id,
            artifact: value,
            independent: independent,
            documentName: documentName,
            download: (destination) => value['cloud_url'] is String
                ? service.downloadCloudArtifact(
                    identity,
                    workspace,
                    value['cloud_url'] as String,
                    destination,
                  )
                : service.downloadArtifact(
                    identity,
                    workspace,
                    chatId,
                    id,
                    index,
                    destination,
                  ),
          );
          if (epoch != _epoch || !await _isCurrent()) return;
          artifactFiles[key] = file;
          if (cloudSync && value['cloud_url'] == null) {
            final url = await service.uploadArtifact(
              identity,
              workspace,
              file,
              'pn-agent-v1-$chatId-$id-$index${p.extension(file.path)}',
            );
            if (epoch != _epoch || !await _isCurrent()) return;
            if (independent) {
              await service.request('POST', workspace, chatId, '/artifacts', {
                'message_id': id,
                'index': index,
                'file_name': value['file_name'],
                'file_size': value['file_size'],
                'cloud_url': url,
              });
              if (epoch != _epoch || !await _isCurrent()) return;
              cloudArtifacts[key] = {
                ...value,
                'message_id': id,
                'cloud_url': url,
              };
              artifact['cloud_url'] = url;
              continue;
            }
            final view = (await ViewBackendService.getView(chatId))
                .fold((v) => v, (e) => throw StateError(e.msg));
            final extra = view.extra.isEmpty
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(jsonDecode(view.extra) as Map);
            final files = Map<String, dynamic>.from(
              extra['agent_artifacts'] as Map? ?? {},
            );
            files[key] = {...value, 'message_id': id, 'cloud_url': url};
            extra['agent_artifacts'] = files;
            if (epoch != _epoch || !await _isCurrent()) return;
            (await ViewBackendService.updateView(
              viewId: chatId,
              extra: jsonEncode(extra),
            ))
                .fold((_) {}, (e) => throw StateError(e.msg));
            cloudArtifacts[key] = files[key];
            artifact['cloud_url'] = url;
          }
        }
      }
    } catch (e) {
      if (epoch == _epoch) {
        artifactError = '文件保存失败，可重试：${agentDisplayText('$e')}';
      }
    } finally {
      if (epoch == _epoch) {
        savingArtifacts = false;
        changed();
        if (_saveArtifactsAgain) {
          _saveArtifactsAgain = false;
          unawaited(saveArtifacts());
        }
      }
    }
  }

  Future<void> refreshCredits() async {
    final config = providerConfig;
    if (config == null) return;
    if (_creditsInFlight) {
      _creditsRefreshAgain = true;
      return;
    }
    _creditsInFlight = true;
    final epoch = _epoch;
    try {
      if (_identity != null && !await _isCurrent()) {
        throw StateError('账号或工作区已切换');
      }
      final value = config.isInternal
          ? await internalService.credits()
          : await fetchAgentCredits(config);
      if (_identity != null && !await _isCurrent()) {
        throw StateError('账号或工作区已切换');
      }
      if (epoch == _epoch && identical(config, providerConfig)) {
        credits = value;
        creditsError = null;
        changed();
      }
    } catch (_) {
      if (epoch == _epoch && identical(config, providerConfig)) {
        credits = null;
        creditsError = '积分查询失败，请稍后重试';
        changed();
      }
    } finally {
      _creditsInFlight = false;
      if (_creditsRefreshAgain && connected && !_disposed) {
        _creditsRefreshAgain = false;
        unawaited(refreshCredits());
      } else {
        _creditsRefreshAgain = false;
      }
    }
  }

  Future<void> disconnect() async {
    _acceptNoteCalls = false;
    _cancelApprovals();
    _attachmentPoll?.cancel();
    _attachmentPoll = null;
    _toolTimer?.cancel();
    _toolTimer = null;
    if (_workspaceId != null) {
      unawaited(
        service
            .request(
              'DELETE',
              _workspaceId!,
              chatId,
              '/tools?client_id=$_clientId',
            )
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    ++_epoch;
    service.closeStream();
    await _subscription?.cancel();
    _subscription = null;
    connected = false;
    _streamOpen = false;
    connecting = false;
    running = false;
    ++clearanceVersion;
    messages.clear();
    artifactFiles.clear();
    cloudArtifacts.clear();
    savingArtifacts = false;
    _saveArtifactsAgain = false;
    artifactError = null;
    activities.clear();
    prompts.clear();
    preparingNotes = false;
    progressText = '';
    references.clear();
    sources.clear();
    queuedInputs.clear();
    _answerSegments.clear();
    streamingText = '';
    activeMessageId = null;
    _identity = null;
    _workspaceId = null;
    credits = null;
    creditsError = null;
    error = null;
    notice = null;
    changed();
  }

  Future<void> _registerNoteTools() async {
    _cancelApprovals();
    await service.request('POST', _workspaceId!, chatId, '/tools', {
      'client_id': _clientId,
      'tools': noteTools.toolSpecs
          .where((spec) => !permissions.disabledTools.contains(spec.name))
          .map(
            (spec) => {
              'name': spec.name, 'description': spec.description,
              'inputSchema': spec.inputSchema.toJson(),
              // This relay submits a request; Flutter approves the actual mutation.
              'annotations': {
                'readOnlyHint': spec.readOnly,
                'destructiveHint': spec.destructive,
              },
            },
          )
          .toList(),
    });
    _acceptNoteCalls = true;
  }

  void _startHeartbeat() {
    _toolTimer?.cancel();
    _toolTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_acceptNoteCalls) unawaited(_pollNoteTools());
      if (connected && timer.tick % 5 == 0) unawaited(refreshCredits());
    });
  }

  Future<void> configurePermissions({
    String? mode,
    Set<String>? disabled,
  }) async {
    if (mode != null && !AgentPermissions.modes.contains(mode)) {
      throw ArgumentError.value(mode, 'mode');
    }
    if (running || connecting || interactions.isNotEmpty || prompts.isNotEmpty) {
      throw StateError('请等待当前任务结束后修改审批模式或笔记工具');
    }
    final previousMode = permissions.mode;
    final previousDisabled = permissions.disabledTools.toSet();
    if (mode != null) permissions.mode = mode;
    if (disabled != null) {
      permissions.disabledTools
        ..clear()
        ..addAll(disabled);
    }
    try {
      await permissions.save();
    } catch (_) {
      permissions.mode = previousMode;
      permissions.disabledTools
        ..clear()
        ..addAll(previousDisabled);
      rethrow;
    }
    if (connected && disabled != null) await _registerNoteTools();
    changed();
  }

  Future<void> _pollNoteTools() async {
    if (_pollingTools ||
        !_acceptNoteCalls ||
        (!connected && !connecting) ||
        _disposed) {
      return;
    }
    _pollingTools = true;
    final epoch = _epoch;
    try {
      if (!await _isCurrent()) {
        await disconnect();
        return;
      }
      final data = await service
          .request('GET', _workspaceId!, chatId, '/tools?client_id=$_clientId')
          .timeout(const Duration(seconds: 10));
      if (epoch != _epoch) return;
      if (!running && queuedInputs.isNotEmpty) await _reloadHistory();
      for (final value in data['calls'] as List? ?? []) {
        final call = Map<String, dynamic>.from(value as Map);
        if (_acceptNoteCalls && _handledCalls.add('${call['id']}')) {
          unawaited(_noteCall(call));
        }
      }
    } catch (e) {
      if (epoch == _epoch) {
        _cancelApprovals();
        _toolTimer?.cancel();
        error = '笔记工具连接已断开，请重新连接：${agentDisplayText('$e')}';
        connected = false;
        changed();
      }
    } finally {
      _pollingTools = false;
    }
  }

  static String _resultText(CallToolResult result) => result.content
      .whereType<TextContent>()
      .map((part) => part.text)
      .join('\n');
  Future<void> _noteCall(Map<String, dynamic> call) async {
    final epoch = _epoch;
    final toolEpoch = _toolEpoch;
    final workspace = _workspaceId!;
    final clientId = _clientId;
    final tools = noteTools;
    String? before;
    String? after;
    final activity = AgentActivity(
      id: 'note-${call['id']}',
      name: '${call['name']}',
      arguments: Map<String, dynamic>.from(call['arguments'] as Map),
    );
    activities[activity.id] = activity;
    changed();
    final bridge = AgentNoteBridge(
      tools: tools,
      workspaceId: workspace,
      isCurrent: () async {
        if (epoch != _epoch ||
            toolEpoch != _toolEpoch ||
            !connected ||
            !await _isCurrent()) {
          return false;
        }
        final pending = await service.request(
          'GET',
          workspace,
          chatId,
          '/tools?client_id=$clientId',
        );
        return epoch == _epoch &&
            toolEpoch == _toolEpoch &&
            connected &&
            (pending['calls'] as List? ?? [])
                .any((value) => value['id'] == call['id']);
      },
      approve: (spec, args) async {
        if (args['page_id'] is String &&
            !permissions.disabledTools.contains('get_page')) {
          final snapshot = await tools.executeTool(
            'get_page',
            {'workspace_id': workspace, 'page_id': args['page_id']},
          );
          if (!snapshot.isError) before = _resultText(snapshot);
        }
        if (permissions.mode == 'full' ||
            (permissions.mode == 'auto' && !spec.destructive)) {
          return true;
        }
        final confirmation = Completer<bool>();
        final approval = <String, dynamic>{
          ...call,
          'title': spec.name,
          'confirmation': confirmation,
          'before': before,
        };
        interactions.add(approval);
        activity.status = 'waiting';
        changed();
        final allowed = await confirmation.future
            .timeout(const Duration(seconds: 110), onTimeout: () => false);
        interactions.remove(approval);
        activity.status = 'running';
        changed();
        if (allowed && before != null) {
          final snapshot = await tools.executeTool(
            'get_page',
            {'workspace_id': workspace, 'page_id': args['page_id']},
          );
          if (snapshot.isError || _resultText(snapshot) != before) {
            throw StateError('确认期间页面已改变，请重新读取后再修改');
          }
        }
        return allowed;
      },
    );
    final result = await bridge.execute(
      '${call['name']}',
      Map<String, dynamic>.from(call['arguments'] as Map),
    );
    if (before != null &&
        !result.isError &&
        epoch == _epoch &&
        toolEpoch == _toolEpoch &&
        await _isCurrent()) {
      final snapshot = await tools.executeTool(
        'get_page',
        {'workspace_id': workspace, 'page_id': call['arguments']['page_id']},
      );
      if (!snapshot.isError) after = _resultText(snapshot);
    }
    activity
      ..status = result.isError ? 'failed' : 'completed'
      ..result = _resultText(result)
      ..before = before
      ..after = after;
    if (epoch != _epoch) return;
    activities[activity.id] = activity;
    changed();
    try {
      await service.request(
        'POST',
        workspace,
        chatId,
        '/tool-result',
        {'client_id': clientId, 'id': call['id'], 'result': result.toJson()},
      );
    } catch (e) {
      if (epoch == _epoch) {
        error = '笔记操作结果回传失败，请查询实际结果，不要重复写入：${agentDisplayText('$e')}';
        changed();
      }
    }
  }

  void respond(Map<String, dynamic> request, bool allowed) {
    interactions.remove(request);
    final confirmation = request['confirmation'] as Completer<bool>;
    if (!confirmation.isCompleted) confirmation.complete(allowed);
    changed();
  }

  void _cancelApprovals() {
    ++_toolEpoch;
    for (final request in interactions.toList()) {
      respond(request, false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _attachmentPoll?.cancel();
    _attachmentPoll = null;
    _instances.remove(this);
    unawaited(disconnect());
    super.dispose();
  }
}
