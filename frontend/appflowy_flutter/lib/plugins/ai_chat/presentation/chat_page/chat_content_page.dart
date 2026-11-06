import 'package:appflowy/plugins/ai_chat/application/ai_chat_prelude.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/load_chat_message_status_ready.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/features/agent/presentation/ai_mode_shell.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

class ChatContentPage extends StatelessWidget {
  const ChatContentPage({
    super.key,
    required this.view,
    required this.userProfile,
  });

  final UserProfilePB userProfile;
  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        return AiModeShell(
          key: ValueKey(view.id),
          chatId: view.id,
          chatBusy: !state.promptResponseState.isReady,
          chatContext: () => context
              .read<ChatBloc>()
              .chatController
              .messages
              .whereType<TextMessage>()
              .map(
                (message) =>
                    '${message.author.id == userProfile.id.toString() ? '用户' : 'AI'}：${message.text}',
              )
              .join('\n\n'),
          chat: switch (state.loadingState) {
            LoadChatMessageStatus.ready => LoadChatMessageStatusReady(
                view: view,
                userProfile: userProfile,
                chatController: context.read<ChatBloc>().chatController,
              ),
            _ => const Center(child: CircularProgressIndicator.adaptive()),
          },
        );
      },
    );
  }
}
