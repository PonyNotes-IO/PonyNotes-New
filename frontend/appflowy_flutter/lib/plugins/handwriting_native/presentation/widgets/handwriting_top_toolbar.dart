import 'package:flutter/material.dart';

/// 顶部工具栏：文档操作 / 撤销重做 / 视图导航 / 工具选择 / 颜色与粗细
class HandwritingTopToolbar extends StatelessWidget {
  const HandwritingTopToolbar({
    super.key,
    required this.selectedTool,
    required this.selectedColor,
    required this.strokeWidth,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onStrokeWidthChanged,
    this.onSave,
    this.onExport,
    this.onOpenPdf,
    this.onUndo,
    this.onRedo,
    this.onPrevPage,
    this.onNextPage,
  });

  final HandwritingTool selectedTool;
  final Color selectedColor;
  final double strokeWidth;

  final ValueChanged<HandwritingTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onStrokeWidthChanged;

  final VoidCallback? onSave;
  final VoidCallback? onExport;
  final VoidCallback? onOpenPdf;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;

  static const _presetColors = <Color>[
    Colors.black,
    Color(0xFFD32F2F), // red
    Color(0xFFF57C00), // orange
    Color(0xFFFBC02D), // yellow
    Color(0xFF388E3C), // green
    Color(0xFF1976D2), // blue
    Color(0xFF7B1FA2), // purple
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // 文档操作
          _iconButton(
            context,
            tooltip: '打开PDF',
            icon: Icons.folder_open_outlined,
            onTap: onOpenPdf,
          ),
          _iconButton(
            context,
            tooltip: '保存',
            icon: Icons.save_outlined,
            onTap: onSave,
          ),
          _iconButton(
            context,
            tooltip: '导出',
            icon: Icons.ios_share_outlined,
            onTap: onExport,
          ),
          const VerticalDivider(width: 12),

          // 撤销/重做
          _iconButton(
            context,
            tooltip: '撤销',
            icon: Icons.undo,
            onTap: onUndo,
          ),
          _iconButton(
            context,
            tooltip: '重做',
            icon: Icons.redo,
            onTap: onRedo,
          ),
          const VerticalDivider(width: 12),

          // 视图导航
          _iconButton(
            context,
            tooltip: '上一页',
            icon: Icons.chevron_left,
            onTap: onPrevPage,
          ),
          _iconButton(
            context,
            tooltip: '下一页',
            icon: Icons.chevron_right,
            onTap: onNextPage,
          ),
          const VerticalDivider(width: 12),

          // 工具选择
          _toolToggle(
            context,
            tool: HandwritingTool.pen,
            icon: Icons.edit_outlined,
            label: '笔',
          ),
          _toolToggle(
            context,
            tool: HandwritingTool.eraser,
            icon: Icons.cleaning_services_outlined,
            label: '橡皮',
          ),
          _toolToggle(
            context,
            tool: HandwritingTool.highlighter,
            icon: Icons.brush_outlined,
            label: '荧光',
          ),
          _toolToggle(
            context,
            tool: HandwritingTool.selector,
            icon: Icons.crop_free,
            label: '选择',
          ),
          const VerticalDivider(width: 12),

          // 颜色选择
          SizedBox(
            height: 36,
            child: Row(
              children: _presetColors.map((c) {
                final selected = c.value == selectedColor.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => onColorSelected(c),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withOpacity(0.6),
                          width: selected ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 12),

          // 粗细调节
          SizedBox(
            width: 140,
            child: Row(
              children: [
                const Text('粗细', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 0.5,
                    max: 15,
                    divisions: 29,
                    value: strokeWidth.clamp(0.5, 15),
                    label: '${strokeWidth.toStringAsFixed(1)} px',
                    onChanged: onStrokeWidthChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolToggle(
    BuildContext context, {
    required HandwritingTool tool,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final bool selected = selectedTool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onToolSelected(tool),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: theme.colorScheme.onSurface.withOpacity(0.8),
        onPressed: onTap,
      ),
    );
  }
}

/// 与页面内部使用的工具枚举保持一致
enum HandwritingTool {
  pen,
  eraser,
  highlighter,
  selector,
}

