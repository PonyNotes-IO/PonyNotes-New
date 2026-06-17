import 'dart:convert';
import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_content_page.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:universal_platform/universal_platform.dart';

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
    this.isInSpaceHub = false,
  });

  final ViewPB view;
  final VoidCallback onDeleted;
  final UserProfilePB userProfile;
  final bool isInSpaceHub;

  @override
  Widget build(BuildContext context) {
    // 从view.extra中读取初始消息、首选模型、深度思考和全网搜索开关、初始图片
    final viewExtra = view.extra;
    String? initialMessage;
    String? preferredModelId;
    bool enableDeepThinking = false;
    bool enableWebSearch = false;
    List<String>? initialImagePaths;
    
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
        
        // 读取初始图片路径列表
        if (extraData.containsKey('initial_images')) {
          final imagesList = extraData['initial_images'];
          if (imagesList is List) {
            initialImagePaths = imagesList.cast<String>();
            Log.info('✅ AIChatPage: 找到 ${initialImagePaths!.length} 张初始图片');
          }
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
              initialImagePaths: initialImagePaths,  // 传递图片路径
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
                child: BlocBuilder<HomeSettingBloc, HomeSettingState>(
                  buildWhen: (p, c) => p.menuStatus != c.menuStatus,
                  builder: (context, menuState) {
                    final isSidebarHidden = menuState.menuStatus == MenuStatus.hidden;
                    return Stack(
                      children: [
                        ChatContentPage(
                          view: view,
                          userProfile: userProfile,
                        ),
                        // 侧边栏收起时，在左上角显示展开按钮（不在 SpaceHub 中时显示）
                        if (isSidebarHidden && !isInSpaceHub)
                          Positioned(
                            top: 10,
                            left: UniversalPlatform.isMacOS ? 88 : 16,
                            child: FlowyTooltip(
                              message: LocaleKeys.sideBar_openSidebar.tr(),
                              child: FlowyIconButton(
                                width: 24,
                                icon: FlowySvg(
                                  FlowySvgs.sidebar_collapse_custom_m,
                                  size: const Size.square(24),
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                onPressed: () => context.read<HomeSettingBloc>().add(
                                  const HomeSettingEvent.changeMenuStatus(MenuStatus.expanded),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
