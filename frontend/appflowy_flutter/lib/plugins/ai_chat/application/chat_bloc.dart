import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_animation_list_widget.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'chat_entity.dart';
import 'chat_message_handler.dart';
import 'chat_message_listener.dart';
import 'chat_message_stream.dart';
import 'chat_settings_manager.dart';
import 'chat_stream_manager.dart';

part 'chat_bloc.freezed.dart';

/// Returns current Unix timestamp (seconds since epoch)
int timestamp() {
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required this.chatId,
    required this.userId,
    this.initialMessage,
    this.preferredModelId,
    this.enableDeepThinking = false,
    this.enableWebSearch = false,
    this.initialImagePaths,
  })  : chatController = InMemoryChatController(),
        listener = ChatMessageListener(chatId: chatId),
        super(ChatState.initial()) {
    // Initialize managers
    _messageHandler = ChatMessageHandler(
      chatId: chatId,
      userId: userId,
      chatController: chatController,
    );

    _streamManager = ChatStreamManager(
      chatId,
      enableDeepThinking: enableDeepThinking,
      enableWebSearch: enableWebSearch,
    );
    _settingsManager = ChatSettingsManager(chatId: chatId);

    _startListening();
    _dispatch();
    _loadMessages();
    _loadSettings();

    // workspaceId 将在异步获取后设置

    // 如果有首选模型，设置为默认模型
    if (preferredModelId != null && preferredModelId!.isNotEmpty) {
      Log.info('🔄 ChatBloc: 检测到首选模型，准备设置: $preferredModelId');
      _setPreferredModel(preferredModelId!);
    } else {
      // 如果没有首选模型，立即标记模型设置完成
      _modelSettingCompleted = true;
      if (!_modelSettingCompleter.isCompleted) {
        _modelSettingCompleter.complete();
      }
    }

    // 注意：初始消息的自动发送逻辑移到了 _handleLatestMessages 中
    // 这样可以确保只在首次创建（本地无消息）时才自动发送
    if (initialMessage != null && initialMessage!.isNotEmpty) {
      Log.info('ℹ️ ChatBloc: 检测到初始消息（将在加载消息后判断是否发送）');
      Log.info('   - 消息: $initialMessage');
      Log.info('   - 首选模型: $preferredModelId');
      Log.info('   - 深度思考: ${enableDeepThinking ? "开启" : "关闭"}');
      Log.info('   - 全网搜索: ${enableWebSearch ? "开启" : "关闭"}');
      Log.info('   - 图片数量: ${initialImagePaths?.length ?? 0}');
    } else {
      Log.info('ℹ️ ChatBloc: 没有初始消息');
    }
  }

  // 首条消息暂存于 view.extra，移动端在异步清除前可能重建 ChatBloc。
  // 图片复制和 Base64 转换会放大该窗口，因此同一会话在本进程内只允许一个
  // ChatBloc 消费 initial_message，避免重复发出完整的图文请求。
  static final Set<String> _claimedInitialMessageChatIds = <String>{};

  final String chatId;
  final String userId;
  final String? initialMessage;
  final String? preferredModelId;
  final bool enableDeepThinking;
  final bool enableWebSearch;
  final List<String>? initialImagePaths;
  String? _workspaceId;
  final ChatMessageListener listener;
  final ChatController chatController;

  // Managers
  late final ChatMessageHandler _messageHandler;
  late final ChatStreamManager _streamManager;
  late final ChatSettingsManager _settingsManager;

  ChatMessagePB? lastSentMessage;

  bool isLoadingPreviousMessages = false;
  bool hasMorePreviousMessages = true;
  bool isFetchingRelatedQuestions = false;
  bool shouldFetchRelatedQuestions = false;

  // 标志：初始消息是否已经发送过
  bool _initialMessageSent = false;

  // 标志：模型设置是否完成
  bool _modelSettingCompleted = false;
  final Completer<void> _modelSettingCompleter = Completer<void>();

  // Accessor for selected sources
  ValueNotifier<List<String>> get selectedSourcesNotifier =>
      _settingsManager.selectedSourcesNotifier;

  @override
  Future<void> close() async {
    // Safely dispose all resources
    await _streamManager.dispose();
    await listener.stop();

    final request = ViewIdPB(value: chatId);
    unawaited(FolderEventCloseView(request).send());

    _settingsManager.dispose();
    chatController.dispose();

    // 重置全局欢迎页标志，以免影响下一个Chat
    skipAIChatWelcomePage = false;
    Log.info('🔄 ChatBloc: 已重置欢迎页标志');

    return super.close();
  }

  void _dispatch() {
    on<ChatEvent>((event, emit) async {
      await event.when(
        // Chat settings
        didReceiveChatSettings: (settings) async =>
            _handleChatSettings(settings),
        updateSelectedSources: (selectedSourcesIds) async =>
            _handleUpdateSources(selectedSourcesIds),

        // Message loading
        didLoadLatestMessages: (messages) async =>
            _handleLatestMessages(messages, emit),
        loadPreviousMessages: () async => _loadPreviousMessagesIfNeeded(),
        didLoadPreviousMessages: (messages, hasMore) async =>
            _handlePreviousMessages(messages, hasMore),

        // Message handling
        receiveMessage: (message) async => _handleReceiveMessage(message),

        // Sending messages
        sendMessage: (message, format, metadata, promptId, enableDeepThinking,
                enableWebSearch) async =>
            _handleSendMessage(message, format, metadata, promptId,
                enableDeepThinking, enableWebSearch, emit),
        finishSending: () async {
          if (state.promptResponseState.isReady) {
            return;
          }
          emit(
            state.copyWith(
              promptResponseState: PromptResponseState.streamingAnswer,
            ),
          );
        },

        // Stream control
        stopStream: () async => _handleStopStream(emit),
        failedSending: () async => _handleFailedSending(emit),

        // Answer regeneration
        regenerateAnswer: (id, format, model) async =>
            _handleRegenerateAnswer(id, format, model, emit),

        // Streaming completion
        didFinishAnswerStream: () async => emit(
          state.copyWith(
            promptResponseState: PromptResponseState.ready,
          ),
        ),

        // Related questions
        didReceiveRelatedQuestions: (questions) async =>
            _handleRelatedQuestions(
          questions,
          emit,
        ),

        // Usage refresh
        refreshUsage: () async => _refreshUsage(emit),
        setWorkspaceId: (workspaceId) async {
          // 更新 workspaceId 并刷新使用情况
          _workspaceId = workspaceId;
          await _refreshUsage(emit);
        },

        // Message management
        deleteMessage: (message) async => chatController.remove(message),

        // AI follow-up
        onAIFollowUp: (followUpData) async {
          shouldFetchRelatedQuestions =
              followUpData.shouldGenerateRelatedQuestion;
        },
      );
    });
  }

  // Chat settings handlers
  void _handleChatSettings(ChatSettingsPB settings) {
    _settingsManager.selectedSourcesNotifier.value = settings.ragIds;
  }

  Future<void> _handleUpdateSources(List<String> selectedSourcesIds) async {
    await _settingsManager.updateSelectedSources(selectedSourcesIds);
  }

  // Message loading handlers
  Future<void> _handleLatestMessages(
    List<Message> messages,
    Emitter<ChatState> emit,
  ) async {
    Log.info('🔍 ChatBloc._handleLatestMessages 被调用');
    Log.info('   - 接收到消息数: ${messages.length}');
    Log.info('   - 当前controller中消息数: ${chatController.messages.length}');
    Log.info('   - initialMessage: $initialMessage');

    // 【修复消息重复】去重：只插入不存在的消息
    int insertedCount = 0;
    for (final message in messages) {
      // 检查消息是否已存在
      final exists = chatController.messages.any((m) => m.id == message.id);
      if (!exists) {
        await chatController.insert(message, index: 0);
        insertedCount++;
      } else {
        Log.info('⚠️  ChatBloc: 跳过重复消息 id=${message.id}');
      }
    }
    Log.info('   - 实际插入消息数: $insertedCount');
    Log.info('   - 插入后controller消息总数: ${chatController.messages.length}');

    // Check if emit is still valid after async operations
    if (emit.isDone) {
      Log.info('⚠️ ChatBloc._handleLatestMessages: emit已完成，提前返回');
      return;
    }

    // AIEventLoadNextMessage already returns the authoritative message list,
    // including an empty list for a new chat. Waiting for a second remote
    // notification leaves empty chats in loadingRemote forever, while the UI
    // only renders the conversation when the state is ready.
    if (state.loadingState != LoadChatMessageStatus.ready) {
      emit(state.copyWith(loadingState: LoadChatMessageStatus.ready));
    }

    // 【关键修复】只在首次创建（本地无消息）时才自动发送初始消息
    // 这样可以防止每次切换回视图时重复发送
    // 添加 _initialMessageSent 标志防止重复发送
    if (initialMessage != null &&
        initialMessage!.isNotEmpty &&
        chatController.messages.isEmpty &&
        !_initialMessageSent) {
      if (!_claimInitialMessage()) {
        Log.warn(
          '⚠️ ChatBloc: 初始消息已由其他会话实例消费，跳过重复自动发送: '
          'chatId=$chatId, images=${initialImagePaths?.length ?? 0}',
        );
        return;
      }

      Log.info('🔄 ChatBloc: 本地无消息记录，这是首次创建，准备自动发送初始消息');
      Log.info('   - 消息: $initialMessage');
      Log.info('   - 首选模型: $preferredModelId');
      Log.info('   - _initialMessageSent标志: $_initialMessageSent');
      Log.info('   - skipAIChatWelcomePage当前值: $skipAIChatWelcomePage');

      // 设置标志，防止重复发送
      _initialMessageSent = true;

      // 关键：跳过AI Chat欢迎页，直接进入聊天状态
      skipAIChatWelcomePage = true;
      Log.info('✅ ChatBloc: 已设置跳过欢迎页标志');

      // 【关键修复】等待模型设置完成后再发送消息
      // 这确保了用户选择的多模态模型（如豆包）能正确生效
      Log.info('📤 ChatBloc: 等待模型设置完成...');

      // 使用 Future.delayed 配合 async/await 确保模型设置完成
      _sendInitialMessageAfterModelSet();
    } else if (initialMessage != null &&
        initialMessage!.isNotEmpty &&
        chatController.messages.isNotEmpty) {
      Log.info(
          'ℹ️ ChatBloc: 本地已有 ${chatController.messages.length} 条消息，跳过自动发送');
      Log.info('   - 这是重新打开已存在的会话，不应该重复发送消息');
    } else if (_initialMessageSent) {
      Log.info('ℹ️ ChatBloc: 初始消息已发送过，跳过重复发送');
    }
  }

  bool _claimInitialMessage() {
    if (_claimedInitialMessageChatIds.contains(chatId)) {
      return false;
    }

    _claimedInitialMessageChatIds.add(chatId);
    // 每个新会话都有唯一 ID；控制集合大小，避免客户端长时间运行后持续增长。
    if (_claimedInitialMessageChatIds.length > 1000) {
      _claimedInitialMessageChatIds.remove(
        _claimedInitialMessageChatIds.first,
      );
    }
    Log.info(
      '✅ ChatBloc: 已声明初始消息消费权: '
      'chatId=$chatId, images=${initialImagePaths?.length ?? 0}',
    );
    return true;
  }

  void _handlePreviousMessages(List<Message> messages, bool hasMore) {
    for (final message in messages) {
      chatController.insert(message, index: 0);
    }

    isLoadingPreviousMessages = false;
    hasMorePreviousMessages = hasMore;
  }

  // Message handling
  void _handleReceiveMessage(Message message) {
    final oldMessage =
        chatController.messages.firstWhereOrNull((m) => m.id == message.id);
    if (oldMessage == null) {
      chatController.insert(message);
    } else {
      chatController.update(oldMessage, message);
    }
  }

  // Message sending handlers
  Future<void> _handleSendMessage(
    String message,
    PredefinedFormat? format,
    Map<String, dynamic>? metadata,
    String? promptId,
    // PonyNotes: 深度思考开关（可选，为null时使用ChatBloc初始设置）
    bool? enableDeepThinkingOverride,
    // PonyNotes: 联网搜索开关（可选，为null时使用ChatBloc初始设置）
    bool? enableWebSearchOverride,
    Emitter<ChatState> emit,
  ) async {
    // AI聊天限制检查说明：
    // 协作区场景下，AI配额消耗的是workspace owner的订阅次数，而非当前用户自己的。
    // 例如：用户B在用户A的协作区中使用AI会话，消耗的是A的AI订阅次数。
    // 因此客户端不再做硬性限制检查（因为无法准确获取workspace owner的配额信息），
    // 而是交由服务器端根据workspace_id确定资源归属并进行配额校验。
    // 服务器返回的错误（如AI_LIMIT_EXCEEDED, SUBSCRIPTION_NOT_FOUND）会在流式响应中处理。

    _messageHandler.clearErrorMessages();
    emit(state.copyWith(clearErrorMessages: !state.clearErrorMessages));

    _messageHandler.clearRelatedQuestions();
    // PonyNotes: 使用覆盖参数或默认设置
    final actualEnableDeepThinking =
        enableDeepThinkingOverride ?? enableDeepThinking;
    final actualEnableWebSearch = enableWebSearchOverride ?? enableWebSearch;
    _startStreamingMessage(message, format, metadata, promptId,
        actualEnableDeepThinking, actualEnableWebSearch);
    lastSentMessage = null;

    isFetchingRelatedQuestions = false;
    shouldFetchRelatedQuestions = format == null || format.imageFormat.hasText;

    emit(
      state.copyWith(
        promptResponseState: PromptResponseState.sendingQuestion,
      ),
    );
  }

  // Stream control handlers
  Future<void> _handleStopStream(Emitter<ChatState> emit) async {
    await _streamManager.stopStream();

    // Allow user input
    emit(state.copyWith(promptResponseState: PromptResponseState.ready));

    // No need to remove old message if stream has started already
    if (_streamManager.hasAnswerStreamStarted) {
      return;
    }

    // Remove the non-started message from the list
    // 查找所有正在发送中的答案消息
    for (final answerId in _messageHandler.currentAnswerStreamMessageIds) {
      final message = chatController.messages.lastWhereOrNull(
        (e) => e.id == answerId,
      );
      if (message != null) {
        await chatController.remove(message);
      }
    }

    await _streamManager.disposeAnswerStream();
  }

  void _handleFailedSending(Emitter<ChatState> emit) {
    // 不要移除最后一条消息，因为错误消息可能已经添加
    // 如果移除，可能会删除错误消息，导致用户看不到错误提示
    // 只更新状态为ready，让用户可以继续输入
    emit(state.copyWith(promptResponseState: PromptResponseState.ready));
  }

  // Answer regeneration handler
  Future<void> _handleRegenerateAnswer(
    String id,
    PredefinedFormat? format,
    AIModelPB? model,
    Emitter<ChatState> emit,
  ) async {
    // AI聊天限制检查说明（同_handleSendMessage）：
    // 协作区场景下AI配额消耗的是workspace owner的订阅次数，
    // 服务器端会根据workspace_id进行正确的资源归属检查。

    _messageHandler.clearRelatedQuestions();
    _regenerateAnswer(id, format, model);
    lastSentMessage = null;

    isFetchingRelatedQuestions = false;
    shouldFetchRelatedQuestions = false;

    emit(
      state.copyWith(
        promptResponseState: PromptResponseState.sendingQuestion,
      ),
    );
  }

  // Related questions handler
  void _handleRelatedQuestions(
    List<String> questions,
    Emitter<ChatState> emit,
  ) {
    if (questions.isEmpty) {
      return;
    }

    final metadata = {
      onetimeShotType: OnetimeShotType.relatedQuestion,
      'questions': questions,
    };

    final createdAt = DateTime.now();
    final message = TextMessage(
      id: "related_question_$createdAt",
      text: '',
      metadata: metadata,
      author: const User(id: systemUserId),
      createdAt: createdAt,
    );

    chatController.insert(message);

    emit(
      state.copyWith(
        promptResponseState: PromptResponseState.relatedQuestionsReady,
      ),
    );
  }

  void _startListening() {
    listener.start(
      chatMessageCallback: (pb) {
        if (isClosed) {
          return;
        }

        if (_messageHandler.processReceivedMessage(pb)) {
          final message = _messageHandler.createTextMessage(pb);
          add(ChatEvent.receiveMessage(message));
          if (pb.authorType == 3) {
            add(const ChatEvent.didFinishAnswerStream());
          }
        }
      },
      chatErrorMessageCallback: (err) {
        if (!isClosed) {
          Log.error("chat error: ${err.errorMessage}");
          _showSendingError(err.errorMessage);
          add(const ChatEvent.didFinishAnswerStream());
        }
      },
      latestMessageCallback: (list) {
        if (!isClosed) {
          // 【修复消息重复】必须先调用processReceivedMessage建立ID映射
          // 并过滤掉已处理过的消息（可能通过chatMessageCallback已经处理过了）
          final List<ChatMessagePB> newMessages = [];
          for (final pb in list.messages) {
            // processReceivedMessage返回true表示这是新消息，false表示已处理过
            if (_messageHandler.processReceivedMessage(pb)) {
              newMessages.add(pb);
            }
          }
          Log.info(
              '📋 ChatBloc: latestMessageCallback 过滤后，新消息数: ${newMessages.length}/${list.messages.length}');
          final messages =
              newMessages.map(_messageHandler.createTextMessage).toList();
          add(ChatEvent.didLoadLatestMessages(messages));
        }
      },
      prevMessageCallback: (list) {
        if (!isClosed) {
          // 【修复消息重复】必须先调用processReceivedMessage建立ID映射
          // 并过滤掉已处理过的消息
          final List<ChatMessagePB> newMessages = [];
          for (final pb in list.messages) {
            // processReceivedMessage返回true表示这是新消息，false表示已处理过
            if (_messageHandler.processReceivedMessage(pb)) {
              newMessages.add(pb);
            }
          }
          Log.info(
              '📋 ChatBloc: prevMessageCallback 过滤后，新消息数: ${newMessages.length}/${list.messages.length}');
          final messages =
              newMessages.map(_messageHandler.createTextMessage).toList();
          add(ChatEvent.didLoadPreviousMessages(messages, list.hasMore));
        }
      },
      finishStreamingCallback: () async {
        if (isClosed) {
          return;
        }

        add(const ChatEvent.didFinishAnswerStream());
        unawaited(_fetchRelatedQuestionsIfNeeded());
        // 刷新使用情况
        add(const ChatEvent.refreshUsage());
      },
    );
  }

  // Refresh workspace usage
  Future<void> _refreshUsage(Emitter<ChatState> emit) async {
    if (_workspaceId == null) {
      Log.warn('[ChatBloc] workspaceId 为空，无法刷新使用情况');
      return;
    }

    Log.info('[ChatBloc] 开始刷新使用情况，workspaceId: $_workspaceId, userId: $userId');

    try {
      final service = WorkspaceService(
        workspaceId: _workspaceId!,
        userId: Int64.parseInt(userId),
      );

      Log.info('[ChatBloc] 调用 getWorkspaceUsage API...');
      final result = await service.getWorkspaceUsage();
      result.fold(
        (usage) {
          if (!isClosed && usage != null) {
            Log.info(
              '[ChatBloc] ✅ 获取使用情况成功: 已使用=${usage.aiResponsesCount}, 限制=${usage.aiResponsesCountLimit}, 剩余=${usage.aiResponsesCountLimit - usage.aiResponsesCount}, 无限制=${usage.aiResponsesUnlimited}',
            );

            // 验证数据有效性
            if (usage.aiResponsesCountLimit == 0 &&
                !usage.aiResponsesUnlimited) {
              Log.warn('[ChatBloc] ⚠️ 警告：检测到限制为0且非无限制，可能是数据未正确加载');
            }

            emit(state.copyWith(usageInfo: usage));
          } else {
            Log.warn('[ChatBloc] ⚠️ 获取使用情况返回null');
          }
        },
        (error) {
          Log.error('[ChatBloc] ❌ 获取使用情况失败: $error');
          // 不设置默认值，保持 usageInfo 为 null
        },
      );
    } catch (e, stackTrace) {
      Log.error('[ChatBloc] ❌ 刷新使用情况异常: $e');
      Log.error('[ChatBloc] 堆栈跟踪: $stackTrace');
    }
  }

  // Split method to handle related questions
  Future<void> _fetchRelatedQuestionsIfNeeded() async {
    // Don't fetch related questions if conditions aren't met
    if (_streamManager.answerStream == null ||
        lastSentMessage == null ||
        !shouldFetchRelatedQuestions) {
      return;
    }

    final payload = ChatMessageIdPB(
      chatId: chatId,
      messageId: lastSentMessage!.messageId,
    );

    isFetchingRelatedQuestions = true;
    await AIEventGetRelatedQuestion(payload).send().fold(
      (list) {
        // while fetching related questions, the user might enter a new
        // question or regenerate a previous response. In such cases, don't
        // display the relatedQuestions
        if (!isClosed && isFetchingRelatedQuestions) {
          add(
            ChatEvent.didReceiveRelatedQuestions(
              list.items.map((e) => e.content).toList(),
            ),
          );
          isFetchingRelatedQuestions = false;
        }
      },
      (err) => Log.error("Failed to get related questions: $err"),
    );
  }

  void _loadSettings() async {
    final getChatSettingsPayload =
        AIEventGetChatSettings(ChatId(value: chatId));

    await getChatSettingsPayload.send().fold(
      (settings) {
        if (!isClosed) {
          add(ChatEvent.didReceiveChatSettings(settings: settings));
        }
      },
      (err) => Log.error("Failed to load chat settings: $err"),
    );
  }

  /// 模型ID到Name的映射表
  /// 因为前端AIModel使用ID（如"qwen3-vl-plus"），而后端AIModelPB只有name（如"通义千问"）
  static const Map<String, String> _modelIdToNameMap = {
    'deepseek-chat': 'DeepSeek',
    'qwen3-vl-plus': '通义千问',
    'doubao': '豆包',
  };

  /// 设置首选AI模型
  void _setPreferredModel(String modelId) async {
    try {
      Log.info('🔄 ChatBloc: 开始设置首选模型...');
      Log.info('   - Chat ID: $chatId');
      Log.info('   - Model ID: $modelId');

      // 获取当前 Chat 的模型选择信息
      final result = await AIEventGetSourceModelSelection(
        ModelSourcePB(source: chatId),
      ).send();

      await result.fold(
        (modelSelection) async {
          var availableModels = modelSelection.models;
          Log.info(
            '🔍 ChatBloc: 当前会话返回 ${availableModels.length} 个可用模型',
          );

          if (availableModels.isEmpty) {
            Log.warn('⚠️ ChatBloc: 当前会话未返回可用模型，尝试读取全局配置');
            final fallbackResult = await AIEventGetSettingModelSelection(
              ModelSourcePB(source: kGlobalAIModelSource),
            ).send();
            await fallbackResult.fold(
              (fallbackSelection) async {
                availableModels = fallbackSelection.models;
                Log.info(
                  '✅ ChatBloc: 通过全局配置获取到 ${availableModels.length} 个模型',
                );
              },
              (err) async {
                Log.error('❌ ChatBloc: 获取全局模型配置失败: ${err.msg}');
                // 即使获取全局配置失败，availableModels 仍然是空列表，继续执行构造逻辑
              },
            );
          }

          AIModelPB? matchedModel;

          // 【关键修复】如果后端模型列表为空，直接根据modelId构造AIModelPB对象
          // 这是按照文档要求的兜底方案，确保即使后端没有返回模型列表，也能正确设置模型
          if (availableModels.isEmpty) {
            Log.warn(
              '⚠️ ChatBloc: 后端模型列表为空，直接根据modelId构造模型对象',
            );
            Log.info('   - 使用的modelId: $modelId');
            Log.info('   - 映射表内容: $_modelIdToNameMap');

            final expectedName = _modelIdToNameMap[modelId];
            if (expectedName != null) {
              matchedModel = AIModelPB()
                ..name = expectedName
                ..isLocal = false
                ..desc = '';
              Log.info(
                '✅ ChatBloc: 根据映射表构造模型对象: ${matchedModel.name} (来自modelId: $modelId)',
              );
            } else {
              // 如果映射表中没有，尝试使用modelId作为name
              matchedModel = AIModelPB()
                ..name = modelId
                ..isLocal = false
                ..desc = '';
              Log.warn(
                '⚠️ ChatBloc: 映射表中未找到模型ID "$modelId"，使用ID作为名称',
              );
            }
          } else {
            Log.info('✅ ChatBloc: 获取到 ${availableModels.length} 个可用模型');

            for (final model in availableModels) {
              Log.info('   - 模型: ${model.name} (isLocal: ${model.isLocal})');
            }

            // 尝试从可用模型列表中匹配
            final expectedName = _modelIdToNameMap[modelId];
            if (expectedName != null) {
              matchedModel = availableModels.cast<AIModelPB?>().firstWhere(
                    (model) => model?.name == expectedName,
                    orElse: () => null,
                  );
              if (matchedModel != null) {
                Log.info(
                  '✅ ChatBloc: 通过映射表找到匹配的模型: ${matchedModel.name}',
                );
              }
            }

            if (matchedModel == null) {
              for (final model in availableModels) {
                if (model.name == modelId ||
                    model.name.toLowerCase() == modelId.toLowerCase()) {
                  matchedModel = model;
                  Log.info('✅ ChatBloc: 通过ID直接找到匹配的模型: ${model.name}');
                  break;
                }
              }
            }

            if (matchedModel == null && availableModels.isNotEmpty) {
              matchedModel = availableModels.firstWhere(
                (model) => model.name != 'Auto',
                orElse: () => availableModels.first,
              );
              Log.warn(
                '⚠️ ChatBloc: 无法匹配模型ID "$modelId"，使用第一个可用模型: ${matchedModel.name}',
              );
            }
          }

          if (matchedModel == null) {
            Log.error('❌ ChatBloc: 无法构造或匹配模型对象');
            return;
          }

          Log.info('✅ ChatBloc: 将使用模型: ${matchedModel.name}');

          final updatePayload = UpdateSelectedModelPB(
            source: chatId,
            selectedModel: matchedModel,
          );

          await AIEventUpdateSelectedModel(updatePayload).send().fold(
            (_) {
              Log.info(
                '✅ ChatBloc: 成功设置首选模型: ${matchedModel?.name ?? "未知"}',
              );
              _modelSettingCompleted = true;
              if (!_modelSettingCompleter.isCompleted) {
                _modelSettingCompleter.complete();
              }
            },
            (err) {
              Log.error('❌ ChatBloc: 设置首选模型失败: ${err.msg}');
              _modelSettingCompleted = true;
              if (!_modelSettingCompleter.isCompleted) {
                _modelSettingCompleter.complete();
              }
            },
          );
        },
        (err) async {
          Log.error('❌ ChatBloc: 获取模型选择信息失败: ${err.msg}');
          Log.warn(
            '⚠️ ChatBloc: 由于获取模型列表失败，直接根据modelId构造模型对象',
          );

          // 【关键修复】即使获取模型列表失败，也根据modelId直接构造模型对象
          // 这是按照文档要求的兜底方案
          final expectedName = _modelIdToNameMap[modelId];
          AIModelPB? matchedModel;

          if (expectedName != null) {
            matchedModel = AIModelPB()
              ..name = expectedName
              ..isLocal = false
              ..desc = '';
            Log.info(
              '✅ ChatBloc: 根据映射表构造模型对象: ${matchedModel.name} (来自modelId: $modelId)',
            );
          } else {
            matchedModel = AIModelPB()
              ..name = modelId
              ..isLocal = false
              ..desc = '';
            Log.warn(
              '⚠️ ChatBloc: 映射表中未找到模型ID "$modelId"，使用ID作为名称',
            );
          }

          // matchedModel 在这里不可能是 null，因为上面已经构造了
          final modelToSet = matchedModel;
          final updatePayload = UpdateSelectedModelPB(
            source: chatId,
            selectedModel: modelToSet,
          );

          await AIEventUpdateSelectedModel(updatePayload).send().fold(
            (_) {
              Log.info(
                '✅ ChatBloc: 成功设置首选模型: ${modelToSet.name}',
              );
              _modelSettingCompleted = true;
              if (!_modelSettingCompleter.isCompleted) {
                _modelSettingCompleter.complete();
              }
            },
            (updateErr) {
              Log.error('❌ ChatBloc: 设置首选模型失败: ${updateErr.msg}');
              _modelSettingCompleted = true;
              if (!_modelSettingCompleter.isCompleted) {
                _modelSettingCompleter.complete();
              }
            },
          );
        },
      );
    } catch (e, stackTrace) {
      Log.error('❌ ChatBloc: 设置首选模型异常: $e', e, stackTrace);
      _modelSettingCompleted = true;
      if (!_modelSettingCompleter.isCompleted) {
        _modelSettingCompleter.complete();
      }
    }
  }

  Future<void> _sendInitialMessageAfterModelSet() async {
    try {
      await _modelSettingCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Log.warn('⚠️ ChatBloc: 等待模型设置超时，继续发送消息');
        },
      );

      Log.info('✅ ChatBloc: 模型设置完成，开始发送初始消息');

      final metadata = <String, dynamic>{};

      if (initialImagePaths != null && initialImagePaths!.isNotEmpty) {
        Log.info('📸 ChatBloc: 准备发送 ${initialImagePaths!.length} 张图片');

        // 1. 将图片拷贝到永久目录，防止源文件被删除
        final permanentPaths =
            await _saveImagesToPermanentDir(initialImagePaths!);

        // 2. 转换图片为base64（用于发送到AI服务器）
        final imageBase64List =
            await _convertImagesToBase64(initialImagePaths!);
        if (imageBase64List.isNotEmpty && !isClosed) {
          metadata['images'] = imageBase64List;
          metadata['has_images'] = true;
          Log.info(
              '✅ ChatBloc: 已添加 ${imageBase64List.length} 张图片(base64)到metadata');
        }

        // 3. 保存永久文件路径到metadata，用于跨会话持久化显示
        if (permanentPaths.isNotEmpty) {
          metadata['image_paths'] = permanentPaths;
          Log.info('✅ ChatBloc: 已添加 ${permanentPaths.length} 张永久图片路径到metadata');
        } else {
          metadata['image_paths'] = initialImagePaths;
        }
      }

      // 【竞态防护】等待模型设置期间，远端历史消息可能已异步加载进来。
      // 若此时已有历史消息，说明这是“重新打开的已有会话”（本地缓存冷导致首个空回调被误判为首次创建），
      // 必须取消自动发送，否则会重复执行会话请求与回复。
      if (chatController.messages.isNotEmpty) {
        Log.info(
            '🛑 ChatBloc: 发送前检测到已有 ${chatController.messages.length} 条历史消息，取消自动发送（重开已有会话）');
        unawaited(_clearInitialMessageFromViewExtra());
        return;
      }

      if (!isClosed) {
        add(
          ChatEvent.sendMessage(
            message: initialMessage!,
            metadata: metadata,
          ),
        );
        // initial_message 是一次性触发标记，消费后立即从 view.extra 中清除，
        // 防止以后任何一次重新打开该会话时再次自动发送（彻底根除复发）。
        unawaited(_clearInitialMessageFromViewExtra());
      }
    } catch (e) {
      Log.error('❌ ChatBloc: 发送初始消息失败: $e');
    }
  }

  /// 清除 view.extra 中的一次性字段 initial_message（及随附的初始图片），
  /// 保留 preferred_model 等其它配置。失败不影响主流程。
  Future<void> _clearInitialMessageFromViewExtra() async {
    try {
      final viewResult = await ViewBackendService.getView(chatId);
      final view = viewResult.toNullable();
      if (view == null || view.extra.isEmpty) {
        return;
      }
      final decoded = jsonDecode(view.extra);
      if (decoded is! Map) {
        return;
      }
      final map = Map<String, dynamic>.from(decoded);
      if (!map.containsKey('initial_message') &&
          !map.containsKey('initial_images')) {
        return;
      }
      map.remove('initial_message');
      map.remove('initial_images');
      await ViewBackendService.updateView(
        viewId: chatId,
        extra: jsonEncode(map),
      );
      Log.info('🧹 ChatBloc: 已清除 view.extra 中的一次性 initial_message');
    } catch (e) {
      Log.warn('⚠️ ChatBloc: 清除 view.extra 的 initial_message 失败: $e');
    }
  }

  void _loadMessages() async {
    final loadMessagesPayload = LoadNextChatMessagePB(
      chatId: chatId,
      limit: Int64(50),
    );

    await AIEventLoadNextMessage(loadMessagesPayload).send().fold(
      (list) {
        if (!isClosed) {
          final messages =
              list.messages.map(_messageHandler.createTextMessage).toList();
          add(ChatEvent.didLoadLatestMessages(messages));
        }
      },
      (err) => Log.error("Failed to load messages: $err"),
    );
  }

  void _loadPreviousMessagesIfNeeded() {
    if (isLoadingPreviousMessages) {
      return;
    }

    final oldestMessage = _messageHandler.getOldestMessage();

    if (oldestMessage != null) {
      var oldestMessageId = Int64.tryParseInt(oldestMessage.id);
      
      if (oldestMessageId == null) {
        final parsed = int.tryParse(oldestMessage.id);
        if (parsed != null) {
          oldestMessageId = Int64(parsed);
          Log.info('⚠️ ChatBloc: 使用 int.parse 解析消息ID: ${oldestMessage.id}');
        } else {
          Log.error("Failed to parse message_id: ${oldestMessage.id}");
          return;
        }
      }
      
      isLoadingPreviousMessages = true;
      _loadPreviousMessages(oldestMessageId);
    }
  }

  void _loadPreviousMessages(Int64? beforeMessageId) {
    final payload = LoadPrevChatMessagePB(
      chatId: chatId,
      limit: Int64(50),
      beforeMessageId: beforeMessageId,
    );
    AIEventLoadPrevMessage(payload).send();
  }

  Future<void> _startStreamingMessage(
    String message,
    PredefinedFormat? format,
    Map<String, dynamic>? metadata,
    String? promptId,
    // PonyNotes: 深度思考开关（用于动态覆盖）
    bool actualEnableDeepThinking,
    // PonyNotes: 联网搜索开关（用于动态覆盖）
    bool actualEnableWebSearch,
  ) async {
    // Prepare streams
    await _streamManager.prepareStreams();
    _listenForAnswerStreamEnd();

    // 获取当前选择的模型
    AIModelPB? selectedModel;
    String? modelError;
    try {
      final modelResult = await AIEventGetSourceModelSelection(
        ModelSourcePB(source: chatId),
      ).send();
      modelResult.fold(
        (modelSelection) {
          selectedModel = modelSelection.selectedModel;
          if (selectedModel != null) {
            Log.info('📤 ChatBloc: 发送消息使用模型: ${selectedModel!.name}');
          } else {
            modelError = '未获取到选择的模型';
            Log.error('❌ ChatBloc: $modelError');
          }
        },
        (err) {
          modelError = '获取选择模型失败: ${err.msg}';
          Log.error('❌ ChatBloc: $modelError');
        },
      );
    } catch (e) {
      modelError = '获取模型异常: $e';
      Log.error('❌ ChatBloc: $modelError');
    }

    // 【关键修复】如果获取不到模型，直接报错并阻止发送消息
    // 按照用户要求：获取不到模型的时候就报获取模型失败，不要使用本地的模型
    if (selectedModel == null) {
      Log.error('❌ ChatBloc: 无法获取模型对象，停止发送消息');
      Log.error('   错误信息: ${modelError ?? "未知错误"}');
      _showSendingError(modelError ?? '未获取到可用模型，请稍后重试。');
      add(const ChatEvent.failedSending());
      return;
    }

    // 发起请求前必须先让临时问题进入消息列表。否则服务端快速确认带图问题时，
    // 可能早于 receiveMessage 队列事件到达，留下两个 ID 不同的重复气泡。
    final questionStreamMessage =
        await _messageHandler.createAndInsertQuestionStreamMessage(
      _streamManager.questionStream!,
      metadata,
      text: message,
    );

    List<String>? images;
    bool hasImages = false;
    if (metadata != null) {
      final imagesData = metadata['images'];
      final hasImagesData = metadata['has_images'];
      if (imagesData is List && imagesData.isNotEmpty) {
        images = imagesData.cast<String>();
        hasImages = true;
        Log.info(
            '📸 ChatBloc._startStreamingMessage: 提取到 ${images.length} 张图片，准备发送到Rust层');
      }
      if (hasImagesData == true) {
        hasImages = true;
      }
    }

    await _streamManager
        .sendStreamRequest(
      message,
      format,
      promptId,
      images: images,
      hasImages: hasImages,
      enableDeepThinkingOverride: actualEnableDeepThinking,
      enableWebSearchOverride: actualEnableWebSearch,
    )
        .fold(
      (question) {
        if (!isClosed) {
          _messageHandler.registerTemporaryQuestion(
            temporaryMessageId: questionStreamMessage.id,
            questionMessageId: question.messageId,
          );
          // Create and add answer stream message
          final streamAnswer = _messageHandler.createAnswerStreamMessage(
            stream: _streamManager.answerStream!,
            questionMessageId: question.messageId,
            fakeQuestionMessageId: questionStreamMessage.id,
          );

          lastSentMessage = question;
          add(const ChatEvent.finishSending());
          add(ChatEvent.receiveMessage(streamAnswer));
        }
      },
      (err) {
        if (!isClosed) {
          Log.error("Failed to send message: ${err.msg}");

          // 【AI 报错不显示根因修复 2026-07-20】原实现为
          //   `if (err.code != ErrorCode.Internal) errorMessageTextKey: err.msg`
          // ——即错误码为 Internal 时**丢弃错误文案**，只留一个空的错误气泡。
          //
          // 问题在于后端错误几乎都会落到 Internal：flowy-error 的
          // impl_from/cloud.rs 明确注释「由于后端的 ErrorCode 反序列化时会默认变成
          // Internal」。于是真实故障（如 AI 供应商返回 429 额度耗尽）传到 UI 后
          // 变成一个**没有任何文字的空气泡**，用户既看不到原因、也不知道该怎么办。
          // 实测：服务端日志明确记录 DeepSeek 429 SetLimitExceeded 并重试 3 次后失败，
          // 而客户端只显示一个空气泡（见用户截图）。
          //
          // 改为：始终带上错误文案；仅在 msg 为空时回退到通用提示，
          // 保证任何失败都有可读信息，不再出现空白气泡。
          final errorText =
              err.msg.trim().isNotEmpty ? err.msg : LocaleKeys.chat_requestFailedFallback.tr();
          _showSendingError(errorText);
          add(const ChatEvent.failedSending());
        }
      },
    );
  }

  void _showSendingError(String error) {
    final message = error.trim().isEmpty ? 'AI 服务暂时不可用，请稍后重试。' : error;
    showToastNotification(message: message);
    add(
      ChatEvent.receiveMessage(
        TextMessage(
          text: '',
          metadata: {
            onetimeShotType: OnetimeShotType.error,
            errorMessageTextKey: message,
          },
          author: const User(id: systemUserId),
          id: '${systemUserId}_${DateTime.now().microsecondsSinceEpoch}',
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  // Refactored method to handle answer regeneration
  void _regenerateAnswer(
    String answerMessageIdString,
    PredefinedFormat? format,
    AIModelPB? model,
  ) async {
    final id = _messageHandler.getEffectiveMessageId(answerMessageIdString);
    final answerMessageId = Int64.tryParseInt(id);
    if (answerMessageId == null) {
      return;
    }

    await _streamManager.prepareStreams();
    _listenForAnswerStreamEnd();
    await _streamManager
        .sendRegenerateRequest(
      answerMessageId,
      format,
      model,
    )
        .fold(
      (_) {
        if (!isClosed) {
          final streamAnswer = _messageHandler
              .createAnswerStreamMessage(
                stream: _streamManager.answerStream!,
                questionMessageId: answerMessageId - 1,
              )
              .copyWith(id: answerMessageIdString);

          add(ChatEvent.receiveMessage(streamAnswer));
          add(const ChatEvent.finishSending());
        }
      },
      (err) => Log.error("Failed to regenerate answer: ${err.msg}"),
    );
  }

  void _listenForAnswerStreamEnd() {
    _streamManager.answerStream?.listen(
      onEnd: () {
        if (!isClosed) {
          add(const ChatEvent.didFinishAnswerStream());
        }
      },
    );
  }

  /// 将图片拷贝到永久目录，防止源文件（如临时文件）被清理
  Future<List<String>> _saveImagesToPermanentDir(
      List<String> sourcePaths) async {
    final permanentPaths = <String>[];
    try {
      final appDir = await getApplicationSupportDirectory();
      final chatImagesDir = Directory('${appDir.path}/ai_chat_images/$chatId');
      if (!chatImagesDir.existsSync()) {
        chatImagesDir.createSync(recursive: true);
      }

      for (int i = 0; i < sourcePaths.length; i++) {
        final sourceFile = File(sourcePaths[i]);
        if (await sourceFile.exists()) {
          final ext = path.extension(sourcePaths[i]).toLowerCase();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final destPath = '${chatImagesDir.path}/${ts}_$i$ext';
          await sourceFile.copy(destPath);
          permanentPaths.add(destPath);
          Log.info('📸 ChatBloc: 图片已拷贝到永久目录 - $destPath');
        }
      }
    } catch (e) {
      Log.error('❌ ChatBloc: 保存图片到永久目录失败: $e');
    }
    return permanentPaths;
  }

  /// 将图片文件路径列表转换为base64列表
  Future<List<String>> _convertImagesToBase64(List<String> imagePaths) async {
    final base64List = <String>[];

    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64 = base64Encode(bytes);
          base64List.add(base64);
          Log.info('✅ ChatBloc: 图片转换为base64成功 - $path (${bytes.length} bytes)');
        } else {
          Log.warn('⚠️  ChatBloc: 图片文件不存在 - $path');
        }
      } catch (e) {
        Log.error('❌ ChatBloc: 图片转换失败 - $path: $e');
      }
    }

    return base64List;
  }
}

@freezed
class ChatEvent with _$ChatEvent {
  // chat settings
  const factory ChatEvent.didReceiveChatSettings({
    required ChatSettingsPB settings,
  }) = _DidReceiveChatSettings;
  const factory ChatEvent.updateSelectedSources({
    required List<String> selectedSourcesIds,
  }) = _UpdateSelectedSources;

  // send message
  const factory ChatEvent.sendMessage({
    required String message,
    PredefinedFormat? format,
    Map<String, dynamic>? metadata,
    String? promptId,
    // PonyNotes: 深度思考开关（可选，用于动态覆盖ChatBloc初始设置）
    bool? enableDeepThinking,
    // PonyNotes: 联网搜索开关（可选，用于动态覆盖ChatBloc初始设置）
    bool? enableWebSearch,
  }) = _SendMessage;
  const factory ChatEvent.finishSending() = _FinishSendMessage;
  const factory ChatEvent.failedSending() = _FailSendMessage;

  // regenerate
  const factory ChatEvent.regenerateAnswer(
    String id,
    PredefinedFormat? format,
    AIModelPB? model,
  ) = _RegenerateAnswer;

  // streaming answer
  const factory ChatEvent.stopStream() = _StopStream;
  const factory ChatEvent.didFinishAnswerStream() = _DidFinishAnswerStream;

  // receive message
  const factory ChatEvent.receiveMessage(Message message) = _ReceiveMessage;

  // loading messages
  const factory ChatEvent.didLoadLatestMessages(List<Message> messages) =
      _DidLoadMessages;
  const factory ChatEvent.loadPreviousMessages() = _LoadPreviousMessages;
  const factory ChatEvent.didLoadPreviousMessages(
    List<Message> messages,
    bool hasMore,
  ) = _DidLoadPreviousMessages;

  // related questions
  const factory ChatEvent.didReceiveRelatedQuestions(
    List<String> questions,
  ) = _DidReceiveRelatedQueston;

  // usage refresh
  const factory ChatEvent.refreshUsage() = _RefreshUsage;
  const factory ChatEvent.setWorkspaceId(String workspaceId) = _SetWorkspaceId;

  const factory ChatEvent.deleteMessage(Message message) = _DeleteMessage;

  const factory ChatEvent.onAIFollowUp(AIFollowUpData followUpData) =
      _OnAIFollowUp;
}

@freezed
class ChatState with _$ChatState {
  const factory ChatState({
    required LoadChatMessageStatus loadingState,
    required PromptResponseState promptResponseState,
    required bool clearErrorMessages,
    WorkspaceUsagePB? usageInfo,
  }) = _ChatState;

  factory ChatState.initial() => const ChatState(
        loadingState: LoadChatMessageStatus.loading,
        promptResponseState: PromptResponseState.ready,
        clearErrorMessages: false,
        usageInfo: null,
      );
}

bool isOtherUserMessage(Message message) {
  return message.author.id != aiResponseUserId &&
      message.author.id != systemUserId &&
      !message.author.id.startsWith("streamId:");
}
