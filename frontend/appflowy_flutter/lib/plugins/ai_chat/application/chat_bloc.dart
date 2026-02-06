import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_animation_list_widget.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
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
        sendMessage: (message, format, metadata, promptId, enableDeepThinking, enableWebSearch) async =>
            _handleSendMessage(message, format, metadata, promptId, enableDeepThinking, enableWebSearch, emit),
        finishSending: () async => emit(
          state.copyWith(
            promptResponseState: PromptResponseState.streamingAnswer,
          ),
        ),

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

    switch (state.loadingState) {
      case LoadChatMessageStatus.loading when chatController.messages.isEmpty:
        emit(state.copyWith(loadingState: LoadChatMessageStatus.loadingRemote));
        break;
      case LoadChatMessageStatus.loading:
      case LoadChatMessageStatus.loadingRemote:
        emit(state.copyWith(loadingState: LoadChatMessageStatus.ready));
        break;
      default:
        break;
    }
    
    // 【关键修复】只在首次创建（本地无消息）时才自动发送初始消息
    // 这样可以防止每次切换回视图时重复发送
    // 添加 _initialMessageSent 标志防止重复发送
    if (initialMessage != null && 
        initialMessage!.isNotEmpty && 
        chatController.messages.isEmpty &&
        !_initialMessageSent) {
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
      Log.info('ℹ️ ChatBloc: 本地已有 ${chatController.messages.length} 条消息，跳过自动发送');
      Log.info('   - 这是重新打开已存在的会话，不应该重复发送消息');
    } else if (_initialMessageSent) {
      Log.info('ℹ️ ChatBloc: 初始消息已发送过，跳过重复发送');
    }
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
    // 检查AI聊天限制
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );
      
      final canUseAI = await MembershipCheckerService().checkAIChatLimit(userProfile: userProfile);
      if (!canUseAI) {
        Log.info('❌ ChatBloc: AI聊天次数已达上限，停止发送消息');
        return;
      }
    } catch (e) {
      Log.error('Failed to check AI chat limit: $e');
      // 如果检查失败，默认允许使用AI
      return;
    }

    _messageHandler.clearErrorMessages();
    emit(state.copyWith(clearErrorMessages: !state.clearErrorMessages));

    _messageHandler.clearRelatedQuestions();
    // PonyNotes: 使用覆盖参数或默认设置
    final actualEnableDeepThinking = enableDeepThinkingOverride ?? enableDeepThinking;
    final actualEnableWebSearch = enableWebSearchOverride ?? enableWebSearch;
    _startStreamingMessage(message, format, metadata, promptId, actualEnableDeepThinking, actualEnableWebSearch);
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
    final message = chatController.messages.lastWhereOrNull(
      (e) => e.id == _messageHandler.answerStreamMessageId,
    );
    if (message != null) {
      await chatController.remove(message);
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
    // 检查AI聊天限制
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );
      
      final canUseAI = await MembershipCheckerService().checkAIChatLimit(userProfile: userProfile);
      if (!canUseAI) {
        Log.info('❌ ChatBloc: AI聊天次数已达上限，停止重新生成答案');
        return;
      }
    } catch (e) {
      Log.error('Failed to check AI chat limit: $e');
      // 如果检查失败，默认允许使用AI
      return;
    }

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

        _messageHandler.processReceivedMessage(pb);
        final message = _messageHandler.createTextMessage(pb);
        add(ChatEvent.receiveMessage(message));
      },
      chatErrorMessageCallback: (err) {
        if (!isClosed) {
          Log.error("chat error: ${err.errorMessage}");
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
          Log.info('📋 ChatBloc: latestMessageCallback 过滤后，新消息数: ${newMessages.length}/${list.messages.length}');
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
          Log.info('📋 ChatBloc: prevMessageCallback 过滤后，新消息数: ${newMessages.length}/${list.messages.length}');
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
            if (usage.aiResponsesCountLimit == 0 && !usage.aiResponsesUnlimited) {
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

  /// 等待模型设置完成后发送初始消息
  /// 这是解决多模态模型（如豆包）选择后调用错误的关键修复
  Future<void> _sendInitialMessageAfterModelSet() async {
    try {
      // 等待模型设置完成，最多等待3秒
      await _modelSettingCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Log.warn('⚠️ ChatBloc: 等待模型设置超时，继续发送消息');
        },
      );
      
      Log.info('✅ ChatBloc: 模型设置完成，开始发送初始消息');
      
      // 准备metadata（包含图片）
      final metadata = <String, dynamic>{};

      // 处理初始图片
      if (initialImagePaths != null && initialImagePaths!.isNotEmpty) {
        Log.info('📸 ChatBloc: 准备发送 ${initialImagePaths!.length} 张图片');

        // 1. 转换图片为base64（用于发送到服务器）
        final imageBase64List = await _convertImagesToBase64(initialImagePaths!);
        if (imageBase64List.isNotEmpty && !isClosed) {
          metadata['images'] = imageBase64List;
          metadata['has_images'] = true;
          Log.info('✅ ChatBloc: 已添加 ${imageBase64List.length} 张图片(base64)到metadata');
        }

        // 2. 同时保存图片文件路径（作为备用，用于本地持久化）
        // 这样即使base64数据在存储过程中丢失，也能从文件路径恢复图片
        metadata['image_paths'] = initialImagePaths;
        Log.info('✅ ChatBloc: 已添加 ${initialImagePaths!.length} 张图片路径到metadata');
      }
      
      // 发送消息
      if (!isClosed) {
        add(
          ChatEvent.sendMessage(
            message: initialMessage!,
            metadata: metadata,
          ),
        );
      }
    } catch (e) {
      Log.error('❌ ChatBloc: 发送初始消息失败: $e');
    }
  }

  void _loadMessages() async {
    final loadMessagesPayload = LoadNextChatMessagePB(
      chatId: chatId,
      limit: Int64(10),
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
      final oldestMessageId = Int64.tryParseInt(oldestMessage.id);
      if (oldestMessageId == null) {
        Log.error("Failed to parse message_id: ${oldestMessage.id}");
        return;
      }
      isLoadingPreviousMessages = true;
      _loadPreviousMessages(oldestMessageId);
    }
  }

  void _loadPreviousMessages(Int64? beforeMessageId) {
    final payload = LoadPrevChatMessagePB(
      chatId: chatId,
      limit: Int64(10),
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
      // 直接返回，不发送消息，不构造本地模型
      return;
    }

    // Create and add question message
    final questionStreamMessage = _messageHandler.createQuestionStreamMessage(
      _streamManager.questionStream!,
      metadata,
    );
    add(ChatEvent.receiveMessage(questionStreamMessage));

    // 从 metadata 中提取图片数据
    List<String>? images;
    bool hasImages = false;
    if (metadata != null) {
      final imagesData = metadata['images'];
      final hasImagesData = metadata['has_images'];
      if (imagesData is List && imagesData.isNotEmpty) {
        images = imagesData.cast<String>();
        hasImages = true;
        Log.info('📸 ChatBloc._startStreamingMessage: 提取到 ${images.length} 张图片，准备发送到Rust层');
      }
      if (hasImagesData == true) {
        hasImages = true;
      }
    }

    // Send stream request (model is already set via _setPreferredModel)
    // 【关键修复】传递图片数据到 Rust 层
    // PonyNotes: 传递深度思考和联网搜索覆盖参数
    await _streamManager.sendStreamRequest(
      message, 
      format, 
      promptId,
      images: images,
      hasImages: hasImages,
      enableDeepThinkingOverride: actualEnableDeepThinking,
      enableWebSearchOverride: actualEnableWebSearch,
    ).fold(
      (question) {
        if (!isClosed) {
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

          final metadata = {
            onetimeShotType: OnetimeShotType.error,
            if (err.code != ErrorCode.Internal) errorMessageTextKey: err.msg,
          };

          final error = TextMessage(
            text: '',
            metadata: metadata,
            author: const User(id: systemUserId),
            id: systemUserId,
            createdAt: DateTime.now(),
          );

          add(const ChatEvent.failedSending());
          add(ChatEvent.receiveMessage(error));
        }
      },
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
