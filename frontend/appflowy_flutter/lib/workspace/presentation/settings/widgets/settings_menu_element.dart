import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';

import '../../../../generated/flowy_svgs.g.dart';

class SettingsMenuElement extends StatelessWidget {
  const SettingsMenuElement({
    super.key,
    required this.page,
    required this.label,
    required this.changeSelectedPage,
    required this.selectedPage,
    this.showArrow = true, // 默认显示箭头
    this.trailingText,
    this.isEnabled = true,
    this.showIcon = false,
    this.svg,
  });

  final SettingsPage page;
  final SettingsPage selectedPage;
  final String label;
  final void Function(SettingsPage page) changeSelectedPage;
  final bool showArrow; // 是否显示右侧箭头
  final String? trailingText;
  final bool isEnabled;
  final bool showIcon;
  final FlowySvgData? svg;

  static const _fontFamilyFallback = [
    'SimHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Segoe UI',
  ];

  static const _textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final labelStyle = _menuTextStyle(
      theme,
      color: theme.textColorScheme.primary,
    );
    final trailingStyle = _menuTextStyle(
      theme,
      color: isEnabled
          ? theme.textColorScheme.secondary
          : theme.textColorScheme.secondary.withValues(alpha: 0.5),
      fontSize: 12,
    );
    final hasTrailingText = trailingText != null && trailingText!.isNotEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: AFBaseButton(
        onTap: () {
          if (!isEnabled) return;
          changeSelectedPage(page);
        },
        padding: EdgeInsets.all(theme.spacing.m),
        borderRadius: theme.borderRadius.m,
        borderColor: (_, __, ___, ____) => Colors.transparent,
        backgroundColor: (_, isHovering, __) {
          if (isHovering && isEnabled) {
            return theme.fillColorScheme.contentHover;
          } else if (page == selectedPage) {
            return theme.fillColorScheme.themeSelect;
          }
          return Colors.transparent;
        },
        builder: (_, __, ___) {
          return Row(
            children: [
              if (showIcon) ...[
                FlowySvg(
                  svg ?? FlowySvgs.icon_setting_upgrade_s,
                  blendMode: null,
                  size: Size(18, 18),
                ),
                const HSpace(4),
              ],
              Expanded(
                flex: hasTrailingText ? 2 : 1,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                  strutStyle: _menuStrutStyle(labelStyle),
                  textHeightBehavior: _textHeightBehavior,
                ),
              ),
              if (hasTrailingText) ...[
                const HSpace(6),
                Expanded(
                  flex: 3,
                  child: Text(
                    trailingText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: trailingStyle,
                    strutStyle: _menuStrutStyle(trailingStyle),
                    textHeightBehavior: _textHeightBehavior,
                  ),
                ),
              ],
              if (showArrow) ...[
                const HSpace(8),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: isEnabled
                      ? theme.textColorScheme.secondary
                      : theme.textColorScheme.secondary.withValues(alpha: 0.5),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  TextStyle _menuTextStyle(
    AppFlowyThemeData theme, {
    required Color color,
    double? fontSize,
  }) {
    return theme.textStyle.body.standard(color: color).copyWith(
          // Settings menu only: SimHei avoids uneven Chinese glyph weight on
          // Windows; Microsoft YaHei remains as a stable fallback.
          // 仅设置页菜单使用黑体优先，微软雅黑保留为兜底字体。
          fontFamily: 'SimHei',
          fontFamilyFallback: _fontFamilyFallback,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
        );
  }

  StrutStyle _menuStrutStyle(TextStyle style) {
    return StrutStyle(
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize ?? 14,
      height: style.height ?? 1.35,
      leading: 0,
      forceStrutHeight: true,
    );
  }

  // return FlowyHover(
  //   isSelected: () => page == selectedPage,
  //   resetHoverOnRebuild: false,
  //   style: HoverStyle(
  //     hoverColor: AFThemeExtension.of(context).greyHover,
  //     borderRadius: BorderRadius.circular(4),
  //   ),
  //   builder: (_, isHovering) => ListTile(
  //     dense: true,
  //     leading: iconWidget(
  //       isHovering || page == selectedPage
  //           ? Theme.of(context).colorScheme.onSurface
  //           : AFThemeExtension.of(context).textColor,
  //     ),
  //     onTap: () => changeSelectedPage(page),
  //     selected: page == selectedPage,
  //     selectedColor: Theme.of(context).colorScheme.onSurface,
  //     selectedTileColor: Theme.of(context).colorScheme.primary,
  //     shape: RoundedRectangleBorder(
  //       borderRadius: BorderRadius.circular(5),
  //     ),
  //     minLeadingWidth: 0,
  //     title: FlowyText.medium(
  //       label,
  //       fontSize: FontSizes.s14,
  //       overflow: TextOverflow.ellipsis,
  //       color: page == selectedPage
  //           ? Theme.of(context).colorScheme.onSurface
  //           : null,
  //     ),
  //   ),
  // );
}
