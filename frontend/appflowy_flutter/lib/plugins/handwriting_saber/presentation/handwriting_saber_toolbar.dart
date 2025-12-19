import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/data/tools/tool.dart';

/// 手写笔记工具栏组件
class HandwritingSaberToolbar extends StatelessWidget {
  const HandwritingSaberToolbar({
    super.key,
    required this.currentTool,
    required this.onToolChanged,
    required this.currentBackgroundPattern,
    required this.onBackgroundPatternChanged,
    required this.currentColor,
    required this.onColorChanged,
    required this.currentStrokeWidth,
    required this.onStrokeWidthChanged,
    this.onImportPdf,  // ✅ PDF 导入回调（可选）
  });

  final Tool currentTool;
  final ValueChanged<Tool> onToolChanged;
  final CanvasBackgroundPattern currentBackgroundPattern;
  final ValueChanged<CanvasBackgroundPattern> onBackgroundPatternChanged;
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final double currentStrokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback? onImportPdf;  // ✅ PDF 导入回调

  // 预定义颜色列表
  static const List<Color> presetColors = [
    Colors.black,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.brown,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 工具选择
          Flexible(
            child: _buildToolSelector(),
          ),
          const SizedBox(width: 8),
          // 颜色选择
          Flexible(
            child: _buildColorSelector(),
          ),
          const SizedBox(width: 8),
          // 粗细调整
          Flexible(
            child: _buildStrokeWidthSelector(),
          ),
          const Spacer(),
          // ✅ PDF 导入按钮
          if (onImportPdf != null)
            IconButton(
              icon: const Icon(FontAwesomeIcons.filePdf),
              tooltip: '导入 PDF',
              onPressed: onImportPdf,
            ),
          const SizedBox(width: 8),
          // 背景纸模式选择
          _buildBackgroundPatternSelector(),
        ],
      ),
    );
  }

  Widget _buildToolSelector() {
    return Builder(
      builder: (context) => Wrap(
        spacing: 4,
        children: [
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.penFancy,
            tool: Pen(
              toolId: ToolId.fountainPen,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '钢笔',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.pen,
            tool: Pen(
              toolId: ToolId.ballpointPen,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '圆珠笔',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.pencil,
            tool: Pen(
              toolId: ToolId.pencil,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '铅笔',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.highlighter,
            tool: Pen(
              toolId: ToolId.highlighter,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '荧光笔',
          ),
          _buildToolButton(
            context: context,
            icon: Symbols.stylus_laser_pointer,
            tool: Pen(
              toolId: ToolId.laserPointer,
              color: Colors.red,
              strokeWidth: currentStrokeWidth,
            ),
            label: '激光笔',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.eraser,
            tool: Eraser(strokeWidth: currentStrokeWidth),
            label: '橡皮擦',
          ),
          // ✅ 形状工具
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.square,
            tool: Pen(
              toolId: ToolId.rectangle,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '矩形',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.circle,
            tool: Pen(
              toolId: ToolId.circle,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '圆形',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.shapes,  // ✅ 使用 shapes 图标代替 triangle
            tool: Pen(
              toolId: ToolId.triangle,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '三角形',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.diamond,
            tool: Pen(
              toolId: ToolId.diamond,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '菱形',
          ),
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.drawPolygon,
            tool: Pen(
              toolId: ToolId.freePolygon,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '自由多边形',
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required BuildContext context,
    required dynamic icon, // 支持 IconData (FontAwesome) 和 IconData? (Material Symbols)
    required Tool tool,
    required String label,
  }) {
    final bool isSelected = currentTool.toolId == tool.toolId;
    return Tooltip(
      message: label,
      child: Material(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => onToolChanged(tool),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _buildIconWidget(icon, isSelected, context),
          ),
        ),
      ),
    );
  }

  Widget _buildIconWidget(dynamic icon, bool isSelected, BuildContext context) {
    final iconColor = isSelected
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurface;
    
    // 判断是 Material Symbols 还是 FontAwesome
    if (icon.toString().contains('Symbols')) {
      // Material Symbols 图标
      return Icon(
        icon as IconData,
        size: 20,
        color: iconColor,
      );
    } else {
      // FontAwesome 图标
      return FaIcon(
        icon as IconData,
        size: 16,
        color: iconColor,
      );
    }
  }

  Widget _buildColorSelector() {
    return Builder(
      builder: (context) => Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 当前颜色显示
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: currentColor,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // 预设颜色
          ...presetColors.map((color) {
            final bool isSelected = color == currentColor;
            return Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => onColorChanged(color),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.outline,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStrokeWidthSelector() {
    return Row(
      children: [
        const Icon(Icons.line_weight, size: 20),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          child: Slider(
            value: currentStrokeWidth,
            min: 1,
            max: 20,
            divisions: 19,
            label: currentStrokeWidth.toStringAsFixed(0),
            onChanged: onStrokeWidthChanged,
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            currentStrokeWidth.toStringAsFixed(0),
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundPatternSelector() {
    return Builder(
      builder: (context) => PopupMenuButton<CanvasBackgroundPattern>(
        tooltip: '背景纸模式',
        onSelected: onBackgroundPatternChanged,
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: CanvasBackgroundPattern.none,
            child: Text('无背景'),
          ),
          const PopupMenuItem(
            value: CanvasBackgroundPattern.lined,
            child: Text('横线纸'),
          ),
          const PopupMenuItem(
            value: CanvasBackgroundPattern.grid,
            child: Text('网格纸'),
          ),
          const PopupMenuItem(
            value: CanvasBackgroundPattern.dots,
            child: Text('点阵纸'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.grid_view, size: 20),
              const SizedBox(width: 4),
              Text(_getBackgroundPatternName(currentBackgroundPattern)),
            ],
          ),
        ),
      ),
    );
  }

  String _getBackgroundPatternName(CanvasBackgroundPattern pattern) {
    switch (pattern) {
      case CanvasBackgroundPattern.none:
        return '无背景';
      case CanvasBackgroundPattern.lined:
        return '横线纸';
      case CanvasBackgroundPattern.grid:
        return '网格纸';
      case CanvasBackgroundPattern.dots:
        return '点阵纸';
    }
  }
}

