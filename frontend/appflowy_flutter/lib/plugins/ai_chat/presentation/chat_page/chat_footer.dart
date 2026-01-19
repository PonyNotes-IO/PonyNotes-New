import 'package:appflowy/ai/ai.dart';
// PonyNotes: 添加AIPromptInputBloc导入以获取深度思考和联网搜索状态
import 'package:appflowy/ai/service/ai_prompt_input_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/ai_chat_prelude.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_bloc.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_input/mobile_chat_input.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/ai_chat_usage_indicator.dart';
import 'package:appflowy/plugins/ai_chat/presentation/layout_define.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

class ChatFooter extends StatefulWidget {
  const ChatFooter({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<ChatFooter> createState() => _ChatFooterState();
}

class _ChatFooterState extends State<ChatFooter> {
  final textController = AiPromptInputTextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChatSelectMessageBloc, ChatSelectMessageState, bool>(
      selector: (state) => state.isSelectingMessages,
      builder: (context, isSelectingMessages) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) {
            return NonClippingSizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            );
          },
          child: isSelectingMessages
              ? const SizedBox.shrink()
              : Padding(
                  padding: AIChatUILayout.safeAreaInsets(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BlocSelector<ChatBloc, ChatState, bool>(
                        selector: (state) {
                          return state.promptResponseState.isReady;
                        },
                        builder: (context, canSendMessage) {
                          final chatBloc = context.read<ChatBloc>();

                          return UniversalPlatform.isDesktop
                              ? _buildDesktopInput(
                                  context,
                                  chatBloc,
                                  canSendMessage,
                                )
                              : _buildMobileInput(
                                  context,
                                  chatBloc,
                                  canSendMessage,
                                );
                        },
                      ),
                      // PonyNotes: 移除重复的使用次数显示，因为输入框内已经有了
                      // BlocSelector<ChatBloc, ChatState, WorkspaceUsagePB?>(
                      //   selector: (state) => state.usageInfo,
                      //   builder: (context, usage) {
                      //     return AIChatUsageIndicator(usage: usage);
                      //   },
                      // ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildDesktopInput(
    BuildContext context,
    ChatBloc chatBloc,
    bool canSendMessage,
  ) {
    return DesktopPromptInput(
      isStreaming: !canSendMessage,
      textController: textController,
      // PonyNotes: 在桌面 AI 对话中不展示输入框上方的预设格式按钮行
      hideFormats: true,
      onStopStreaming: () {
        chatBloc.add(const ChatEvent.stopStream());
      },
      onSubmitted: (text, format, metadata, promptId) {
        // PonyNotes: 获取深度思考和联网搜索状态
        final promptInputBloc = context.read<AIPromptInputBloc?>();
        final enableDeepThinking = promptInputBloc?.state.enableDeepThinking;
        final enableWebSearch = promptInputBloc?.state.enableWebSearch;
        
        chatBloc.add(
          ChatEvent.sendMessage(
            message: text,
            format: format,
            metadata: metadata,
            promptId: promptId,
            // PonyNotes: 传递深度思考和联网搜索状态
            enableDeepThinking: enableDeepThinking,
            enableWebSearch: enableWebSearch,
          ),
        );
      },
      selectedSourcesNotifier: chatBloc.selectedSourcesNotifier,
      onUpdateSelectedSources: (ids) {
        chatBloc.add(
          ChatEvent.updateSelectedSources(
            selectedSourcesIds: ids,
          ),
        );
      },
    );
  }

  Widget _buildMobileInput(
    BuildContext context,
    ChatBloc chatBloc,
    bool canSendMessage,
  ) {
    return MobileChatInput(
      isStreaming: !canSendMessage,
      onStopStreaming: () {
        chatBloc.add(const ChatEvent.stopStream());
      },
      onSubmitted: (text, format, metadata) {
        chatBloc.add(
          ChatEvent.sendMessage(
            message: text,
            format: format,
            metadata: metadata,
          ),
        );
      },
      selectedSourcesNotifier: chatBloc.selectedSourcesNotifier,
      onUpdateSelectedSources: (ids) {
        chatBloc.add(
          ChatEvent.updateSelectedSources(
            selectedSourcesIds: ids,
          ),
        );
      },
    );
  }
}
