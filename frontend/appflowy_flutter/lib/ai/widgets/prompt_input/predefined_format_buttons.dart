import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../service/ai_entities.dart';
import 'layout_define.dart';

/// 输出格式入口：折叠成底部操作栏里的一个小按钮，点击弹出格式选项。
///
/// 之前 [ChangeFormatBar] 是直接铺在输入框顶部的，既占用了输入框的空间，
/// 又容易被当成输入框内容的一部分。现在收成图标按钮（样式与 AI 回复尾部的
/// 操作图标一致），把配置能力留在尾部区域。
class PromptInputFormatMenuButton extends StatefulWidget {
  const PromptInputFormatMenuButton({
    super.key,
    required this.predefinedFormat,
    required this.showImageFormats,
    required this.onSelectPredefinedFormat,
  });

  final PredefinedFormat? predefinedFormat;
  final bool showImageFormats;
  final void Function(PredefinedFormat) onSelectPredefinedFormat;

  @override
  State<PromptInputFormatMenuButton> createState() =>
      _PromptInputFormatMenuButtonState();
}

class _PromptInputFormatMenuButtonState
    extends State<PromptInputFormatMenuButton> {
  final popoverController = PopoverController();

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      controller: popoverController,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.topWithLeftAligned,
      margin: EdgeInsets.zero,
      offset: const Offset(0, -6),
      constraints: const BoxConstraints(),
      child: _buildButton(context),
      popupBuilder: (_) {
        return _FormatMenuPopoverContent(
          predefinedFormat: widget.predefinedFormat,
          showImageFormats: widget.showImageFormats,
          onSelectPredefinedFormat: widget.onSelectPredefinedFormat,
        );
      },
    );
  }

  Widget _buildButton(BuildContext context) {
    final iconColor = Theme.of(context).hintColor;
    // 图标跟随当前选中的输出模式：文本 / 图片+文本 / 纯图片。
    // 未选过格式（predefinedFormat == null）时按"文本"显示，
    // 与输入框不请求图片时的实际行为保持一致。
    final imageFormat =
        widget.predefinedFormat?.imageFormat ?? ImageFormat.text;
    return FlowyIconButton(
      tooltipText: '输出格式',
      preferBelow: false,
      width: DesktopAIPromptSizes.actionBarSendButtonSize,
      height: DesktopAIPromptSizes.actionBarButtonSize,
      hoverColor: AFThemeExtension.of(context).lightGreyHover,
      radius: const BorderRadius.all(Radius.circular(6.0)),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlowySvg(
            imageFormat.icon,
            color: iconColor,
            size: imageFormat == ImageFormat.textAndImage
                ? const Size(21.0, 16.0)
                : const Size.square(16.0),
          ),
          FlowySvg(
            FlowySvgs.ai_source_drop_down_s,
            color: iconColor,
            size: const Size.square(8.0),
          ),
        ],
      ),
      onPressed: popoverController.toggle,
    );
  }
}

class _FormatMenuPopoverContent extends StatefulWidget {
  const _FormatMenuPopoverContent({
    required this.predefinedFormat,
    required this.showImageFormats,
    required this.onSelectPredefinedFormat,
  });

  final PredefinedFormat? predefinedFormat;
  final bool showImageFormats;
  final void Function(PredefinedFormat) onSelectPredefinedFormat;

  @override
  State<_FormatMenuPopoverContent> createState() =>
      _FormatMenuPopoverContentState();
}

class _FormatMenuPopoverContentState extends State<_FormatMenuPopoverContent> {
  late PredefinedFormat? predefinedFormat;

  @override
  void initState() {
    super.initState();
    predefinedFormat = widget.predefinedFormat;
  }

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      // 弹层挂在根 Overlay 上，默认会被当成"输入框外部"的点击从而收起键盘，
      // 这里显式声明它属于输入框的点击区域。
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: ChangeFormatBar(
          predefinedFormat: predefinedFormat,
          showImageFormats: widget.showImageFormats,
          spacing: 4.0,
          onSelectPredefinedFormat: (format) {
            setState(() => predefinedFormat = format);
            widget.onSelectPredefinedFormat(format);
          },
        ),
      ),
    );
  }
}

class ChangeFormatBar extends StatelessWidget {
  const ChangeFormatBar({
    super.key,
    required this.predefinedFormat,
    required this.spacing,
    required this.onSelectPredefinedFormat,
    this.showImageFormats = true,
  });

  final PredefinedFormat? predefinedFormat;
  final double spacing;
  final void Function(PredefinedFormat) onSelectPredefinedFormat;
  final bool showImageFormats;

  @override
  Widget build(BuildContext context) {
    final showTextFormats = predefinedFormat?.imageFormat.hasText ?? true;
    return SizedBox(
      height: DesktopAIPromptSizes.predefinedFormatButtonHeight,
      child: SeparatedRow(
        mainAxisSize: MainAxisSize.min,
        separatorBuilder: () => HSpace(spacing),
        children: [
          if (showImageFormats) ...[
            _buildFormatButton(context, ImageFormat.text),
            _buildFormatButton(context, ImageFormat.textAndImage),
            _buildFormatButton(context, ImageFormat.image),
          ],
          if (showImageFormats && showTextFormats) _buildDivider(),
          if (showTextFormats) ...[
            _buildTextFormatButton(context, TextFormat.paragraph),
            _buildTextFormatButton(context, TextFormat.bulletList),
            _buildTextFormatButton(context, TextFormat.numberedList),
            _buildTextFormatButton(context, TextFormat.table),
          ],
        ],
      ),
    );
  }

  Widget _buildFormatButton(BuildContext context, ImageFormat format) {
    // 未选过格式时按"文本"高亮，和左下角按钮图标保持一致。
    final selected =
        format == (predefinedFormat?.imageFormat ?? ImageFormat.text);
    return _buildButton(
      context: context,
      selected: selected,
      tooltip: format.i18n,
      onTap: () {
        if (predefinedFormat != null &&
            format == predefinedFormat!.imageFormat) {
          return;
        }
        if (format.hasText) {
          final textFormat =
              predefinedFormat?.textFormat ?? TextFormat.paragraph;
          onSelectPredefinedFormat(
            PredefinedFormat(imageFormat: format, textFormat: textFormat),
          );
        } else {
          onSelectPredefinedFormat(
            PredefinedFormat(imageFormat: format, textFormat: null),
          );
        }
      },
      icon: FlowySvg(
        format.icon,
        size: format == ImageFormat.textAndImage
            ? Size(21.0 / 16.0 * _iconSize, _iconSize)
            : Size.square(_iconSize),
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }

  Widget _buildDivider() {
    return VerticalDivider(
      indent: 6.0,
      endIndent: 6.0,
      width: 1.0 + spacing * 2,
    );
  }

  Widget _buildTextFormatButton(
    BuildContext context,
    TextFormat format,
  ) {
    final selected = format == predefinedFormat?.textFormat;
    return _buildButton(
      context: context,
      selected: selected,
      tooltip: format.i18n,
      onTap: () {
        if (predefinedFormat != null &&
            format == predefinedFormat!.textFormat) {
          return;
        }
        onSelectPredefinedFormat(
          PredefinedFormat(
            imageFormat: predefinedFormat?.imageFormat ?? ImageFormat.text,
            textFormat: format,
          ),
        );
      },
      icon: FlowySvg(
        format.icon,
        size: Size.square(_iconSize),
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }

  /// 统一格式按钮外观：选中态用主色描边 + 淡主色底，
  /// 原来的 FlowyHover 只叠一层极淡的 hover 底色，深色主题下几乎看不出来。
  Widget _buildButton({
    required BuildContext context,
    required bool selected,
    required String tooltip,
    required VoidCallback onTap,
    required Widget icon,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FlowyTooltip(
        message: tooltip,
        preferBelow: false,
        child: Container(
          width: _buttonSize,
          height: _buttonSize,
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.12) : null,
            borderRadius: const BorderRadius.all(Radius.circular(6.0)),
            border: Border.all(
              color: selected
                  ? primary.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  double get _buttonSize {
    return PlatformInfo.isMobile
        ? MobileAIPromptSizes.predefinedFormatButtonHeight
        : DesktopAIPromptSizes.predefinedFormatButtonHeight;
  }

  double get _iconSize {
    return PlatformInfo.isMobile
        ? MobileAIPromptSizes.predefinedFormatIconHeight
        : DesktopAIPromptSizes.predefinedFormatIconHeight;
  }
}

class PromptInputMobileToggleFormatButton extends StatelessWidget {
  const PromptInputMobileToggleFormatButton({
    super.key,
    required this.showFormatBar,
    required this.onTap,
  });

  final bool showFormatBar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 26.0,
      child: FlowyButton(
        radius: const BorderRadius.all(Radius.circular(4.0)),
        margin: EdgeInsets.zero,
        expandText: false,
        text: showFormatBar
            ? const FlowySvg(
                FlowySvgs.m_aa_text_s,
                size: Size.square(16.0),
              )
            : const FlowySvg(
                FlowySvgs.ai_text_image_s,
                size: Size(20.0, 16.0),
              ),
        onTap: onTap,
      ),
    );
  }
}
