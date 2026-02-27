import 'package:appflowy_ui/src/component/component.dart';
import 'package:appflowy_ui/src/theme/appflowy_theme.dart';
import 'package:flutter/material.dart';

typedef AFGhostIconBuilder = Widget Function(
  BuildContext context,
  bool isHovering,
  bool disabled,
);

/// 展开箭头位置
enum AFExpandArrowPosition {
  /// 紧跟在文字后面
  afterText,
  /// 在整个 Row 的最右边
  rowEnd,
}

class AFGhostIconTextButton extends StatelessWidget {
  const AFGhostIconTextButton({
    super.key,
    required this.text,
    required this.onTap,
    required this.iconBuilder,
    this.textColor,
    this.backgroundColor,
    this.size = AFButtonSize.m,
    this.padding,
    this.borderRadius,
    this.disabled = false,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.showExpandArrow = false,
    this.isExpanded = false,
    this.expandArrowPosition = AFExpandArrowPosition.afterText,
    this.expandArrowBuilder,
  });

  /// Primary ghost text button.
  factory AFGhostIconTextButton.primary({
    Key? key,
    required String text,
    required VoidCallback onTap,
    required AFGhostIconBuilder iconBuilder,
    AFButtonSize size = AFButtonSize.m,
    EdgeInsetsGeometry? padding,
    double? borderRadius,
    bool disabled = false,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.center,
    bool showExpandArrow = false,
    bool isExpanded = false,
    AFExpandArrowPosition expandArrowPosition = AFExpandArrowPosition.afterText,
    AFGhostIconBuilder? expandArrowBuilder,
  }) {
    return AFGhostIconTextButton(
      key: key,
      text: text,
      onTap: onTap,
      iconBuilder: iconBuilder,
      size: size,
      padding: padding,
      borderRadius: borderRadius,
      disabled: disabled,
      mainAxisAlignment: mainAxisAlignment,
      showExpandArrow: showExpandArrow,
      isExpanded: isExpanded,
      expandArrowPosition: expandArrowPosition,
      expandArrowBuilder: expandArrowBuilder,
      backgroundColor: (context, isHovering, disabled) {
        final theme = AppFlowyTheme.of(context);
        if (disabled) {
          return Colors.transparent;
        }
        if (isHovering) {
          return theme.fillColorScheme.contentHover;
        }
        return Colors.transparent;
      },
      textColor: (context, isHovering, disabled) {
        final theme = AppFlowyTheme.of(context);
        if (disabled) {
          return theme.textColorScheme.tertiary;
        }
        return theme.textColorScheme.secondary;
      },
    );
  }

  /// Disabled ghost text button.
  factory AFGhostIconTextButton.disabled({
    Key? key,
    required String text,
    required AFGhostIconBuilder iconBuilder,
    AFButtonSize size = AFButtonSize.m,
    EdgeInsetsGeometry? padding,
    double? borderRadius,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.center,
  }) {
    return AFGhostIconTextButton(
      key: key,
      text: text,
      iconBuilder: iconBuilder,
      onTap: () {},
      size: size,
      padding: padding,
      borderRadius: borderRadius,
      disabled: true,
      mainAxisAlignment: mainAxisAlignment,
      backgroundColor: (context, isHovering, disabled) {
        return Colors.transparent;
      },
      textColor: (context, isHovering, disabled) {
        final theme = AppFlowyTheme.of(context);
        return theme.textColorScheme.tertiary;
      },
    );
  }

  final String text;
  final bool disabled;
  final VoidCallback onTap;
  final AFButtonSize size;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  final AFGhostIconBuilder iconBuilder;

  final AFBaseButtonColorBuilder? textColor;
  final AFBaseButtonColorBuilder? backgroundColor;

  final MainAxisAlignment mainAxisAlignment;

  /// 是否显示展开/收起箭头
  final bool showExpandArrow;

  /// 当前是否展开状态
  final bool isExpanded;

  /// 展开箭头的位置
  final AFExpandArrowPosition expandArrowPosition;

  /// 自定义展开箭头构建器，如果为 null 则使用默认箭头
  final AFGhostIconBuilder? expandArrowBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return AFBaseButton(
      disabled: disabled,
      backgroundColor: backgroundColor,
      borderColor: (context, isHovering, disabled, isFocused) {
        return Colors.transparent;
      },
      padding: padding ?? size.buildPadding(context),
      borderRadius: borderRadius ?? size.buildBorderRadius(context),
      onTap: onTap,
      builder: (context, isHovering, disabled) {
        final textColor = this.textColor?.call(context, isHovering, disabled) ??
            theme.textColorScheme.primary;

        // 构建展开箭头
        Widget? expandArrow;
        if (showExpandArrow) {
          expandArrow = expandArrowBuilder?.call(context, isHovering, disabled) ??
              _buildDefaultExpandArrow(context, isHovering, disabled, textColor);
        }

        return Row(
          mainAxisAlignment: mainAxisAlignment,
          children: [
            // 左侧图标
            iconBuilder(
              context,
              isHovering,
              disabled,
            ),
            SizedBox(width: theme.spacing.m),
            // 文字
            if (expandArrowPosition == AFExpandArrowPosition.rowEnd)
              Expanded(
                child: Text(
                  text,
                  style: size.buildTextStyle(context).copyWith(
                        color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold
                      ),
                ),
              )
            else
              Text(
                text,
                style: size.buildTextStyle(context).copyWith(
                      color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold
                    ),
              ),
            // 箭头在文字后
            if (showExpandArrow &&
                expandArrowPosition == AFExpandArrowPosition.afterText) ...[
              SizedBox(width: theme.spacing.s),
              expandArrow!,
            ],
            // 箭头在行尾
            if (showExpandArrow &&
                expandArrowPosition == AFExpandArrowPosition.rowEnd) ...[
              expandArrow!,
            ],
          ],
        );
      },
    );
  }

  /// 构建默认的展开/收起箭头
  Widget _buildDefaultExpandArrow(
    BuildContext context,
    bool isHovering,
    bool disabled,
    Color color,
  ) {
    return AnimatedRotation(
      turns: isExpanded ? 0.25 : 0, // 0.25 = 90度，展开时向下
      duration: const Duration(milliseconds: 150),
      child: Icon(
        Icons.chevron_right,
        size: 16,
        color: disabled
            ? AppFlowyTheme.of(context).textColorScheme.tertiary
            : color,
      ),
    );
  }
}
