import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/mcp/application/mcp_tools.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

import 'ai_provider_config.dart';

/// 内部 AI 的一次工具调用记录，供界面展示「AI 做了什么」。
class AiToolCallRecord {
  AiToolCallRecord({
    required this.name,
    required this.arguments,
    required this.result,
    required this.isError,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final String result;
  final bool isError;
}

/// 内部 AI 的最终结果。
class InternalAiResult {
  InternalAiResult({
    required this.text,
    required this.toolCalls,
    this.requiresConfirmation = false,
    this.pendingWrite,
  });

  /// 模型给出的自然语言答复。
  final String text;

  /// 本轮执行过的全部工具调用，按顺序。
  final List<AiToolCallRecord> toolCalls;

  /// 是否因为命中写操作而暂停，等待用户确认。
  final bool requiresConfirmation;

  /// 等待确认的写操作。
  final AiToolCallRecord? pendingWrite;
}

/// 内部 AI 调用失败的原因，区分开给用户看。
enum InternalAiErrorKind {
  /// 用户没配置模型地址、模型名或 API Key。
  notConfigured,

  /// 网络不通或超时。
  network,

  /// 模型服务返回 401/403，通常是 Key 无效。
  unauthorized,

  /// 模型服务返回 429，配额耗尽——这部分成本由用户自己承担。
  quotaExhausted,

  /// 用户主动中断。
  canceled,

  /// 模型服务返回其他错误。
  serverError,

  /// 模型反复要求调用工具，超过轮次上限。
  tooManyRounds,
}

class InternalAiException implements Exception {
  InternalAiException(this.kind, this.message);

  final InternalAiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 内部 AI：使用用户自行配置的模型服务（OpenAI 兼容端点），复用 [McpTools] 的工具能力。
///
/// 与外部 Agent 的 MCP 通道相互独立：MCP Token 用于 Agent 访问小马，
/// 这里的 API Key 用于小马访问模型服务，两者不混用、不互相透传。
class InternalAiService {
  InternalAiService({
    McpTools? tools,
    http.Client? httpClient,
    this.writeConfirmationRequired = true,
  })  : _tools = tools ?? McpTools(endpoint: 'internal', version: '1.0.0'),
        _clientFactory = httpClient == null ? http.Client.new : (() => httpClient);

  final McpTools _tools;

  /// 每次请求新建一个 client，取消时直接 close 掉当前这个，
  /// 下一个请求不受影响。
  final http.Client Function() _clientFactory;
  http.Client? _activeClient;
  bool _canceled = false;

  /// 写操作是否需要用户确认。默认开启：内部 AI 具备删页面、删块的能力，
  /// 全自动执行的风险不可接受。
  final bool writeConfirmationRequired;

  /// 单次提问允许的最大工具调用轮次，防止模型陷入无限循环。
  static const int maxRounds = 8;

  /// 用户是否中断了当前请求。
  bool get isCanceled => _canceled;

  /// 中断当前请求：关掉连接，正在等待的请求会抛 canceled。
  void cancel() {
    _canceled = true;
    _activeClient?.close();
  }

  static const Duration _requestTimeout = Duration(seconds: 60);

  /// 读取用户配置的模型地址、模型名与 API Key。
  ///
  /// 存在 Dart 侧的 `SharedPreferences`，与 Ollama 的 `LocalAISetting` 互不影响。
  Future<AiProviderConfig> loadConfig() =>
      const AiProviderConfigStorage().load();

  /// 判断配置是否可用。
  bool isConfigured(AiProviderConfig config) => config.isComplete;

  /// 系统提示：告诉模型它在哪、工具怎么用、写操作要确认。
  /// 模型不知道训练截止之后的日期，所以当前时间按运行时生成。
  static String buildSystemPrompt({DateTime? now}) {
    final time = (now ?? DateTime.now()).toIso8601String().substring(0, 16);
    return '你是小马笔记（PonyNotes）的内置 AI 助手，通过工具读写用户的笔记。\n'
        '当前时间：$time。\n'
        '- 调用其他工具前先用 get_context 取 current_workspace.workspace_id，之后每个工具都带上它。\n'
        '- 页面 ID、块 ID 一律通过 list_pages / search_notes / get_page / list_blocks 查询，不要编造。\n'
        '- 写操作需要用户确认，确认前不会执行；一次只提交一个写操作，等结果再继续。\n'
        '- 用户说「这个页面」「当前页面」但上下文里没有页面 ID 时，先用 search_notes 查找或直接问清楚。\n'
        '- 用中文回答，简洁直接；工具报错时如实说明，不要假装成功。';
  }

  /// 发起一次带工具能力的对话。
  ///
  /// [history] 是此前的对话消息（OpenAI 格式），用于多轮上下文。
  /// [confirmWrite] 在遇到写操作时询问用户；返回 false 表示拒绝执行。
  /// 不传该回调时，遇到写操作会直接返回 `requiresConfirmation` 结果。
  Future<InternalAiResult> ask({
    required String question,
    List<Map<String, dynamic>> history = const [],
    bool confirmedWrite = false,
    Future<bool> Function(AiToolCallRecord pending)? confirmWrite,
    AiProviderConfig? configOverride,
  }) async {
    _canceled = false;
    final config = configOverride ?? await loadConfig();
    if (!isConfigured(config)) {
      throw InternalAiException(
        InternalAiErrorKind.notConfigured,
        '尚未配置模型地址、模型名称或 API Key。',
      );
    }

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': buildSystemPrompt()},
      ...history,
      {'role': 'user', 'content': question},
    ];
    final records = <AiToolCallRecord>[];

    for (var round = 0; round < maxRounds; round++) {
      final response = await _postChatCompletion(
        config,
        messages,
      );

      final choice = _firstChoice(response);
      final message = choice['message'] as Map<String, dynamic>? ?? const {};
      final toolCalls = (message['tool_calls'] as List<dynamic>?) ?? const [];

      if (toolCalls.isEmpty) {
        return InternalAiResult(
          text: (message['content'] as String?)?.trim() ?? '',
          toolCalls: records,
        );
      }

      // 把模型这一轮的 tool_calls 原样回填，OpenAI 协议要求成对出现。
      messages.add(message);

      for (final raw in toolCalls) {
        final call = raw as Map<String, dynamic>;
        final function = call['function'] as Map<String, dynamic>? ?? const {};
        final name = function['name'] as String? ?? '';
        final rawArgs = function['arguments'] as String? ?? '{}';
        final parsedArgs = _decodeArguments(rawArgs);

        // 写操作在未确认时暂停执行：先告诉用户将要做什么。
        if (writeConfirmationRequired &&
            !confirmedWrite &&
            !_isReadOnly(name)) {
          final pending = AiToolCallRecord(
            name: name,
            arguments: parsedArgs,
            result: '等待用户确认',
            isError: false,
          );
          if (confirmWrite == null) {
            return InternalAiResult(
              text: '需要你确认后才会执行：$name',
              toolCalls: records,
              requiresConfirmation: true,
              pendingWrite: pending,
            );
          }
          final allowed = await confirmWrite(pending);
          if (!allowed) {
            return InternalAiResult(
              text: '已取消：$name 没有执行。',
              toolCalls: records,
            );
          }
        }

        final result = await _tools.executeTool(name, parsedArgs);
        final isError = result.isError;
        final text = _resultText(result);
        records.add(
          AiToolCallRecord(
            name: name,
            arguments: parsedArgs,
            result: text,
            isError: isError,
          ),
        );

        messages.add({
          'role': 'tool',
          'tool_call_id': call['id'] ?? '',
          'content': text,
        });
      }
    }

    throw InternalAiException(
      InternalAiErrorKind.tooManyRounds,
      '模型连续调用工具超过 $maxRounds 轮，已停止。请把问题拆细一些再试。',
    );
  }

  /// 工具名到只读属性的判断，复用 [McpTools] 的注册表。
  bool _isReadOnly(String name) {
    final spec = _tools.toolSpecs.where((s) => s.name == name).firstOrNull;
    return spec?.readOnly ?? false;
  }

  /// 把 OpenAI 的 tools 声明由 [McpTools] 注册表生成。
  List<Map<String, dynamic>> _toolsPayload() {
    return _tools.toolSpecs.map((spec) {
      return {
        'type': 'function',
        'function': {
          'name': spec.name,
          'description': spec.description,
          'parameters': spec.inputSchema.toJson(),
        },
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _postChatCompletion(
    AiProviderConfig config,
    List<Map<String, dynamic>> messages,
  ) async {
    final uri = _chatCompletionsUri(config.baseUrl);
    final body = jsonEncode({
      'model': config.modelName,
      'messages': messages,
      'tools': _toolsPayload(),
      'tool_choice': 'auto',
    });

    final client = _clientFactory();
    _activeClient = client;
    http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: body,
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw InternalAiException(
        InternalAiErrorKind.network,
        '模型服务响应超时，请稍后重试。',
      );
    } catch (e) {
      if (_canceled) {
        throw InternalAiException(InternalAiErrorKind.canceled, '已取消。');
      }
      throw InternalAiException(
        InternalAiErrorKind.network,
        '连接模型服务失败：$e',
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
    }

    switch (response.statusCode) {
      case 200:
        try {
          return jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          throw InternalAiException(
            InternalAiErrorKind.serverError,
            '模型服务返回的内容无法解析：$e',
          );
        }
      case 401:
      case 403:
        throw InternalAiException(
          InternalAiErrorKind.unauthorized,
          'API Key 无效或无权访问该模型，请检查配置。',
        );
      case 429:
        throw InternalAiException(
          InternalAiErrorKind.quotaExhausted,
          '模型服务配额已用尽或触发限流。'
          '这部分额度由你自己的账号承担，请检查用量或更换 Key。',
        );
      default:
        throw InternalAiException(
          InternalAiErrorKind.serverError,
          '模型服务返回 HTTP ${response.statusCode}：${_truncate(response.body)}',
        );
    }
  }

  /// 兼容用户填写的地址是否已包含 `/v1` 或完整路径。
  Uri _chatCompletionsUri(String serverUrl) {
    var base = serverUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) {
      return Uri.parse(base);
    }
    if (base.endsWith('/v1')) {
      return Uri.parse('$base/chat/completions');
    }
    return Uri.parse('$base/v1/chat/completions');
  }

  Map<String, dynamic> _firstChoice(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw InternalAiException(
        InternalAiErrorKind.serverError,
        '模型服务没有返回任何回复内容。',
      );
    }
    return choices.first as Map<String, dynamic>;
  }

  Map<String, dynamic> _decodeArguments(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (e) {
      // 模型偶发返回非法 JSON，不中断整个流程，交给工具层报参数错误。
      Log.warn('[InternalAI] decode tool arguments failed: $e');
      return const {};
    }
  }

  String _resultText(mcpResult) {
    final content = mcpResult.content as List<dynamic>? ?? const [];
    final buffer = StringBuffer();
    for (final item in content) {
      final text = (item as dynamic).text;
      if (text is String) buffer.write(text);
    }
    return _truncate(buffer.toString());
  }

  String _truncate(String text) {
    const max = 8000;
    return text.length <= max ? text : '${text.substring(0, max)}…(已截断)';
  }

  void dispose() {
    _activeClient?.close();
    _activeClient = null;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
