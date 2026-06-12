import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  /// 当前用户是否为受限成员（Guest）
  /// 由 build() 中 context.watch 驱动重建
  late bool _isRestrictedMember;

  @override
  void dispose() {
    isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      _isRestrictedMember = context.watch<UserWorkspaceBloc>().state.currentUserRole == AFRolePB.Guest;
    } catch (_) {
      _isRestrictedMember = false;
    }
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
    // 受限成员按钮禁用（保留在 tree 中，context.watch 实时响应权限变化）

    if (widget.showCreateSpaceButton && widget.onCreateSpace != null) {
      final btn = FlowyIconButton(
        width: 24,
        iconPadding: const EdgeInsets.all(4.0),
        tooltipText: widget.addButtonTooltip,
        icon: const FlowySvg(FlowySvgs.space_add_s),
        onPressed: widget.onCreateSpace,
      );
      // 受限成员禁用（保留在 tree 中，context.watch 实时响应权限变化）
      if (_isRestrictedMember) {
        return IgnorePointer(
          child: Opacity(opacity: 0.3, child: btn),
        );
      }
      return btn;
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
          enabled: !_isRestrictedMember,
          onImportCompleted: (importedViews) async {
            // 导入完成后，将导入的文件移动到列表第一位
            for (final view in importedViews) {
              await ViewBackendService.moveViewV2(
                viewId: view.id,
                newParentId: widget.parentViewId!,
                prevViewId: null,  // null 表示移动到列表开头
              );
            }
          },
        ),
      );
    }

    final btn = FlowyIconButton(
      width: 24,
      iconPadding: const EdgeInsets.all(4.0),
      tooltipText: widget.addButtonTooltip,
      icon: const FlowySvg(FlowySvgs.view_item_add_s),
      onPressed: widget.onAdded,
    );
    // 受限成员禁用（保留在 tree 中，context.watch 实时响应权限变化）
    if (_isRestrictedMember) {
      return IgnorePointer(
        child: Opacity(opacity: 0.3, child: btn),
      );
    }
    return btn;
  }
}
