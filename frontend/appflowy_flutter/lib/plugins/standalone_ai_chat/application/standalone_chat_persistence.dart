import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:appflowy/core/config/ai_config.dart';
import 'standalone_chat_bloc.dart';

/// 独立AI聊天持久化服务
/// 使用 shared_preferences 进行本地持久化存储
class StandaloneChatPersistence {
  static StandaloneChatPersistence? _instance;
  static StandaloneChatPersistence get instance => 
      _instance ??= StandaloneChatPersistence._();
  StandaloneChatPersistence._();

  // 独立聊天的固定ID，用于标识这是独立AI聊天
  static const String standaloneChatId = 'standalone_ai_chat';
  static const String standaloneWorkspaceId = 'standalone_workspace';
  
  // SharedPreferences 存储键
  static const String _storageKeyLegacy = 'standalone_chat_messages';
  static const String _sessionsKey = 'standalone_chat_sessions';
  static String _messagesKey(String sessionId) => 'standalone_chat_messages_$sessionId';

  /// 加载所有会话（带旧数据迁移）
  Future<List<ChatSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJsonList = prefs.getStringList(_sessionsKey) ?? [];
    if (sessionJsonList.isEmpty) {
      // 旧版迁移：将单会话消息迁移为一个新会话
      final legacy = prefs.getStringList(_storageKeyLegacy);
      if (legacy != null && legacy.isNotEmpty) {
        final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
        final messages = legacy.map((e) {
          try {
            return _messageFromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<ChatMessage>().toList();
        final session = ChatSession(
          id: sessionId,
          title: _makeTitleFromFirstUser(messages),
          lastMessage: messages.isNotEmpty ? messages.last.content : null,
          lastMessageTime: messages.isNotEmpty ? messages.last.timestamp : DateTime.now(),
          messageCount: messages.length,
          provider: messages.isNotEmpty ? messages.last.aiProvider : null,
        );
        await prefs.setStringList(_messagesKey(sessionId), legacy);
        await prefs.remove(_storageKeyLegacy);
        await prefs.setStringList(_sessionsKey, [jsonEncode(_sessionToJson(session))]);
        return [session];
      }
      return [];
    }
    final sessions = <ChatSession>[];
    for (final s in sessionJsonList) {
      try {
        sessions.add(_sessionFromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('⚠️ 解析会话失败: $e');
      }
    }
    return sessions;
  }

  /// 创建新会话
  Future<ChatSession> createSession({String? title, AIProvider? provider}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();
    final session = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: (title ?? '').trim().isNotEmpty ? title!.trim() : '新的会话',
      lastMessage: null,
      lastMessageTime: DateTime.now(),
      messageCount: 0,
      provider: provider,
    );
    final updated = [...sessions, session];
    await prefs.setStringList(_sessionsKey, updated.map((s) => jsonEncode(_sessionToJson(s))).toList());
    await prefs.setStringList(_messagesKey(session.id), []);
    return session;
  }

  /// 重命名会话
  Future<void> renameSession(String sessionId, String newTitle) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final updated = sessions[idx].copyWith(
      title: newTitle.trim().isEmpty ? sessions[idx].title : newTitle.trim(),
    );
    sessions[idx] = updated;
    await prefs.setStringList(_sessionsKey, sessions.map((s) => jsonEncode(_sessionToJson(s))).toList());
  }

  /// 删除会话（及其消息）
  Future<void> deleteSessions(List<String> sessionIds) async {
    final prefs = await SharedPreferences.getInstance();
    var sessions = await loadSessions();
    sessions = sessions.where((s) => !sessionIds.contains(s.id)).toList();
    await prefs.setStringList(_sessionsKey, sessions.map((s) => jsonEncode(_sessionToJson(s))).toList());
    for (final id in sessionIds) {
      await prefs.remove(_messagesKey(id));
    }
  }

  /// 保存消息到本地存储
  Future<void> saveMessage(ChatMessage message, {required String sessionId}) async {
    try {
      // 加载现有消息
      final messages = await loadMessages(sessionId: sessionId);
      
      // 检查消息是否已存在（避免重复）
      final existingIndex = messages.indexWhere((m) => m.id == message.id);
      if (existingIndex >= 0) {
        // 更新现有消息
        messages[existingIndex] = message;
        debugPrint('🔄 更新现有消息: ${message.id}');
      } else {
        // 添加新消息
        messages.add(message);
        debugPrint('➕ 添加新消息: ${message.id}');
      }
      
      // 保存到 SharedPreferences
      await _saveMessagesToStorage(messages, sessionId: sessionId);
      await _updateSessionMetaForMessages(sessionId, messages);
      
      debugPrint('✅ 消息已保存: ${message.content.length > 50 ? message.content.substring(0, 50) + '...' : message.content}');
    } catch (e) {
      debugPrint('❌ 保存消息失败: $e');
      // 不抛出异常，避免影响用户体验
    }
  }

  /// 从本地存储加载消息
  Future<List<ChatMessage>> loadMessages({required String sessionId}) async {
    try {
      debugPrint('🔄 开始加载历史消息...');
      
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getStringList(_messagesKey(sessionId)) ?? [];
      
      final messages = messagesJson.map((jsonStr) {
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          return _messageFromJson(json);
        } catch (e) {
          debugPrint('⚠️ 解析消息失败: $e');
          return null;
        }
      }).whereType<ChatMessage>().toList();
      
      debugPrint('✅ 加载了 ${messages.length} 条历史消息');
      return messages;
    } catch (e) {
      debugPrint('❌ 加载历史消息失败: $e');
      return []; // 返回空列表，不影响用户体验
    }
  }

  /// 清空所有消息
  Future<void> clearMessages({required String sessionId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_messagesKey(sessionId));
      debugPrint('✅ 已清空所有聊天记录');
    } catch (e) {
      debugPrint('❌ 清空聊天记录失败: $e');
      rethrow; // 清空失败需要让用户知道
    }
  }

  /// 保存消息列表到存储
  Future<void> _saveMessagesToStorage(List<ChatMessage> messages, {required String sessionId}) async {
    final prefs = await SharedPreferences.getInstance();
    final messagesJson = messages.map((m) => jsonEncode(_messageToJson(m))).toList();
    await prefs.setStringList(_messagesKey(sessionId), messagesJson);
  }
  
  /// 将 ChatMessage 转换为 JSON
  Map<String, dynamic> _messageToJson(ChatMessage message) {
    return {
      'id': message.id,
      'content': message.content,
      'isUser': message.isUser,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'aiProvider': message.aiProvider?.id,
      'provider': message.provider?.id,
      'isStreaming': message.isStreaming,
      'hasError': message.hasError,
      'imageIds': message.imageIds,
    };
  }
  
  /// 从 JSON 创建 ChatMessage
  ChatMessage _messageFromJson(Map<String, dynamic> json) {
    // 解析 AI 提供商
    AIProvider? aiProvider;
    final providerIdFromAiProvider = json['aiProvider'] as String?;
    final providerIdFromProvider = json['provider'] as String?;
    final providerId = providerIdFromAiProvider ?? providerIdFromProvider;
    
    if (providerId != null) {
      try {
        aiProvider = AIProvider.values.firstWhere(
          (p) => p.id == providerId,
          orElse: () => AIProvider.deepseek,
        );
      } catch (e) {
        debugPrint('⚠️ 无法解析 AI 提供商: $providerId');
      }
    }
    
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      isUser: json['isUser'] as bool,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      aiProvider: aiProvider,
      provider: aiProvider,
      isStreaming: json['isStreaming'] as bool? ?? false,
      hasError: json['hasError'] as bool? ?? false,
      imageIds: (json['imageIds'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// 获取聊天统计信息
  Future<Map<String, dynamic>> getChatStats() async {
    try {
      final sessions = await loadSessions();
      if (sessions.isEmpty) {
        return {
          'totalMessages': 0,
          'userMessages': 0,
          'aiMessages': 0,
          'lastMessageTime': null,
        };
      }
      final messages = await loadMessages(sessionId: sessions.first.id);
      final userMessages = messages.where((m) => m.isUser).length;
      final aiMessages = messages.where((m) => !m.isUser).length;
      
      return {
        'totalMessages': messages.length,
        'userMessages': userMessages,
        'aiMessages': aiMessages,
        'lastMessageTime': messages.isNotEmpty 
            ? messages.last.timestamp.toIso8601String()
            : null,
      };
    } catch (e) {
      debugPrint('获取聊天统计失败: $e');
      return {
        'totalMessages': 0,
        'userMessages': 0,
        'aiMessages': 0,
        'lastMessageTime': null,
      };
    }
  }

  /// 搜索消息内容
  Future<List<ChatMessage>> searchMessages(String query) async {
    try {
      final sessions = await loadSessions();
      if (sessions.isEmpty) return [];
      final allMessages = await loadMessages(sessionId: sessions.first.id);
      return allMessages.where((message) {
        return message.content.toLowerCase().contains(query.toLowerCase());
      }).toList();
    } catch (e) {
      debugPrint('搜索消息失败: $e');
      return [];
    }
  }

  /// 导出聊天记录
  Future<String> exportChat(String sessionId) async {
    try {
      final messages = await loadMessages(sessionId: sessionId);
      final exportData = {
        'exportTime': DateTime.now().toIso8601String(),
        'chatId': sessionId,
        'totalMessages': messages.length,
        'messages': messages.map((m) => {
          'id': m.id,
          'content': m.content,
          'isUser': m.isUser,
          'timestamp': m.timestamp.toIso8601String(),
          'aiProvider': m.aiProvider?.id,
        }).toList(),
      };
      
      return jsonEncode(exportData);
    } catch (e) {
      debugPrint('导出聊天记录失败: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _sessionToJson(ChatSession session) {
    return {
      'id': session.id,
      'title': session.title,
      'lastMessage': session.lastMessage,
      'lastMessageTime': session.lastMessageTime.toIso8601String(),
      'messageCount': session.messageCount,
      'provider': session.provider?.id,
    };
  }

  ChatSession _sessionFromJson(Map<String, dynamic> json) {
    AIProvider? provider;
    final providerId = json['provider'] as String?;
    if (providerId != null) {
      try {
        provider = AIProvider.values.firstWhere((p) => p.id == providerId, orElse: () => AIProvider.deepseek);
      } catch (_) {}
    }
    return ChatSession(
      id: json['id'] as String,
      title: ((json['title'] as String?) ?? '').trim().isNotEmpty ? (json['title'] as String) : '新的会话',
      lastMessage: json['lastMessage'] as String?,
      lastMessageTime: DateTime.tryParse(json['lastMessageTime'] as String? ?? '') ?? DateTime.now(),
      messageCount: (json['messageCount'] as int?) ?? 0,
      provider: provider,
    );
  }

  Future<void> _updateSessionMetaForMessages(String sessionId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadSessions();
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final last = messages.isNotEmpty ? messages.last : null;
    final updated = sessions[idx].copyWith(
      lastMessage: last?.content,
      lastMessageTime: last?.timestamp ?? DateTime.now(),
      messageCount: messages.length,
      provider: last?.aiProvider ?? sessions[idx].provider,
    );
    sessions[idx] = updated;
    await prefs.setStringList(_sessionsKey, sessions.map((s) => jsonEncode(_sessionToJson(s))).toList());
  }

  String _makeTitleFromFirstUser(List<ChatMessage> messages) {
    final candidate = messages.firstWhere(
      (m) => m.isUser,
      orElse: () => messages.isNotEmpty
          ? messages.first
          : ChatMessage(id: 'empty', content: '新的会话', isUser: true, timestamp: DateTime.now()),
    );
    final raw = candidate.content.replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (raw.isEmpty) return '新的会话';
    return raw.length > 24 ? raw.substring(0, 24) : raw;
  }
}
