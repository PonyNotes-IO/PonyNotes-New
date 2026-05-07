import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/ai/service/ai_model_state_notifier.dart';
import 'package:appflowy/ai/service/select_model_bloc.dart';
import 'package:appflowy/ai/widgets/prompt_input/mentioned_page_text_span.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_input_control_cubit.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_bloc.dart';
import 'package:appflowy/plugins/ai_chat/presentation/layout_define.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

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

  late SendButtonState sendButtonState;

  @override
  void initState() {
    super.initState();

    textController.addListener(handleTextControllerChanged);
    // focusNode.onKeyEvent = handleKeyEvent;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
      checkForAskingAI();
    });

    updateSendButtonState();
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    updateSendButtonState();
    super.didUpdateWidget(oldWidget);
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
    return Hero(
      tag: "ai_chat_prompt",
      child: BlocProvider.value(
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
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
            ),
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
                    // 底部工具栏
                    _buildBottomToolbar(context, state),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// PonyNotes: 构建底部工具栏 - 参考桌面端设计，所有按钮在同一行
  Widget _buildBottomToolbar(BuildContext context, AIPromptInputState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 来源选择按钮
          PromptInputMobileSelectSourcesButton(
            selectedSourcesNotifier: widget.selectedSourcesNotifier,
            onUpdateSelectedSources: widget.onUpdateSelectedSources,
          ),
          const SizedBox(width: 2),
          // 格式切换按钮
          PromptInputMobileToggleFormatButton(
            showFormatBar: state.showPredefinedFormats,
            onTap: () {
              context
                  .read<AIPromptInputBloc>()
                  .add(AIPromptInputEvent.toggleShowPredefinedFormat());
            },
          ),
          const SizedBox(width: 2),
          // 模型选择按钮
          _MobileSelectModelButton(
            aiModelStateNotifier:
                context.read<AIPromptInputBloc>().aiModelStateNotifier,
          ),
          const SizedBox(width: 2),
          // 深度思考按钮
          _MobileDeepThinkingButton(
            isEnabled: state.enableDeepThinking,
            isDisabled: state.attachedFiles.isNotEmpty,
          ),
          const SizedBox(width: 2),
          // 联网搜索按钮
          _MobileWebSearchButton(
            isEnabled: state.enableWebSearch,
            isDisabled: state.attachedFiles.isNotEmpty,
          ),
          const SizedBox(width: 4),
          // 使用次数显示
          const _MobileAIUsageIndicator(),
          const SizedBox(width: 4),
          // 发送按钮
          sendButton(),
        ],
      ),
    );
  }

  void updateSendButtonState() {
    if (widget.isStreaming) {
      sendButtonState = SendButtonState.streaming;
    } else if (textController.text.trim().isEmpty) {
      sendButtonState = SendButtonState.disabled;
    } else {
      sendButtonState = SendButtonState.enabled;
    }
  }

  Future<void> handleSendPressed() async {
    // 检查AI对话限制
    final canUseAI = await context.checkAndHandleAIChatLimit();
    if (!canUseAI) {
      return;
    }

    if (widget.isStreaming) {
      return;
    }
    final trimmedText = inputControlCubit.formatIntputText(
      textController.text.trim(),
    );
    textController.clear();
    if (trimmedText.isEmpty) {
      return;
    }

    onSubmitText(trimmedText);
  }

  Future<void> onSubmitText(String text) async {
    // get the attached files and mentioned pages (异步处理图片)
    final metadata = await context.read<AIPromptInputBloc>().consumeMetadata();

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
    if (!UniversalPlatform.isMobile) return;
    final paletteBloc = context.read<CommandPaletteBloc?>(),
        paletteState = paletteBloc?.state;
    if (paletteBloc == null || paletteState == null) return;
    final isAskingAI = paletteState.askAI;
    if (!isAskingAI) return;
    paletteBloc.add(CommandPaletteEvent.askedAI());
    final query = paletteState.query ?? '';
    if (query.isEmpty) return;
    final sources = (paletteState.askAISources ?? []).map((e) => e.id).toList();
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
    // inputControlCubit.updateInputText(textController.text);
    setState(() => updateSendButtonState());
  }

  // KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
  //   if (event.character == '@') {
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       mentionPage(context);
  //     });
  //   }
  //   return KeyEventResult.ignored;
  // }

  Future<void> mentionPage(BuildContext context) async {
    // if the focus node is on focus, unfocus it for better animation
    // otherwise, the page sheet animation will be blocked by the keyboard
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
            offset:
                textController.selection.baseOffset + selectedView.id.length,
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
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.transparent, width: 0),
          ),
          child: ExtendedTextField(
            controller: textController,
            focusNode: focusNode,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              hintText: state.modelState.hintText,
              hintStyle: inputHintTextStyle(context),
              isCollapsed: true,
              isDense: true,
              filled: false,
            ),
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 6,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 20 / 14),
            specialTextSpanBuilder: PromptInputTextSpanBuilder(
              inputControlCubit: inputControlCubit,
              mentionedPageTextStyle:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
            ),
            onTapOutside: (_) => focusNode.unfocus(),
          ),
        );
      },
    );
  }

  TextStyle? inputHintTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).isLightMode
              ? const Color(0xFFBDC2C8)
              : const Color(0xFF3C3E51),
        );
  }

  Widget sendButton() {
    return PromptInputSendButton(
      state: sendButtonState,
      onSendPressed: handleSendPressed,
      onStopStreaming: widget.onStopStreaming,
    );
  }
}

/// PonyNotes: 移动端AI使用次数显示组件
class _MobileAIUsageIndicator extends StatelessWidget {
  const _MobileAIUsageIndicator();

  @override
  Widget build(BuildContext context) {
    final chatBloc = context.read<ChatBloc?>();
    if (chatBloc == null) {
      return const SizedBox.shrink();
    }
    return BlocBuilder<ChatBloc, ChatState>(
      bloc: chatBloc,
      builder: (context, state) {
        final used = state.usageInfo?.aiResponsesCount.toInt() ?? 0;
        final total = state.usageInfo?.aiResponsesCountLimit.toInt() ?? 0;
        final remaining = total - used;
        final textColor = remaining <= 0
            ? Colors.red
            : remaining <= 5
                ? Colors.orange.shade700
                : Theme.of(context).hintColor;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            remaining <= 0 ? '0次' : '$remaining次',
            style: TextStyle(fontSize: 10, color: textColor),
          ),
        );
      },
    );
  }
}

/// PonyNotes: 移动端深度思考按钮
class _MobileDeepThinkingButton extends StatelessWidget {
  const _MobileDeepThinkingButton({
    required this.isEnabled,
    required this.isDisabled,
  });

  final bool isEnabled;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDisabled
        ? isDarkMode
            ? const Color(0xFF333333)
            : const Color(0xFFE0E0E0)
        : isEnabled
            ? const Color(0xFFE94618)
            : isDarkMode
                ? const Color(0xFF4A4A4A)
                : const Color(0xFFCDCDCD);
    final textColor = isDisabled
        ? isDarkMode
            ? const Color(0xFF666666)
            : const Color(0xFFB0B0B0)
        : isEnabled
            ? const Color(0xFFE94618)
            : isDarkMode
                ? const Color(0xFFB0B0B0)
                : const Color(0xFF636363);
    final backgroundColor = isDisabled
        ? isDarkMode
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFF5F5F5)
        : isDarkMode
            ? const Color(0xFF2A2A2A)
            : Colors.white;

    return Tooltip(
      message: isDisabled ? '附件模式下不支持深度思考' : (isEnabled ? '关闭深度思考' : '开启深度思考'),
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                context
                    .read<AIPromptInputBloc>()
                    .add(const AIPromptInputEvent.toggleDeepThinking());
              },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '深度思考',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PonyNotes: 移动端联网搜索按钮
class _MobileWebSearchButton extends StatelessWidget {
  const _MobileWebSearchButton({
    required this.isEnabled,
    required this.isDisabled,
  });

  final bool isEnabled;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDisabled
        ? isDarkMode
            ? const Color(0xFF333333)
            : const Color(0xFFE0E0E0)
        : isEnabled
            ? const Color(0xFFE94618)
            : isDarkMode
                ? const Color(0xFF4A4A4A)
                : const Color(0xFFCDCDCD);
    final textColor = isDisabled
        ? isDarkMode
            ? const Color(0xFF666666)
            : const Color(0xFFB0B0B0)
        : isEnabled
            ? const Color(0xFFE94618)
            : isDarkMode
                ? const Color(0xFFB0B0B0)
                : const Color(0xFF636363);
    final backgroundColor = isDisabled
        ? isDarkMode
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFF5F5F5)
        : isDarkMode
            ? const Color(0xFF2A2A2A)
            : Colors.white;

    return Tooltip(
      message: isDisabled ? '附件模式下不支持联网搜索' : (isEnabled ? '关闭联网搜索' : '开启联网搜索'),
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                context
                    .read<AIPromptInputBloc>()
                    .add(const AIPromptInputEvent.toggleWebSearch());
              },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '联网搜索',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PonyNotes: 移动端模型选择按钮
class _MobileSelectModelButton extends StatelessWidget {
  const _MobileSelectModelButton({
    required this.aiModelStateNotifier,
  });

  final AIModelStateNotifier aiModelStateNotifier;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SelectModelBloc(
        aiModelStateNotifier: aiModelStateNotifier,
      ),
      child: _MobileSelectModelButtonContent(
        aiModelStateNotifier: aiModelStateNotifier,
      ),
    );
  }
}

class _MobileSelectModelButtonContent extends StatelessWidget {
  const _MobileSelectModelButtonContent({
    required this.aiModelStateNotifier,
  });

  final AIModelStateNotifier aiModelStateNotifier;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDarkMode
        ? const Color(0xFFB0B0B0)
        : const Color(0xFF858585);

    return BlocBuilder<SelectModelBloc, SelectModelState>(
      builder: (context, state) {
        final model = state.selectedModel;
        final modelName = model?.i18n ?? '';
        final isDefault = model?.isDefault ?? true;

        return GestureDetector(
          onTap: () => _showModelSelector(context),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF2A2A2A)
                  : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDarkMode
                    ? const Color(0xFF4A4A4A)
                    : const Color(0xFFCDCDCD),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: hintColor,
                ),
                const SizedBox(width: 2),
                if (modelName.isNotEmpty && !isDefault)
                  Text(
                    modelName,
                    style: TextStyle(
                      fontSize: 10,
                      color: hintColor,
                    ),
                  ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 12,
                  color: hintColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showModelSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (bottomSheetContext) => BlocProvider.value(
        value: context.read<SelectModelBloc>(),
        child: const _MobileModelSelectorSheet(),
      ),
    );
  }
}

/// PonyNotes: 移动端模型选择底部弹窗
class _MobileModelSelectorSheet extends StatelessWidget {
  const _MobileModelSelectorSheet();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SelectModelBloc, SelectModelState>(
      builder: (context, state) {
        final models = state.models;
        final selectedModel = state.selectedModel;

        if (models.isEmpty) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final localModels = models.where((m) => m.isLocal).toList();
        final cloudModels = models.where((m) => !m.isLocal).toList();

        return Container(
          constraints: const BoxConstraints(maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '选择模型',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (localModels.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          '本地模型',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ...localModels.map((model) => _buildModelItem(
                            context,
                            model,
                            model == selectedModel,
                          )),
                    ],
                    if (cloudModels.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          '云端模型',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ...cloudModels.map((model) => _buildModelItem(
                            context,
                            model,
                            model == selectedModel,
                          )),
                    ],
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModelItem(BuildContext context, AIModelPB model, bool isSelected) {
    return ListTile(
      dense: true,
      title: Text(model.i18n),
      subtitle: model.desc.isNotEmpty
          ? Text(
              model.desc,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            )
          : null,
      trailing: isSelected
          ? Icon(
              Icons.check,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: () {
        context
            .read<SelectModelBloc>()
            .add(SelectModelEvent.selectModel(model));
        Navigator.pop(context);
      },
    );
  }
}
