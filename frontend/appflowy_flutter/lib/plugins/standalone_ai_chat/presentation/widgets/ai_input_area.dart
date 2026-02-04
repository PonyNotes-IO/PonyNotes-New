import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/ai_chat_usage_indicator.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../ai_welcome_theme.dart';
import '../../services/image_service.dart';
import '../../models/chat_image.dart';
import 'package:flowy_svg/flowy_svg.dart';

/// AI欢迎页面的输入交互区域
/// 对应设计图中的 block_3 区域
class AIInputArea extends StatefulWidget {
  const AIInputArea({
    super.key,
    this.onMessageSent,
    this.onChatHistoryTap,
    this.customWidth,
    this.customMargin,
    this.customToolbarPadding,
    this.customToolbarWidth,
  });

  /// 发送消息的回调（使用AIModel系统）
  /// 参数：message - 消息内容, model - 选择的模型, images - 图片列表, enableDeepThinking - 是否启用深度思考, enableWebSearch - 是否启用全网搜索
  final Function(String message, AIModel? model, List<ChatImage>? images, bool enableDeepThinking, bool enableWebSearch)? onMessageSent;
  
  /// 点击聊天记录按钮的回调（若提供，则在工具栏显示图标按钮）
  final VoidCallback? onChatHistoryTap;
  final double? customWidth; // 可选的自定义宽度
  final EdgeInsets? customMargin; // 可选的自定义边距
  final EdgeInsets? customToolbarPadding; // 可选的自定义工具栏边距
  final double? customToolbarWidth; // 可选的自定义工具栏宽度

  @override
  State<AIInputArea> createState() => _AIInputAreaState();
}

class _AIInputAreaState extends State<AIInputArea> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _selectorKey = GlobalKey(); // 用于获取模型选择器位置
  
  // 模型选择相关状态
  AIModel? _selectedModel; // 初始化为null，显示"选择模型"
  bool _isDropdownOpen = false;
  List<AIModel> _availableModels = [];
  OverlayEntry? _overlayEntry;
  
  // 图片选择相关状态
  final List<ChatImage> _selectedImages = [];
  final ChatImageService _imageService = ChatImageService.instance;
  
  // 附件列表（包含图片和文件）
  final List<_AttachmentItem> _attachments = [];
  
  // 功能开关状态
  bool _isDeepThinkingEnabled = false;  // 深度思考开关
  bool _isWebSearchEnabled = false;     // 全网搜索开关
  // 文本长度限制与计数
  static const int _kMaxMessageLength = 120;
  int _currentCharCount = 0;

  @override
  void initState() {
    super.initState();
    _loadModelsFromAPI();
    // 监听文本变化以更新字符计数并限制长度
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (text.length > _kMaxMessageLength) {
      // 截断并恢复光标到末尾
      final truncated = text.substring(0, _kMaxMessageLength);
      _textController.value = TextEditingValue(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
      _currentCharCount = _kMaxMessageLength;
    } else {
      _currentCharCount = text.length;
    }
    // 更新显示
    if (mounted) setState(() {});
  }

  /// 从API加载模型列表
  Future<void> _loadModelsFromAPI() async {
    try {
      debugPrint('🔄 AIInputArea: 开始加载AI模型列表...');
      final models = await AIModelService.instance.fetchAvailableModels();
      if (mounted) {
        setState(() {
          _availableModels = models;
          // 选择默认模型
          _selectedModel = models.firstWhere(
            (model) => model.isDefault,
            orElse: () => models.isNotEmpty ? models.first : _getDefaultModel(),
          );
          debugPrint('✅ AIInputArea: 模型列表加载完成，当前选择: ${_selectedModel?.name}');
        });
      }
    } catch (e) {
      debugPrint('❌ AIInputArea: 加载AI模型失败: $e');
      if (mounted) {
        setState(() {
          // 使用本地的默认模型作为fallback
          _availableModels = [_getDefaultModel()];
          _selectedModel = _availableModels.first;
        });
      }
    }
  }

  AIModel _getDefaultModel() {
    return AIModel(
      id: 'deepseek-chat',
      name: 'DeepSeek',
      description: '',
      isDefault: true,
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty) return;

    // 关闭可能打开的下拉框，避免遮挡或悬浮层遗留
    if (_isDropdownOpen) {
      _closeDropdown();
    }

    // 确保已选择模型
    if (_selectedModel == null) {
      if (_availableModels.isNotEmpty) {
        // 选择第一个可用模型（通常是默认模型）
        _selectModel(_availableModels.first);
      } else {
        debugPrint('❌ 没有可用的AI模型');
        // TODO: 显示错误提示，需要配置AI模型
        return;
      }
    }

    debugPrint('📤 AIInputArea: 准备发送消息');
    debugPrint('   - 消息: $text');
    debugPrint('   - 模型: ${_selectedModel?.name} (${_selectedModel?.id})');
    debugPrint('   - 图片数: ${_selectedImages.length}');
    debugPrint('   - 深度思考: ${_isDeepThinkingEnabled ? "开启" : "关闭"}');
    debugPrint('   - 全网搜索: ${_isWebSearchEnabled ? "开启" : "关闭"}');

    // 清空输入框和图片
    _textController.clear();
    final images = List<ChatImage>.from(_selectedImages);
    _selectedImages.clear();
    
    // 调用回调，使用AIModel系统，传递深度思考和全网搜索状态
    widget.onMessageSent?.call(text, _selectedModel, images.isNotEmpty ? images : null, _isDeepThinkingEnabled, _isWebSearchEnabled);
    
    // 发送后收起键盘
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false, // 防止与TextField的焦点冲突
      skipTraversal: true,    // 跳过焦点遍历
      includeSemantics: false, // 不包含在语义树中
      onKeyEvent: (node, event) {
        // 监听 Ctrl+V 或 Cmd+V 粘贴图片，但不拦截事件（让TextField也能处理）
        if (event is KeyDownEvent) {
          final isControlPressed = HardwareKeyboard.instance.isControlPressed || 
                                   HardwareKeyboard.instance.isMetaPressed;
          final isVPressed = event.logicalKey == LogicalKeyboardKey.keyV;
          
          if (isControlPressed && isVPressed) {
            // 异步检查剪贴板是否有图片
            _pasteImageFromClipboard();
          }
        }
        // 返回 KeyEventResult.ignored 让事件继续传递给TextField
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          // 点击其他区域时关闭下拉框
          if (_isDropdownOpen) {
            _closeDropdown();
          }
        },
        child: Container(
          margin: widget.customMargin ?? AIWelcomeTheme.inputContainerPadding,
          width: widget.customWidth ?? AIWelcomeTheme.inputContainerWidth,
          constraints: BoxConstraints(
            minHeight: AIWelcomeTheme.inputContainerHeight,
            // 有附件时允许高度扩展，最大高度增加到原来的1.5倍
            maxHeight: _attachments.isNotEmpty 
                ? AIWelcomeTheme.inputContainerHeight * 1.5 
                : AIWelcomeTheme.inputContainerHeight,
          ),
          decoration: AIWelcomeTheme.inputContainerDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 输入文本区域（对应 text-wrapper_5）
              Expanded(
                child: Container(
                  margin: AIWelcomeTheme.inputTextPadding,
                  constraints: const BoxConstraints(
                    minHeight: 60, // 确保输入框有最小高度
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: AIWelcomeTheme.placeholderStyle(context).copyWith(
                      color: AIWelcomeTheme.primaryTextColor(context),
                    ),
                    decoration: InputDecoration(
                      hintText: '在小马笔记可以问或找到每一件事…',
                      hintStyle: AIWelcomeTheme.placeholderStyle(context),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              // 工具栏区域（对应 group_2）
              Container(
                margin: widget.customToolbarPadding ?? AIWelcomeTheme.toolbarPadding,
                width: widget.customToolbarWidth ?? AIWelcomeTheme.toolbarWidth,
                height: AIWelcomeTheme.toolbarHeight,
                child: Row(
                  children: [
                    // 模型选择下拉框（对应 block_4）
                    _buildModelSelector(),
                    // 深度思考按钮（移到模型选择器右侧，相邻）
                    const SizedBox(width: 10),
                    _buildDeepThinkingButton(),
                    // 联网搜索按钮（移到深度思考按钮右侧）
                    const SizedBox(width: 10),
                    _buildWebSearchButton(),
                    const Spacer(),
                    // 功能图标按钮组
                    
                    // 聊天记录图标按钮（仅图标）
                    if (widget.onChatHistoryTap != null) ...[
                      const SizedBox(width: 22),
                      _buildHistoryButton(),
                    ],
                    // 字数与剩余可用次数合并显示（紧凑样式，靠近附件按钮）
                    _buildCountAndRemainingIndicator(),
                    const SizedBox(width: 12),
                    // 合并后的附件上传按钮（包含图片和附件上传功能）
                    const SizedBox(width: 12),
                    _buildAttachmentButton(),
                    // 去掉附件与发送按钮之间的竖向分割线，保持适当间距
                    const SizedBox(width: 12),
                    // 发送按钮（对应 label_9）
                    _buildSendButton(),
                  ],
                ),
              ),
              // 附件预览区域（显示在工具栏下方）
              if (_attachments.isNotEmpty) _buildAttachmentPreviewArea(),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建聊天记录图标按钮（仅图标）
  Widget _buildHistoryButton() {
    return GestureDetector(
      onTap: widget.onChatHistoryTap,
      child: Container(
        width: AIWelcomeTheme.iconSize,
        height: AIWelcomeTheme.iconSize,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.history,
          size: AIWelcomeTheme.iconSize,
          color: AIWelcomeTheme.secondaryTextColor(context),
        ),
      ),
    );
  }

  /// 判断是否有功能开关开启（深度思考或联网搜索）
  bool get _hasFeatureEnabled => _isDeepThinkingEnabled || _isWebSearchEnabled;

  /// 获取按钮文字颜色（适配深色模式和禁用状态）
  Color _getButtonTextColor(BuildContext context, bool isEnabled, {bool isDisabled = false}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (isDisabled) {
      return isDarkMode ? const Color(0xFF666666) : const Color(0xFFB0B0B0);
    }
    if (isEnabled) {
      return const Color(0xFFE94618); // 启用状态始终使用主题橙色
    }
    return isDarkMode ? const Color(0xFFB0B0B0) : const Color(0xFF636363);
  }

  /// 获取按钮边框颜色（适配深色模式和禁用状态）
  Color _getButtonBorderColor(BuildContext context, bool isEnabled, {bool isDisabled = false}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (isDisabled) {
      return isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0);
    }
    if (isEnabled) {
      return const Color(0xFFE94618); // 启用状态始终使用主题橙色
    }
    return isDarkMode ? const Color(0xFF4A4A4A) : const Color(0xFFCDCDCD);
  }

  /// 获取按钮背景颜色（适配深色模式和禁用状态）
  Color _getButtonBackgroundColor(BuildContext context, {bool isDisabled = false}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (isDisabled) {
      return isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    }
    return isDarkMode ? const Color(0xFF2C2C2C) : Colors.white;
  }

  /// 显示互斥提示弹窗
  void _showMutualExclusionDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 构建模型选择下拉框
  Widget _buildModelSelector() {
    return GestureDetector(
      key: _selectorKey, // 添加GlobalKey
      onTap: _toggleDropdown,
      child: Container(
        width: 102,
        height: 30,
        decoration: BoxDecoration(
          color: _getButtonBackgroundColor(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _getButtonBorderColor(context, _selectedModel != null),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedModel?.name ?? 'DeepSeek',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _getButtonTextColor(context, _selectedModel != null),
                  fontFamily: 'PingFangSC-Medium',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Transform.rotate(
              angle: _isDropdownOpen ? 3.14159 : 0, // 180度旋转
              child: Image.asset(
                'assets/images/icons/dropdown_arrow.png',
                width: 9,
                height: 7,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.arrow_drop_down,
                    size: 7,
                    color: _getButtonTextColor(context, _selectedModel != null),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  /// 切换下拉框状态
  void _toggleDropdown() {
    if (_availableModels.isEmpty) return;
    
    if (_isDropdownOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  /// 打开下拉框
  void _openDropdown() {
    if (_availableModels.isEmpty) return;
    
    setState(() {
      _isDropdownOpen = true;
    });

    // 使用GlobalKey获取模型选择器的准确位置
    final RenderBox? selectorRenderBox = _selectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (selectorRenderBox == null) return;
    
    final selectorSize = selectorRenderBox.size;
    final selectorOffset = selectorRenderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: selectorOffset.dx, // 与选择器左对齐
        top: selectorOffset.dy + selectorSize.height + 4, // 在选择器下方4px处
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 150, // 与选择器宽度一致
            constraints: const BoxConstraints(
              maxHeight: 200, // 最大高度限制
            ),
            decoration: AIWelcomeTheme.dropdownDecoration(context),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _availableModels.asMap().entries.map((entry) {
                  final index = entry.key;
                  final model = entry.value;
                  final isFirst = index == 0;
                  final isLast = index == _availableModels.length - 1;
                  final isSelected = _selectedModel?.id == model.id;
                  
                  return InkWell(
                    onTap: () => _selectModel(model),
                    borderRadius: BorderRadius.vertical(
                      top: isFirst ? const Radius.circular(8) : Radius.zero,
                      bottom: isLast ? const Radius.circular(8) : Radius.zero,
                    ),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: isSelected
                          ? BoxDecoration(
                              color: AIWelcomeTheme.selectedItemColor(context),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            model.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? AIWelcomeTheme.selectedItemTextColor(context)
                                  : AIWelcomeTheme.primaryTextColor(context),
                              fontWeight: isSelected
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                          if (model.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              model.description,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? AIWelcomeTheme.selectedItemTextColor(context).withOpacity(0.7)
                                    : AIWelcomeTheme.secondaryTextColor(context),
                              ),
                            ),
                          ],
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

  /// 关闭下拉框
  void _closeDropdown() {
    setState(() {
      _isDropdownOpen = false;
    });
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// 选择模型
  void _selectModel(AIModel model) {
    debugPrint('✅ AIInputArea: 选择模型 ${model.name} (${model.id})');
    setState(() {
      _selectedModel = model;
    });
    _closeDropdown();
  }

  /// 选择图片 - 直接打开文件选择器
  Future<void> _selectImage() async {
    if (_isDropdownOpen) {
      _closeDropdown();
    }
    
    // 直接从文件系统选择图片，不显示选择对话框
    final image = await _imageService.pickImageFromFile();
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
      
      // 选择图片后自动聚焦到输入框，确保用户可以继续输入文字
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  /// 从剪贴板粘贴图片
  Future<void> _pasteImageFromClipboard() async {
    final image = await _imageService.pasteImageFromClipboard();
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
      debugPrint('📋 从剪贴板粘贴图片成功');
    } else {
      debugPrint('📋 剪贴板中没有图片');
    }
  }

  /// 移除选中的图片
  void _removeImage(ChatImage image) {
    setState(() {
      _selectedImages.remove(image);
    });
  }

  /// 构建全网搜索按钮
  Widget _buildWebSearchButton() {
    final isEnabled = _isWebSearchEnabled;
    // 有附件时禁用
    final isDisabled = _attachments.isNotEmpty;
    final isDisabledReason = isDisabled ? '附件模式下不支持联网搜索' : null;

    return FlowyTooltip(
      message: isDisabledReason ?? (isEnabled ? '关闭联网搜索' : '开启联网搜索'),
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                setState(() {
                  _isWebSearchEnabled = !_isWebSearchEnabled;
                });
                debugPrint('🌐 联网搜索按钮: ${_isWebSearchEnabled ? "开启" : "关闭"}');
              },
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _getButtonBackgroundColor(context, isDisabled: isDisabled),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _getButtonBorderColor(context, isEnabled, isDisabled: isDisabled),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '联网搜索',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getButtonTextColor(context, isEnabled, isDisabled: isDisabled),
                fontFamily: 'PingFangSC-Medium',
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建合并后的附件上传按钮（包含图片和附件上传功能）
  Widget _buildAttachmentButton() {
    final hasAttachments = _attachments.isNotEmpty;
    // 有功能开关开启时禁用附件上传
    final isDisabled = _hasFeatureEnabled;
    final isDisabledReason = isDisabled ? '开启深度思考或联网搜索后不支持上传附件' : null;

    return FlowyTooltip(
      message: isDisabledReason ?? (hasAttachments ? '已添加 ${_attachments.length} 个附件' : '上传附件（支持图片和文件）'),
      child: GestureDetector(
        onTap: isDisabled ? null : _handleAttachmentTap,
        child: Container(
          width: AIWelcomeTheme.iconSize,
          height: AIWelcomeTheme.iconSize,
          decoration: BoxDecoration(
            color: hasAttachments ? AIWelcomeTheme.selectedItemColor(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              Center(
                child: FlowySvg(
                  // 根据禁用状态显示不同图标
                  isDisabled
                      ? const FlowySvgData('assets/flowy_icons/32x/askAHBU.svg')
                      : hasAttachments
                          ? const FlowySvgData('assets/flowy_icons/32x/askAHBU.svg')
                          : const FlowySvgData('assets/flowy_icons/32x/askNAU.svg'),
                  size: Size.square(AIWelcomeTheme.iconSize * 0.8),
                  // 禁用时使用灰色（通过 color 参数设置）
                  color: isDisabled
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                      : null,
                  blendMode: isDisabled ? BlendMode.srcIn : null,
                ),
              ),
              // 禁用状态遮罩
              if (isDisabled)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 处理附件按钮点击事件（支持图片和文件上传）
  /// 直接打开系统文件浏览器，不显示类型选择对话框
  Future<void> _handleAttachmentTap() async {
    if (_isDropdownOpen) {
      _closeDropdown();
    }
    
    try {
      // 直接打开系统文件浏览器，支持所有文件类型
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any, // 支持所有文件类型
        withData: false, // 大文件不直接加载到内存
      );
      
      if (result == null || result.files.isEmpty) {
        return;
      }
      
      // 支持的图片扩展名
      const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff'];
      
      // 处理选中的文件
      final List<_AttachmentItem> newAttachments = [];
      final List<ChatImage> newImages = [];
      
      for (final pickedFile in result.files) {
        final filePath = pickedFile.path;
        if (filePath == null || filePath.isEmpty) continue;
        
        final file = File(filePath);
        if (!file.existsSync()) continue;
        
        final extension = pickedFile.extension?.toLowerCase() ?? '';
        final isImage = imageExtensions.contains(extension);
        final fileSize = file.lengthSync();
        
        if (isImage) {
          // 如果是图片，创建ChatImage对象并添加到图片列表
          try {
            final image = await ChatImage.fromFile(file);
            newImages.add(image);
            newAttachments.add(_AttachmentItem(
              type: _AttachmentType.image,
              name: pickedFile.name,
              size: fileSize,
              image: image,
              file: file,
              uploadStatus: _UploadStatus.success,
            ));
          } catch (e) {
            debugPrint('创建图片对象失败: $e');
            // 如果创建图片对象失败，作为普通文件处理
            newAttachments.add(_AttachmentItem(
              type: _AttachmentType.file,
              name: pickedFile.name,
              size: fileSize,
              image: null,
              file: file,
              uploadStatus: _UploadStatus.success,
            ));
          }
        } else {
          // 普通文件
          newAttachments.add(_AttachmentItem(
            type: _AttachmentType.file,
            name: pickedFile.name,
            size: fileSize,
            image: null,
            file: file,
            uploadStatus: _UploadStatus.success,
          ));
        }
      }
      
      // 批量更新状态
      if (mounted && (newImages.isNotEmpty || newAttachments.isNotEmpty)) {
        setState(() {
          _selectedImages.addAll(newImages);
          _attachments.addAll(newAttachments);
        });
      }
      
      // 选择后自动聚焦到输入框
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    } catch (e) {
      debugPrint('文件选择失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件选择失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  /// 构建AI使用次数显示
  Widget _buildAIUsageIndicator() {
    return FutureBuilder<FlowyResult<WorkspaceUsagePB?, FlowyError>>(
      future: _loadUsage(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final result = snapshot.data!;
        return result.fold(
          (usage) {
            if (usage == null) {
              return const SizedBox.shrink();
            }

            // 如果无限制，不显示（无限制通常表示不需要展示次数）
            if (usage.aiResponsesUnlimited) {
              return const SizedBox.shrink();
            }

            final used = usage.aiResponsesCount.toInt();
            final total = usage.aiResponsesCountLimit.toInt();

            // 检测未订阅状态：total == -1 表示用户未订阅
            if (total == -1) {
              return Text(
                '未订阅，不可用',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              );
            }

            if (total == 0) {
              return const SizedBox.shrink();
            }

            final remaining = total - used;
            final textColor = remaining <= 0 ? Colors.red : Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

            // 仅显示“X 次可用”的提示，放在字数与附件之间
            return Text(
              '${remaining < 0 ? 0 : remaining} 次可用',
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            );
          },
          (error) {
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  /// 构建输入框字符计数器（显示 x/120），并在超出时限制长度
  Widget _buildCharCountIndicator() {
    final textColor = _currentCharCount >= _kMaxMessageLength
        ? Colors.red
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    // 简洁文本显示（去掉暗色背景），字号加大并加粗
    return Text(
      '$_currentCharCount/$_kMaxMessageLength',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }
 
  /// 合并显示：字符计数 + 剩余可用次数，样式为轻灰圆角 pill，与设计图保持一致
  Widget _buildCountAndRemainingIndicator() {
    return FutureBuilder<FlowyResult<WorkspaceUsagePB?, FlowyError>>(
      future: _loadUsage(),
      builder: (context, snapshot) {
        String remainingText = '';
        Color remainingColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

        if (!snapshot.hasData) {
          // 尚未加载到数据时显示占位（仅字符计数）
          remainingText = '';
        } else {
          final result = snapshot.data!;
          result.fold((usage) {
            if (usage == null) {
              remainingText = '';
              return;
            }
            if (usage.aiResponsesUnlimited) {
              remainingText = '';
              return;
            }
            final used = usage.aiResponsesCount.toInt();
            final total = usage.aiResponsesCountLimit.toInt();
            if (total == -1) {
              remainingText = '未订阅';
              remainingColor = Theme.of(context).colorScheme.error;
              return;
            }
            final remaining = total - used;
            remainingText = '${remaining < 0 ? 0 : remaining} 次可用';
            if (remaining <= 0) {
              remainingColor = Colors.red;
            } else {
              remainingColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
            }
          }, (error) {
            remainingText = '';
          });
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_currentCharCount/$_kMaxMessageLength',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _currentCharCount >= _kMaxMessageLength ? Colors.red : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (remainingText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '|',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  remainingText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: remainingColor,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
  
  /// 加载使用情况
  Future<FlowyResult<WorkspaceUsagePB?, FlowyError>> _loadUsage() async {
    try {
      final workspaceBloc = context.read<UserWorkspaceBloc>();
      final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId;
      if (workspaceId == null || workspaceId.isEmpty) {
        return FlowyResult.success(null);
      }
      
      final service = WorkspaceService(
        workspaceId: workspaceId,
        userId: fixnum.Int64.ZERO,
      );
      
      return service.getWorkspaceUsage();
    } catch (e) {
      return FlowyResult.failure(FlowyError(msg: e.toString()));
    }
  }
  
  String _getUsageDisplayText(int used, int total, int remaining) {
    if (remaining <= 0) {
      return '$used/$total 0次可用';
    }
    return '$used/$total $remaining次可用';
  }
  
  Color _getUsageTextColor(int remaining) {
    if (remaining <= 0) {
      return Colors.red;
    } else if (remaining <= 5) {
      return Colors.orange.shade700;
    } else {
      return Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    }
  }
  
  /// 构建附件预览区域（包含图片和文件）
  /// 显示在工具栏下方
  Widget _buildAttachmentPreviewArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _attachments.map((attachment) => _buildAttachmentItem(attachment)).toList(),
        ),
      ),
    );
  }
  
  /// 构建单个附件项
  /// 使用小图标，紧凑布局，文件名过长时用...显示
  Widget _buildAttachmentItem(_AttachmentItem attachment) {
    // 获取文件扩展名用于显示文件类型
    final extension = attachment.name.split('.').last.toLowerCase();
    final fileType = _getFileTypeDisplay(extension);
    
    return Container(
      width: 220, // larger card so ~4 cards fit per row in typical toolbar width
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: attachment.isSelected
            ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.2)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: attachment.uploadStatus == _UploadStatus.failed
              ? Colors.red
              : Theme.of(context).colorScheme.outline.withOpacity(0.16),
          width: 1,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          // If not selected, select this attachment (and deselect others).
          if (!attachment.isSelected) {
            setState(() {
              for (final a in _attachments) {
                a.isSelected = false;
              }
              attachment.isSelected = true;
            });
            return;
          }
          // If already selected, open the attachment.
          _openAttachment(attachment);
        },
        child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 小图标（放大一点）
              Icon(
                attachment.type == _AttachmentType.image
                    ? Icons.image
                    : _getFileIcon(extension),
                size: 20,
                color: attachment.type == _AttachmentType.image
                    ? Colors.red
                    : Colors.blue,
              ),
              const SizedBox(width: 10),
              // 文件名和大小
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                // 文件名（限制宽度，过长用...显示）
                // reserve right padding so top-right delete button doesn't overlap title
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(right: 36),
                  child: Text(
                    attachment.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AIWelcomeTheme.primaryTextColor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                    const SizedBox(height: 4),
                    // 文件类型和大小
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fileType,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                          ),
                        ),
                        if (attachment.size != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formatFileSize(attachment.size!),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 上传失败提示
                    if (attachment.uploadStatus == _UploadStatus.failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          '上传失败',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 删除按钮放在卡片右上角
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () => _removeAttachment(attachment),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
  
  /// 根据文件扩展名获取文件类型显示文本
  String _getFileTypeDisplay(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
        return 'DOC';
      case 'xls':
      case 'xlsx':
        return 'XLS';
      case 'ppt':
      case 'pptx':
        return 'PPT';
      case 'txt':
        return 'TXT';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return '图片';
      default:
        return extension.toUpperCase();
    }
  }
  
  /// 根据文件扩展名获取文件图标
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }
  
  /// 移除附件
  void _removeAttachment(_AttachmentItem attachment) {
    setState(() {
      _attachments.remove(attachment);
      // 如果是图片，也从图片列表中移除
      if (attachment.type == _AttachmentType.image && attachment.image != null) {
        _selectedImages.remove(attachment.image);
      }
    });
  }

  /// 构建发送按钮
  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _sendMessage,
      child: Container(
        width: AIWelcomeTheme.sendButtonSize,
        height: AIWelcomeTheme.sendButtonSize,
        child: FlowySvg(
          // show different svg based on input content
          _currentCharCount > 0
              ? const FlowySvgData('assets/flowy_icons/32x/askSendContent.svg')
              : const FlowySvgData('assets/flowy_icons/32x/askSendNoContent.svg'),
          size: Size.square(AIWelcomeTheme.sendButtonSize),
          blendMode: null,
        ),
      ),
    );
  }

  /// 构建深度思考按钮
  Widget _buildDeepThinkingButton() {
    final isEnabled = _isDeepThinkingEnabled;
    // 有附件时禁用
    final isDisabled = _attachments.isNotEmpty;
    final isDisabledReason = isDisabled ? '附件模式下不支持深度思考' : null;

    return FlowyTooltip(
      message: isDisabledReason ?? (isEnabled ? '关闭深度思考' : '开启深度思考'),
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                setState(() {
                  _isDeepThinkingEnabled = !_isDeepThinkingEnabled;
                });
                debugPrint('🔍 深度思考按钮: ${_isDeepThinkingEnabled ? "开启" : "关闭"}');
              },
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _getButtonBackgroundColor(context, isDisabled: isDisabled),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _getButtonBorderColor(context, isEnabled, isDisabled: isDisabled),
              width: 1,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '深度思考',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _getButtonTextColor(context, isEnabled, isDisabled: isDisabled),
                    fontFamily: 'PingFangSC-Medium',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建图片选择按钮
  Widget _buildImagePickerButton() {
    return FlowyTooltip(
      message: '上传图片',
      child: GestureDetector(
        onTap: _selectImage,
        child: Container(
          width: AIWelcomeTheme.iconSize,
          height: AIWelcomeTheme.iconSize,
          decoration: BoxDecoration(
            color: _selectedImages.isNotEmpty ? AIWelcomeTheme.selectedItemColor(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.image,
                  size: AIWelcomeTheme.iconSize,
                  color: _selectedImages.isNotEmpty ? AIWelcomeTheme.selectedItemTextColor(context) : AIWelcomeTheme.secondaryTextColor(context),
                ),
              ),
              if (_selectedImages.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${_selectedImages.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建图片预览区域
  Widget _buildImagePreviewArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: AIWelcomeTheme.imagePreviewAreaDecoration(context),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _selectedImages.map((image) => _buildImagePreviewItem(image)).toList(),
      ),
    );
  }

  /// 构建单个图片预览项
  Widget _buildImagePreviewItem(ChatImage image) {
    return Container(
      width: 60,
      height: 60,
      decoration: AIWelcomeTheme.imagePreviewItemDecoration(context),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: _buildImageWidget(image),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removeImage(image),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图片显示组件
  Widget _buildImageWidget(ChatImage image) {
    if (image.bytes != null) {
      return Image.memory(
        image.bytes!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildErrorImageWidget(),
      );
    } else if (image.filePath != null) {
      return Image.file(
        File(image.filePath!),
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildErrorImageWidget(),
      );
    } else if (image.url != null) {
      return Image.network(
        image.url!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildErrorImageWidget(),
      );
    }
    return _buildErrorImageWidget();
  }

  /// 打开附件（图片展示或使用系统默认程序打开文件）
  Future<void> _openAttachment(_AttachmentItem attachment) async {
    try {
      // Always open attachments using the system default application.
      // If the attachment is an in-memory image, write it to a temp file first.
      File? targetFile;

      if (attachment.file != null) {
        targetFile = attachment.file!;
      } else if (attachment.image != null) {
        final image = attachment.image!;
        if (image.filePath != null && image.filePath!.isNotEmpty) {
          targetFile = File(image.filePath!);
        } else if (image.bytes != null) {
          // write bytes to temp file with the original name if possible
          final tempDir = Directory.systemTemp;
          final sanitizedName = attachment.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final tempFile = File('${tempDir.path}${Platform.pathSeparator}$sanitizedName');
          await tempFile.writeAsBytes(image.bytes!);
          targetFile = tempFile;
        }
      }

      if (targetFile != null) {
        final path = targetFile.path;
        if (Platform.isWindows) {
          await Process.start('cmd', ['/c', 'start', '', path]);
        } else if (Platform.isMacOS) {
          await Process.start('open', [path]);
        } else if (Platform.isLinux) {
          await Process.start('xdg-open', [path]);
        }
      }
    } catch (e) {
      debugPrint('打开附件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开附件: $e')),
        );
      }
    }
  }

  /// 构建错误图片显示
  Widget _buildErrorImageWidget() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AIWelcomeTheme.containerColor(context),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(
        Icons.broken_image,
        size: 30,
        color: AIWelcomeTheme.secondaryTextColor(context),
      ),
    );
  }
}

/// 附件类型枚举
enum _AttachmentType {
  image, // 图片
  file,  // 文件
}

/// 上传状态枚举
enum _UploadStatus {
  success, // 成功
  failed,  // 失败
  // uploading, // 上传中（预留，未来使用）
}

/// 附件项数据模型
class _AttachmentItem {
  final _AttachmentType type;
  final String name;
  final int? size; // 文件大小（字节）
  final ChatImage? image; // 如果是图片
  final File? file; // 如果是文件
  final _UploadStatus uploadStatus;
  // 是否被选中（用于点击高亮）
  bool isSelected;
  
  _AttachmentItem({
    required this.type,
    required this.name,
    this.size,
    this.image,
    this.file,
    required this.uploadStatus,
    this.isSelected = false,
  });
}

