import 'dart:async';
import 'dart:io';
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:appflowy/core/config/ai_config.dart';
import '../services/standalone_ai_service.dart';
import '../models/chat_image.dart';
import '../services/image_storage_service.dart';
import 'standalone_chat_persistence.dart';

part 'standalone_chat_bloc.freezed.dart';

/// 独立AI聊天的事件
@freezed
class StandaloneChatEvent with _$StandaloneChatEvent {
  const factory StandaloneChatEvent.sendMessage({
    required String message,
    AIProvider? provider,
  }) = _SendMessage;

  const factory StandaloneChatEvent.sendMessageWithImages({
    required String message,
    required List<ChatImage> images,
    AIProvider? provider,
  }) = _SendMessageWithImages;

  const factory StandaloneChatEvent.receiveStreamChunk({
    required String chunk,
  }) = _ReceiveStreamChunk;

  const factory StandaloneChatEvent.finishResponse() = _FinishResponse;

  const factory StandaloneChatEvent.stopStreaming() = _StopStreaming;

  const factory StandaloneChatEvent.errorOccurred({
    required String error,
  }) = _ErrorOccurred;

  const factory StandaloneChatEvent.loadHistory() = _LoadHistory;

  const factory StandaloneChatEvent.clearChat() = _ClearChat;

  const factory StandaloneChatEvent.changeProvider({
    required AIProvider provider,
  }) = _ChangeProvider;

  // 聊天历史相关事件
  const factory StandaloneChatEvent.loadChatHistory() = _LoadChatHistory;

  const factory StandaloneChatEvent.loadChatSession({
    required String sessionId,
  }) = _LoadChatSession;

  const factory StandaloneChatEvent.createNewChatSession() = _CreateNewChatSession;

  const factory StandaloneChatEvent.renameChatSession({
    required String sessionId,
    required String newTitle,
  }) = _RenameChatSession;

  const factory StandaloneChatEvent.deleteChatSessions({
    required List<String> sessionIds,
  }) = _DeleteChatSessions;

  const factory StandaloneChatEvent.clearAllChatHistory() = _ClearAllChatHistory;

  const factory StandaloneChatEvent.exportChatHistory() = _ExportChatHistory;

  // 消息相关事件
  const factory StandaloneChatEvent.retryMessage({
    required String messageId,
  }) = _RetryMessage;

  const factory StandaloneChatEvent.editMessage({
    required String messageId,
    required String newContent,
  }) = _EditMessage;
}

/// 独立AI聊天的状态
@freezed
class StandaloneChatState with _$StandaloneChatState {
  const factory StandaloneChatState({
    @Default([]) List<ChatMessage> messages,
    @Default(false) bool isLoading,
    @Default(false) bool isStreaming,
    String? error,
    String? currentStreamingMessage,
    AIProvider? selectedProvider,
    @Default(false) bool isHistoryLoaded,
    @Default([]) List<ChatSession> chatSessions,
    String? currentSessionId,
  }) = _StandaloneChatState;
}

/// 聊天消息模型
@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String content,
    required bool isUser,
    required DateTime timestamp,
    AIProvider? aiProvider,
    AIProvider? provider, // 添加provider别名，与aiProvider相同
    @Default(false) bool isStreaming,
    @Default(false) bool hasError,
    @Default([]) List<String> imageIds, // 添加图片ID列表
  }) = _ChatMessage;
}

/// 聊天会话数据模型
@freezed
class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,
    required String title,
    String? lastMessage,
    required DateTime lastMessageTime,
    required int messageCount,
    AIProvider? provider,
  }) = _ChatSession;
}

/// 独立AI聊天Bloc
class StandaloneChatBloc extends Bloc<StandaloneChatEvent, StandaloneChatState> {
  final StandaloneAiService _aiService = StandaloneAiService.instance;
  final AIConfigService _configService = AIConfigService.instance;
  final StandaloneChatPersistence _persistence = StandaloneChatPersistence.instance;
  final ImageStorageService _imageStorage = ImageStorageService.instance;
  
  StreamSubscription<String>? _streamSubscription;
  String _currentMessageId = '';
  bool _isUserStopped = false; // 用户是否主动停止了流式输出

  StandaloneChatBloc() : super(const StandaloneChatState()) {
    on<StandaloneChatEvent>((event, emit) async {
      event.when(
        sendMessage: (message, provider) => _handleSendMessage(message, provider, emit),
        sendMessageWithImages: (message, images, provider) => _handleSendMessageWithImages(message, images, provider, emit),
        receiveStreamChunk: (chunk) => _handleReceiveStreamChunk(chunk, emit),
        finishResponse: () => _handleFinishResponse(emit),
        stopStreaming: () => _handleStopStreaming(emit),
        errorOccurred: (error) => _handleErrorOccurred(error, emit),
        loadHistory: () => _handleLoadHistory(emit),
        clearChat: () => _handleClearChat(emit),
        changeProvider: (provider) => _handleChangeProvider(provider, emit),
        loadChatHistory: () => _handleLoadChatHistory(emit),
        loadChatSession: (sessionId) => _handleLoadChatSession(sessionId, emit),
        createNewChatSession: () => _handleCreateNewChatSession(emit),
        renameChatSession: (sessionId, newTitle) => _handleRenameChatSession(sessionId, newTitle, emit),
        deleteChatSessions: (sessionIds) => _handleDeleteChatSessions(sessionIds, emit),
        clearAllChatHistory: () => _handleClearAllChatHistory(emit),
        exportChatHistory: () => _handleExportChatHistory(emit),
        retryMessage: (messageId) => _handleRetryMessage(messageId, emit),
        editMessage: (messageId, newContent) => _handleEditMessage(messageId, newContent, emit),
      );
    });
  }

  @override
  Future<void> close() async {
    // 取消所有订阅
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    
    return super.close();
  }

  /// 处理发送消息
  Future<void> _handleSendMessage(
    String message,
    AIProvider? provider,
    Emitter<StandaloneChatState> emit,
  ) async {
    if (message.trim().isEmpty) return;

    // 确保有可用会话
    await _ensureSessionInitialized(emit);
    final currentSessionId = state.currentSessionId!;

    // 确定使用的AI提供商
    final selectedProvider = provider ?? 
        state.selectedProvider ?? 
        _configService.currentProvider;

    // 重置用户停止标志
    _isUserStopped = false;
    
    // 生成消息ID
    final userMessageId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentMessageId = '${DateTime.now().millisecondsSinceEpoch + 1}'; // AI消息ID

    // 添加用户消息
    final userMessage = ChatMessage(
      id: userMessageId,
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    // 先更新UI状态，显示用户消息
    if (!emit.isDone) {
      emit(state.copyWith(
        messages: [...state.messages, userMessage],
        isLoading: true,
        isStreaming: true,
        error: null,
        selectedProvider: selectedProvider,
        currentStreamingMessage: '',
      ));
      debugPrint('✅ 用户消息已添加到UI');
    }

    // 异步保存用户消息到数据库（不阻塞UI）
    _saveMessageAsync(userMessage, sessionId: currentSessionId);

    // 若是新会话的第一条用户消息，基于内容生成标题摘要
    if (state.messages.isEmpty) {
      final title = _summarizeTitleFrom(message);
      try {
        await _persistence.renameSession(currentSessionId, title);
        final sessions = await _persistence.loadSessions();
        if (!emit.isDone) {
          emit(state.copyWith(chatSessions: sessions));
        }
      } catch (e) {
        debugPrint('⚠️ 重命名会话失败: $e');
      }
    }

    debugPrint('🎯 准备进入AI服务调用try块');
    debugPrint('🔍 选中的提供商: ${selectedProvider.displayName}');
    
    // 使用 unawaited 来防止阻塞事件处理器
    debugPrint('⚡ 开始异步调用AI服务...');
    unawaited(_callAIServiceAsync(message, selectedProvider, null));
  }

  /// 处理发送带图片的消息
  Future<void> _handleSendMessageWithImages(
    String message,
    List<ChatImage> images,
    AIProvider? provider,
    Emitter<StandaloneChatState> emit,
  ) async {
    debugPrint('🚀📷 _handleSendMessageWithImages 被调用！消息: "$message", 图片数量: ${images.length}');
    if (message.trim().isEmpty && images.isEmpty) return;

    await _ensureSessionInitialized(emit);
    final currentSessionId = state.currentSessionId!;

    // 确定使用的AI提供商
    final selectedProvider = provider ?? 
        state.selectedProvider ?? 
        _configService.currentProvider;
    debugPrint('✅ 最终选择的提供商: ${selectedProvider.displayName}');

    try {
      // 初始化图片存储服务
      await _imageStorage.initialize();

      // 保存图片并获取图片ID
      final imageIds = <String>[];
      for (final image in images) {
        final imageId = await _imageStorage.saveImage(image);
        if (imageId != null) {
          imageIds.add(imageId);
        }
      }

      // 重置用户停止标志
      _isUserStopped = false;
      
      // 生成消息ID
      final userMessageId = DateTime.now().millisecondsSinceEpoch.toString();
      _currentMessageId = '${DateTime.now().millisecondsSinceEpoch + 1}'; // AI消息ID

      // 创建用户消息（包含图片ID）
      final userMessage = ChatMessage(
        id: userMessageId,
        content: message,
        isUser: true,
        timestamp: DateTime.now(),
        imageIds: imageIds,
      );

      // 先更新UI状态，显示用户消息
      if (!emit.isDone) {
        emit(state.copyWith(
          messages: [...state.messages, userMessage],
          isLoading: true,
          isStreaming: true,
          error: null,
          selectedProvider: selectedProvider,
          currentStreamingMessage: '',
        ));
        debugPrint('✅ 带图片的用户消息已添加到UI');
      }

      // 异步保存用户消息到数据库（不阻塞UI）
    _saveMessageAsync(userMessage, sessionId: currentSessionId);

      // 构建包含图片的消息内容
      String fullMessage = message;
      if (images.isNotEmpty) {
        fullMessage += '\n\n[包含 ${images.length} 张图片，请分析这些图片]';
      }

      debugPrint('🎯 准备调用AI服务分析图片');
      
      // 异步调用AI服务，包含图片数据
      unawaited(_callAIServiceWithImagesAsync(fullMessage, images, selectedProvider));
    } catch (e) {
      debugPrint('❌ 处理带图片消息失败: $e');
      if (!emit.isDone) {
        emit(state.copyWith(
          isLoading: false,
          isStreaming: false,
          error: '发送消息失败: $e',
        ));
      }
    }
  }

  /// 异步调用AI服务，包含图片分析
  Future<void> _callAIServiceWithImagesAsync(
    String message,
    List<ChatImage> images,
    AIProvider selectedProvider,
  ) async {
    debugPrint('🌟📷 _callAIServiceWithImagesAsync 方法被调用！');
    try {
      // 开始AI流式响应
      await _streamSubscription?.cancel();
      debugPrint('📡 流订阅已取消');
      
      // 构建包含图片信息的完整消息
      String enhancedMessage = message;
      if (images.isNotEmpty) {
        enhancedMessage += '\n\n图片信息：\n';
        for (int i = 0; i < images.length; i++) {
          final image = images[i];
          enhancedMessage += '- 图片${i + 1}: ${image.name ?? '未知'} (${image.fileSizeFormatted})\n';
        }
        enhancedMessage += '\n请详细分析这些图片的内容。';
      }
      
      debugPrint('🤖 准备调用AI服务: 消息长度=${enhancedMessage.length}, 图片数量=${images.length}');
      
      await _aiService.sendMessage(
        message: message, // 使用原始消息，不添加额外描述
        provider: selectedProvider,
        images: images, // 传递图片数据
        onResponse: (response) {
          debugPrint('📨 收到AI响应片段: $response');
          add(StandaloneChatEvent.receiveStreamChunk(chunk: response));
        },
        onError: (error) {
          debugPrint('❌ AI响应错误: $error');
          add(StandaloneChatEvent.errorOccurred(error: error));
        },
        onComplete: () {
          debugPrint('✅ AI流式响应完成，发送完成事件');
          add(const StandaloneChatEvent.finishResponse());
        },
      );
    } catch (e) {
      debugPrint('❌ AI服务调用异常: $e');
      add(StandaloneChatEvent.errorOccurred(error: e.toString()));
    }
  }

  /// 异步调用AI服务，避免阻塞事件处理器
  Future<void> _callAIServiceAsync(String message, AIProvider selectedProvider, List<ChatImage>? images) async {
    debugPrint('🌟 _callAIServiceAsync 方法被调用！');
    try {
      // 开始AI流式响应
      await _streamSubscription?.cancel();
      debugPrint('📡 流订阅已取消');
      
      debugPrint('🤖 准备调用AI服务: 消息="$message", 提供商=${selectedProvider.displayName}');
      
      await _aiService.sendMessage(
        message: message,
        provider: selectedProvider,
        images: images, // 传递图片数据
        onResponse: (response) {
          debugPrint('📨 收到AI响应片段: $response');
          add(StandaloneChatEvent.receiveStreamChunk(chunk: response));
        },
        onError: (error) {
          debugPrint('❌ AI响应错误: $error');
          add(StandaloneChatEvent.errorOccurred(error: error));
        },
        onComplete: () {
          debugPrint('✅ AI流式响应完成，发送完成事件');
          debugPrint('🚀 准备调用 finishResponse 事件');
          add(const StandaloneChatEvent.finishResponse());
          debugPrint('📤 finishResponse 事件已添加到队列');
        },
      );
    } catch (e) {
      debugPrint('❌ AI服务调用异常: $e');
      add(StandaloneChatEvent.errorOccurred(error: e.toString()));
    }
  }

  /// 处理接收流式数据块
  void _handleReceiveStreamChunk(
    String chunk,
    Emitter<StandaloneChatState> emit,
  ) {
    if (emit.isDone) return;
    
    // 如果用户已经停止了，忽略后续的流式数据
    if (_isUserStopped) {
      debugPrint('⚠️ 用户已停止流式输出，忽略数据块: $chunk');
      return;
    }
    
    final currentContent = state.currentStreamingMessage ?? '';
    final newContent = currentContent + chunk;

    if (!emit.isDone) {
      emit(state.copyWith(
        currentStreamingMessage: newContent,
        isStreaming: true,
      ));
    }
  }

  /// 处理完成响应
  Future<void> _handleFinishResponse(Emitter<StandaloneChatState> emit) async {
    debugPrint('🎯 _handleFinishResponse 方法被调用');
    debugPrint('📊 当前状态: isLoading=${state.isLoading}, isStreaming=${state.isStreaming}');
    debugPrint('🛑 用户是否停止: $_isUserStopped');
    
    // 如果用户已经停止了，忽略这个完成事件
    if (_isUserStopped) {
      debugPrint('⚠️ 用户已停止流式输出，忽略完成事件');
      return;
    }
    
    if (emit.isDone) return;
    
    final streamingContent = state.currentStreamingMessage ?? '';
    
    if (streamingContent.isNotEmpty) {
      // 创建AI消息
      final aiMessage = ChatMessage(
        id: _currentMessageId,
        content: streamingContent,
        isUser: false,
        timestamp: DateTime.now(),
        aiProvider: state.selectedProvider,
      );

      // 先更新UI状态，然后异步保存到数据库
      debugPrint('🔄 _handleFinishResponse: 设置 isLoading: false, isStreaming: false');
      emit(state.copyWith(
        messages: [...state.messages, aiMessage],
        isLoading: false,
        isStreaming: false,
        currentStreamingMessage: null,
      ));
      debugPrint('✅ _handleFinishResponse: 状态已更新，isLoading: false');

      // 异步保存到数据库（不阻塞UI更新）
      final sessionId = state.currentSessionId;
      if (sessionId != null) {
        _saveMessageAsync(aiMessage, sessionId: sessionId);
      }
    } else {
      debugPrint('🔄 _handleFinishResponse: 空响应，设置 isLoading: false, isStreaming: false');
      emit(state.copyWith(
        isLoading: false,
        isStreaming: false,
        currentStreamingMessage: null,
      ));
      debugPrint('✅ _handleFinishResponse: 空响应状态已更新');
    }
  }

  /// 处理停止流式传输
  Future<void> _handleStopStreaming(Emitter<StandaloneChatState> emit) async {
    debugPrint('🛑 _handleStopStreaming 方法被调用');
    debugPrint('📊 当前状态: isLoading=${state.isLoading}, isStreaming=${state.isStreaming}');
    
    // 设置用户停止标志
    _isUserStopped = true;
    
    // 取消AI服务的当前请求
    _aiService.cancelCurrentRequest();
    
    // 取消流式传输订阅
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    
    if (emit.isDone) return;
    
    final streamingContent = state.currentStreamingMessage ?? '';
    
    if (streamingContent.isNotEmpty) {
      // 如果有部分流式内容，保存为AI消息
      final aiMessage = ChatMessage(
        id: _currentMessageId,
        content: streamingContent + '\n\n[响应已被用户中止]',
        isUser: false,
        timestamp: DateTime.now(),
        aiProvider: state.selectedProvider,
      );

      // 更新UI状态并保存部分消息
      debugPrint('🔄 _handleStopStreaming: 保存部分响应并设置 isLoading: false, isStreaming: false');
      emit(state.copyWith(
        messages: [...state.messages, aiMessage],
        isLoading: false,
        isStreaming: false,
        currentStreamingMessage: null,
      ));
      debugPrint('✅ _handleStopStreaming: 状态已更新，isLoading: false');

      // 异步保存到数据库
      final sessionId = state.currentSessionId;
      if (sessionId != null) {
        _saveMessageAsync(aiMessage, sessionId: sessionId);
      }
    } else {
      // 如果没有内容，只是停止状态
      debugPrint('🔄 _handleStopStreaming: 无内容，仅停止流式传输状态');
      emit(state.copyWith(
        isLoading: false,
        isStreaming: false,
        currentStreamingMessage: null,
      ));
      debugPrint('✅ _handleStopStreaming: 状态已更新');
    }
  }

  /// 异步保存消息到数据库
  void _saveMessageAsync(ChatMessage message, {required String sessionId}) async {
    try {
      final messageType = message.isUser ? '用户' : 'AI';
      debugPrint('💾 开始异步保存${messageType}消息到数据库...');
      await _persistence.saveMessage(message, sessionId: sessionId);
      debugPrint('✅ ${messageType}消息已成功异步保存到数据库');
    } catch (e) {
      final messageType = message.isUser ? '用户' : 'AI';
      debugPrint('❌ 异步保存${messageType}消息失败: $e');
    }
  }

  /// 处理错误
  void _handleErrorOccurred(
    String error,
    Emitter<StandaloneChatState> emit,
  ) {
    if (emit.isDone) return;
    
    emit(state.copyWith(
      isLoading: false,
      isStreaming: false,
      error: error,
      currentStreamingMessage: null,
    ));
  }

  /// 处理加载历史记录
  Future<void> _handleLoadHistory(Emitter<StandaloneChatState> emit) async {
    if (state.isHistoryLoaded) return;
    try {
      // 会话列表
      var sessions = await _persistence.loadSessions();
      if (sessions.isEmpty) {
        final created = await _persistence.createSession(provider: _configService.currentProvider);
        sessions = [created];
      }
      final currentSessionId = state.currentSessionId ?? sessions.last.id;
      final historyMessages = await _persistence.loadMessages(sessionId: currentSessionId);
      if (emit.isDone) return;
      emit(state.copyWith(
        chatSessions: sessions,
        currentSessionId: currentSessionId,
        messages: historyMessages,
        isHistoryLoaded: true,
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(error: '加载历史记录失败: $e'));
    }
  }

  /// 处理清空聊天
  Future<void> _handleClearChat(Emitter<StandaloneChatState> emit) async {
    try {
      final sessionId = state.currentSessionId;
      if (sessionId != null) {
        await _persistence.clearMessages(sessionId: sessionId);
      }
      if (emit.isDone) return;
      emit(state.copyWith(
        messages: [],
        error: null,
        currentStreamingMessage: null,
        isStreaming: false,
        isLoading: false,
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(
        error: '清空聊天失败: $e',
      ));
    }
  }

  /// 处理切换提供商
  void _handleChangeProvider(
    AIProvider provider,
    Emitter<StandaloneChatState> emit,
  ) {
    _configService.setProvider(provider);
    if (emit.isDone) return;
    emit(state.copyWith(
      selectedProvider: provider,
    ));
  }


  /// 处理加载聊天历史 - 与 loadHistory 相同
  Future<void> _handleLoadChatHistory(
    Emitter<StandaloneChatState> emit,
  ) async {
    await _handleLoadHistory(emit);
  }

  /// 处理加载聊天会话
  Future<void> _handleLoadChatSession(
    String sessionId,
    Emitter<StandaloneChatState> emit,
  ) async {
    try {
      final messages = await _persistence.loadMessages(sessionId: sessionId);
      final sessions = await _persistence.loadSessions();
      if (emit.isDone) return;
      emit(state.copyWith(
        currentSessionId: sessionId,
        messages: messages,
        chatSessions: sessions,
        isHistoryLoaded: true,
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(error: '加载会话失败: $e'));
    }
  }

  /// 处理创建新聊天会话
  Future<void> _handleCreateNewChatSession(
    Emitter<StandaloneChatState> emit,
  ) async {
    try {
      final created = await _persistence.createSession(provider: state.selectedProvider ?? _configService.currentProvider);
      final sessions = await _persistence.loadSessions();
      if (emit.isDone) return;
      emit(state.copyWith(
        currentSessionId: created.id,
        chatSessions: sessions,
        messages: [],
        isHistoryLoaded: true,
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(error: '创建新会话失败: $e'));
    }
  }

  /// 处理重命名聊天会话
  Future<void> _handleRenameChatSession(
    String sessionId,
    String newTitle,
    Emitter<StandaloneChatState> emit,
  ) async {
    try {
      await _persistence.renameSession(sessionId, newTitle);
      final sessions = await _persistence.loadSessions();
      if (emit.isDone) return;
      emit(state.copyWith(chatSessions: sessions));
    } catch (e) {
      debugPrint('⚠️ 重命名会话失败: $e');
    }
  }

  /// 处理删除聊天会话
  Future<void> _handleDeleteChatSessions(
    List<String> sessionIds,
    Emitter<StandaloneChatState> emit,
  ) async {
    try {
      final currentId = state.currentSessionId;
      await _persistence.deleteSessions(sessionIds);
      var sessions = await _persistence.loadSessions();
      String? nextId = currentId;
      if (currentId == null || sessionIds.contains(currentId)) {
        if (sessions.isEmpty) {
          final created = await _persistence.createSession(provider: state.selectedProvider ?? _configService.currentProvider);
          sessions = [created];
          nextId = created.id;
        } else {
          nextId = sessions.last.id;
        }
      }
      final messages = await _persistence.loadMessages(sessionId: nextId!);
      if (emit.isDone) return;
      emit(state.copyWith(
        chatSessions: sessions,
        currentSessionId: nextId,
        messages: messages,
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(error: '删除会话失败: $e'));
    }
  }

  /// 处理清空所有聊天历史
  Future<void> _handleClearAllChatHistory(
    Emitter<StandaloneChatState> emit,
  ) async {
    try {
      final sessions = await _persistence.loadSessions();
      await _persistence.deleteSessions(sessions.map((e) => e.id).toList());
      final created = await _persistence.createSession(provider: state.selectedProvider ?? _configService.currentProvider);
      if (emit.isDone) return;
      emit(state.copyWith(
        chatSessions: [created],
        currentSessionId: created.id,
        messages: [],
      ));
    } catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(error: '清空所有聊天失败: $e'));
    }
  }

  /// 处理导出聊天历史
  Future<void> _handleExportChatHistory(
    Emitter<StandaloneChatState> emit,
  ) async {
    final sessionId = state.currentSessionId;
    if (sessionId == null) {
      debugPrint('⚠️ 尚无可导出的会话');
      return;
    }
    try {
      final jsonStr = await _persistence.exportChat(sessionId);
      final dir = _getDefaultExportDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final timestamp = DateTime.now();
      final filename = 'ai_chat_${timestamp.year}${_two(timestamp.month)}${_two(timestamp.day)}_${_two(timestamp.hour)}${_two(timestamp.minute)}${_two(timestamp.second)}_$sessionId.json';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(jsonStr);
      debugPrint('✅ 聊天记录已导出到: ${file.path}');
    } catch (e) {
      debugPrint('❌ 导出聊天记录失败: $e');
      if (!emit.isDone) {
        emit(state.copyWith(error: '导出聊天记录失败: $e'));
      }
    }
  }

  /// 处理重试消息
  Future<void> _handleRetryMessage(
    String messageId,
    Emitter<StandaloneChatState> emit,
  ) async {
    // TODO: 实现消息重试功能
    debugPrint('消息重试功能暂未实现');
  }

  /// 处理编辑消息
  Future<void> _handleEditMessage(
    String messageId,
    String newContent,
    Emitter<StandaloneChatState> emit,
  ) async {
    // TODO: 实现消息编辑功能
    debugPrint('消息编辑功能暂未实现');
  }

}

/// 扩展方法
extension ListExtension<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}

/// 私有工具方法
extension _BlocUtils on StandaloneChatBloc {
  String _summarizeTitleFrom(String content) {
    final raw = content.replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (raw.isEmpty) return '新的会话';
    return raw.length > 24 ? raw.substring(0, 24) : raw;
  }

  Future<void> _ensureSessionInitialized(Emitter<StandaloneChatState> emit) async {
    if (state.currentSessionId != null) return;
    var sessions = await _persistence.loadSessions();
    if (sessions.isEmpty) {
      final created = await _persistence.createSession(provider: state.selectedProvider ?? _configService.currentProvider);
      sessions = [created];
    }
    if (!emit.isDone) {
      emit(state.copyWith(
        chatSessions: sessions,
        currentSessionId: sessions.last.id,
        isHistoryLoaded: true,
      ));
    }
  }

  Directory _getDefaultExportDir() {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '.';
      return Directory('$home\\PonyNotes-Exports');
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      return Directory('$home/PonyNotes-Exports');
    }
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}
