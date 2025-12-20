import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/data/tools/tool.dart';
import 'color_picker_dialog.dart';

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
    this.currentFillColor, // ✅ 当前填充颜色（可选）
    this.onFillColorChanged, // ✅ 填充颜色改变回调（可选）
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
  final Color? currentFillColor; // ✅ 当前填充颜色
  final ValueChanged<Color?>? onFillColorChanged; // ✅ 填充颜色改变回调
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ✅ 工具选择（左侧主要区域，分组显示）
          Expanded(
            flex: 4,
            child: _buildToolSelectorGrouped(),
          ),
          // ✅ 分隔线
          _buildDivider(),
          // ✅ 颜色和样式区域
          _buildColorAndStyleSection(),
          // ✅ 分隔线
          _buildDivider(),
          // ✅ 粗细调整
          _buildStrokeWidthSelector(),
          // ✅ 分隔线
          _buildDivider(),
          // ✅ 其他工具（PDF导入、背景模式）
          _buildOtherToolsSection(),
        ],
      ),
    );
  }
  
  /// ✅ 构建分隔线
  Widget _buildDivider() {
    return Builder(
      builder: (context) => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
      ),
    );
  }
  
  /// ✅ 构建颜色和样式区域
  Widget _buildColorAndStyleSection() {
    return Builder(
      builder: (context) => SizedBox(
        width: _isShapeTool(currentTool.toolId) && onFillColorChanged != null ? 400 : 200,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ 颜色选择
              _buildColorSelector(),
              // ✅ 填充颜色选择（仅形状工具显示）
              if (_isShapeTool(currentTool.toolId) && onFillColorChanged != null) ...[
                const SizedBox(width: 8),
                _buildFillColorSelector(),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  /// ✅ 构建其他工具区域
  Widget _buildOtherToolsSection() {
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ PDF 导入按钮
          if (onImportPdf != null)
            Tooltip(
              message: '导入 PDF',
              child: IconButton(
                icon: const Icon(FontAwesomeIcons.filePdf, size: 20),
                onPressed: onImportPdf,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ),
          // ✅ 背景纸模式选择
          _buildBackgroundPatternSelector(),
        ],
      ),
    );
  }
  
  /// ✅ 构建分组工具选择器（专业、美观、大方）
  Widget _buildToolSelectorGrouped() {
    return Builder(
      builder: (context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ 第一组：笔类工具
            _buildToolGroup(
              context: context,
              title: '笔类',
              tools: [
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
              ],
            ),
            // ✅ 分隔符
            _buildGroupSeparator(context),
            // ✅ 第二组：形状工具
            _buildToolGroup(
              context: context,
              title: '形状',
              tools: [
                _buildToolButton(
                  context: context,
                  icon: FontAwesomeIcons.minus,
                  tool: Pen(
                    toolId: ToolId.line,
                    color: currentColor,
                    strokeWidth: currentStrokeWidth,
                  ),
                  label: '直线',
                ),
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
                  icon: FontAwesomeIcons.shapes,
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
            // ✅ 分隔符
            _buildGroupSeparator(context),
            // ✅ 第三组：其他工具
            _buildToolGroup(
              context: context,
              title: '其他',
              tools: [
                _buildToolButton(
                  context: context,
                  icon: FontAwesomeIcons.eraser,
                  tool: Eraser(strokeWidth: currentStrokeWidth),
                  label: '橡皮擦',
                ),
                _buildToolButton(
                  context: context,
                  icon: FontAwesomeIcons.handPointer,
                  tool: const SelectTool(),
                  label: '选择',
                ),
                _buildToolButton(
                  context: context,
                  icon: FontAwesomeIcons.textHeight,
                  tool: Pen(
                    toolId: ToolId.textBox,
                    color: currentColor,
                    strokeWidth: currentStrokeWidth,
                  ),
                  label: '文本框',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// ✅ 构建工具组
  Widget _buildToolGroup({
    required BuildContext context,
    required String title,
    required List<Widget> tools,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ 组标题
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
          ),
          // ✅ 工具按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: tools,
          ),
        ],
      ),
    );
  }
  
  /// ✅ 构建组分隔符
  Widget _buildGroupSeparator(BuildContext context) {
    return Container(
      width: 1,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
    );
  }

  Widget _buildToolSelector() {
    return Builder(
      builder: (context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
            icon: FontAwesomeIcons.minus,
            tool: Pen(
              toolId: ToolId.line,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '直线',
          ),
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
          // ✅ 文本框工具
          _buildToolButton(
            context: context,
            icon: FontAwesomeIcons.textHeight,
            tool: Pen(
              toolId: ToolId.textBox,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            label: '文本框',
          ),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onToolChanged(tool),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        width: 1,
                      )
                    : null,
              ),
              child: _buildIconWidget(icon, isSelected, context),
            ),
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
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 当前颜色显示（可点击打开颜色选择器）
          GestureDetector(
            onTap: () async {
              final selectedColor = await ColorPickerDialog.show(
                context,
                initialColor: currentColor,
                colorHistory: const [], // TODO: 从存储中读取颜色历史
              );
              if (selectedColor != null) {
                onColorChanged(selectedColor);
              }
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: currentColor,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 预设颜色
          ...presetColors.map((color) {
            final bool isSelected = color == currentColor;
            return Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.only(right: 6),
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
                            : Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3),
                        width: isSelected ? 2.5 : 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
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
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.line_weight,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
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
            width: 36,
            child: Text(
              currentStrokeWidth.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
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

  /// ✅ 判断是否是形状工具
  bool _isShapeTool(ToolId toolId) {
    return toolId == ToolId.rectangle ||
        toolId == ToolId.circle ||
        toolId == ToolId.triangle ||
        toolId == ToolId.diamond;
  }

  /// ✅ 构建填充颜色选择器
  Widget _buildFillColorSelector() {
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 填充颜色标签
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '填充',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          // 当前填充颜色显示（带"无填充"选项）
          GestureDetector(
            onTap: () {
              // 点击切换填充/无填充
              if (onFillColorChanged != null) {
                if (currentFillColor == null) {
                  // 当前无填充，设置为当前描边颜色
                  onFillColorChanged!(currentColor);
                } else {
                  // 当前有填充，取消填充
                  onFillColorChanged!(null);
                }
              }
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: currentFillColor ?? Colors.transparent,
                border: Border.all(
                  color: currentFillColor == null
                      ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: currentFillColor != null
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: currentFillColor == null
                  ? Icon(
                      Icons.close,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          // 预设填充颜色
          ...presetColors.map((color) {
            final bool isSelected = color == currentFillColor;
            return Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    if (onFillColorChanged != null) {
                      onFillColorChanged!(color);
                    }
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3),
                        width: isSelected ? 2.5 : 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
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
}

