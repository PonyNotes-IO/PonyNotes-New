import 'dart:convert';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/ai_chat/application/ai_chat_prelude.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_animation_list_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_footer.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/load_chat_message_status_ready.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_welcome_page.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:go_router/go_router.dart';

class MobileChatScreen extends StatefulWidget {
  const MobileChatScreen({
    super.key,
    this.id,
    this.title,
    this.extra,
  });

  /// view id, null when entering from bottom nav (will create chat on first message)
  final String? id;
  final String? title;
  /// view.extra, for passing initial message, model, etc.
  final String? extra;

  static const routeName = '/chat';
  static const viewId = 'id';
  static const viewTitle = 'title';

  @override
  State<MobileChatScreen> createState() => _MobileChatScreenState();
}

class _MobileChatScreenState extends State<MobileChatScreen> {
  ChatBloc? _chatBloc;
  AIPromptInputBloc? _promptInputBloc;

  // Parsed from extra
  String? _initialMessage;
  String? _preferredModelId;
  bool _enableDeepThinking = false;
  bool _enableWebSearch = false;

  UserProfilePB? _userProfile;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _parseExtra();
    _initBlocs();
  }

  void _parseExtra() {
    if (widget.extra == null || widget.extra!.isEmpty) return;
    try {
      final data = json.decode(widget.extra!) as Map<String, dynamic>;
      _initialMessage = data['initial_message'] as String?;
      _preferredModelId = data['preferred_model'] as String?;
      _enableDeepThinking = data['enable_deep_thinking'] == 'true';
      _enableWebSearch = data['enable_web_search'] == 'true';
    } catch (_) {}
  }

  Future<void> _initBlocs() async {
    final profileResult = await UserBackendService.getCurrentUserProfile();
    _userProfile = profileResult.fold((p) => p, (_) => null);

    if (widget.id != null) {
      _chatBloc = ChatBloc(
        chatId: widget.id!,
        userId: _userProfile?.id.toString() ?? '',
        initialMessage: _initialMessage,
        preferredModelId: _preferredModelId,
        enableDeepThinking: _enableDeepThinking,
        enableWebSearch: _enableWebSearch,
      );
      _promptInputBloc = AIPromptInputBloc(
        objectId: widget.id!,
        predefinedFormat: PredefinedFormat(
          imageFormat: ImageFormat.text,
          textFormat: TextFormat.bulletList,
        ),
      );
      AIChatViewService.getCurrentWorkspaceId().then((workspaceId) {
        if (workspaceId != null && !_chatBloc!.isClosed) {
          _chatBloc!.add(ChatEvent.setWorkspaceId(workspaceId));
        }
      });
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _chatBloc?.close();
    _promptInputBloc?.close();
    super.dispose();
  }

  bool get _hasChat => widget.id != null && _chatBloc != null;

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _userProfile == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              const Expanded(
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasChat) {
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _chatBloc!),
          BlocProvider.value(value: _promptInputBloc!),
        ],
        child: BlocBuilder<ChatBloc, ChatState>(
          builder: (context, chatState) {
            if (_chatBloc!.chatController.messages.isNotEmpty) {
              return _buildChatLayout(context);
            }
            if (chatState.loadingState is LoadChatMessageStatusReady) {
              return _buildWelcomeLayout(context);
            }
            return const Center(child: CircularProgressIndicator.adaptive());
          },
        ),
      );
    }

    return _buildWelcomeLayout(context);
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const FlowySvg(FlowySvgs.mobile_return_s),
          ),
          Expanded(
            child: Text(
              widget.title ?? '小马笔记AI',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildWelcomeLayout(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ChatWelcomePage(
                userProfile: _userProfile!,
                onSelectedQuestion: (question) {
                  if (_isSending) return;
                  _sendMessage(question);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatLayout(BuildContext context) {
    final view = ViewPB.create()..id = widget.id!;

    return Scaffold(
      body: SafeArea(
        child: LoadChatMessageStatusReady(
          view: view,
          userProfile: _userProfile!,
          chatController: _chatBloc!.chatController,
        ),
      ),
    );
  }

  Future<void> _sendMessage(String message) async {
    if (_isSending) return;
    if (message.trim().isEmpty) return;

    setState(() => _isSending = true);

    try {
      final workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      if (workspaceId == null) {
        _showError('无法获取工作空间信息');
        setState(() => _isSending = false);
        return;
      }

      final view = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspaceId,
        initialMessage: message,
        selectedModelId: _preferredModelId,
        enableDeepThinking: _enableDeepThinking,
        enableWebSearch: _enableWebSearch,
      );

      if (view == null) {
        _showError('创建AI对话失败');
        setState(() => _isSending = false);
        return;
      }

      if (mounted) {
        context.push(
          '${MobileChatScreen.routeName}'
          '?${MobileChatScreen.viewId}=${view.id}'
          '&${MobileChatScreen.viewTitle}=${Uri.encodeComponent(view.name)}',
        );
      }
    } catch (e) {
      Log.error('[MobileAI] 发送消息失败: $e');
      _showError('发送消息失败');
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }
}
