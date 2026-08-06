import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/ai/service/ai_model_capabilities.dart';
import 'package:appflowy/ai/service/ai_model_state_notifier.dart';
import 'package:appflowy/ai/widgets/prompt_input/mentioned_page_text_span.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_input_control_cubit.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_bloc.dart';
import 'package:appflowy/plugins/ai_chat/presentation/layout_define.dart';
import 'package:appflowy/shared/permission/permission_checker.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

class MobileChatInput extends StatefulWidget {
  const MobileChatInput({
    super.key,
    required this.isStreaming,
    required this.onStopStreaming,
    required this.onSubmitted,
    required this.selectedSourcesNotifier,
    required this.onUpdateSelectedSources,
  });

  final bool isStreaming;
  final void Function() onStopStreaming;
  final ValueNotifier<List<String>> selectedSourcesNotifier;
  final void Function(String, PredefinedFormat?, Map<String, dynamic>)
      onSubmitted;
  final void Function(List<String>) onUpdateSelectedSources;

  @override
  State<MobileChatInput> createState() => _MobileChatInputState();
}

class _MobileChatInputState extends State<MobileChatInput> {
  final inputControlCubit = ChatInputControlCubit();
  final focusNode = FocusNode();
  final textController = TextEditingController();

  // 附件加载状态
  bool _isAttachmentLoading = false;

  @override
  void initState() {
    super.initState();
    textController.addListener(handleTextControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
      checkForAskingAI();
    });
  }

  @override
  void dispose() {
    focusNode.dispose();
    textController.dispose();
    inputControlCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: inputControlCubit,
      child: BlocListener<ChatInputControlCubit, ChatInputControlState>(
        listener: (context, state) {
          state.maybeWhen(
            updateSelectedViews: (selectedViews) {
              context.read<AIPromptInputBloc>().add(
                    AIPromptInputEvent.updateMentionedViews(selectedViews),
                  );
            },
            orElse: () {},
          );
        },
        child: Container(
          margin: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2C2C2C)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
            builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 附件文件列表
                  if (state.attachedFiles.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MobileAIPromptSizes
                                .attachedFilesBarPadding.vertical +
                            MobileAIPromptSizes.attachedFilesPreviewHeight,
                      ),
                      child: PromptInputFile(
                        onDeleted: (file) => context
                            .read<AIPromptInputBloc>()
                            .add(AIPromptInputEvent.removeFile(file)),
                      ),
                    ),
                  // 输入框主体
                  inputTextField(context),
                  const SizedBox(height: 10),
                  // 底部工具栏：对标欢迎页
                  _buildBottomToolbar(context, state),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 对标欢迎页底部工具栏：模型 / 深度思考 / 联网搜索 / 附件 / 发送
  Widget _buildBottomToolbar(BuildContext context, AIPromptInputState state) {
    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModelButton(context),
                const SizedBox(width: 3),
                _buildFeatureButton(
                  context: context,
                  label: '深度思考',
                  icon: Icons.psychology,
                  isEnabled: state.enableDeepThinking,
                  onTap: () => context
                      .read<AIPromptInputBloc>()
                      .add(const AIPromptInputEvent.toggleDeepThinking()),
                ),
                const SizedBox(width: 3),
                _buildFeatureButton(
                  context: context,
                  label: '联网搜索',
                  icon: Icons.language,
                  isEnabled: state.enableWebSearch,
                  onTap: () => context
                      .read<AIPromptInputBloc>()
                      .add(const AIPromptInputEvent.toggleWebSearch()),
                ),
                const SizedBox(width: 3),
              ],
            ),
          ),
          _buildAttachmentButton(context),
          sendButton(),
        ],
      ),
    );
  }

  /// 对标欢迎页：模型选择按钮
  Widget _buildModelButton(BuildContext context) {
    final notifier = context.read<AIPromptInputBloc>().aiModelStateNotifier;
    return BlocProvider(
      create: (_) => SelectModelBloc(aiModelStateNotifier: notifier),
      child: _ModelButtonContent(aiModelStateNotifier: notifier),
    );
  }

  /// 对标欢迎页：功能按钮（深度思考 / 联网搜索）
  Widget _buildFeatureButton({
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
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  /// 对标欢迎页：附件上传按钮
  Widget _buildAttachmentButton(BuildContext context) {
    return BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
      buildWhen: (prev, curr) =>
          prev.attachedFiles.length != curr.attachedFiles.length ||
          prev.enableDeepThinking != curr.enableDeepThinking ||
          prev.enableWebSearch != curr.enableWebSearch,
      builder: (context, state) {
        final hasAttachments = state.attachedFiles.isNotEmpty;
        final isDisabled = state.enableDeepThinking || state.enableWebSearch;
        final colorScheme = Theme.of(context).colorScheme;
        final iconColor = isDisabled
            ? colorScheme.onSurface.withValues(alpha: 0.3)
            : colorScheme.onSurfaceVariant;

        return GestureDetector(
          onTap: isDisabled || _isAttachmentLoading
              ? null
              : () => _showAttachmentSourceMenu(context),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: _isAttachmentLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 1.5,
                          ),
                        )
                      : FlowySvg(
                          FlowySvgs.m_ai_attachment_m,
                          size: const Size.square(24),
                          color: iconColor,
                        ),
                ),
                if (hasAttachments)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94618),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${state.attachedFiles.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示附件来源选择菜单
  void _showAttachmentSourceMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.blue),
                ),
                title: const Text('从相册选择'),
                subtitle: const Text('选择图片'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImages();
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder_open, color: Colors.green),
                ),
                title: const Text('从文件选择'),
                subtitle: const Text('PDF、Word、文本等'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFiles();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    if (!mounted) return;
    setState(() => _isAttachmentLoading = true);
    try {
      final hasPermission =
          await PermissionChecker.checkPhotoPermission(context);
      if (!hasPermission) {
        debugPrint('[MobileAI] 没有相册访问权限');
        return;
      }

      final xFiles = await ImagePicker().pickMultiImage();
      if (xFiles.isEmpty) return;

      if (!mounted) return;
      final bloc = context.read<AIPromptInputBloc>();
      for (final xFile in xFiles) {
        bloc.add(AIPromptInputEvent.attachFile(xFile.path, xFile.name));
      }

      debugPrint('[MobileAI] 选择了 ${xFiles.length} 张图片');

      // 【PonyNotes】添加图片后，自动切换到支持多模态的模型（如 DeepSeek 不支持图片）
      await _ensureModelSupportsImages(showHint: true);
    } catch (e) {
      debugPrint('[MobileAI] 选择图片失败: $e');
      if (mounted) _showToast('选择图片失败');
    } finally {
      if (mounted) setState(() => _isAttachmentLoading = false);
    }
  }

  Future<void> _pickFiles() async {
    if (!mounted) return;
    setState(() => _isAttachmentLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'gif', 'webp',
          'pdf', 'doc', 'docx', 'txt', 'md',
          'xls', 'xlsx', 'ppt', 'pptx',
        ],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      if (!mounted) return;
      final bloc = context.read<AIPromptInputBloc>();
      for (final pickedFile in result.files) {
        if (pickedFile.path != null && pickedFile.path!.isNotEmpty) {
          bloc.add(AIPromptInputEvent.attachFile(pickedFile.path!, pickedFile.name));
        }
      }

      debugPrint('[MobileAI] 选择了 ${result.files.length} 个文件');
    } catch (e) {
      debugPrint('[MobileAI] 选择文件失败: $e');
      if (mounted) _showToast('选择文件失败');
    } finally {
      if (mounted) setState(() => _isAttachmentLoading = false);
    }
  }

  /// 【PonyNotes】确保当前选中的 AI 模型支持多模态（图片附件）
  ///
  /// 若当前模型不支持图片附件（例如 DeepSeek），
  /// 自动切换到第一个支持多模态的模型（通义千问 / 豆包）。
  /// 行为与电脑端 `ai_input_area.dart._ensureModelSupportsImages` 一致。
  ///
  /// 实现说明：依次尝试 3 种数据源读取模型列表：
  /// 1. 全局设置模型列表（kGlobalAIModelSource）
  /// 2. 本地模型列表（AIEventGetLocalModelSelection）
  /// 3. 当前会话模型列表（notifier）
  /// 以最先返回非空列表的数据源为准。
  ///
  /// 返回值：true = 当前模型已支持 / 已成功切换；false = 切换失败或无可用模型。
  Future<bool> _ensureModelSupportsImages({bool showHint = false}) async {
    if (!mounted) return false;
    final notifier = context.read<AIPromptInputBloc>().aiModelStateNotifier;
    final (sessionModels, selectedModel) = notifier.getModelSelection();

    debugPrint(
      '[MobileAI] _ensureModelSupportsImages: '
      'selectedModel=${selectedModel?.name ?? 'null'}, '
      'sessionModels.length=${sessionModels.length}',
    );

    if (AIModelCapabilities.supportsAIModelPB(selectedModel)) {
      debugPrint('[MobileAI] 当前模型已支持图片，无需切换');
      return true;
    }

    // 依次尝试 3 种数据源读取模型列表
    List<AIModelPB>? allModels;

    // 数据源 1：全局设置模型
    try {
      final result = await AIEventGetSettingModelSelection(
        ModelSourcePB(source: kGlobalAIModelSource),
      ).send();
      allModels = result.fold(
        (ms) {
          debugPrint('[MobileAI] 全局设置模型数量: ${ms.models.length}');
          for (final m in ms.models) {
            debugPrint('  - ${m.name} (isLocal=${m.isLocal})');
          }
          return ms.models;
        },
        (err) {
          debugPrint('[MobileAI] 读取全局设置失败: ${err.msg}');
          return null;
        },
      );
    } catch (e) {
      debugPrint('[MobileAI] 读取全局设置异常: $e');
    }

    // 数据源 2：本地模型
    if ((allModels == null || allModels.isEmpty) && mounted) {
      try {
        final result = await AIEventGetLocalModelSelection().send();
        allModels = result.fold(
          (ms) {
            debugPrint('[MobileAI] 本地模型数量: ${ms.models.length}');
            return ms.models;
          },
          (err) {
            debugPrint('[MobileAI] 读取本地模型失败: ${err.msg}');
            return null;
          },
        );
      } catch (e) {
        debugPrint('[MobileAI] 读取本地模型异常: $e');
      }
    }

    // 数据源 3：当前会话模型（作为最后 fallback）
    if ((allModels == null || allModels.isEmpty) && sessionModels.isNotEmpty) {
      debugPrint('[MobileAI] 使用当前会话模型: ${sessionModels.length}');
      allModels = sessionModels;
    }

    if (allModels == null || allModels.isEmpty) {
      if (showHint && mounted) {
        _showToast('当前无可用模型，请检查网络或 AI 配置');
      }
      debugPrint('[MobileAI] 所有数据源均无模型，放弃切换');
      return false;
    }

    // 过滤出支持图片的模型（诊断日志已内置在 AIModelCapabilities.supportsAIModelPB）
    final multimodalModels =
        allModels.where(AIModelCapabilities.supportsAIModelPB).toList();
    if (multimodalModels.isEmpty) {
      debugPrint('[MobileAI] 可用模型中无多模态模型: ${allModels.map((m) => m.name).join(', ')}');
      if (showHint && mounted) {
        _showToast('当前无可支持图片的多模态模型');
      }
      return false;
    }

    final newModel = multimodalModels.first;
    final oldName = selectedModel?.name ?? 'null';
    debugPrint(
      '[MobileAI] 自动切换: $oldName → ${newModel.name} (source=${notifier.objectId})',
    );

    // 调用后端切换模型
    final payload = UpdateSelectedModelPB(
      source: notifier.objectId,
      selectedModel: newModel,
    );
    final result = await AIEventUpdateSelectedModel(payload).send();
    if (result.isFailure) {
      final err = result.fold((_) => null, (err) => err);
      debugPrint('[MobileAI] 切换模型失败: ${err?.msg ?? '未知错误'}');
      if (showHint && mounted) {
        _showToast('切换模型失败：${err?.msg ?? '请稍后重试'}');
      }
      return false;
    }

    if (showHint && mounted) {
      _showToast('已自动切换到 ${newModel.i18n}');
    }
    return true;
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget sendButton() {
    final isStreaming = widget.isStreaming;
    final isEnabled = !isStreaming;
    return GestureDetector(
      onTap: isEnabled ? handleSendPressed : widget.onStopStreaming,
      child: SizedBox(
        width: 28,
        height: 28,
        child: isStreaming
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
    );
  }

  Future<void> handleSendPressed() async {
    final bloc = context.read<AIPromptInputBloc>();
    final canUseAI = await context.checkAndHandleAIChatLimit();
    if (!canUseAI) return;

    if (widget.isStreaming) return;
    final trimmedText = textController.text.trim();
    if (trimmedText.isEmpty) return;

    // 【PonyNotes】如果当前消息包含图片附件，确保模型支持多模态（DeepSeek 不支持图片）
    // - 必须在 consumeMetadata() 之前执行，否则附件已被清空，无法再判断
    final hasImageAttachment = bloc.state.attachedFiles.any(
      (f) => _isImageExtension(f.filePath),
    );
    if (hasImageAttachment) {
      // 显示提示框说明切换
      if (!mounted) return;
      final ok = await _ensureModelSupportsImages(showHint: true);
      // 切换成功与否都继续：失败时让后端返回错误，行为更透明
      if (!ok) {
        debugPrint('[MobileAI] 自动切换模型失败，仍尝试发送，可能后端会拒绝');
      }
    }

    textController.clear();
    onSubmitText(trimmedText);
  }

  /// 判断文件名是否为图片（基于扩展名）
  bool _isImageExtension(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'gif' ||
        ext == 'webp';
  }

  Future<void> onSubmitText(String text) async {
    final metadata =
        await context.read<AIPromptInputBloc>().consumeMetadata();

    final bloc = context.read<AIPromptInputBloc>();
    final showPredefinedFormats = bloc.state.showPredefinedFormats;
    final predefinedFormat = bloc.state.predefinedFormat;

    widget.onSubmitted(
      text,
      showPredefinedFormats ? predefinedFormat : null,
      metadata,
    );
  }

  Future<void> checkForAskingAI() async {
    if (!PlatformInfo.isMobile) return;
    final paletteBloc = context.read<CommandPaletteBloc?>(),
        paletteState = paletteBloc?.state;
    if (paletteBloc == null || paletteState == null) return;
    final isAskingAI = paletteState.askAI;
    if (!isAskingAI) return;
    paletteBloc.add(CommandPaletteEvent.askedAI());
    final query = paletteState.query ?? '';
    if (query.isEmpty) return;
    final sources =
        (paletteState.askAISources ?? []).map((e) => e.id).toList();
    final metadata =
        await context.read<AIPromptInputBloc?>()?.consumeMetadata() ?? {};
    final promptState = context.read<AIPromptInputBloc?>()?.state;
    final predefinedFormat = promptState?.predefinedFormat;
    if (sources.isNotEmpty) {
      widget.onUpdateSelectedSources(sources);
    }
    widget.onSubmitted.call(query, predefinedFormat, metadata);
  }

  void handleTextControllerChanged() {
    if (textController.value.isComposingRangeValid) {
      return;
    }
  }

  Future<void> mentionPage(BuildContext context) async {
    inputControlCubit.refreshViews();
    inputControlCubit.startSearching(textController.value);
    if (focusNode.hasFocus) {
      focusNode.unfocus();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (context.mounted) {
      final selectedView = await showPageSelectorSheet(
        context,
        filter: (view) =>
            !view.isSpace &&
            view.layout.isDocumentView &&
            view.parentViewId != view.id &&
            !inputControlCubit.selectedViewIds.contains(view.id),
      );
      if (selectedView != null) {
        final newText = textController.text.replaceRange(
          inputControlCubit.filterStartPosition,
          inputControlCubit.filterStartPosition,
          selectedView.id,
        );
        textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: textController.selection.baseOffset + selectedView.id.length,
            affinity: TextAffinity.upstream,
          ),
        );

        inputControlCubit.selectPage(selectedView);
      }
      focusNode.requestFocus();
      inputControlCubit.reset();
    }
  }

  Widget inputTextField(BuildContext context) {
    return BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
      builder: (context, state) {
        return ExtendedTextField(
          controller: textController,
          focusNode: focusNode,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
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
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            hintText: state.modelState.hintText,
            hintStyle: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 13,
            ),
            filled: false,
            fillColor: null,
          ),
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontSize: 13),
          specialTextSpanBuilder: PromptInputTextSpanBuilder(
            inputControlCubit: inputControlCubit,
            mentionedPageTextStyle:
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
          ),
          onTapOutside: (_) => focusNode.unfocus(),
        );
      },
    );
  }
}

/// 模型按钮内容：通过 SelectModelBloc 监听模型列表变化
class _ModelButtonContent extends StatelessWidget {
  const _ModelButtonContent({required this.aiModelStateNotifier});

  final AIModelStateNotifier aiModelStateNotifier;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SelectModelBloc, SelectModelState>(
      builder: (context, state) {
        final model = state.selectedModel;
        final modelName = model?.i18n ?? '';
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor =
            isDark ? const Color(0xFFB0B0B0) : const Color(0xFF636363);
        final borderColor =
            isDark ? const Color(0xFF4A4A4A) : const Color(0xFFCDCDCD);
        final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;

        return GestureDetector(
          onTap: () => _showModelSelector(context, state),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child:             Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (modelName.isNotEmpty)
                  Text(
                    modelName,
                    style: TextStyle(fontSize: 11, color: textColor),
                  ),
                const SizedBox(width: 3),
                Icon(Icons.expand_more, size: 14, color: textColor),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showModelSelector(BuildContext context, SelectModelState state) {
    final models = state.models;
    final selectedModel = state.selectedModel;
    if (models.isEmpty) return;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  children: models.map((model) {
                    final isSelected = selectedModel?.name == model.name;
                    return InkWell(
                      onTap: () {
                        context
                            .read<SelectModelBloc>()
                            .add(SelectModelEvent.selectModel(model));
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        color: isSelected
                            ? Theme.of(ctx)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3)
                            : null,
                        child: Text(
                          model.i18n,
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
}
