import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/ai/service/ai_prompt_input_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_input_file_bloc.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:styled_widget/styled_widget.dart';

import 'layout_define.dart';

class PromptInputFile extends StatefulWidget {
  const PromptInputFile({
    super.key,
    required this.onDeleted,
  });

  final void Function(ChatFile) onDeleted;

  @override
  State<PromptInputFile> createState() => _PromptInputFileState();
}

class _PromptInputFileState extends State<PromptInputFile> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<AIPromptInputBloc, AIPromptInputState, List<ChatFile>>(
      selector: (state) => state.attachedFiles,
      builder: (context, files) {
        if (files.isEmpty) {
          return const SizedBox.shrink();
        }
        return Scrollbar(
          controller: _scrollController,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: DesktopAIPromptSizes.attachedFilesBarPadding -
                const EdgeInsets.only(top: 6),
            separatorBuilder: (context, index) => const HSpace(
              DesktopAIPromptSizes.attachedFilesPreviewSpacing - 6,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) => ChatFilePreview(
              file: files[index],
              onDeleted: () => widget.onDeleted(files[index]),
            ),
          ),
        );
      },
    );
  }
}

class ChatFilePreview extends StatefulWidget {
  const ChatFilePreview({
    required this.file,
    required this.onDeleted,
    super.key,
  });

  final ChatFile file;
  final VoidCallback onDeleted;

  @override
  State<ChatFilePreview> createState() => _ChatFilePreviewState();
}

class _ChatFilePreviewState extends State<ChatFilePreview> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatInputFileBloc(file: widget.file),
      child: BlocBuilder<ChatInputFileBloc, ChatInputFileState>(
        builder: (context, state) {
          return MouseRegion(
            onEnter: (_) => setHover(true),
            onExit: (_) => setHover(false),
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsetsDirectional.only(top: 4, end: 4),
                  constraints: const BoxConstraints(maxWidth: 240),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AFThemeExtension.of(context).tint1,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        height: 28,
                        width: 28,
                        child: Center(
                          child: FlowySvg(
                            FlowySvgs.page_m,
                            size: const Size.square(14),
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                      const HSpace(6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FlowyText(
                              widget.file.fileName,
                              fontSize: 11.0,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            FlowyText(
                              widget.file.fileType.name,
                              color: Theme.of(context).hintColor,
                              fontSize: 10.0,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isHover)
                  _CloseButton(
                    onTap: widget.onDeleted,
                  ).positioned(top: 0, right: 0),
              ],
            ),
          );
        },
      ),
    );
  }

  void setHover(bool value) {
    if (value != isHover) {
      setState(() => isHover = value);
    }
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: FlowySvg(
          FlowySvgs.ai_close_filled_s,
          color: AFThemeExtension.of(context).greyHover,
          size: const Size.square(16),
        ),
      ),
    );
  }
}
