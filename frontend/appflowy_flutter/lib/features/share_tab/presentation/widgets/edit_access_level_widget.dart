import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';

class EditAccessLevelWidget extends StatefulWidget {
  const EditAccessLevelWidget({
    super.key,
    required this.callbacks,
    required this.selectedAccessLevel,
    required this.supportedAccessLevels,
    required this.additionalUserManagementOptions,
    this.disabled = false,
    this.compact = false,
  });

  /// Callbacks
  final AccessLevelListCallbacks callbacks;

  /// The currently selected access level
  final ShareAccessLevel selectedAccessLevel;

  /// Whether the widget is disabled
  final bool disabled;
  final bool compact;

  /// Supported access levels
  final List<ShareAccessLevel> supportedAccessLevels;

  /// Additional user management options
  final List<AdditionalUserManagementOptions> additionalUserManagementOptions;

  @override
  State<EditAccessLevelWidget> createState() => _EditAccessLevelWidgetState();
}

class _EditAccessLevelWidgetState extends State<EditAccessLevelWidget> {
  final popoverController = AFPopoverController();
  final _triggerFocus = FocusNode();

  @override
  void dispose() {
    popoverController.dispose();
    _triggerFocus.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (widget.compact) return _buildCompactMenu(context, theme);

    return AFPopover(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(), // the access level widget has a border
      controller: popoverController,
      popover: (_) {
        return AccessLevelListWidget(
          selectedAccessLevel: widget.selectedAccessLevel,
          supportedAccessLevels: widget.supportedAccessLevels,
          additionalUserManagementOptions:
              widget.additionalUserManagementOptions,
          callbacks: widget.callbacks.copyWith(
            onSelectAccessLevel: (accessLevel) {
              widget.callbacks.onSelectAccessLevel(accessLevel);

              popoverController.hide();
            },
            onRemoveAccess: () {
              widget.callbacks.onRemoveAccess();

              popoverController.hide();
            },
          ),
        );
      },
      child: AFGhostButton.normal(
        disabled: widget.disabled,
        onTap: () {
          popoverController.show();
        },
        padding: EdgeInsets.symmetric(
          vertical: theme.spacing.s,
          horizontal: theme.spacing.l,
        ),
        builder: (context, isHovering, disabled) {
          return Row(
            children: [
              Text(
                widget.selectedAccessLevel.title,
                style: theme.textStyle.body.standard(
                  color: disabled
                      ? theme.textColorScheme.secondary
                      : theme.textColorScheme.primary,
                ),
              ),
              HSpace(theme.spacing.xs),
              FlowySvg(
                FlowySvgs.arrow_down_s,
                color: theme.textColorScheme.secondary,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactMenu(BuildContext context, AppFlowyThemeData theme) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final foreground = theme.textColorScheme.primary;
    final secondary = theme.textColorScheme.secondary;
    final highlight = dark ? const Color(0xFF343434) : const Color(0xFFF2F2F2);
    final hover = dark ? const Color(0xFF2E2E2) : const Color(0xFFF7F7F7);
    final canRemove = widget.additionalUserManagementOptions.contains(
      AdditionalUserManagementOptions.removeAccess,
    );
    final levels = widget.supportedAccessLevels;
    const menuWidth = 196.0;

    ButtonStyle itemStyle({bool selected = false}) => ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected || states.contains(WidgetState.pressed))
              return highlight;
            if (states.contains(WidgetState.hovered)) return hover;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? BorderSide(color: secondary.withValues(alpha: .65))
                  : BorderSide.none),
        );

    return MenuAnchor(
      childFocusNode: _triggerFocus,
      consumeOutsideTap: true,
      crossAxisUnconstrained: false,
      alignmentOffset: const Offset(-menuWidth, 4),
      style: const MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        fixedSize: WidgetStatePropertyAll(Size(menuWidth, double.infinity)),
        visualDensity: VisualDensity.standard,
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        TweenAnimationBuilder<double>(
          key: const ValueKey('document-share-permission-menu'),
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (_, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: Material(
            color: dark
                ? const Color(0xFF222222)
                : theme.surfaceContainerColorScheme.layer01,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: .25),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: foreground.withValues(alpha: .10)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final level in levels)
                    Semantics(
                      selected: level == widget.selectedAccessLevel,
                      child: MenuItemButton(
                        autofocus: level == widget.selectedAccessLevel,
                        requestFocusOnHover: false,
                        style: itemStyle(
                            selected: level == widget.selectedAccessLevel),
                        onPressed: () {
                          if (level != widget.selectedAccessLevel) {
                            widget.callbacks.onSelectAccessLevel(level);
                          }
                        },
                        child: Row(
                          children: [
                            FlowySvg(level.icon,
                                size: const Size.square(16),
                                color: theme.iconColorScheme.secondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(level.title,
                                      style: theme.textStyle.body.standard(
                                          weight: FontWeight.w600,
                                          color: foreground)),
                                  Text(level.subtitle,
                                      style: theme.textStyle.caption
                                          .standard(color: secondary)),
                                ],
                              ),
                            ),
                            if (level == widget.selectedAccessLevel)
                              Icon(Icons.check,
                                  size: 16,
                                  color: dark ? foreground : colors.primary),
                          ],
                        ),
                      ),
                    ),
                  if (canRemove) ...[
                    if (levels.isNotEmpty)
                      Divider(
                          height: 9,
                          indent: 4,
                          endIndent: 4,
                          color: foreground.withValues(alpha: .10)),
                    MenuItemButton(
                      autofocus: levels.isEmpty,
                      requestFocusOnHover: false,
                      style: itemStyle(),
                      onPressed: widget.callbacks.onRemoveAccess,
                      child: Text(LocaleKeys.shareTab_removeAccess.tr(),
                          style: theme.textStyle.body
                              .standard(color: theme.textColorScheme.error)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => Semantics(
        expanded: controller.isOpen,
        child: TextButton(
          focusNode: _triggerFocus,
          style: itemStyle(selected: controller.isOpen).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
          ),
          onPressed: widget.disabled
              ? null
              : () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    _triggerFocus.requestFocus();
                    controller.open();
                  }
                },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.selectedAccessLevel.title,
                  style: theme.textStyle.body.standard(
                      color: widget.disabled ? secondary : foreground)),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down,
                  size: 16, color: theme.iconColorScheme.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
