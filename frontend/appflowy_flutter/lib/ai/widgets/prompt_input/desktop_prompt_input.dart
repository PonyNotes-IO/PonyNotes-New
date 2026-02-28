import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_input_control_cubit.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_user_cubit.dart';
import 'package:appflowy/plugins/ai_chat/presentation/layout_define.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';

// PonyNotes: 添加使用次数相关的protobuf导入
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// PonyNotes: 添加使用次数相关导入
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import '../../../plugins/ai_chat/application/chat_bloc.dart';
import 'browse_prompts_button.dart';

typedef OnPromptInputSubmitted = void Function(
  String input,
  PredefinedFormat? predefinedFormat,
  Map<String, dynamic> metadata,
  String? promptId,
);

class DesktopPromptInput extends StatefulWidget {
  const DesktopPromptInput({
    super.key,
    required this.isStreaming,
    required this.textController,
    required this.onStopStreaming,
    required this.onSubmitted,
    required this.selectedSourcesNotifier,
    required this.onUpdateSelectedSources,
    this.hideDecoration = false,
    this.hideFormats = false,
    this.extraBottomActionButton,
  });

  final bool isStreaming;
  final AiPromptInputTextEditingController textController;
  final void Function() onStopStreaming;
  final OnPromptInputSubmitted onSubmitted;
  final ValueNotifier<List<String>> selectedSourcesNotifier;
  final void Function(List<String>) onUpdateSelectedSources;
  final bool hideDecoration;
  final bool hideFormats;
  final Widget? extraBottomActionButton;

  @override
  State<DesktopPromptInput> createState() => _DesktopPromptInputState();
}

class _DesktopPromptInputState extends State<DesktopPromptInput> {
  static const double _extraInputHeight = 30.0;
  final textFieldKey = GlobalKey();
  final layerLink = LayerLink();
  final overlayController = OverlayPortalController();
  final inputControlCubit = ChatInputControlCubit();
  final chatUserCubit = ChatUserCubit();
  final focusNode = FocusNode();

  late SendButtonState sendButtonState;
  bool isComposing = false;

  @override
  void initState() {
    super.initState();

    widget.textController.addListener(handleTextControllerChanged);
    focusNode
      ..addListener(
        () {
          if (!widget.hideDecoration) {
            setState(() {}); // refresh border color
          }
          if (!focusNode.hasFocus) {
            cancelMentionPage(); // hide menu when lost focus
          }
        },
      )
      ..onKeyEvent = handleKeyEvent;

    updateSendButtonState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
      checkForAskingAI();
    });
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    updateSendButtonState();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    focusNode.dispose();
    widget.textController.removeListener(handleTextControllerChanged);
    inputControlCubit.close();
    chatUserCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: inputControlCubit),
        BlocProvider.value(value: chatUserCubit),
      ],
      child: BlocListener<ChatInputControlCubit, ChatInputControlState>(
        listener: (context, state) {
          state.maybeWhen(
            updateSelectedViews: (selectedViews) {
              context
                  .read<AIPromptInputBloc>()
                  .add(AIPromptInputEvent.updateMentionedViews(selectedViews));
            },
            orElse: () {},
          );
        },
        child: OverlayPortal(
          controller: overlayController,
          overlayChildBuilder: (context) {
            return PromptInputMentionPageMenu(
              anchor: PromptInputAnchor(textFieldKey, layerLink),
              textController: widget.textController,
              onPageSelected: handlePageSelected,
            );
          },
          child: DecoratedBox(
            decoration: decoration(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        DesktopAIPromptSizes.attachedFilesBarPadding.vertical +
                            DesktopAIPromptSizes.attachedFilesPreviewHeight,
                  ),
                  child: TextFieldTapRegion(
                    child: PromptInputFile(
                      onDeleted: (file) => context
                          .read<AIPromptInputBloc>()
                          .add(AIPromptInputEvent.removeFile(file)),
                    ),
                  ),
                ),
                const VSpace(4.0),
                BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
                  builder: (context, state) {
                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ConstrainedBox(
                            constraints: getTextFieldConstraints(
                              state.showPredefinedFormats && !widget.hideFormats,
                            ),
                            child: inputTextField(),
                          ),
                        ),
                        if (state.showPredefinedFormats && !widget.hideFormats)
                          Positioned.fill(
                            bottom: null,
                            child: TextFieldTapRegion(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 8.0,
                                ),
                                child: ChangeFormatBar(
                                  showImageFormats:
                                      state.modelState.type == AiType.cloud,
                                  predefinedFormat: state.predefinedFormat,
                                  spacing: 4.0,
                                  onSelectPredefinedFormat: (format) =>
                                      context.read<AIPromptInputBloc>().add(
                                            AIPromptInputEvent
                                                .updatePredefinedFormat(format),
                                          ),
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          top: null,
                          child: TextFieldTapRegion(
                            child: _PromptBottomActions(
                              showPredefinedFormatBar:
                                  state.showPredefinedFormats,
                              showPredefinedFormatButton: !widget.hideFormats,
                              onTogglePredefinedFormatSection: () =>
                                  context.read<AIPromptInputBloc>().add(
                                        AIPromptInputEvent
                                            .toggleShowPredefinedFormat(),
                                      ),
                              onStartMention: startMentionPageFromButton,
                              sendButtonState: sendButtonState,
                              onSendPressed: handleSend,
                              onStopStreaming: widget.onStopStreaming,
                              selectedSourcesNotifier:
                                  widget.selectedSourcesNotifier,
                              onUpdateSelectedSources:
                                  widget.onUpdateSelectedSources,
                              onSelectPrompt: handleOnSelectPrompt,
                              extraBottomActionButton:
                                  widget.extraBottomActionButton,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration decoration(BuildContext context) {
    if (widget.hideDecoration) {
      return BoxDecoration();
    }
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(
        color: focusNode.hasFocus
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
        width: focusNode.hasFocus ? 1.5 : 1.0,
      ),
      borderRadius: const BorderRadius.all(Radius.circular(12.0)),
    );
  }

  Future<void> checkForAskingAI() async {
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
    final promptBloc = context.read<AIPromptInputBloc?>();
    final promptId = promptBloc?.promptId;
    final promptState = promptBloc?.state;
    final predefinedFormat = promptState?.predefinedFormat;
    if (sources.isNotEmpty) {
      widget.onUpdateSelectedSources(sources);
    }
    widget.onSubmitted.call(query, predefinedFormat, metadata, promptId ?? '');
  }

  void startMentionPageFromButton() {
    if (overlayController.isShowing) {
      return;
    }
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
    widget.textController.text += '@';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context
            .read<ChatInputControlCubit>()
            .startSearching(widget.textController.value);
        overlayController.show();
      }
    });
  }

  void cancelMentionPage() {
    if (overlayController.isShowing) {
      inputControlCubit.reset();
      overlayController.hide();
    }
  }

  void updateSendButtonState() {
    if (widget.isStreaming) {
      sendButtonState = SendButtonState.streaming;
    } else if (widget.textController.text.trim().isEmpty) {
      sendButtonState = SendButtonState.disabled;
    } else {
      sendButtonState = SendButtonState.enabled;
    }
  }

  Future<void> handleSend() async {
    if (widget.isStreaming) {
      return;
    }
    // 检查AI对话限制
    final canUseAI = await context.checkAndHandleAIChatLimit();
    if (!canUseAI) {
      return;
    }
    String userInput = widget.textController.text.trim();
    userInput = inputControlCubit.formatIntputText(userInput);
    userInput = AiPromptInputTextEditingController.restore(userInput);

    widget.textController.clear();
    if (userInput.isEmpty) {
      return;
    }

    // get the attached files and mentioned pages (异步处理图片)
    final metadata = await context.read<AIPromptInputBloc>().consumeMetadata();

    final bloc = context.read<AIPromptInputBloc>();
    final showPredefinedFormats = bloc.state.showPredefinedFormats;
    final predefinedFormat = bloc.state.predefinedFormat;

    widget.onSubmitted(
      userInput,
      showPredefinedFormats ? predefinedFormat : null,
      metadata,
      bloc.promptId,
    );
  }

  void handleTextControllerChanged() {
    setState(() {
      // update whether send button is clickable
      updateSendButtonState();
      isComposing = !widget.textController.value.composing.isCollapsed;
    });

    if (isComposing) {
      return;
    }

    // disable mention
    return;

    // handle text and selection changes ONLY when mentioning a page
    // ignore: dead_code
    if (!overlayController.isShowing ||
        inputControlCubit.filterStartPosition == -1) {
      return;
    }

    // handle cases where mention a page is cancelled
    final textController = widget.textController;
    final textSelection = textController.value.selection;
    final isSelectingMultipleCharacters = !textSelection.isCollapsed;
    final isCaretBeforeStartOfRange =
        textSelection.baseOffset < inputControlCubit.filterStartPosition;
    final isCaretAfterEndOfRange =
        textSelection.baseOffset > inputControlCubit.filterEndPosition;
    final isTextSame = inputControlCubit.inputText == textController.text;

    if (isSelectingMultipleCharacters ||
        isTextSame && (isCaretBeforeStartOfRange || isCaretAfterEndOfRange)) {
      cancelMentionPage();
      return;
    }

    final previousLength = inputControlCubit.inputText.characters.length;
    final currentLength = textController.text.characters.length;

    // delete "@"
    if (previousLength != currentLength && isCaretBeforeStartOfRange) {
      cancelMentionPage();
      return;
    }

    // handle cases where mention the filter is updated
    if (previousLength != currentLength) {
      final diff = currentLength - previousLength;
      final newEndPosition = inputControlCubit.filterEndPosition + diff;
      final newFilter = textController.text.substring(
        inputControlCubit.filterStartPosition,
        newEndPosition,
      );
      inputControlCubit.updateFilter(
        textController.text,
        newFilter,
        newEndPosition: newEndPosition,
      );
    } else if (!isTextSame) {
      final newFilter = textController.text.substring(
        inputControlCubit.filterStartPosition,
        inputControlCubit.filterEndPosition,
      );
      inputControlCubit.updateFilter(textController.text, newFilter);
    }
  }

  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    // if (event.character == '@') {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     inputControlCubit.startSearching(widget.textController.value);
    //     overlayController.show();
    //   });
    // }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void handlePageSelected(ViewPB view) {
    final newText = widget.textController.text.replaceRange(
      inputControlCubit.filterStartPosition,
      inputControlCubit.filterEndPosition,
      view.id,
    );
    widget.textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: inputControlCubit.filterStartPosition + view.id.length,
        affinity: TextAffinity.upstream,
      ),
    );

    inputControlCubit.selectPage(view);
    overlayController.hide();
  }

  Widget inputTextField() {
    return Shortcuts(
      shortcuts: buildShortcuts(),
      child: Actions(
        actions: buildActions(),
        child: CompositedTransformTarget(
          link: layerLink,
          child: BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
            builder: (context, state) {
              Widget textField = PromptInputTextField(
                key: textFieldKey,
                editable: state.modelState.isEditable,
                cubit: inputControlCubit,
                textController: widget.textController,
                textFieldFocusNode: focusNode,
                contentPadding:
                    calculateContentPadding(state.showPredefinedFormats),
                hintText: state.modelState.hintText,
              );

              if (state.modelState.tooltip != null) {
                textField = FlowyTooltip(
                  message: state.modelState.tooltip!,
                  child: textField,
                );
              }

              return textField;
            },
          ),
        ),
      ),
    );
  }

  BoxConstraints getTextFieldConstraints(bool showPredefinedFormats) {
    double minHeight = DesktopAIPromptSizes.textFieldMinHeight +
        DesktopAIPromptSizes.actionBarSendButtonSize +
        DesktopAIChatSizes.inputActionBarMargin.vertical +
        _extraInputHeight;
    double maxHeight = 300;
    if (showPredefinedFormats) {
      minHeight += DesktopAIPromptSizes.predefinedFormatButtonHeight;
      maxHeight += DesktopAIPromptSizes.predefinedFormatButtonHeight;
    }
    return BoxConstraints(minHeight: minHeight, maxHeight: maxHeight);
  }

  EdgeInsetsGeometry calculateContentPadding(bool showPredefinedFormats) {
    final top = showPredefinedFormats
        ? DesktopAIPromptSizes.predefinedFormatButtonHeight
        : 0.0;
    final bottom = DesktopAIPromptSizes.actionBarSendButtonSize +
        DesktopAIChatSizes.inputActionBarMargin.vertical;

    // 修复：将top padding设置为0，确保文字从顶部开始显示
    // textAlignVertical.top 需要配合 top padding = 0 才能生效
    final basePadding = DesktopAIPromptSizes.textFieldContentPadding;
    return EdgeInsets.only(
      left: basePadding.horizontal / 2,
      right: basePadding.horizontal / 2,
      top: top,
      // top padding 设置为0（当showPredefinedFormats为false时）或predefinedFormatButtonHeight
      bottom: bottom,
    );
  }

  Map<ShortcutActivator, Intent> buildShortcuts() {
    if (isComposing) {
      return const {};
    }

    return const {
      SingleActivator(LogicalKeyboardKey.arrowUp): _FocusPreviousItemIntent(),
      SingleActivator(LogicalKeyboardKey.arrowDown): _FocusNextItemIntent(),
      SingleActivator(LogicalKeyboardKey.escape): _CancelMentionPageIntent(),
      SingleActivator(LogicalKeyboardKey.enter): _SubmitOrMentionPageIntent(),
    };
  }

  Map<Type, Action<Intent>> buildActions() {
    return {
      _FocusPreviousItemIntent: CallbackAction<_FocusPreviousItemIntent>(
        onInvoke: (intent) {
          inputControlCubit.updateSelectionUp();
          return;
        },
      ),
      _FocusNextItemIntent: CallbackAction<_FocusNextItemIntent>(
        onInvoke: (intent) {
          inputControlCubit.updateSelectionDown();
          return;
        },
      ),
      _CancelMentionPageIntent: CallbackAction<_CancelMentionPageIntent>(
        onInvoke: (intent) {
          cancelMentionPage();
          return;
        },
      ),
      _SubmitOrMentionPageIntent: CallbackAction<_SubmitOrMentionPageIntent>(
        onInvoke: (intent) {
          if (overlayController.isShowing) {
            inputControlCubit.state.maybeWhen(
              ready: (visibleViews, focusedViewIndex) {
                if (focusedViewIndex != -1 &&
                    focusedViewIndex < visibleViews.length) {
                  handlePageSelected(visibleViews[focusedViewIndex]);
                }
              },
              orElse: () {},
            );
          } else {
            handleSend(); // 异步调用，但不等待结果
          }
          return;
        },
      ),
    };
  }

  void handleOnSelectPrompt(AiPrompt prompt) {
    final bloc = context.read<AIPromptInputBloc>();
    bloc
      ..add(AIPromptInputEvent.updateMentionedViews([]))
      ..add(AIPromptInputEvent.updatePromptId(prompt.id));

    final content = AiPromptInputTextEditingController.replace(prompt.content);

    widget.textController.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(
        offset: content.length,
      ),
    );

    if (bloc.state.showPredefinedFormats) {
      bloc.add(
        AIPromptInputEvent.toggleShowPredefinedFormat(),
      );
    }
  }
}

class _SubmitOrMentionPageIntent extends Intent {
  const _SubmitOrMentionPageIntent();
}

class _CancelMentionPageIntent extends Intent {
  const _CancelMentionPageIntent();
}

class _FocusPreviousItemIntent extends Intent {
  const _FocusPreviousItemIntent();
}

class _FocusNextItemIntent extends Intent {
  const _FocusNextItemIntent();
}

class PromptInputTextField extends StatelessWidget {
  const PromptInputTextField({
    super.key,
    required this.editable,
    required this.cubit,
    required this.textController,
    required this.textFieldFocusNode,
    required this.contentPadding,
    this.hintText = "",
  });

  final ChatInputControlCubit cubit;
  final TextEditingController textController;
  final FocusNode textFieldFocusNode;
  final EdgeInsetsGeometry contentPadding;
  final bool editable;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return TextField(
      controller: textController,
      focusNode: textFieldFocusNode,
      readOnly: !editable,
      enabled: editable,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        // 修复：确保contentPadding的top为0，让文字从顶部开始
        contentPadding: EdgeInsets.only(
          left: contentPadding.resolve(TextDirection.ltr).left,
          right: contentPadding.resolve(TextDirection.ltr).right,
          top: 0, // 强制top为0
          bottom: contentPadding.resolve(TextDirection.ltr).bottom,
        ),
        hintText: hintText,
        hintStyle: inputHintTextStyle(context),
        isCollapsed: true,
        isDense: true,
      ),
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      minLines: 1,
      maxLines: null,
      style: theme.textStyle.body.standard(
        color: theme.textColorScheme.primary,
      ),
    );
  }

  TextStyle? inputHintTextStyle(BuildContext context) {
    return AppFlowyTheme.of(context).textStyle.body.standard(
          color: Theme.of(context).isLightMode
              ? const Color(0xFFBDC2C8)
              : const Color(0xFF3C3E51),
        );
  }
}

class _PromptBottomActions extends StatelessWidget {
  const _PromptBottomActions({
    required this.sendButtonState,
    required this.showPredefinedFormatBar,
    required this.showPredefinedFormatButton,
    required this.onTogglePredefinedFormatSection,
    required this.onStartMention,
    required this.onSendPressed,
    required this.onStopStreaming,
    required this.selectedSourcesNotifier,
    required this.onUpdateSelectedSources,
    required this.onSelectPrompt,
    this.extraBottomActionButton,
  });

  final bool showPredefinedFormatBar;
  final bool showPredefinedFormatButton;
  final void Function() onTogglePredefinedFormatSection;
  final void Function() onStartMention;
  final SendButtonState sendButtonState;
  final void Function() onSendPressed;
  final void Function() onStopStreaming;
  final ValueNotifier<List<String>> selectedSourcesNotifier;
  final void Function(List<String>) onUpdateSelectedSources;
  final void Function(AiPrompt) onSelectPrompt;
  final Widget? extraBottomActionButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesktopAIPromptSizes.actionBarSendButtonSize,
      margin: DesktopAIChatSizes.inputActionBarMargin,
      child: BlocBuilder<AIPromptInputBloc, AIPromptInputState>(
        builder: (context, state) {
          return Row(
            spacing: DesktopAIChatSizes.inputActionBarButtonSpacing,
            children: [
              // PonyNotes: 精简底部工具栏，移除"浏览提示词"和来源选择，只保留必要功能
              if (showPredefinedFormatButton) _predefinedFormatButton(),
              _selectModelButton(context),
              // PonyNotes: 添加深度思考按钮
              const SizedBox(width: 10),
              _buildDeepThinkingButton(context, state),
              // PonyNotes: 添加联网搜索按钮
              const SizedBox(width: 10),
              _buildWebSearchButton(context, state),

              const Spacer(),

              // PonyNotes: 添加使用次数显示
              _buildAIUsageIndicator(context),
              const SizedBox(width: 10),
              if (extraBottomActionButton != null) extraBottomActionButton!,
              // PonyNotes: 始终显示附件上传按钮（支持图片和文件）
              _buildAttachmentButton(context),
              const SizedBox(width: 10),
              _sendButton(),
            ],
          );
        },
      ),
    );
  }

  Widget _predefinedFormatButton() {
    return PromptInputDesktopToggleFormatButton(
      showFormatBar: showPredefinedFormatBar,
      onTap: onTogglePredefinedFormatSection,
    );
  }

  Widget _selectSourcesButton() {
    return PromptInputDesktopSelectSourcesButton(
      onUpdateSelectedSources: onUpdateSelectedSources,
      selectedSourcesNotifier: selectedSourcesNotifier,
    );
  }

  Widget _selectModelButton(BuildContext context) {
    return SelectModelMenu(
      aiModelStateNotifier:
          context.read<AIPromptInputBloc>().aiModelStateNotifier,
    );
  }

  Widget _buildBrowsePromptsButton() {
    return BrowsePromptsButton(
      onSelectPrompt: onSelectPrompt,
    );
  }

  // Widget _mentionButton(BuildContext context) {
  //   return PromptInputMentionButton(
  //     iconSize: DesktopAIPromptSizes.actionBarIconSize,
  //     buttonSize: DesktopAIPromptSizes.actionBarButtonSize,
  //     onTap: onStartMention,
  //   );
  // }

  Widget _attachmentButton(BuildContext context) {
    return PromptInputAttachmentButton(
      onTap: () async {
        final path = await getIt<FilePickerService>().pickFiles(
          dialogTitle: '',
          type: FileType.custom,
          allowedExtensions: ["pdf", "txt", "md"],
        );

        if (path == null) {
          return;
        }

        for (final file in path.files) {
          if (file.path != null && context.mounted) {
            context
                .read<AIPromptInputBloc>()
                .add(AIPromptInputEvent.attachFile(file.path!, file.name));
          }
        }
      },
    );
  }

  Widget _sendButton() {
    return PromptInputSendButton(
      state: sendButtonState,
      onSendPressed: onSendPressed,
      onStopStreaming: onStopStreaming,
    );
  }

  /// PonyNotes: 构建附件上传按钮（支持图片和文件）
  Widget _buildAttachmentButton(BuildContext context) {
    // 有附件时显示选中状态
    final hasAttachments = context.select<AIPromptInputBloc, bool>(
      (bloc) => bloc.state.attachedFiles.isNotEmpty,
    );
    // 有功能开关开启时禁用附件上传
    final isDisabled = context.select<AIPromptInputBloc, bool>(
      (bloc) => bloc.state.enableDeepThinking || bloc.state.enableWebSearch,
    );

    return FlowyTooltip(
      message: isDisabled
          ? '开启深度思考或联网搜索后不支持上传附件'
          : (hasAttachments ? '已添加附件' : '上传附件'),
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () async {
                // 打开文件选择器，支持所有文件类型
                final result = await getIt<FilePickerService>().pickFiles(
                  dialogTitle: '选择附件',
                  type: FileType.any, // 支持所有文件类型
                  allowMultiple: true,
                );

                if (result == null || result.files.isEmpty) {
                  return;
                }

                for (final file in result.files) {
                  if (file.path != null && context.mounted) {
                    context.read<AIPromptInputBloc>().add(
                        AIPromptInputEvent.attachFile(file.path!, file.name));
                  }
                }
              },
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            isDisabled ? Icons.attach_file : Icons.attach_file,
            size: 20,
            color: isDisabled
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  /// PonyNotes: 构建深度思考按钮（适配深色模式）
  Widget _buildDeepThinkingButton(
      BuildContext context, AIPromptInputState state) {
    final isEnabled = state.enableDeepThinking;
    // 有附件时禁用
    final isDisabled = state.attachedFiles.isNotEmpty;
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

    return FlowyTooltip(
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
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '深度思考',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
                fontFamily: 'PingFangSC-Medium',
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// PonyNotes: 构建联网搜索按钮（适配深色模式）
  Widget _buildWebSearchButton(BuildContext context, AIPromptInputState state) {
    final isEnabled = state.enableWebSearch;
    // 有附件时禁用
    final isDisabled = state.attachedFiles.isNotEmpty;
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

    return FlowyTooltip(
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
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '联网搜索',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
                fontFamily: 'PingFangSC-Medium',
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// PonyNotes: 构建AI使用次数显示
  Widget _buildAIUsageIndicator(BuildContext context) {
    return _AIUsageIndicatorWidget();
  }
}

/// PonyNotes: AI使用次数显示组件（需要异步加载数据）
class _AIUsageIndicatorWidget extends StatefulWidget {
  @override
  State<_AIUsageIndicatorWidget> createState() =>
      _AIUsageIndicatorWidgetState();
}

class _AIUsageIndicatorWidgetState extends State<_AIUsageIndicatorWidget> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(builder: (context, state) {
      // 根据剩余次数选择颜色
      final textColor = _getUsageTextColor(
          context, (state.usageInfo?.aiResponsesCountLimit.toInt() ?? 0) - (state.usageInfo?.aiResponsesCount.toInt() ?? 0)
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _getUsageDisplayText(
              state.usageInfo?.aiResponsesCount.toInt() ?? 0,
              state.usageInfo?.aiResponsesCountLimit.toInt() ?? 0,
              ),
          style: TextStyle(
            fontSize: 12,
            color: textColor,
          ),
        ),
      );
    });
  }

  String _getUsageDisplayText(int used, int total) {
    // PonyNotes: 只显示剩余可用次数，不显示已用/总数
    if ((total - used) <= 0) {
      return '0次可用';
    }
    return '${total - used}次可用';
  }

  Color _getUsageTextColor(BuildContext context, int remaining) {
    if (remaining <= 0) {
      return Colors.red;
    } else if (remaining <= 5) {
      return Colors.orange.shade700;
    } else {
      return Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    }
  }
}
