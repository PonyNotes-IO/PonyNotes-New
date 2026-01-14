import 'dart:convert';
import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_content_page.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/log.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'application/chat_bloc.dart';
import 'application/chat_member_bloc.dart';

// Intent for stopping AI stream
class _StopStreamIntent extends Intent {
  const _StopStreamIntent();
}

class AIChatPage extends StatelessWidget {
  const AIChatPage({
    super.key,
    required this.view,
    required this.onDeleted,
    required this.userProfile,
  });

  final ViewPB view;
  final VoidCallback onDeleted;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    // 从view.extra中读取初始消息、首选模型、深度思考和全网搜索开关
    final viewExtra = view.extra;
    String? initialMessage;
    String? preferredModelId;
    bool enableDeepThinking = false;
    bool enableWebSearch = false;
    
    if (viewExtra.isNotEmpty) {
      Log.info('🔍 AIChatPage: 解析view.extra...');
      Log.info('   - view.extra: $viewExtra');
      
      try {
        // view.extra可能是JSON字符串，尝试解析
        final extraData = json.decode(viewExtra) as Map<String, dynamic>;
        initialMessage = extraData['initial_message'] as String?;
        preferredModelId = extraData['preferred_model'] as String?;
        
        // 读取深度思考开关
        final enableDeepThinkingStr = extraData['enable_deep_thinking'] as String?;
        if (enableDeepThinkingStr == 'true') {
          enableDeepThinking = true;
        }
        
        // 读取全网搜索开关
        final enableWebSearchStr = extraData['enable_web_search'] as String?;
        if (enableWebSearchStr == 'true') {
          enableWebSearch = true;
        }
        
        if (initialMessage != null) {
          Log.info('✅ AIChatPage: 找到初始消息: $initialMessage');
        }
        if (preferredModelId != null) {
          Log.info('✅ AIChatPage: 找到首选模型: $preferredModelId');
        }
        if (enableDeepThinking) {
          Log.info('✅ AIChatPage: 深度思考模式已开启');
        }
        if (enableWebSearch) {
          Log.info('✅ AIChatPage: 全网搜索模式已开启');
        }
      } catch (e) {
        Log.warn('⚠️  AIChatPage: view.extra不是JSON格式，跳过解析: $e');
      }
    } else {
      Log.info('ℹ️  AIChatPage: view.extra为空');
    }
    
    return MultiBlocProvider(
      providers: [
        /// [ChatBloc] is used to handle chat messages including send/receive message
        BlocProvider(
          create: (_) {
            final bloc = ChatBloc(
              chatId: view.id,
              userId: userProfile.id.toString(),
              initialMessage: initialMessage,
              preferredModelId: preferredModelId,
              enableDeepThinking: enableDeepThinking,
              enableWebSearch: enableWebSearch,
            );
            // 异步获取 workspace ID 并刷新使用情况
            AIChatViewService.getCurrentWorkspaceId().then((workspaceId) {
              if (workspaceId != null) {
                bloc.add(ChatEvent.setWorkspaceId(workspaceId));
              }
            });
            return bloc;
          },
        ),

        /// [AIPromptInputBloc] is used to handle the user prompt
        BlocProvider(
          create: (_) => AIPromptInputBloc(
            objectId: view.id,
            predefinedFormat: PredefinedFormat(
              imageFormat: ImageFormat.text,
              textFormat: TextFormat.bulletList,
            ),
          ),
        ),
        BlocProvider(create: (_) => ChatMemberBloc()),
      ],
      child: Builder(
        builder: (context) {
          return DropTarget(
            onDragDone: (DropDoneDetails detail) async {
              if (context.read<AIPromptInputBloc>().state.supportChatWithFile) {
                for (final file in detail.files) {
                  context
                      .read<AIPromptInputBloc>()
                      .add(AIPromptInputEvent.attachFile(file.path, file.name));
                }
              }
            },
            child: Shortcuts(
              shortcuts: {
                // 定义快捷键，不影响普通输入
                const SingleActivator(LogicalKeyboardKey.escape): _StopStreamIntent(),
                const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  control: true,
                ): _StopStreamIntent(),
              },
              child: Actions(
                actions: {
                  _StopStreamIntent: CallbackAction<_StopStreamIntent>(
                    onInvoke: (intent) {
                      final chatBloc = context.read<ChatBloc>();
                      if (!chatBloc.state.promptResponseState.isReady) {
                        chatBloc.add(ChatEvent.stopStream());
                      }
                      return null;
                    },
                  ),
                },
                child: ChatContentPage(
                  view: view,
                  userProfile: userProfile,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
