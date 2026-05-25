import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_ai_message_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_height_manager.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:appflowy/plugins/ai_chat/presentation/widgets/message_height_calculator.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../layout_define.dart';
import 'ai_markdown_text.dart';
import 'ai_message_bubble.dart';
import 'ai_metadata.dart';
import 'error_text_message.dart';

/// [ChatAIMessageWidget] includes both the text of the AI response as well as
/// the avatar, decorations and hover effects that are also rendered. This is
/// different from [ChatUserMessageWidget] which only contains the message and
/// has to be separately wrapped with a bubble since the hover effects need to
/// know the current streaming status of the message.
class ChatAIMessageWidget extends StatelessWidget {
  const ChatAIMessageWidget({
    super.key,
    required this.user,
    required this.messageUserId,
    required this.message,
    required this.stream,
    required this.questionId,
    required this.chatId,
    required this.refSourceJsonString,
    required this.onStopStream,
    this.onSelectedMetadata,
    this.onRegenerate,
    this.onChangeFormat,
    this.onChangeModel,
    this.isLastMessage = false,
    this.isStreaming = false,
    this.isSelectingMessages = false,
    this.enableAnimation = true,
    this.hasRelatedQuestions = false,
  });

  final User user;
  final String messageUserId;

  final Message message;
  final AnswerStream? stream;
  final Int64? questionId;
  final String chatId;
  final String? refSourceJsonString;
  final void Function(ChatMessageRefSource metadata)? onSelectedMetadata;
  final void Function()? onRegenerate;
  final void Function() onStopStream;
  final void Function(PredefinedFormat)? onChangeFormat;
  final void Function(AIModelPB)? onChangeModel;
  final bool isStreaming;
  final bool isLastMessage;
  final bool isSelectingMessages;
  final bool enableAnimation;
  final bool hasRelatedQuestions;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatAIMessageBloc(
        message: stream ?? (message as TextMessage).text,
        refSourceJsonString: refSourceJsonString,
        chatId: chatId,
        questionId: questionId,
        originalMessage: stream == null ? message : null,
      ),
      child: BlocConsumer<ChatAIMessageBloc, ChatAIMessageState>(
        listenWhen: (previous, current) =>
            previous.messageState != current.messageState,
        listener: (context, state) => _handleMessageState(state, context),
        builder: (context, blocState) {
          final loadingText = blocState.progress?.step ??
              LocaleKeys.chat_generatingResponse.tr();

          // Calculate minimum height only for the last AI answer message
          double minHeight = 0;
          if (isLastMessage && !hasRelatedQuestions) {
            final screenHeight = MediaQuery.of(context).size.height;
            minHeight = ChatMessageHeightManager().calculateMinHeight(
              messageId: message.id,
              screenHeight: screenHeight,
            );
          }

          return Container(
            alignment: Alignment.topLeft,
            constraints: BoxConstraints(
              minHeight: minHeight,
            ),
            padding: AIChatUILayout.messageMargin,
            child: MessageHeightCalculator(
              messageId: message.id,
              onHeightMeasured: (messageId, height) {
                ChatMessageHeightManager().cacheWithoutMinHeight(
                  messageId: messageId,
                  height: height,
                );
              },
              child: blocState.messageState.when(
                loading: () => ChatAIMessageBubble(
                  message: message,
                  showActions: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: AILoadingIndicator(text: loadingText),
                  ),
                ),
                ready: () {
                  // 正文为空但有思考内容时（深度思考流式阶段），也显示消息气泡
                  return (blocState.text.isEmpty && blocState.thinkingText.isEmpty)
                      ? _LoadingMessage(
                          message: message,
                          loadingText: loadingText,
                        )
                      : _NonEmptyMessage(
                          user: user,
                          messageUserId: messageUserId,
                          message: message,
                          stream: stream,
                          questionId: questionId,
                          chatId: chatId,
                          refSourceJsonString: refSourceJsonString,
                          onStopStream: onStopStream,
                          onSelectedMetadata: onSelectedMetadata,
                          onRegenerate: onRegenerate,
                          onChangeFormat: onChangeFormat,
                          onChangeModel: onChangeModel,
                          isLastMessage: isLastMessage,
                          isStreaming: isStreaming,
                          isSelectingMessages: isSelectingMessages,
                          enableAnimation: enableAnimation,
                        );
                },
                onError: (error) {
                  return ChatErrorMessageWidget(
                    errorMessage: LocaleKeys.chat_aiServerUnavailable.tr(),
                  );
                },
                onAIResponseLimit: () {
                  return ChatErrorMessageWidget(
                    errorMessage:
                        LocaleKeys.sideBar_askOwnerToUpgradeToAIMax.tr(),
                  );
                },
                onAIImageResponseLimit: () {
                  return ChatErrorMessageWidget(
                    errorMessage: LocaleKeys.sideBar_purchaseAIMax.tr(),
                  );
                },
                onAIMaxRequired: (message) {
                  return ChatErrorMessageWidget(
                    errorMessage: message,
                  );
                },
                onInitializingLocalAI: () {
                  onStopStream();

                  return ChatErrorMessageWidget(
                    errorMessage: LocaleKeys
                        .settings_aiPage_keys_localAIInitializing
                        .tr(),
                  );
                },
                aiFollowUp: (followUpData) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleMessageState(ChatAIMessageState state, BuildContext context) {
    if (state.stream?.error?.isEmpty != false) {
      state.messageState.maybeMap(
        aiFollowUp: (messageState) {
          context
              .read<ChatBloc>()
              .add(ChatEvent.onAIFollowUp(messageState.followUpData));
        },
        orElse: () {
          // do nothing
        },
      );

      return;
    }
    context.read<ChatBloc>().add(ChatEvent.deleteMessage(message));
  }
}

class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage({
    required this.message,
    required this.loadingText,
  });

  final Message message;
  final String loadingText;

  @override
  Widget build(BuildContext context) {
    return ChatAIMessageBubble(
      message: message,
      showActions: false,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: 4.0, top: 8.0),
        child: AILoadingIndicator(text: loadingText),
      ),
    );
  }
}

class _NonEmptyMessage extends StatefulWidget {
  const _NonEmptyMessage({
    required this.user,
    required this.messageUserId,
    required this.message,
    required this.stream,
    required this.questionId,
    required this.chatId,
    required this.refSourceJsonString,
    required this.onStopStream,
    this.onSelectedMetadata,
    this.onRegenerate,
    this.onChangeFormat,
    this.onChangeModel,
    this.isLastMessage = false,
    this.isStreaming = false,
    this.isSelectingMessages = false,
    this.enableAnimation = true,
  });

  final User user;
  final String messageUserId;

  final Message message;
  final AnswerStream? stream;
  final Int64? questionId;
  final String chatId;
  final String? refSourceJsonString;
  final ValueChanged<ChatMessageRefSource>? onSelectedMetadata;
  final VoidCallback? onRegenerate;
  final VoidCallback onStopStream;
  final ValueChanged<PredefinedFormat>? onChangeFormat;
  final ValueChanged<AIModelPB>? onChangeModel;
  final bool isStreaming;
  final bool isLastMessage;
  final bool isSelectingMessages;
  final bool enableAnimation;

  @override
  State<_NonEmptyMessage> createState() => _NonEmptyMessageState();
}

class _NonEmptyMessageState extends State<_NonEmptyMessage> {
  bool _thinkingExpanded = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatAIMessageBloc, ChatAIMessageState>(
      builder: (context, state) {
        final showActions =
            widget.stream == null && state.text.isNotEmpty && !widget.isStreaming;
        return ChatAIMessageBubble(
          message: widget.message,
          isLastMessage: widget.isLastMessage,
          showActions: showActions,
          isSelectingMessages: widget.isSelectingMessages,
          onRegenerate: widget.onRegenerate,
          onChangeFormat: widget.onChangeFormat,
          onChangeModel: widget.onChangeModel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.thinkingText.isNotEmpty)
                _ThinkingSection(
                  thinkingText: state.thinkingText,
                  isExpanded: _thinkingExpanded,
                  isStreaming: widget.isStreaming,
                  onToggle: () =>
                      setState(() => _thinkingExpanded = !_thinkingExpanded),
                ),
              Padding(
                padding: EdgeInsetsDirectional.only(start: 4.0),
                child: AIMarkdownText(
                  markdown: state.text,
                  withAnimation: widget.enableAnimation && widget.stream != null,
                ),
              ),
              if (state.sources.isNotEmpty)
                SelectionContainer.disabled(
                  child: AIMessageMetadata(
                    sources: state.sources,
                    onSelectedMetadata: widget.onSelectedMetadata,
                  ),
                ),
              if (state.sources.isNotEmpty && !widget.isLastMessage)
                const VSpace(8.0),
            ],
          ),
        );
      },
    );
  }
}

class _ThinkingSection extends StatelessWidget {
  const _ThinkingSection({
    required this.thinkingText,
    required this.isExpanded,
    required this.isStreaming,
    required this.onToggle,
  });

  final String thinkingText;
  final bool isExpanded;
  final bool isStreaming;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.02);
    final labelColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: labelColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isStreaming && isExpanded ? '思考中...' : '思考过程',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: labelColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4.0),
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectionArea(
                child: Text(
                  thinkingText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
