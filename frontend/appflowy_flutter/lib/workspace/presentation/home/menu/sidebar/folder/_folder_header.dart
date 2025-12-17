import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: Stack(children: [
          AFGhostIconTextButton.primary(
            text: widget.title,
            mainAxisAlignment: MainAxisAlignment.start,
            size: AFButtonSize.l,
            onTap: widget.onPressed,
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            borderRadius: theme.borderRadius.s,
            iconBuilder: (context, isHover, disabled) => FlowySvg(
              FlowySvgs.folder_m,
              size: const Size.square(16.0),
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
            showExpandArrow: true,
            isExpanded: widget.isExpanded,
          ),
          Positioned(
            right: 8,
            top: 0.0,
            bottom: 0.0,
            child: Align(
              alignment: Alignment.center,
              child: ValueListenableBuilder(
                valueListenable: isHovered,
                builder: (context, onHover, child) =>
                    Opacity(opacity: onHover ? 1 : 0, child: child),
                child: _buildAddButton(),
              ),
            ),
          )
        ]),

        // FlowyButton(
        //   onTap: widget.onPressed,
        //   rightIcon: ,
        //
        //   text: Row(
        //     children: [
        //       // 添加文件夹图标（只为"我的空间"显示）
        //       Padding(
        //         padding: const EdgeInsets.only(right: 8.0),
        //         child: FlowySvg(
        //           FlowySvgs.folder_m,
        //           size: const Size.square(16.0),
        //         ),
        //       ),
        //       FlowyText(
        //         widget.title,
        //         lineHeight: 1.15,
        //       ),
        //       const HSpace(4.0),
        //       FlowySvg(
        //         // 展开时使用向下箭头，收起时使用向右箭头
        //         widget.isExpanded
        //             ? FlowySvgs.workspace_drop_down_menu_show_s
        //             : FlowySvgs.workspace_drop_down_menu_hide_s,
        //         size: const Size.square(16.0),
        //       ),
        //     ],
        //   ),
        // ),
      ),
    );
  }

  Widget _buildAddButton() {
    // 如果提供了parentViewId和onViewSelected回调，则使用ViewAddButton显示选择菜单
    if (widget.parentViewId != null && widget.onViewSelected != null) {
      return SizedBox(
        width: 24,
        height: 24,
        child: ViewAddButton(
          parentViewId: widget.parentViewId!,
          onEditing: (value) {
            // 这里可以处理编辑状态，暂时留空
          },
          onSelected: widget.onViewSelected!,
          tooltipText: widget.addButtonTooltip,
        ),
      );
    }

    // 否则使用原来的简单按钮
    return FlowyIconButton(
      width: 24,
      iconPadding: const EdgeInsets.all(4.0),
      tooltipText: widget.addButtonTooltip,
      icon: const FlowySvg(FlowySvgs.view_item_add_s),
      onPressed: widget.onAdded,
    );
  }
}
