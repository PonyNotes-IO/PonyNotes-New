import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_panel.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class ViewAddButton extends StatelessWidget {
  const ViewAddButton({
    super.key,
    required this.parentViewId,
    required this.onEditing,
    required this.onSelected,
    this.isHovered = false,
    this.tooltipText,
    this.enabled = true,
  });

  final String parentViewId;
  final void Function(bool value) onEditing;
  final Function(
    PluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) onSelected;
  final bool isHovered;
  final String? tooltipText;

  /// 是否可用。为 false 时按钮显示为禁用态（半透明 + 不可点击），
  /// 但仍保留在 widget tree 中，以便 context.watch 实时响应权限变化。
  final bool enabled;

  List<PopoverAction> get _actions {
    return [
      // document, grid, kanban, calendar
      ...pluginBuilders().map(
        (pluginBuilder) => ViewAddButtonActionWrapper(
          pluginBuilder: pluginBuilder,
        ),
      ),
      // import from ...
      ...getIt<PluginSandbox>().builders.whereType<DocumentPluginBuilder>().map(
            (pluginBuilder) => ViewImportActionWrapper(
              pluginBuilder: pluginBuilder,
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 受限用户：按钮保留在 widget tree 中但禁用，
    // 确保 context.watch 实时切换权限时能立即响应
    if (!enabled) {
      final disabledButton = Opacity(
        opacity: 0.3,
        child: FlowyIconButton(
          width: 24,
          icon: FlowySvg(
            FlowySvgs.view_item_add_s,
            color: isHovered ? Theme.of(context).colorScheme.onSurface : null,
          ),
          onPressed: () {},
        ),
      );

      if (tooltipText != null && tooltipText!.isNotEmpty) {
        return IgnorePointer(
          child: FlowyTooltip(
            message: tooltipText!,
            child: disabledButton,
          ),
        );
      }
      return IgnorePointer(child: disabledButton);
    }

    return PopoverActionList<PopoverAction>(
      direction: PopoverDirection.bottomWithLeftAligned,
      actions: _actions,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(
        minWidth: 200,
      ),
      buildChild: (popover) {
        final button = FlowyIconButton(
          width: 24,
          icon: FlowySvg(
            FlowySvgs.view_item_add_s,
            color: isHovered ? Theme.of(context).colorScheme.onSurface : null,
          ),
          onPressed: () {
            onEditing(true);
            popover.show();
          },
        );

        // 如果有tooltip文本，则包装在FlowyTooltip中
        if (tooltipText != null && tooltipText!.isNotEmpty) {
          return FlowyTooltip(
            message: tooltipText!,
            child: button,
          );
        }

        return button;
      },
      onSelected: (action, popover) {
        onEditing(false);
        if (action is ViewAddButtonActionWrapper) {
          _showViewAddButtonActions(context, action);
        } else if (action is ViewImportActionWrapper) {
          _showViewImportAction(context, action);
        }
        popover.close();
      },
      onClosed: () {
        onEditing(false);
      },
    );
  }

  void _showViewAddButtonActions(
    BuildContext context,
    ViewAddButtonActionWrapper action,
  ) {
    onSelected(action.pluginBuilder, null, null, true, true);
  }

  void _showViewImportAction(
    BuildContext context,
    ViewImportActionWrapper action,
  ) {
    showImportPanel(
      parentViewId,
      context,
      (type, name, initialDataBytes) {
        onSelected(action.pluginBuilder, null, null, true, false);
      },
    );
  }
}

class ViewAddButtonActionWrapper extends ActionCell {
  ViewAddButtonActionWrapper({
    required this.pluginBuilder,
  });

  final PluginBuilder pluginBuilder;

  @override
  Widget? leftIcon(Color iconColor) => FlowySvg(
        pluginBuilder.icon,
        size: const Size.square(16),
      );

  @override
  String get name => pluginBuilder.menuName;

  PluginType get pluginType => pluginBuilder.pluginType;
}

class ViewImportActionWrapper extends ActionCell {
  ViewImportActionWrapper({
    required this.pluginBuilder,
  });

  final DocumentPluginBuilder pluginBuilder;

  @override
  Widget? leftIcon(Color iconColor) => const FlowySvg(FlowySvgs.icon_import_s);

  @override
  String get name => "导入";
}
