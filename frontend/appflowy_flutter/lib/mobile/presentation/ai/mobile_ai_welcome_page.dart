import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/chat/mobile_chat_screen.dart';
import 'package:appflowy/mobile/presentation/home/mobile_home_page.dart';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MobileAIWelcomePage extends StatefulWidget {
  const MobileAIWelcomePage({super.key});

  static const routeName = '/ai';

  @override
  State<MobileAIWelcomePage> createState() => _MobileAIWelcomePageState();
}

class _MobileAIWelcomePageState extends State<MobileAIWelcomePage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  AIModel? _selectedModel;
  List<AIModel> _availableModels = [];
  bool _isLoadingModels = true;
  bool _isSending = false;

  bool _isDeepThinkingEnabled = false;
  bool _isWebSearchEnabled = false;

  final List<ChatImage> _selectedImages = [];

  static const int _kMaxMessageLength = 500;

  @override
  void initState() {
    super.initState();
    _loadModelsFromAPI();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadModelsFromAPI() async {
    try {
      final models = await AIModelService.instance.fetchAvailableModels();
      if (mounted) {
        setState(() {
          _availableModels = models;
          if (models.isNotEmpty) {
            _selectedModel = models.first;
          }
          _isLoadingModels = false;
        });
      }
    } catch (e) {
      Log.error('[MobileAI] 加载模型失败: $e');
      if (mounted) {
        setState(() => _isLoadingModels = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _textController.text.trim();
    if (message.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _focusNode.unfocus();
    });

    try {
      final workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      if (workspaceId == null) {
        _showError('无法获取工作空间信息');
        return;
      }

      final view = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspaceId,
        initialMessage: message,
        selectedModelId: _selectedModel?.id,
        enableDeepThinking: _isDeepThinkingEnabled,
        enableWebSearch: _isWebSearchEnabled,
        initialImages: _selectedImages.isEmpty ? null : _selectedImages,
      );

      if (view == null) {
        _showError('创建AI对话失败');
        return;
      }

      if (mounted) {
        context.push(
          '${MobileChatScreen.routeName}?${MobileChatScreen.viewId}=${view.id}&${MobileChatScreen.viewTitle}=${Uri.encodeComponent(view.name)}',
        );
        _textController.clear();
        setState(() {
          _selectedImages.clear();
          _isSending = false;
        });
      }
    } catch (e, stackTrace) {
      Log.error('[MobileAI] 发送消息失败: $e', e, stackTrace);
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

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newImages = result.files
            .where((f) => f.bytes != null)
            .map((f) => ChatImage.fromBytes(f.bytes!, name: f.name))
            .toList();

        if (mounted) {
          setState(() => _selectedImages.addAll(newImages));
        }
      }
    } catch (e) {
      Log.error('[MobileAI] 选择图片失败: $e');
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final afTheme = AppFlowyTheme.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, afTheme, theme),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    _buildHeroSection(context, afTheme, theme),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildBottomInputBar(context, afTheme, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    AppFlowyThemeData afTheme,
    ThemeData theme,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                GoRouter.of(context).go(MobileHomeScreen.routeName),
            icon: FlowySvg(
              FlowySvgs.mobile_return_s,
              size: const Size(7, 12),
              color: afTheme.iconColorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '小马笔记AI',
              style: afTheme.textStyle.heading3.standard(
                color: afTheme.textColorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: FlowySvg(
              FlowySvgs.three_dots_s,
              size: const Size.square(24),
              color: afTheme.iconColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    AppFlowyThemeData afTheme,
    ThemeData theme,
  ) {
    final primaryColor = theme.colorScheme.primary;

    return Column(
      children: [
        // Orange circle with horse icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.pets,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Main greeting text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '我是小马笔记AI，很高兴见到你！',
            style: afTheme.textStyle.heading2.standard(
              color: afTheme.textColorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 10),
        // Subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            '我可以帮你写代码、写作各种创意内容，请把你的任务交给我吧~',
            style: afTheme.textStyle.body.standard(
              color: afTheme.textColorScheme.secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInputBar(
    BuildContext context,
    AppFlowyThemeData afTheme,
    ThemeData theme,
  ) {
    final primaryColor = theme.colorScheme.primary;
    final canSend =
        _textController.text.trim().isNotEmpty && !_isSending;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hint text
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '在小马笔记可以问或找到每一件事...',
                style: afTheme.textStyle.body.standard(
                  color: afTheme.textColorScheme.tertiary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Controls row — horizontally scrollable to handle narrow screens
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildModelChip(context, afTheme, theme),
                  const SizedBox(width: 6),
                  _buildToggleChip(
                    label: '深度思考',
                    icon: Icons.psychology_outlined,
                    isEnabled: _isDeepThinkingEnabled,
                    afTheme: afTheme,
                    theme: theme,
                    onChanged: (v) =>
                        setState(() => _isDeepThinkingEnabled = v),
                  ),
                  const SizedBox(width: 6),
                  _buildToggleChip(
                    label: '联网搜索',
                    icon: Icons.language_outlined,
                    isEnabled: _isWebSearchEnabled,
                    afTheme: afTheme,
                    theme: theme,
                    onChanged: (v) =>
                        setState(() => _isWebSearchEnabled = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Input row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.attachment_outlined,
                        size: 20,
                        color: afTheme.iconColorScheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Text input
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: null,
                        minLines: 1,
                        maxLength: _kMaxMessageLength,
                        buildCounter: (context,
                                {required currentLength,
                                required isFocused,
                                required maxLength}) =>
                            null,
                        style: afTheme.textStyle.body.standard(
                          color: afTheme.textColorScheme.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: '输入你的问题...',
                          hintStyle: afTheme.textStyle.body.standard(
                            color: afTheme.textColorScheme.tertiary,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Send button
                  GestureDetector(
                    onTap: canSend ? _sendMessage : null,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: canSend
                            ? primaryColor
                            : primaryColor.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: _isSending
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Image attachment preview strip
            if (_selectedImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final image = _selectedImages[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: image.bytes != null
                              ? Image.memory(
                                  image.bytes!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 56,
                                  height: 56,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.image,
                                    color: afTheme.iconColorScheme.secondary,
                                    size: 20,
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildModelChip(
    BuildContext context,
    AppFlowyThemeData afTheme,
    ThemeData theme,
  ) {
    final primaryColor = theme.colorScheme.primary;

    if (_isLoadingModels) {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: primaryColor,
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<AIModel>(
      initialValue: _selectedModel,
      onSelected: (model) => setState(() => _selectedModel = model),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      itemBuilder: (context) => _availableModels.map((model) {
        final isRecommended = model.id == 'deepseek-v3';
        return PopupMenuItem<AIModel>(
          value: model,
          height: 44,
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Center(
                  child: FlowySvg(
                    FlowySvgs.icon_ai_s,
                    size: const Size.square(14),
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.name,
                  style: afTheme.textStyle.body.standard(
                    color: afTheme.textColorScheme.primary,
                  ),
                ),
              ),
              if (isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '推荐',
                    style: TextStyle(
                      fontSize: 10,
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              FlowySvgs.icon_ai_s,
              size: const Size.square(12),
              color: primaryColor,
            ),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60),
              child: Text(
                _selectedModel?.name ?? '选择模型',
                style: TextStyle(
                  fontSize: 11,
                  color: primaryColor,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool isEnabled,
    required AppFlowyThemeData afTheme,
    required ThemeData theme,
    required ValueChanged<bool> onChanged,
  }) {
    final primaryColor = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => onChanged(!isEnabled),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isEnabled
            ? primaryColor.withValues(alpha: 0.1)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isEnabled
              ? primaryColor.withValues(alpha: 0.4)
              : theme.dividerColor.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isEnabled
                ? primaryColor
                : afTheme.iconColorScheme.secondary,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isEnabled
                  ? primaryColor
                  : afTheme.textColorScheme.secondary,
              fontWeight: isEnabled ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: 1),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 13,
            color: isEnabled
                ? primaryColor
                : afTheme.iconColorScheme.secondary,
          ),
          ],
        ),
      ),
    );
  }
}
