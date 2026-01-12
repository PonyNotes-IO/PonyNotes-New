import 'dart:io';
import 'package:flutter/material.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import '../ai_welcome_theme.dart';
import '../../services/image_service.dart';
import '../../models/chat_image.dart';

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
  /// 参数：message - 消息内容, model - 选择的模型, images - 图片列表, enableDeepThinking - 是否启用深度思考
  final Function(String message, AIModel? model, List<ChatImage>? images, bool enableDeepThinking)? onMessageSent;
  
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
  
  // 功能开关状态
  bool _isDeepThinkingEnabled = false;  // 深度思考开关
  bool _isWebSearchEnabled = false;     // 全网搜索开关

  @override
  void initState() {
    super.initState();
    _loadModelsFromAPI();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
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

    // 清空输入框和图片
    _textController.clear();
    final images = List<ChatImage>.from(_selectedImages);
    _selectedImages.clear();
    
    // 调用回调，使用AIModel系统，传递深度思考状态
    widget.onMessageSent?.call(text, _selectedModel, images.isNotEmpty ? images : null, _isDeepThinkingEnabled);
    
    // 发送后收起键盘
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
          maxHeight: _selectedImages.isNotEmpty ? 
            AIWelcomeTheme.inputContainerHeight + (_selectedImages.length <= 3 ? 80 : 140) : // 根据图片数量动态调整
            AIWelcomeTheme.inputContainerHeight,
        ),
        decoration: AIWelcomeTheme.inputContainerDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 选中图片预览区域
            if (_selectedImages.isNotEmpty) _buildImagePreviewArea(),
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
                  const Spacer(),
                  // 功能图标按钮组
                  
                  // 聊天记录图标按钮（仅图标）
                  if (widget.onChatHistoryTap != null) ...[
                    const SizedBox(width: 22),
                    _buildHistoryButton(),
                  ],
                  // 深度思考按钮（最左边）
                  const SizedBox(width: 22),
                  _buildDeepThinkingButton(),
                  // 全网搜索按钮（tool_2，与图片上传交换位置后移到这里）
                  const SizedBox(width: 22),
                  _buildWebSearchButton(),
                  // 图片上传按钮（与全网搜索交换位置后移到这里）
                  const SizedBox(width: 22),
                  _buildImagePickerButton(),
                  // 附件上传按钮（tool_3）
                  const SizedBox(width: 20),
                  _buildToolButton('assets/images/icons/tool_3.png', '附件上传'),
                  const SizedBox(width: 21),
                  // 分隔线（对应 block_5）
                  Container(
                    width: 1,
                    height: 20,
                    decoration: AIWelcomeTheme.dividerDecoration(context),
                  ),
                  const SizedBox(width: 21),
                  // 发送按钮（对应 label_9）
                  _buildSendButton(),
                ],
              ),
            ),
          ],
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

  /// 构建模型选择下拉框
  Widget _buildModelSelector() {
    return GestureDetector(
      key: _selectorKey, // 添加GlobalKey
      onTap: _toggleDropdown,
      child: Container(
        width: 130,
        height: AIWelcomeTheme.toolbarButtonSize,
        decoration: AIWelcomeTheme.modelSelectorDecoration(context),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedModel?.name ?? '选择模型',
                style: AIWelcomeTheme.modelSelectorStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Transform.rotate(
              angle: _isDropdownOpen ? 3.14159 : 0, // 180度旋转
              child: Image.asset(
                'assets/images/icons/dropdown_arrow.png',
                width: 12,
                height: 12,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.arrow_drop_down,
                    size: 12,
                    color: AIWelcomeTheme.secondaryTextColor(context),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AIWelcomeTheme.selectedItemColor(context)
                            : Colors.transparent,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            model.name,
                            style: TextStyle(
                              fontSize: 14,
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
                                fontSize: 11,
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

  /// 选择图片
  Future<void> _selectImage() async {
    if (_isDropdownOpen) {
      _closeDropdown();
    }
    
    final image = await _imageService.showImagePickerDialog(context);
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

  /// 移除选中的图片
  void _removeImage(ChatImage image) {
    setState(() {
      _selectedImages.remove(image);
    });
  }

  /// 构建全网搜索按钮
  Widget _buildWebSearchButton() {
    final isEnabled = _isWebSearchEnabled;
    final iconColor = isEnabled
        ? Theme.of(context).colorScheme.primary
        : AIWelcomeTheme.secondaryTextColor(context);
    
    return FlowyTooltip(
      message: '全网搜索',
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isWebSearchEnabled = !_isWebSearchEnabled;
          });
          debugPrint('🌐 全网搜索按钮: ${_isWebSearchEnabled ? "开启" : "关闭"}');
        },
        child: Container(
          width: AIWelcomeTheme.iconSize,
          height: AIWelcomeTheme.iconSize,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              iconColor,
              BlendMode.srcIn,
            ),
            child: Image.asset(
              'assets/images/icons/tool_2.png',
              width: AIWelcomeTheme.iconSize * 0.8,
              height: AIWelcomeTheme.iconSize * 0.8,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: AIWelcomeTheme.iconSize,
                  height: AIWelcomeTheme.iconSize,
                  decoration: BoxDecoration(
                    color: AIWelcomeTheme.containerColor(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.language,
                    size: AIWelcomeTheme.iconSize * 0.6,
                    color: iconColor,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 构建工具按钮
  Widget _buildToolButton(String imageUrl, String tooltip) {
    return FlowyTooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          // TODO: 实现具体的工具功能
        },
        child: Container(
          width: AIWelcomeTheme.iconSize,
          height: AIWelcomeTheme.iconSize,
          child: Image.asset(
            imageUrl,
            width: AIWelcomeTheme.iconSize * 0.8,
            height: AIWelcomeTheme.iconSize * 0.8,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: AIWelcomeTheme.iconSize,
                height: AIWelcomeTheme.iconSize,
                decoration: BoxDecoration(
                  color: AIWelcomeTheme.containerColor(context),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.image_not_supported,
                  size: AIWelcomeTheme.iconSize * 0.6,
                  color: AIWelcomeTheme.secondaryTextColor(context),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 构建发送按钮
  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _sendMessage,
      child: Container(
        width: AIWelcomeTheme.sendButtonSize,
        height: AIWelcomeTheme.sendButtonSize,
        child: Image.asset(
          'assets/images/icons/send_button.png',
          width: AIWelcomeTheme.sendButtonSize,
          height: AIWelcomeTheme.sendButtonSize,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: AIWelcomeTheme.sendButtonSize,
              height: AIWelcomeTheme.sendButtonSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(AIWelcomeTheme.sendButtonSize / 2),
              ),
              child: Icon(
                Icons.send,
                size: AIWelcomeTheme.sendButtonSize * 0.6,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建深度思考按钮
  Widget _buildDeepThinkingButton() {
    final isEnabled = _isDeepThinkingEnabled;
    final iconColor = isEnabled
        ? Theme.of(context).colorScheme.primary
        : AIWelcomeTheme.secondaryTextColor(context);
    
    return FlowyTooltip(
      message: '深度思考',
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isDeepThinkingEnabled = !_isDeepThinkingEnabled;
          });
          debugPrint('🔍 深度思考按钮: ${_isDeepThinkingEnabled ? "开启" : "关闭"}');
        },
        child: Container(
          width: AIWelcomeTheme.iconSize,
          height: AIWelcomeTheme.iconSize,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.auto_awesome,
            size: AIWelcomeTheme.iconSize,
            color: iconColor,
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
