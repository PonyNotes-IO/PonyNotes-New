import 'package:appflowy/plugins/ai_chat/presentation/chat_message_selector_banner.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_animation_list_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_footer.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_message_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/text_message_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/scroll_to_bottom.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' hide ChatMessage;
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

class LoadChatMessageStatusReady extends StatelessWidget {
  const LoadChatMessageStatusReady({
    super.key,
    required this.view,
    required this.userProfile,
    required this.chatController,
  });

  final ViewPB view;
  final UserProfilePB userProfile;
  final ChatController chatController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Chat header, banner
        _buildHeader(context),
        // Chat body, a list of messages
        _buildBody(context),
        // Chat footer, a text input field with toolbar, send button, etc.
        _buildFooter(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ChatMessageSelectorBanner(
      view: view,
      allMessages: chatController.messages,
    );
  }

  Widget _buildBody(BuildContext context) {
    final bool enableAnimation = true;
    return Expanded(
      child: Align(
        alignment: Alignment.topCenter,
        child: _wrapConstraints(
          // 顶部 padding：避开 tab 栏下方的右侧工具栏行（HomeSizes.tabBarHeight），
          // 防止首条消息被右上角按钮遮挡。仅作用于聊天页，不影响其他页面。
          Padding(
            padding: const EdgeInsets.only(
              top: HomeSizes.tabBarHeight + 12.0,
            ),
            child: SelectionArea(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                ),
                child: Chat(
                  chatController: chatController,
                  user: User(id: userProfile.id.toString()),
                  darkTheme: ChatTheme.fromThemeData(Theme.of(context)),
                  theme: ChatTheme.fromThemeData(Theme.of(context)),
                  builders: Builders(
                    // we have a custom input builder, so we don't need the default one
                    inputBuilder: (_) => const SizedBox.shrink(),
                    textMessageBuilder: (
                      context,
                      message,
                    ) =>
                        TextMessageWidget(
                      message: message,
                      userProfile: userProfile,
                      view: view,
                      enableAnimation: enableAnimation,
                    ),
                    chatMessageBuilder: (
                      context,
                      message,
                      animation,
                      child,
                    ) =>
                        ChatMessage(
                      message: message,
                      padding: const EdgeInsets.symmetric(vertical: 18.0),
                      child: child,
                    ),
                    scrollToBottomBuilder: (
                      context,
                      animation,
                      onPressed,
                    ) =>
                        CustomScrollToBottom(
                      animation: animation,
                      onPressed: onPressed,
                    ),
                    chatAnimatedListBuilder: (
                      context,
                      scrollController,
                      itemBuilder,
                    ) =>
                        ChatAnimationListWidget(
                      userProfile: userProfile,
                      scrollController: scrollController,
                      itemBuilder: itemBuilder,
                      enableReversedList: !enableAnimation,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return _wrapConstraints(
      ChatFooter(view: view),
    );
  }

  Widget _wrapConstraints(Widget child) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 784),
      margin: PlatformInfo.isDesktopOrTablet
          ? const EdgeInsets.symmetric(horizontal: 60.0)
          : null,
      child: child,
    );
  }
}
