import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class FolderHeader extends StatefulWidget {
  const FolderHeader({
    super.key,
    required this.title,
    required this.expandButtonTooltip,
    required this.addButtonTooltip,
    required this.onPressed,
    required this.onAdded,
    required this.isExpanded,
    this.parentViewId,
    this.onViewSelected,
    this.onCreateSpace,
    this.showCreateSpaceButton = false,
    this.isTablet = false,
  });

  final String title;
  final String expandButtonTooltip;
  final String addButtonTooltip;
  final VoidCallback onPressed;
  final VoidCallback onAdded;
  final bool isExpanded;
  final String? parentViewId;
  final Function(
    PluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  )? onViewSelected;
  final VoidCallback? onCreateSpace;
  final bool showCreateSpaceButton;
  final bool isTablet;

  @override
  State<FolderHeader> createState() => _FolderHeaderState();
}

class _FolderHeaderState extends State<FolderHeader> {
  final isHovered = ValueNotifier(false);

  @override
  void dispose() {
    isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final alwaysShowButtons = widget.isTablet || PlatformInfo.isTablet;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: Stack(
          children: [
            AFGhostIconTextButton.primary(
              text: widget.title,
              mainAxisAlignment: MainAxisAlignment.start,
              size: AFButtonSize.l,
              onTap: widget.onPressed,
              padding: const EdgeInsets.symmetric(vertical: 10),
              borderRadius: theme.borderRadius.s,
              iconBuilder: (context, isHover, disabled) => SizedBox.shrink(),
              showExpandArrow: true,
              isExpanded: widget.isExpanded,
            ),
            Positioned(
              right: 8,
              top: 0.0,
              bottom: 0.0,
              child: Align(
                child: alwaysShowButtons
                    ? _buildAddButton()
                    : ValueListenableBuilder(
                        valueListenable: isHovered,
                        builder: (context, onHover, child) =>
                            Opacity(opacity: onHover ? 1 : 0, child: child),
                        child: _buildAddButton(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    if (widget.showCreateSpaceButton && widget.onCreateSpace != null) {
      return FlowyIconButton(
        width: 24,
        iconPadding: const EdgeInsets.all(4.0),
        tooltipText: widget.addButtonTooltip,
        icon: const FlowySvg(FlowySvgs.space_add_s),
        onPressed: widget.onCreateSpace,
      );
    }

    if (widget.parentViewId != null && widget.onViewSelected != null) {
      return SizedBox(
        width: 24,
        height: 24,
        child: ViewAddButton(
          parentViewId: widget.parentViewId!,
          onEditing: (value) {},
          onSelected: widget.onViewSelected!,
          tooltipText: widget.addButtonTooltip,
        ),
      );
    }

    return FlowyIconButton(
      width: 24,
      iconPadding: const EdgeInsets.all(4.0),
      tooltipText: widget.addButtonTooltip,
      icon: const FlowySvg(FlowySvgs.view_item_add_s),
      onPressed: widget.onAdded,
    );
  }
}
