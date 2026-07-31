import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/ai/service/ai_model_state_notifier.dart';
import 'package:appflowy/ai/service/select_model_bloc.dart';
import 'package:appflowy/ai/widgets/prompt_input/mentioned_page_text_span.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_input_control_cubit.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_bloc.dart';
import 'package:appflowy/plugins/ai_chat/presentation/layout_define.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: _pickAttachment,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: FlowySvg(
            FlowySvgs.m_ai_attachment_m,
            size: const Size.square(24),
            color: iconColor,
          ),
        ),
      ),
    );
  }

  Future<void> _pickAttachment() async {
    // TODO: 对接附件上传逻辑，与桌面端保持一致
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
    final canUseAI = await context.checkAndHandleAIChatLimit();
    if (!canUseAI) return;

    if (widget.isStreaming) return;
    final trimmedText = textController.text.trim();
    if (trimmedText.isEmpty) return;
    textController.clear();
    onSubmitText(trimmedText);
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
