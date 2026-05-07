import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileAIInputBar extends StatelessWidget {
  final TextEditingController textController;
  final FocusNode focusNode;
  final List<ChatImage> selectedImages;
  final bool isSending;
  final bool isLoadingModels;
  final List<AIModel> availableModels;
  final AIModel? selectedModel;
  final bool isDeepThinkingEnabled;
  final bool isWebSearchEnabled;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final Function(int index) onRemoveImage;
  final Function(bool) onDeepThinkingChanged;
  final Function(bool) onWebSearchChanged;
  final Function(AIModel) onModelSelected;
  final AppFlowyThemeData afTheme;

  const MobileAIInputBar({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.selectedImages,
    required this.isSending,
    required this.isLoadingModels,
    required this.availableModels,
    required this.selectedModel,
    required this.isDeepThinkingEnabled,
    required this.isWebSearchEnabled,
    required this.onSend,
    required this.onPickImages,
    required this.onRemoveImage,
    required this.onDeepThinkingChanged,
    required this.onWebSearchChanged,
    required this.onModelSelected,
    required this.afTheme,
  });

  bool get _canSend =>
      textController.text.trim().isNotEmpty && !isSending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

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
            // Image attachment preview strip
            if (selectedImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: selectedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final image = selectedImages[index];
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
                            onTap: () => onRemoveImage(index),
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
              const SizedBox(height: 8),
            ],
            // Input area container (text input + bottom buttons)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Text input area
                    TextField(
                      controller: textController,
                      focusNode: focusNode,
                      maxLines: 6,
                      minLines: 6,
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
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Bottom button row
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Model selection button
                        _buildModelChip(context, theme),
                        const SizedBox(width: 4),
                        // Deep thinking button
                        _buildToggleChip(
                          context: context,
                          label: '思考',
                          icon: Icons.psychology_outlined,
                          isEnabled: isDeepThinkingEnabled,
                          onChanged: onDeepThinkingChanged,
                        ),
                        const SizedBox(width: 4),
                        // Web search button
                        _buildToggleChip(
                          context: context,
                          label: '联网',
                          icon: Icons.language_outlined,
                          isEnabled: isWebSearchEnabled,
                          onChanged: onWebSearchChanged,
                        ),
                        const Spacer(),
                        // Attachment button
                        GestureDetector(
                          onTap: onPickImages,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 16,
                              color: afTheme.iconColorScheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Send button
                        GestureDetector(
                          onTap: _canSend ? onSend : null,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _canSend
                                  ? primaryColor
                                  : primaryColor.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: isSending
                                  ? SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildModelChip(BuildContext context, ThemeData theme) {
    final primaryColor = theme.colorScheme.primary;

    if (isLoadingModels) {
      return Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: primaryColor,
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<AIModel>(
      initialValue: selectedModel,
      onSelected: onModelSelected,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      itemBuilder: (context) => availableModels.map((model) {
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
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
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
            const SizedBox(width: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 40),
              child: Text(
                selectedModel?.name ?? '模型',
                style: TextStyle(
                  fontSize: 10,
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
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isEnabled,
    required Function(bool) onChanged,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => onChanged(!isEnabled),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6),
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
              size: 14,
              color: isEnabled
                  ? primaryColor
                  : afTheme.iconColorScheme.secondary,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isEnabled
                    ? primaryColor
                    : afTheme.textColorScheme.secondary,
                fontWeight: isEnabled ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
