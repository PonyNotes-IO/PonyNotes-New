import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/ai/mobile_ai_input_bar.dart';
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
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF89C7D), Color(0xFFFFFFFF)],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
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
              MobileAIInputBar(
                textController: _textController,
                focusNode: _focusNode,
                selectedImages: _selectedImages,
                isSending: _isSending,
                isLoadingModels: _isLoadingModels,
                availableModels: _availableModels,
                selectedModel: _selectedModel,
                isDeepThinkingEnabled: _isDeepThinkingEnabled,
                isWebSearchEnabled: _isWebSearchEnabled,
                afTheme: afTheme,
                onSend: _sendMessage,
                onPickImages: _pickImages,
                onRemoveImage: _removeImage,
                onDeepThinkingChanged: (v) =>
                    setState(() => _isDeepThinkingEnabled = v),
                onWebSearchChanged: (v) =>
                    setState(() => _isWebSearchEnabled = v),
                onModelSelected: (model) =>
                    setState(() => _selectedModel = model),
              ),
            ],
          ),
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
        color: Colors.transparent,
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
              FlowySvgs.m_app_bar_back_s,
              size: const Size(7, 12),
              color: afTheme.iconColorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '小马笔记AI',
              style: afTheme.textStyle.heading4.standard(
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
    return Column(
      children: [
        // Pony Notes logo
        Center(
          child: Image.asset(
            'assets/images/cal_logo@2x.png',
            width: 80,
            height: 80,
          ),
        ),
        const SizedBox(height: 20),
        // Main greeting text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '我是小马笔记AI，很高兴见到你！',
            style: afTheme.textStyle.heading3.standard(
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
}
