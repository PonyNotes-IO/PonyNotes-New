import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/plugins/handwriting_native/application/handwriting_native_service.dart';

class HandwritingNativePage extends StatefulWidget {
  const HandwritingNativePage({
    super.key,
    required this.view,
    required this.onViewChanged,
  });

  final ViewPB view;
  final Function(ViewPB) onViewChanged;

  @override
  State<HandwritingNativePage> createState() => _HandwritingNativePageState();
}

class _HandwritingNativePageState extends State<HandwritingNativePage> {
  final HandwritingNativeService _service = HandwritingNativeService();
  bool _isInitializing = true;
  String? _errorMessage;

  /// 当前选中的工具
  _HandwritingTool _selectedTool = _HandwritingTool.pen;

  /// 当前画笔颜色
  Color _selectedColor = Colors.orangeAccent;

  /// 当前画笔粗细
  double _strokeWidth = 3.0;

  @override
  void initState() {
    super.initState();
    print('🎨 [HandwritingNativePage] initState called');
    print('🎨 [HandwritingNativePage] view.id: ${widget.view.id}');
    print('🎨 [HandwritingNativePage] view.name: ${widget.view.name}');
    print('🎨 [HandwritingNativePage] view.layout: ${widget.view.layout}');
    
    _initializeDocument();
  }

  Future<void> _initializeDocument() async {
    try {
      print('🔧 [HandwritingNativePage] Initializing document...');
      final docId = await _service.getOrCreateDoc(widget.view.id);
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
          if (docId == null) {
            _errorMessage = '无法创建或打开文档';
          }
        });
      }
    } catch (e) {
      print('❌ [HandwritingNativePage] Initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '初始化失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    print('🗑️ [HandwritingNativePage] dispose called for view: ${widget.view.id}');
    // 关闭文档
    _service.closeDoc(widget.view.id).then((success) {
      if (success) {
        print('✅ [HandwritingNativePage] Document closed');
      } else {
        print('⚠️ [HandwritingNativePage] Failed to close document');
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🖼️ [HandwritingNativePage] build() called');
    
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.view.name),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化手写笔记...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.view.name),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        toolbarHeight: 56,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.view.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 顶部菜单：保存 / 导出（暂为占位）
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('保存功能开发中（将调用 xopp / PNG 导出）'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('导出功能开发中（计划支持 PNG / PDF）'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_outlined, size: 18),
            label: const Text('导出'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  theme.colorScheme.outlineVariant.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          _buildLeftToolbar(theme),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopInfoBar(theme),
                const Divider(height: 1),
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surface,
                    padding: const EdgeInsets.all(16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.draw_rounded,
                              size: 72,
                              color: theme.colorScheme.primary.withOpacity(0.6),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '手写笔记（原生）',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '画布与笔迹渲染正在集成 Xournal++，当前为 UI 原型状态',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '视图ID: ${widget.view.id}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 左侧垂直工具栏（笔、橡皮擦、荧光笔、选择等）
  Widget _buildLeftToolbar(ThemeData theme) {
    final items = [
      (_HandwritingTool.pen, Icons.edit_outlined, '画笔'),
      (_HandwritingTool.eraser, Icons.cleaning_services_outlined, '橡皮擦'),
      (_HandwritingTool.highlighter, Icons.brush_outlined, '荧光笔'),
      (_HandwritingTool.selector, Icons.crop_free, '选择'),
    ];

    return Container(
      width: 72,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final item in items)
            _HandwritingToolButton(
              icon: item.$2,
              label: item.$3,
              selected: _selectedTool == item.$1,
              onTap: () {
                setState(() {
                  _selectedTool = item.$1;
                });
              },
            ),
          const Spacer(),
          // 颜色与粗细简易控制条（占位）
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_strokeWidth.toStringAsFixed(1)} px',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// 顶部信息条：显示当前工具 / 颜色等（为后续快捷操作预留）
  Widget _buildTopInfoBar(ThemeData theme) {
    String toolLabel;
    switch (_selectedTool) {
      case _HandwritingTool.pen:
        toolLabel = '画笔';
        break;
      case _HandwritingTool.eraser:
        toolLabel = '橡皮擦';
        break;
      case _HandwritingTool.highlighter:
        toolLabel = '荧光笔';
        break;
      case _HandwritingTool.selector:
        toolLabel = '选择';
        break;
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            '当前工具：$toolLabel',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 24),
          Text(
            '颜色：#${_selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 内部使用的工具枚举
enum _HandwritingTool {
  pen,
  eraser,
  highlighter,
  selector,
}

class _HandwritingToolButton extends StatelessWidget {
  const _HandwritingToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

