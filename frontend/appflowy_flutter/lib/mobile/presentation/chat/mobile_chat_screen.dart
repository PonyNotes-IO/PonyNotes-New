import 'dart:convert';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/base/mobile_view_page.dart';
import 'package:appflowy/mobile/presentation/chat/mobile_chat_history_screen.dart';
import 'package:appflowy/mobile/presentation/mobile_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_bloc/flutter_bloc.dart';
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
  // Parsed from extra — only used in the welcome (no-id) path
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
    _loadProfile();
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

  Future<void> _loadProfile() async {
    final profileResult = await UserBackendService.getCurrentUserProfile();
    _userProfile = profileResult.fold((p) => p, (_) => null);
    if (mounted) setState(() => _isLoading = false);
  }

  bool get _hasChat => widget.id != null;

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
      // Use MobileViewPage to render the chat view — it provides every
      // dependency (ChatBloc, ViewBloc, UserWorkspaceBloc, …) via the
      // shared AIChatPagePlugin → AIChatPage → ChatContentPage chain,
      // and parses initial_message from view.extra automatically.
      // The AI chat plugin does not render its own mobile top bar, so
      // wrap with a Scaffold + MobileAppBar to get the standard mobile
      // back button + title chrome (matching Document/Database screens).
      return Scaffold(
        appBar: MobileAppBar(
          title:
              widget.title ?? LocaleKeys.menuAppHeader_defaultNewChatName.tr(),
          showBackButton: true,
          onBackPressed: () {
            // Prefer GoRouter pop (handles stack correctly when this
            // route was pushed via context.push). Fall back to root
            // when the route was reached via context.go (replace).
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        body: Column(
          children: [
            Expanded(
              child: MobileViewPage(
                key: ValueKey('mobile_chat_${widget.id}'),
                id: widget.id!,
                title: widget.title,
                viewLayout: ViewLayoutPB.Chat,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 10,
              ),
              child: _buildRemainingUsageHint(context),
            ),
          ],
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
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(BottomNavigationBarItemType.home.routeName!);
              }
            },
            icon: const FlowySvg(FlowySvgs.mobile_return_s),
          ),
          Expanded(
            child: Text(
              widget.title ?? '小马笔记AI',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: () => context.push(MobileChatHistoryScreen.routeName),
            icon: const FlowySvg(
              FlowySvgs.m_settings_more_s,
            ),
          ),
          const HSpace(8.0),
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
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo — PNG 图片
                        Image.asset(
                          'assets/images/ai_avatar.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                        const SizedBox(height: 16),
                        // Greeting
                        Text(
                          '我是小马笔记AI，很高兴见到你！',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: 17,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        // Subtitle
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '我可以帮你写代码、写作各种创意内容，请把你的任务交给我吧～',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .hintColor
                                          .withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
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
            // AI 剩余次数提示（输入框卡片下方，水平居中，底部额外安全距离）
            Padding(
              padding: EdgeInsets.only(
                top: 4,
                bottom: MediaQuery.of(context).padding.bottom + 10,
              ),
              child: _buildRemainingUsageHint(context),
            ),
          ],
        ),
      ),
    );
  }

  void _handleWelcomeInputSubmit(
      String text, String? modelId, bool deepThinking, bool webSearch) {
    if (_isSending) return;
    if (text.trim().isEmpty) return;
    _sendMessage(text,
        modelId: modelId,
        enableDeepThinking: deepThinking,
        enableWebSearch: webSearch);
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
        context.pushReplacement(
          '${MobileChatScreen.routeName}'
          '?${MobileChatScreen.viewId}=${view.id}'
          '&${MobileChatScreen.viewTitle}=${Uri.encodeComponent(view.name)}',
        );
      }
    } catch (e) {
      Log.error('[MobileAI] 发送消息失败: $e');
      _showError('发送消息失败');
    } finally {
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

  /// AI 剩余次数提示（输入框卡片下方，水平垂直居中，浅色小字）
  Widget _buildRemainingUsageHint(BuildContext context) {
    return FutureBuilder<FlowyResult<WorkspaceUsagePB?, FlowyError>>(
      future: _loadWorkspaceUsage(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        return snapshot.data!.fold(
          (usage) {
            if (usage == null) return const SizedBox.shrink();
            if (usage.aiResponsesUnlimited) return const SizedBox.shrink();

            final used = usage.aiResponsesCount.toInt();
            final total = usage.aiResponsesCountLimit.toInt();
            if (total == -1) {
              return Center(
                child: Text(
                  '未订阅',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.withValues(alpha: 0.7),
                  ),
                ),
              );
            }
            final remaining = total - used;
            final color = remaining <= 0
                ? Colors.red.withValues(alpha: 0.7)
                : Theme.of(context).hintColor;
            return Center(
              child: Text(
                '$remaining 次可用',
                style: TextStyle(fontSize: 11, color: color),
              ),
            );
          },
          (_) => const SizedBox.shrink(),
        );
      },
    );
  }

  Future<FlowyResult<WorkspaceUsagePB?, FlowyError>>
      _loadWorkspaceUsage() async {
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

  void _openModelPicker() {
    if (_availableModels.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '选择模型',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _availableModels.map((model) {
                    final isSelected = _selectedModel?.id == model.id;
                    return InkWell(
                      onTap: () {
                        setState(() => _selectedModel = model);
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        color: isSelected
                            ? Theme.of(ctx)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3)
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(ctx).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (model.supportsImages)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '多模态',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Feature buttons ---

  Widget _modelButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFB0B0B0) : const Color(0xFF636363);
    final borderColor =
        isDark ? const Color(0xFF4A4A4A) : const Color(0xFFCDCDCD);
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return GestureDetector(
      key: _selectorKey,
      onTap: _openModelPicker,
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
              Text(
                _selectedModel?.name ?? '选择模型',
                style: TextStyle(fontSize: 11, color: textColor),
              ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more,
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
            Text(label, style: TextStyle(fontSize: 11, color: textColor)),
          ],
        ),
      ),
    );
  }

  /// 附件上传按钮（对标桌面端 _buildAttachmentButton）
  Widget _buildAttachmentButton(BuildContext context) {
    final isDisabled = _isDeepThinkingEnabled || _isWebSearchEnabled;
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isDisabled
        ? colorScheme.onSurface.withValues(alpha: 0.3)
        : colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: isDisabled || _isAttachmentLoading ? null : _pickAttachment,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: _isAttachmentLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 1.5),
                )
              : FlowySvg(
                  FlowySvgs.m_ai_attachment_m,
                  size: const Size.square(24),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return GestureDetector(
      onTap: () {
        // 关闭输入法等行为（如有需要）
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 8,
          bottom: bottomPadding + 8,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Input row — 自填浅色、自圆角，不带外边框
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 8,
                minLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                // 小图：亮色模式输入区与卡片同底，不填充；暗色模式保留深灰输入壳
                decoration: InputDecoration(
                  hintText: '在小马笔记可以问或找到每一件事...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 13,
                  ),
                  filled: false,
                  fillColor: null,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              // Toolbar row: 模型 / 深度思考 / 联网搜索 / 附件 / 发送
              SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _modelButton(context),
                          const SizedBox(width: 3),
                          _featureButton(
                            context: context,
                            label: '深度思考',
                            icon: Icons.psychology,
                            isEnabled: _isDeepThinkingEnabled,
                            onTap: () => setState(
                              () => _isDeepThinkingEnabled =
                                  !_isDeepThinkingEnabled,
                            ),
                          ),
                          const SizedBox(width: 3),
                          _featureButton(
                            context: context,
                            label: '联网搜索',
                            icon: Icons.language,
                            isEnabled: _isWebSearchEnabled,
                            onTap: () => setState(
                              () => _isWebSearchEnabled = !_isWebSearchEnabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildAttachmentButton(context),
                    _buildSendButton(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送按钮
  Widget _buildSendButton(BuildContext context) {
    final isSending = widget.isSending;
    return GestureDetector(
      onTap: isSending ? null : _submit,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: isSending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                  ),
                )
              : const FlowySvg(
                  FlowySvgs.m_ai_send_m,
                  size: Size.square(24),
                  blendMode: null,
                ),
        ),
      ),
    );
  }
}
