import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:collapsible/collapsible.dart';

import '../third_party/saber_core/components/canvas/canvas_background_pattern.dart';
import '../third_party/saber_core/data/tools/tool.dart';
import '../third_party/saber_core/data/editor/quill_struct.dart';
import 'color_picker_dialog.dart';
import 'widgets/tool_dropdown_button.dart';

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
    this.onImportImage, // ✅ 图片导入回调（可选）
    this.onInsertWebView, // ✅ 网页嵌入回调（可选）
    this.onExtractPdfText, // ✅ PDF文本提取回调（可选）
    this.canUndo = false, // ✅ 是否可以撤销
    this.canRedo = false, // ✅ 是否可以恢复
    this.onUndo, // ✅ 撤销回调（可选）
    this.onRedo, // ✅ 恢复回调（可选）
    this.currentDashStyle, // ✅ 当前虚线样式（可选）
    this.onDashStyleChanged, // ✅ 虚线样式改变回调（可选）
    this.currentArrowStyle, // ✅ 当前箭头样式（可选）
    this.onArrowStyleChanged, // ✅ 箭头样式改变回调（可选）
    this.textEditingMode = false, // ✅ 文本编辑模式标志
    this.onToggleTextEditingMode, // ✅ 切换文本编辑模式回调
    this.quillFocus, // ✅ 当前焦点的 Quill 结构（用于显示 Quill 工具栏）
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
  final VoidCallback? onImportImage;  // ✅ 图片导入回调
  final VoidCallback? onInsertWebView;  // ✅ 网页嵌入回调
  final VoidCallback? onExtractPdfText;  // ✅ PDF文本提取回调
  final bool canUndo; // ✅ 是否可以撤销
  final bool canRedo; // ✅ 是否可以恢复
  final VoidCallback? onUndo; // ✅ 撤销回调
  final VoidCallback? onRedo; // ✅ 恢复回调
  final DashStyle? currentDashStyle; // ✅ 当前虚线样式（可选）
  final ValueChanged<DashStyle>? onDashStyleChanged; // ✅ 虚线样式改变回调（可选）
  final ArrowStyle? currentArrowStyle; // ✅ 当前箭头样式（可选）
  final ValueChanged<ArrowStyle>? onArrowStyleChanged; // ✅ 箭头样式改变回调（可选）
  final bool textEditingMode; // ✅ 文本编辑模式标志
  final VoidCallback? onToggleTextEditingMode; // ✅ 切换文本编辑模式回调
  final QuillStruct? quillFocus; // ✅ 当前焦点的 Quill 结构（用于显示 Quill 工具栏）

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ 主工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
          // ✅ 使用SingleChildScrollView包裹整个工具栏，确保所有内容都可以横向滚动
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ 撤销/恢复按钮
                _buildUndoRedoButtons(),
                _buildDivider(),
                // ✅ 工具选择（分组显示）
                _buildToolSelectorGrouped(),
                // ✅ 分隔线
                _buildDivider(),
                // ✅ 颜色选择
                _buildColorSelector(),
                // ✅ 填充颜色选择（仅形状工具显示）
                if (_isShapeTool(currentTool.toolId) && onFillColorChanged != null) ...[
                  const SizedBox(width: 8),
                  _buildFillColorSelector(),
                ],
                // ✅ 分隔线
                _buildDivider(),
                // ✅ 粗细调整
                _buildStrokeWidthSelector(),
                // ✅ 分隔线
                _buildDivider(),
                // ✅ 其他工具（PDF导入、背景模式、文本编辑）
                _buildOtherToolsSection(),
              ],
            ),
          ),
        ),
        // ✅ Quill 富文本工具栏（只在文本编辑模式下显示）
        _buildQuillToolbar(context),
      ],
    );
  }
  
  /// ✅ 构建分隔线（紧凑布局）
  Widget _buildDivider() {
    return Builder(
      builder: (context) => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
      ),
    );
  }
  
  
  /// ✅ 构建其他工具区域
  Widget _buildOtherToolsSection() {
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ 虚线样式选择器
          if (onDashStyleChanged != null) ...[
            _buildDashStyleSelector(),
            const SizedBox(width: 4),
          ],
          // ✅ 箭头样式选择器
          if (onArrowStyleChanged != null) ...[
            _buildArrowStyleSelector(),
            const SizedBox(width: 4),
          ],
          // ✅ 图片导入按钮
          if (onImportImage != null)
            Tooltip(
              message: '导入图片',
              child: IconButton(
                icon: const Icon(FontAwesomeIcons.image, size: 20),
                onPressed: onImportImage,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ),
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
          // ✅ PDF文本选择工具下拉按钮（替代原有的PDF文本提取按钮）
          if (onExtractPdfText != null)
            ToolDropdownButton(
              currentTool: currentTool,
              mainTool: const PdfTextSelectTool(selectMode: PdfTextSelectMode.rectangle),
              options: [
                ToolOption(
                  icon: FontAwesomeIcons.rectangleList,
                  label: '矩形选择',
                  tool: const PdfTextSelectTool(selectMode: PdfTextSelectMode.rectangle),
                ),
                ToolOption(
                  icon: FontAwesomeIcons.textWidth,
                  label: '线性选择',
                  tool: const PdfTextSelectTool(selectMode: PdfTextSelectMode.linear),
                ),
              ],
              onToolChanged: onToolChanged,
            ),
          // ✅ 网页嵌入按钮
          if (onInsertWebView != null)
            Tooltip(
              message: '嵌入网页',
              child: IconButton(
                icon: const Icon(FontAwesomeIcons.globe, size: 20),
                onPressed: onInsertWebView,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ),
          // ✅ 移除独立的富文本编辑按钮，整合到文本框工具中
          // ✅ 背景纸模式选择
          _buildBackgroundPatternSelector(),
        ],
      ),
    );
  }
  
  /// ✅ 构建分组工具选择器（使用下拉按钮优化布局）
  Widget _buildToolSelectorGrouped() {
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ 画笔工具下拉按钮
          ToolDropdownButton(
            currentTool: currentTool,
            mainTool: Pen(
              toolId: ToolId.pencil,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            options: [
              ToolOption(
                icon: FontAwesomeIcons.penFancy,
                label: '钢笔',
                tool: Pen(
                  toolId: ToolId.fountainPen,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.pen,
                label: '圆珠笔',
                tool: Pen(
                  toolId: ToolId.ballpointPen,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.pencil,
                label: '铅笔',
                tool: Pen(
                  toolId: ToolId.pencil,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.highlighter,
                label: '荧光笔',
                tool: Pen(
                  toolId: ToolId.highlighter,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: Symbols.stylus_laser_pointer,
                label: '激光笔',
                tool: Pen(
                  toolId: ToolId.laserPointer,
                  color: Colors.red,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
            ],
            onToolChanged: onToolChanged,
          ),
          const SizedBox(width: 4),
          
          // ✅ 形状工具下拉按钮
          ToolDropdownButton(
            currentTool: currentTool,
            mainTool: Pen(
              toolId: ToolId.rectangle,
              color: currentColor,
              strokeWidth: currentStrokeWidth,
            ),
            options: [
              ToolOption(
                icon: FontAwesomeIcons.square,
                label: '矩形',
                tool: Pen(
                  toolId: ToolId.rectangle,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.circle,
                label: '圆形',
                tool: Pen(
                  toolId: ToolId.circle,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.shapes,
                label: '三角形',
                tool: Pen(
                  toolId: ToolId.triangle,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.diamond,
                label: '菱形',
                tool: Pen(
                  toolId: ToolId.diamond,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
              ToolOption(
                icon: FontAwesomeIcons.drawPolygon,
                label: '自由多边形',
                tool: Pen(
                  toolId: ToolId.freePolygon,
                  color: currentColor,
                  strokeWidth: currentStrokeWidth,
                ),
              ),
            ],
            onToolChanged: onToolChanged,
          ),
          
          // ✅ 分隔符
          _buildGroupSeparator(context),
          
          // ✅ 橡皮擦下拉按钮
          ToolDropdownButton(
            currentTool: currentTool,
            mainTool: (currentTool is Eraser)
                ? (currentTool as Eraser).copyWith(strokeWidth: currentStrokeWidth)
                : Eraser(strokeWidth: currentStrokeWidth, mode: EraserMode.standard),
            options: [
              ToolOption(
                icon: FontAwesomeIcons.eraser,
                label: '标准',
                tool: Eraser(strokeWidth: currentStrokeWidth, mode: EraserMode.standard),
              ),
              ToolOption(
                icon: FontAwesomeIcons.eraser,
                label: '涂白',
                tool: Eraser(strokeWidth: currentStrokeWidth, mode: EraserMode.whiteout),
              ),
              ToolOption(
                icon: FontAwesomeIcons.eraser,
                label: '删除笔画',
                tool: Eraser(strokeWidth: currentStrokeWidth, mode: EraserMode.deleteStrokes),
              ),
            ],
            onToolChanged: onToolChanged,
          ),
          // ✅ 选择工具下拉按钮
          ToolDropdownButton(
            currentTool: currentTool,
            mainTool: const SelectTool(),
            options: [
              ToolOption(
                icon: FontAwesomeIcons.handPointer,
                label: '点选',
                tool: const SelectTool(selectMode: SelectMode.click),
              ),
              ToolOption(
                icon: FontAwesomeIcons.vectorSquare,
                label: '框选',
                tool: const SelectTool(selectMode: SelectMode.rectangle),
              ),
              ToolOption(
                icon: FontAwesomeIcons.drawPolygon,
                label: '套索',
                tool: const SelectTool(selectMode: SelectMode.lasso),
              ),
            ],
            onToolChanged: onToolChanged,
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
    );
  }
  
  /// ✅ 构建组分隔符（紧凑布局）
  Widget _buildGroupSeparator(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
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
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onToolChanged(tool),
            child: Container(
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
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
      builder: (context) => PopupMenuButton<String>(
        tooltip: '边框颜色',
        onSelected: (value) {
          if (value == '_custom_') {
            // 自定义颜色选项 - 使用Future.microtask确保popup完全关闭后再显示对话框
            Future.microtask(() async {
              final selectedColor = await ColorPickerDialog.show(
                context,
                initialColor: currentColor,
                colorHistory: const [], // TODO: 从存储中读取颜色历史
              );
              if (selectedColor != null) {
                onColorChanged(selectedColor);
              }
            });
          } else {
            // 预设颜色 - 从颜色索引解析
            final colorIndex = int.parse(value);
            onColorChanged(presetColors[colorIndex]);
          }
        },
        itemBuilder: (ctx) => [
          // 预设颜色选项
          ...presetColors.asMap().entries.map((entry) {
            final index = entry.key;
            final color = entry.value;
            final bool isSelected = color == currentColor;
            return PopupMenuItem<String>(
              value: index.toString(),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_getColorName(color)),
                  if (isSelected) ...[
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
          }),
          // 分隔线
          const PopupMenuDivider(),
          // 自定义颜色选项
          const PopupMenuItem<String>(
            value: '_custom_',
            child: Row(
              children: [
                Icon(Icons.color_lens, size: 24),
                SizedBox(width: 12),
                Text('自定义颜色'),
              ],
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 当前颜色显示
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: currentColor,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ 获取颜色名称
  String _getColorName(Color color) {
    if (color == Colors.black) return '黑色';
    if (color == Colors.blue) return '蓝色';
    if (color == Colors.red) return '红色';
    if (color == Colors.green) return '绿色';
    if (color == Colors.orange) return '橙色';
    if (color == Colors.purple) return '紫色';
    if (color == Colors.pink) return '粉色';
    if (color == Colors.brown) return '棕色';
    return '自定义';
  }

  Widget _buildStrokeWidthSelector() {
    return Builder(
      builder: (context) {
        // ✅ 判断当前工具是否需要显示粗细调整器
        // 选择工具不需要调整粗细，所以禁用或隐藏
        final bool isSelectTool = currentTool.toolId == ToolId.select;
        
        // ✅ 确保值在有效范围内（防止 SelectTool 的 strokeWidth=0 导致断言失败）
        final double clampedWidth = currentStrokeWidth.clamp(1.0, 20.0);
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.line_weight,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: isSelectTool ? 0.3 : 0.7),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: Slider(
                value: clampedWidth,
                min: 1,
                max: 20,
                divisions: 19,
                label: clampedWidth.toStringAsFixed(0),
                onChanged: isSelectTool ? null : onStrokeWidthChanged, // ✅ 选择工具时禁用
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                clampedWidth.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: isSelectTool ? 0.3 : 1.0),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.grid_view, size: 18),
              const SizedBox(width: 4),
              Text(
                _getBackgroundPatternName(currentBackgroundPattern),
                style: const TextStyle(fontSize: 12),
              ),
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

  /// ✅ 构建填充颜色选择器（下拉框形式）
  Widget _buildFillColorSelector() {
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 填充颜色标签（紧凑）
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '填充',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          // 填充颜色下拉按钮
          PopupMenuButton<String>(
            tooltip: '填充颜色',
            onSelected: (value) {
              if (onFillColorChanged == null) return;
              
              if (value == '_none_') {
                // 无填充
                onFillColorChanged!(null);
              } else if (value == '_custom_') {
                // 自定义颜色选项 - 使用Future.microtask确保popup完全关闭后再显示对话框
                Future.microtask(() async {
                  final selectedColor = await ColorPickerDialog.show(
                    context,
                    initialColor: currentFillColor ?? currentColor,
                    colorHistory: const [], // TODO: 从存储中读取颜色历史
                  );
                  if (selectedColor != null) {
                    onFillColorChanged!(selectedColor);
                  }
                });
              } else {
                // 预设颜色 - 从颜色索引解析
                final colorIndex = int.parse(value);
                onFillColorChanged!(presetColors[colorIndex]);
              }
            },
            itemBuilder: (ctx) => [
              // 无填充选项
              PopupMenuItem<String>(
                value: '_none_',
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: Border.all(
                          color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('无填充'),
                    if (currentFillColor == null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check,
                        size: 16,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
              // 预设颜色选项
              ...presetColors.asMap().entries.map((entry) {
                final index = entry.key;
                final color = entry.value;
                final bool isSelected = color == currentFillColor;
                return PopupMenuItem<String>(
                  value: index.toString(),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_getColorName(color)),
                      if (isSelected) ...[
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
              }),
              // 分隔线
              const PopupMenuDivider(),
              // 自定义颜色选项
              const PopupMenuItem<String>(
                value: '_custom_',
                child: Row(
                  children: [
                    Icon(Icons.color_lens, size: 24),
                    SizedBox(width: 12),
                    Text('自定义颜色'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 当前填充颜色显示
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: currentFillColor ?? Colors.transparent,
                      border: Border.all(
                        color: currentFillColor == null
                            ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)
                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
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
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// ✅ 构建撤销/恢复按钮
  Widget _buildUndoRedoButtons() {
    return Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 撤销按钮
          Tooltip(
            message: '撤销',
            child: IconButton(
              icon: const Icon(Icons.undo, size: 20),
              onPressed: canUndo ? onUndo : null,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              color: canUndo
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
          // 恢复按钮
          Tooltip(
            message: '恢复',
            child: IconButton(
              icon: const Icon(Icons.redo, size: 20),
              onPressed: canRedo ? onRedo : null,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              color: canRedo
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 构建虚线样式选择器（集成直线工具按钮）
  Widget _buildDashStyleSelector() {
    return Builder(
      builder: (context) {
        final bool isLineToolSelected = currentTool.toolId == ToolId.line;
        return Container(
          decoration: BoxDecoration(
            color: isLineToolSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isLineToolSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 主按钮：切换到直线工具
              Tooltip(
                message: '直线',
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                  onTap: () {
                    onToolChanged(Pen(
                      toolId: ToolId.line,
                      color: currentColor,
                      strokeWidth: currentStrokeWidth,
                    ));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: _getDashStyleIcon(currentDashStyle ?? DashStyle.solid, context),
                  ),
                ),
              ),
              // 分隔线
              Container(
                width: 1,
                height: 24,
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
              // 下拉按钮：选择虚线样式
              PopupMenuButton<DashStyle>(
                tooltip: '虚线样式',
                onSelected: (style) {
                  if (onDashStyleChanged != null) {
                    onDashStyleChanged!(style);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: DashStyle.solid,
                    child: Row(
                      children: [
                        const Icon(FontAwesomeIcons.minus, size: 16),
                        const SizedBox(width: 12),
                        const Text('实线'),
                        if (currentDashStyle == DashStyle.solid) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: DashStyle.shortDash,
                    child: Row(
                      children: [
                        const Text('- - -', style: TextStyle(letterSpacing: 2)),
                        const SizedBox(width: 12),
                        const Text('短虚线'),
                        if (currentDashStyle == DashStyle.shortDash) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: DashStyle.longDash,
                    child: Row(
                      children: [
                        const Text('— —', style: TextStyle(letterSpacing: 2)),
                        const SizedBox(width: 12),
                        const Text('长虚线'),
                        if (currentDashStyle == DashStyle.longDash) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getDashStyleName(currentDashStyle ?? DashStyle.solid),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ✅ 构建箭头样式选择器（集成箭头工具按钮）
  Widget _buildArrowStyleSelector() {
    return Builder(
      builder: (context) {
        final bool isArrowToolSelected = currentTool.toolId == ToolId.arrowLine;
        return Container(
          decoration: BoxDecoration(
            color: isArrowToolSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isArrowToolSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 主按钮：切换到箭头工具
              Tooltip(
                message: '箭头',
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                  onTap: () {
                    onToolChanged(Pen(
                      toolId: ToolId.arrowLine,
                      color: currentColor,
                      strokeWidth: currentStrokeWidth,
                    ));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: _getArrowStyleIcon(currentArrowStyle ?? ArrowStyle.filled),
                  ),
                ),
              ),
              // 分隔线
              Container(
                width: 1,
                height: 24,
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
              // 下拉按钮：选择箭头样式
              PopupMenuButton<ArrowStyle>(
                tooltip: '箭头样式',
                onSelected: (style) {
                  if (onArrowStyleChanged != null) {
                    onArrowStyleChanged!(style);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: ArrowStyle.filled,
                    child: Row(
                      children: [
                        const Text('➤', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 12),
                        const Text('实心箭头'),
                        if (currentArrowStyle == ArrowStyle.filled) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ArrowStyle.hollow,
                    child: Row(
                      children: [
                        const Text('⇢', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 12),
                        const Text('空心箭头'),
                        if (currentArrowStyle == ArrowStyle.hollow) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ArrowStyle.line,
                    child: Row(
                      children: [
                        const Icon(FontAwesomeIcons.arrowRight, size: 16),
                        const SizedBox(width: 12),
                        const Text('线条箭头'),
                        if (currentArrowStyle == ArrowStyle.line) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ArrowStyle.doubleArrow,
                    child: Row(
                      children: [
                        const Icon(FontAwesomeIcons.arrowsLeftRight, size: 16),
                        const SizedBox(width: 12),
                        const Text('双向箭头'),
                        if (currentArrowStyle == ArrowStyle.doubleArrow) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getArrowStyleName(currentArrowStyle ?? ArrowStyle.filled),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ✅ 获取虚线样式图标
  Widget _getDashStyleIcon(DashStyle style, BuildContext context) {
    switch (style) {
      case DashStyle.solid:
        return const Icon(FontAwesomeIcons.minus, size: 16);
      case DashStyle.shortDash:
        return const Text('- -', style: TextStyle(fontSize: 12, letterSpacing: 1));
      case DashStyle.longDash:
        return const Text('—', style: TextStyle(fontSize: 14));
      default:
        return const Icon(FontAwesomeIcons.minus, size: 16);
    }
  }

  /// ✅ 获取虚线样式名称
  String _getDashStyleName(DashStyle style) {
    switch (style) {
      case DashStyle.solid:
        return '实线';
      case DashStyle.shortDash:
        return '短虚线';
      case DashStyle.longDash:
        return '长虚线';
      default:
        return '实线';
    }
  }

  /// ✅ 获取箭头样式图标
  Widget _getArrowStyleIcon(ArrowStyle style) {
    switch (style) {
      case ArrowStyle.filled:
        return const Text('➤', style: TextStyle(fontSize: 14));
      case ArrowStyle.hollow:
        return const Text('⇢', style: TextStyle(fontSize: 14));
      case ArrowStyle.line:
        return const Icon(FontAwesomeIcons.arrowRight, size: 14);
      case ArrowStyle.doubleArrow:
        return const Icon(FontAwesomeIcons.arrowsLeftRight, size: 14);
    }
  }

  /// ✅ 获取箭头样式名称
  String _getArrowStyleName(ArrowStyle style) {
    switch (style) {
      case ArrowStyle.filled:
        return '实心';
      case ArrowStyle.hollow:
        return '空心';
      case ArrowStyle.line:
        return '线条';
      case ArrowStyle.doubleArrow:
        return '双向';
    }
  }
  
  /// ✅ 构建 Quill 富文本工具栏（只在文本编辑模式下显示）
  Widget _buildQuillToolbar(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    
    // 创建图标主题
    final baseButtonStyle = IconButtonTheme.of(context).style ?? const ButtonStyle();
    final iconTheme = quill.QuillIconTheme(
      iconButtonUnselectedData: quill.IconButtonData(
        style: baseButtonStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(colorScheme.primary),
        ),
      ),
      iconButtonSelectedData: quill.IconButtonData(
        style: baseButtonStyle.copyWith(
          backgroundColor: WidgetStateProperty.all(colorScheme.primary),
          foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
        ),
      ),
    );
    
    // ✅ 字号选项配置（显示名称 -> 实际值）
    // 注意：flutter_quill 的 getFontSize 只接受纯数字字符串，不能带 px 后缀
    const fontSizeItems = <String, String>{
      '12': '12',
      '14': '14',
      '16': '16',
      '18': '18',
      '20': '20',
      '24': '24',
      '28': '28',
      '32': '32',
      '36': '36',
      '48': '48',
      '清除': '0', // 清除字号格式
    };
    
    // ✅ 当有活动的 Quill 结构时显示工具栏（可能来自文本框或全页面富文本编辑）
    return Collapsible(
      axis: CollapsibleAxis.vertical,
      maintainState: false,
      collapsed: quillFocus == null, // ✅ 只要有 Quill 焦点就显示，不再依赖 textEditingMode
      child: quillFocus != null
          ? Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: quill.QuillSimpleToolbar(
                controller: quillFocus!.controller,
                config: quill.QuillSimpleToolbarConfig(
                  axis: Axis.horizontal,
                  buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                    base: quill.QuillToolbarBaseButtonOptions(
                      iconTheme: iconTheme,
                    ),
                    // ✅ 配置字号选择器
                    fontSize: quill.QuillToolbarFontSizeButtonOptions(
                      items: fontSizeItems,
                      initialValue: '字号',
                      defaultDisplayText: '字号',
                    ),
                  ),
                  multiRowsDisplay: true,
                  showUndo: false,
                  showRedo: false,
                  showFontSize: true, // ✅ 启用字号选择器
                  showFontFamily: false,
                  showClearFormat: true,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showColorButton: true,
                  showBackgroundColorButton: true,
                  showListNumbers: true,
                  showListBullets: true,
                  showAlignmentButtons: true,
                  showDirection: false,
                  showLink: true,
                  showQuote: true,
                  showIndent: true,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

