import 'dart:io';
import 'dart:typed_data';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_service.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_user_message_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'user_message_bubble.dart';

class ChatUserMessageWidget extends StatelessWidget {
  const ChatUserMessageWidget({
    super.key,
    required this.user,
    required this.message,
  });

  final User user;
  final TextMessage message;

  @override
  Widget build(BuildContext context) {
    final stream = message.metadata?["$QuestionStream"];
    final messageText = stream is QuestionStream ? stream.text : message.text;

    return BlocProvider(
      create: (context) => ChatUserMessageBloc(
        text: messageText,
        questionStream: stream,
      ),
      child: ChatUserMessageBubble(
        message: message,
        files: _getFiles(),
        images: _getImages(),
        imagePaths: _getImagePaths(),
        child: BlocBuilder<ChatUserMessageBloc, ChatUserMessageState>(
          builder: (context, state) {
            return Opacity(
              opacity: state.messageState.isFinish ? 1.0 : 0.8,
              child: TextMessageText(
                text: state.text,
              ),
            );
          },
        ),
      ),
    );
  }

  List<ChatFile> _getFiles() {
    if (message.metadata == null) {
      return const [];
    }

    final refSourceMetadata =
        message.metadata?[messageRefSourceJsonStringKey] as String?;
    if (refSourceMetadata != null) {
      return chatFilesFromMetadataString(refSourceMetadata);
    }

    final chatFileList =
        message.metadata![messageChatFileListKey] as List<ChatFile>?;
    return chatFileList ?? [];
  }

  /// 获取消息中的图片数据（base64编码）
  List<String> _getImages() {
    if (message.metadata == null) {
      Log.info('📸 UserTextMessage: message.metadata为null');
      return const [];
    }

    Log.info('📸 UserTextMessage: 检查metadata中的图片数据');
    Log.info('   - metadata键列表: ${message.metadata!.keys.toList()}');

    final imagesData = message.metadata!['images'];
    Log.info('   - images字段类型: ${imagesData.runtimeType}');
    Log.info('   - images字段值: ${imagesData is List ? "List(${(imagesData as List).length})" : imagesData}');

    if (imagesData is List && imagesData.isNotEmpty) {
      Log.info('📸 UserTextMessage: 找到 ${imagesData.length} 张图片(base64)');
      return imagesData.cast<String>();
    }
    Log.info('📸 UserTextMessage: 没有找到base64图片数据');
    return const [];
  }

  /// 获取消息中的图片文件路径列表（备用方案）
  List<String> _getImagePaths() {
    if (message.metadata == null) {
      return const [];
    }

    final pathsData = message.metadata!['image_paths'];
    if (pathsData is List && pathsData.isNotEmpty) {
      Log.info('📸 UserTextMessage: 找到 ${pathsData.length} 张图片路径');
      return pathsData.cast<String>();
    }
    return const [];
  }
}

/// Widget to reuse the markdown capabilities, e.g., for previews.
class TextMessageText extends StatelessWidget {
  const TextMessageText({
    super.key,
    required this.text,
  });

  /// Text that is shown as markdown.
  final String text;

  @override
  Widget build(BuildContext context) {
    return FlowyText(
      text,
      lineHeight: 1.4,
      maxLines: null,
      color: AFThemeExtension.of(context).textColor,
    );
  }
}
