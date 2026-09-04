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

    // 【修复提问气泡空白 2026-07-30】此处原为
    //   stream is QuestionStream ? stream.text : message.text
    // 即只要 metadata 带 QuestionStream 就一律读 stream.text。
    //
    // 但 Rust 侧 question_sink 只发 StreamMessage::MessageId、**从不发文本**
    // （flowy-ai/src/chat.rs 中 `question_sink.send(MessageId(...))`），
    // QuestionStream._text 初始化为 "" 后再无填充来源，因此恒为空串。
    // 发送侧已把真实提问写入 message.text
    // （createAndInsertQuestionStreamMessage 的 text 入参），
    // 渲染侧却没同步改过来，导致用户的提问气泡渲染成一个空白框。
    //
    // 改为优先取 message.text，仅当它为空时才回退到 stream.text，
    // 这样即便日后 Rust 真的开始推送提问文本，也不会丢失。
    final streamText = stream is QuestionStream ? stream.text : '';
    final messageText = message.text.isNotEmpty ? message.text : streamText;

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
      return const [];
    }

    final imagesData = message.metadata!['images'];

    if (imagesData is List && imagesData.isNotEmpty) {
      Log.info('📸 UserTextMessage: 找到 ${imagesData.length} 张图片(base64)');
      return imagesData.cast<String>();
    }
    return const [];
  }

  /// 获取消息中的图片文件路径列表（备用方案）
  List<String> _getImagePaths() {
    if (message.metadata == null) {
      return const [];
    }

    final pathsData = message.metadata!['image_paths'];
    if (pathsData is List && pathsData.isNotEmpty) {
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
