import 'dart:convert';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/ai_chat/application/ai_chat_prelude.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/load_chat_message_status_ready.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Logo — blendMode=null 保留 SVG 原始颜色（白马+橙色底）
                    const FlowySvg(
                      FlowySvgs.pony_notes_logo_xl,
                      size: Size.square(48),
                      blendMode: null,
                    ),
                    const SizedBox(height: 16),
                    // Greeting
                    Text(
                      '有什么可以帮到你的吗，${_userProfile?.name ?? ""}？',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Sample questions
                    _buildSampleQuestions(context),
                  ],
                ),
              ),
            ),
            // Bottom input bar
            _MobileWelcomeInputBar(
              isSending: _isSending,
              onSend: _handleWelcomeInputSubmit,
              preferredModelId: _preferredModelId,
              enableDeepThinking: _enableDeepThinking,
              enableWebSearch: _enableWebSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSampleQuestions(BuildContext context) {
    final questions = [
      '帮我整理一下今天的待办事项',
      '用一句话概括这篇文章的主要内容',
      '解释一下什么是知识图谱',
      '给我推荐几个效率工具',
      '如何提高写作能力？',
      '帮我写一封商务邮件',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: questions.map((q) {
        return GestureDetector(
          onTap: () => _sendMessage(q),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).dividerColor,
              ),
            ),
            child: Text(
              q,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontSize: 13,
                  ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleWelcomeInputSubmit(String text, String? modelId, bool deepThinking, bool webSearch) {
    if (_isSending) return;
    if (text.trim().isEmpty) return;
    _sendMessage(text, modelId: modelId, enableDeepThinking: deepThinking, enableWebSearch: webSearch);
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

  Future<void> _sendMessage(
    String message, {
    String? modelId,
    bool? enableDeepThinking,
    bool? enableWebSearch,
  }) async {
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

      final effectiveModelId = modelId ?? _preferredModelId;
      final effectiveDeepThinking = enableDeepThinking ?? _enableDeepThinking;
      final effectiveWebSearch = enableWebSearch ?? _enableWebSearch;

      final view = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspaceId,
        initialMessage: message,
        selectedModelId: effectiveModelId,
        enableDeepThinking: effectiveDeepThinking,
        enableWebSearch: effectiveWebSearch,
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

/// 欢迎页底部的固定输入栏，包含模型选择、深度思考、联网搜索和发送按钮
class _MobileWelcomeInputBar extends StatefulWidget {
  const _MobileWelcomeInputBar({
    required this.isSending,
    required this.onSend,
    this.preferredModelId,
    this.enableDeepThinking = false,
    this.enableWebSearch = false,
  });

  final bool isSending;
  final void Function(String, String?, bool, bool) onSend;
  final String? preferredModelId;
  final bool enableDeepThinking;
  final bool enableWebSearch;

  @override
  State<_MobileWelcomeInputBar> createState() => _MobileWelcomeInputBarState();
}

class _MobileWelcomeInputBarState extends State<_MobileWelcomeInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  static const int _maxLength = 120;
  int _charCount = 0;

  // Model selection
  AIModel? _selectedModel;
  List<AIModel> _availableModels = [];
  bool _isModelLoading = true;
  bool _isDropdownOpen = false;
  OverlayEntry? _overlayEntry;
  final _selectorKey = GlobalKey();

  // Feature toggles
  bool _isDeepThinkingEnabled = false;
  bool _isWebSearchEnabled = false;

  // Attachment state
  bool _isAttachmentLoading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _isDeepThinkingEnabled = widget.enableDeepThinking;
    _isWebSearchEnabled = widget.enableWebSearch;
    _loadModels();
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.length > _maxLength) {
      _controller.value = TextEditingValue(
        text: text.substring(0, _maxLength),
        selection: TextSelection.collapsed(offset: _maxLength),
      );
    }
    setState(() => _charCount = _controller.text.length);
  }

  Future<void> _loadModels() async {
    try {
      final models = await AIModelService.instance.fetchAvailableModels();
      if (mounted) {
        setState(() {
          _availableModels = models;
          _selectedModel = models.firstWhere(
            (m) => m.id == widget.preferredModelId,
            orElse: () => models.firstWhere(
              (m) => m.isDefault,
              orElse: () => models.isNotEmpty ? models.first : _fallbackModel(),
            ),
          );
          _isModelLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availableModels = [_fallbackModel()];
          _selectedModel = _availableModels.first;
          _isModelLoading = false;
        });
      }
    }
  }

  AIModel _fallbackModel() => AIModel(
        id: 'deepseek-chat',
        name: 'DeepSeek',
        description: '',
        isDefault: true,
        supportsImages: false,
      );

  @override
  void dispose() {
    _overlayEntry?.remove();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _charCount = 0);
    widget.onSend(
      text,
      _selectedModel?.id,
      _isDeepThinkingEnabled,
      _isWebSearchEnabled,
    );
  }

  void _toggleDropdown() {
    if (_isDropdownOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (_availableModels.isEmpty) return;
    setState(() => _isDropdownOpen = true);

    final box = _selectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 4,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 180,
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(ctx).dividerColor),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _availableModels.asMap().entries.map((entry) {
                  final model = entry.value;
                  final isSelected = _selectedModel?.id == model.id;
                  return InkWell(
                    onTap: () => _selectModel(model),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      color: isSelected
                          ? Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : null,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              model.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Theme.of(ctx).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (model.supportsImages)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '多模态',
                                style: TextStyle(fontSize: 9, color: Colors.green),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeDropdown() {
    setState(() => _isDropdownOpen = false);
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectModel(AIModel model) {
    setState(() => _selectedModel = model);
    _closeDropdown();
  }

  // --- Feature buttons ---

  Widget _modelButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFB0B0B0) : const Color(0xFF636363);
    final borderColor = isDark ? const Color(0xFF4A4A4A) : const Color(0xFFCDCDCD);
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return GestureDetector(
      key: _selectorKey,
      onTap: _toggleDropdown,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isModelLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator.adaptive(strokeWidth: 1.5),
              )
            else
              Icon(Icons.auto_awesome, size: 11, color: textColor),
            const SizedBox(width: 3),
            Text(
              _selectedModel?.name ?? '选择模型',
              style: TextStyle(fontSize: 11, color: textColor),
            ),
            Icon(
              _isDropdownOpen ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: textColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = const Color(0xFFE94618);
    final textColor = isEnabled
        ? activeColor
        : (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF636363));
    final borderColor = isEnabled
        ? activeColor
        : (isDark ? const Color(0xFF4A4A4A) : const Color(0xFFCDCDCD));
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: textColor),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, color: textColor)),
          ],
        ),
      ),
    );
  }

  /// AI 使用次数提示（对标桌面端 _buildCountAndRemainingIndicator）
  Widget _buildUsageIndicator(BuildContext context) {
    return FutureBuilder<FlowyResult<WorkspaceUsagePB?, FlowyError>>(
      future: _loadUsage(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        return snapshot.data!.fold(
          (usage) {
            if (usage == null) return const SizedBox.shrink();
            if (usage.aiResponsesUnlimited) return const SizedBox.shrink();

            final used = usage.aiResponsesCount.toInt();
            final total = usage.aiResponsesCountLimit.toInt();
            if (total == -1) {
              return _usagePill(context, '未订阅', Colors.red);
            }
            final remaining = total - used;
            final color = remaining <= 0
                ? Colors.red
                : Theme.of(context).hintColor;
            return _usagePill(context, '$remaining 次可用', color);
          },
          (_) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _usagePill(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }

  Future<FlowyResult<WorkspaceUsagePB?, FlowyError>> _loadUsage() async {
    try {
      final workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      if (workspaceId == null) return FlowyResult.success(null);

      final service = WorkspaceService(
        workspaceId: workspaceId,
        userId: fixnum.Int64.ZERO,
      );
      return service.getWorkspaceUsage();
    } catch (_) {
      return FlowyResult.failure(FlowyError(msg: ''));
    }
  }

  /// 附件上传按钮（对标桌面端 _buildAttachmentButton）
  Widget _buildAttachmentButton(BuildContext context) {
    final isDisabled = _isDeepThinkingEnabled || _isWebSearchEnabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDisabled
        ? (isDark ? const Color(0xFF666666) : const Color(0xFFB0B0B0))
        : (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF636363));

    return GestureDetector(
      onTap: isDisabled || _isAttachmentLoading ? null : _pickAttachment,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: _isAttachmentLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 1.5),
                )
              : Icon(
                  Icons.add_circle_outline,
                  size: 18,
                  color: iconColor,
                ),
        ),
      ),
    );
  }

  Future<void> _pickAttachment() async {
    setState(() => _isAttachmentLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'txt'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      // TODO: 显示附件预览并支持发送（与桌面端附件系统对接）
      Log.debug('[MobileAI] 选择了 ${result.files.length} 个附件');
    } catch (e) {
      Log.debug('[MobileAI] 附件选择失败: $e');
    } finally {
      if (mounted) setState(() => _isAttachmentLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: () {
        if (_isDropdownOpen) _closeDropdown();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toolbar row — 窄屏用 ScrollView 防止溢出
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 24,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _modelButton(context),
                      const SizedBox(width: 6),
                      _featureButton(
                        context: context,
                        label: '深度思考',
                        icon: Icons.psychology,
                        isEnabled: _isDeepThinkingEnabled,
                        onTap: () =>
                            setState(() => _isDeepThinkingEnabled = !_isDeepThinkingEnabled),
                      ),
                      const SizedBox(width: 6),
                      _featureButton(
                        context: context,
                        label: '联网搜索',
                        icon: Icons.language,
                        isEnabled: _isWebSearchEnabled,
                        onTap: () =>
                            setState(() => _isWebSearchEnabled = !_isWebSearchEnabled),
                      ),
                      const SizedBox(width: 6),
                      _buildAttachmentButton(context),
                      const SizedBox(width: 6),
                      _buildUsageIndicator(context),
                      const SizedBox(width: 6),
                      Text(
                        '$_charCount/$_maxLength',
                        style: TextStyle(
                          fontSize: 11,
                          color: _charCount >= _maxLength
                              ? Colors.red
                              : Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Input + send row
            Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 6,
                bottom: bottomPadding + 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '问小马AI...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 15,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.isSending || _charCount == 0 ? null : _submit,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.isSending
                            ? Theme.of(context).disabledColor
                            : (_charCount > 0
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.surfaceContainerHighest),
                        shape: BoxShape.circle,
                        border: _charCount == 0
                            ? Border.all(
                                color: Theme.of(context).dividerColor,
                                width: 1,
                              )
                            : null,
                      ),
                      child: widget.isSending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: _charCount > 0
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
