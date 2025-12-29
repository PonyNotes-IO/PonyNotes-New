import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../third_party/saber_core/data/tools/tool.dart';

/// 工具选项数据类
class ToolOption {
  const ToolOption({
    required this.icon,
    required this.label,
    required this.tool,
  });

  final IconData icon;
  final String label;
  final Tool tool;
}

/// 带下拉菜单的工具按钮组件
class ToolDropdownButton extends StatelessWidget {
  const ToolDropdownButton({
    super.key,
    required this.currentTool,
    required this.mainTool,
    required this.options,
    required this.onToolChanged,
    this.mainIcon,
    this.mainLabel,
  });

  /// 当前选中的工具
  final Tool currentTool;
  
  /// 主按钮默认工具（用于判断是否显示高亮）
  final Tool mainTool;
  
  /// 下拉菜单选项列表
  final List<ToolOption> options;
  
  /// 工具改变回调
  final ValueChanged<Tool> onToolChanged;
  
  /// 主按钮图标（如果为null，则从options中找到当前选中工具的图标）
  final IconData? mainIcon;
  
  /// 主按钮标签（如果为null，则从options中找到当前选中工具的标签）
  final String? mainLabel;

  @override
  Widget build(BuildContext context) {
    // 找到当前选中的工具选项
    final selectedOption = options.firstWhere(
      (opt) => opt.tool.toolId == currentTool.toolId,
      orElse: () => options.first,
    );
    
    final displayIcon = mainIcon ?? selectedOption.icon;
    final displayLabel = mainLabel ?? selectedOption.label;
    final isSelected = options.any((opt) => opt.tool.toolId == currentTool.toolId);

    return Tooltip(
      message: displayLabel,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 主按钮区域
            InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              onTap: () => onToolChanged(selectedOption.tool),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: FaIcon(
                  displayIcon,
                  size: 16,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            // 下拉指示器区域
            PopupMenuButton<Tool>(
              offset: const Offset(0, 40),
              tooltip: '选择$displayLabel类型',
              onSelected: onToolChanged,
              itemBuilder: (ctx) => options.map((option) {
                final isOptionSelected = option.tool.toolId == currentTool.toolId;
                return PopupMenuItem<Tool>(
                  value: option.tool,
                  child: Row(
                    children: [
                      FaIcon(
                        option.icon,
                        size: 16,
                        color: isOptionSelected
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        option.label,
                        style: TextStyle(
                          color: isOptionSelected
                              ? Theme.of(ctx).colorScheme.primary
                              : Theme.of(ctx).colorScheme.onSurface,
                          fontWeight: isOptionSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (isOptionSelected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check,
                          size: 16,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

