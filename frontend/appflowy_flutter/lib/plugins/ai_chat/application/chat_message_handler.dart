import 'dart:convert';
import 'dart:collection';

import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:nanoid/nanoid.dart';

import 'chat_entity.dart';
import 'chat_message_stream.dart';

/// Returns current Unix timestamp (seconds since epoch)
int timestamp() {
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Handles message creation and manipulation for the chat system
class ChatMessageHandler {
  ChatMessageHandler({
    required this.chatId,
    required this.userId,
    required this.chatController,
  });
  final String chatId;
  final String userId;
  final ChatController chatController;

  /// Maps real message IDs to temporary streaming message IDs
  final HashMap<String, String> _temporaryMessageIDMap = HashMap();
  
  /// 【修复消息重复】追踪已处理的消息ID，防止通过不同callback重复处理同一条消息
  final Set<String> _processedMessageIds = {};

  /// Gets the effective message ID from the temporary map
  String getEffectiveMessageId(String messageId) {
    return _temporaryMessageIDMap.entries
            .firstWhereOrNull((entry) => entry.value == messageId)
            ?.key ??
        messageId;
  }

  String answerStreamMessageId = '';
  String questionStreamMessageId = '';

  /// Create a message from ChatMessagePB object
  Message createTextMessage(ChatMessagePB message) {
    String messageId = message.messageId.toString();
    String originalMessageId = messageId;
    
    // 用于保存从临时消息中复制的图片数据
    List<String>? preservedImages;
    bool? preservedHasImages;

    /// If the message id is in the temporary map, we will use the previous fake message id
    if (_temporaryMessageIDMap.containsKey(messageId)) {
      final mappedId = _temporaryMessageIDMap[messageId]!;
      Log.info('🔄 MessageHandler.createTextMessage: 使用映射ID');
      Log.info('   - 真实ID: $originalMessageId');
      Log.info('   - 映射ID: $mappedId');
      
      // 【关键修复】从临时消息中复制图片数据
      final existingMessage = chatController.messages.firstWhereOrNull(
        (m) => m.id == mappedId,
      );
      if (existingMessage != null && existingMessage.metadata != null) {
        final existingMeta = existingMessage.metadata!;
        if (existingMeta['images'] != null) {
          preservedImages = (existingMeta['images'] as List).cast<String>();
          Log.info('📸 MessageHandler: 从临时消息复制 ${preservedImages.length} 张图片');
        }
        if (existingMeta['has_images'] != null) {
          preservedHasImages = existingMeta['has_images'] as bool;
        }
      }
      
      messageId = mappedId;
    } else {
      Log.info('ℹ️ MessageHandler.createTextMessage: 未找到映射');
      Log.info('   - 消息ID: $messageId');
      Log.info('   - 当前映射表: $_temporaryMessageIDMap');
      
      // 【关键修复】即使没有映射，也尝试从现有消息中查找相同ID的消息，获取图片数据
      // 这可以处理从服务器加载历史消息时的情况
      final existingMessage = chatController.messages.firstWhereOrNull(
        (m) => m.id == messageId,
      );
      if (existingMessage != null && existingMessage.metadata != null) {
        final existingMeta = existingMessage.metadata!;
        if (existingMeta['images'] != null && existingMeta['images'] is List) {
          preservedImages = (existingMeta['images'] as List).cast<String>();
          Log.info('📸 MessageHandler: 从现有消息复制 ${preservedImages.length} 张图片（无映射情况）');
        }
        if (existingMeta['has_images'] != null) {
          preservedHasImages = existingMeta['has_images'] as bool;
        }
      }
    }
    // 处理metadata：如果为空或'null'，使用空对象字符串
    final metadata = (message.metadata.isEmpty || message.metadata == 'null') 
        ? '{}' 
        : message.metadata;
    Log.info('📋 MessageHandler: 原始metadata字符串: ${metadata.length > 200 ? metadata.substring(0, 200) + "..." : metadata}');
    Log.info('📋 MessageHandler: 消息ID: $messageId, 作者ID: ${message.authorId}');

    // 尝试从metadata字符串中解析图片数据
    List<String>? serverImages;
    bool? serverHasImages;
    try {
      final metadataJson = jsonDecode(metadata);
      Log.info('📋 MessageHandler: 解析后的metadata类型: ${metadataJson.runtimeType}');
      if (metadataJson is Map<String, dynamic>) {
        Log.info('📋 MessageHandler: metadata键列表: ${metadataJson.keys.toList()}');
        if (metadataJson['images'] != null) {
          if (metadataJson['images'] is List) {
            serverImages = (metadataJson['images'] as List)
                .map((e) => e.toString())
                .toList();
            Log.info('📸 MessageHandler: 从metadata提取到 ${serverImages.length} 张图片');
          } else {
            Log.warn('⚠️ MessageHandler: images字段不是List类型，是: ${metadataJson['images'].runtimeType}');
          }
        } else {
          Log.info('📋 MessageHandler: metadata中没有images字段');
        }
        if (metadataJson['has_images'] != null) {
          serverHasImages = metadataJson['has_images'] as bool;
        }
      } else if (metadataJson is List) {
        Log.info('📋 MessageHandler: metadata是List类型（可能是旧格式），尝试查找图片数据');
        // 如果是List格式，可能是旧格式，尝试查找包含图片的对象
        for (final item in metadataJson) {
          if (item is Map<String, dynamic> && item['images'] != null) {
            if (item['images'] is List) {
              serverImages = (item['images'] as List).map((e) => e.toString()).toList();
              Log.info('📸 MessageHandler: 从List格式metadata中提取到 ${serverImages.length} 张图片');
              break;
            }
          }
        }
      } else {
        Log.info('📋 MessageHandler: metadata不是Map或List类型，是: ${metadataJson.runtimeType}');
      }
    } catch (e) {
      // 解析失败，忽略
      Log.warn('⚠️ MessageHandler: 解析metadata失败: $e, metadata: $metadata');
    }

    // 构建最终的 metadata，保留图片数据
    final finalMetadata = <String, dynamic>{
      messageRefSourceJsonStringKey: metadata,
    };
    
    // 优先使用从临时消息中保留的图片数据，如果没有则使用从服务器解析的图片数据
    if (preservedImages != null && preservedImages.isNotEmpty) {
      finalMetadata['images'] = preservedImages;
      finalMetadata['has_images'] = preservedHasImages ?? true;
      Log.info('📸 MessageHandler: 图片数据已保留到最终消息（从临时消息）');
    } else if (serverImages != null && serverImages.isNotEmpty) {
      finalMetadata['images'] = serverImages;
      finalMetadata['has_images'] = serverHasImages ?? true;
      Log.info('📸 MessageHandler: 图片数据已保留到最终消息（从服务器metadata）');
    }

    return TextMessage(
      author: User(id: message.authorId),
      id: messageId,
      text: message.content,
      createdAt: message.createdAt.toDateTime(),
      metadata: finalMetadata,
    );
  }

  /// Create a streaming answer message
  Message createAnswerStreamMessage({
    required AnswerStream stream,
    required Int64 questionMessageId,
    String? fakeQuestionMessageId,
  }) {
    answerStreamMessageId = fakeQuestionMessageId == null
        ? (questionMessageId + 1).toString()
        : "${fakeQuestionMessageId}_ans";

    return TextMessage(
      id: answerStreamMessageId,
      text: '',
      author: User(id: "streamId:${nanoid()}"),
      metadata: {
        "$AnswerStream": stream,
        messageQuestionIdKey: questionMessageId,
        "chatId": chatId,
      },
      createdAt: DateTime.now(),
    );
  }

  /// Create a streaming question message
  Message createQuestionStreamMessage(
    QuestionStream stream,
    Map<String, dynamic>? sentMetadata,
  ) {
    final now = DateTime.now();
    questionStreamMessageId = timestamp().toString();

    // 构建 metadata，包含图片和文件附件数据
    final metadata = <String, dynamic>{
      "$QuestionStream": stream,
      "chatId": chatId,
    };
    
    // 复制 sentMetadata 中的附件相关字段
    if (sentMetadata != null) {
      // 文件列表
      if (sentMetadata[messageChatFileListKey] != null) {
        metadata[messageChatFileListKey] = sentMetadata[messageChatFileListKey];
      }
      // 图片数据（base64编码）- 用于发送到服务器
      if (sentMetadata['images'] != null) {
        metadata['images'] = sentMetadata['images'];
        Log.info('📸 MessageHandler: 将 ${(sentMetadata['images'] as List).length} 张图片添加到消息metadata');
      }
      // 图片标志
      if (sentMetadata['has_images'] != null) {
        metadata['has_images'] = sentMetadata['has_images'];
      }
    }

    return TextMessage(
      author: User(id: userId),
      metadata: metadata,
      id: questionStreamMessageId,
      createdAt: now,
      text: '',
    );
  }

  /// Clear error messages from the chat
  void clearErrorMessages() {
    final errorMessages = chatController.messages
        .where(
          (message) =>
              onetimeMessageTypeFromMeta(message.metadata) ==
              OnetimeShotType.error,
        )
        .toList();

    for (final message in errorMessages) {
      chatController.remove(message);
    }
  }

  /// Clear related questions from the chat
  void clearRelatedQuestions() {
    final relatedQuestionMessages = chatController.messages
        .where(
          (message) =>
              onetimeMessageTypeFromMeta(message.metadata) ==
              OnetimeShotType.relatedQuestion,
        )
        .toList();

    for (final message in relatedQuestionMessages) {
      chatController.remove(message);
    }
  }

  /// Checks if a message is a one-time message
  bool isOneTimeMessage(Message message) {
    return message.metadata != null &&
        message.metadata!.containsKey(onetimeShotType);
  }

  /// Get the oldest message that is not a one-time message
  Message? getOldestMessage() {
    return chatController.messages
        .firstWhereOrNull((message) => !isOneTimeMessage(message));
  }

  /// Add a message to the temporary ID map when receiving from server
  /// Returns true if this is a new message that should be processed, false if it's a duplicate
  bool processReceivedMessage(ChatMessagePB pb) {
    final messageIdStr = pb.messageId.toString();
    
    Log.info('📨 MessageHandler.processReceivedMessage 被调用');
    Log.info('   - messageId: $messageIdStr');
    Log.info('   - authorType: ${pb.authorType}');
    Log.info('   - content: ${pb.content.substring(0, pb.content.length > 50 ? 50 : pb.content.length)}...');
    
    // 【关键修复】检查消息是否已经处理过
    if (_processedMessageIds.contains(messageIdStr)) {
      Log.info('✅ MessageHandler: 消息已处理过，跳过重复处理');
      Log.info('   - 已处理消息ID集合: $_processedMessageIds');
      return false; // 返回false表示应该跳过这条消息
    }
    
    // 标记消息为已处理
    _processedMessageIds.add(messageIdStr);
    Log.info('   - 标记消息为已处理，当前已处理消息数: ${_processedMessageIds.length}');
    
    // 3 means message response from AI
    if (pb.authorType == 3 && answerStreamMessageId.isNotEmpty) {
      Log.info('   - 这是AI消息，建立ID映射');
      Log.info('   - 真实ID: $messageIdStr');
      Log.info('   - 临时ID: $answerStreamMessageId');
      _temporaryMessageIDMap.putIfAbsent(
        messageIdStr,
        () => answerStreamMessageId,
      );
      answerStreamMessageId = '';
      Log.info('   - 映射表更新后: $_temporaryMessageIDMap');
    }

    // 1 means message response from User
    if (pb.authorType == 1 && questionStreamMessageId.isNotEmpty) {
      Log.info('   - 这是用户消息，建立ID映射');
      Log.info('   - 真实ID: $messageIdStr');
      Log.info('   - 临时ID: $questionStreamMessageId');
      _temporaryMessageIDMap.putIfAbsent(
        messageIdStr,
        () => questionStreamMessageId,
      );
      questionStreamMessageId = '';
      Log.info('   - 映射表更新后: $_temporaryMessageIDMap');
    }
    
    if (pb.authorType != 1 && pb.authorType != 3) {
      Log.info('   - authorType不是1或3，跳过映射');
    }
    
    if (pb.authorType == 1 && questionStreamMessageId.isEmpty) {
      Log.info('ℹ️  用户消息但questionStreamMessageId为空（可能是从服务器加载的历史消息）');
    }
    
    return true; // 返回true表示这是新消息，应该继续处理
  }
}
