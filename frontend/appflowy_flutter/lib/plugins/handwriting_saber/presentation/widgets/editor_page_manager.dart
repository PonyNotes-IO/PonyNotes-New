import 'package:flutter/material.dart';

import '../../third_party/saber_core/data/editor/editor_core_info.dart';
import 'canvas_preview.dart';

/// 页面管理器组件（左侧预览目录）
/// 
/// 参考 Saber 源版的 EditorPageManager 实现：
/// - 显示所有页面的预览缩略图
/// - 支持点击跳转到指定页面
/// - 支持页面拖拽重排序
/// - 每个页面提供操作按钮：插入、复制、清空、删除
class EditorPageManager extends StatefulWidget {
  const EditorPageManager({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.redrawAndSave,
    required this.scrollToPage,
    required this.insertPageAfter,
    required this.duplicatePage,
    required this.clearPage,
    required this.deletePage,
    this.width = 200,
  });

  final EditorCoreInfo coreInfo;
  final int? currentPageIndex;
  final VoidCallback redrawAndSave;
  final void Function(int pageIndex) scrollToPage;
  final void Function(int pageIndex) insertPageAfter;
  final void Function(int pageIndex) duplicatePage;
  final void Function(int pageIndex) clearPage;
  final void Function(int pageIndex) deletePage;
  final double width;

  @override
  State<EditorPageManager> createState() => _EditorPageManagerState();
}

class _EditorPageManagerState extends State<EditorPageManager> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '页面 (${widget.coreInfo.pages.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // 添加页面按钮
                IconButton(
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  tooltip: '在末尾添加新页',
                  onPressed: () {
                    final lastIndex = widget.coreInfo.pages.length - 1;
                    widget.insertPageAfter(lastIndex);
                    // 滚动到新页面
                    Future.delayed(const Duration(milliseconds: 100), () {
                      widget.scrollToPage(lastIndex + 1);
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
          // 页面列表
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.coreInfo.pages.length,
              itemBuilder: (context, pageIndex) {
                final page = widget.coreInfo.pages[pageIndex];
                final isCurrentPage = pageIndex == widget.currentPageIndex;
                final isEmptyLastPage = pageIndex == widget.coreInfo.pages.length - 1 &&
                    page.strokes.isEmpty &&
                    page.textBoxes.isEmpty &&
                    page.images.isEmpty &&
                    page.backgroundImage == null;
                
                return _PageItem(
                  key: ValueKey('page_$pageIndex'),
                  pageIndex: pageIndex,
                  totalPages: widget.coreInfo.pages.length,
                  coreInfo: widget.coreInfo,
                  isCurrentPage: isCurrentPage,
                  isEmptyLastPage: isEmptyLastPage,
                  onTap: () => widget.scrollToPage(pageIndex),
                  onInsert: () {
                    widget.insertPageAfter(pageIndex);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      widget.scrollToPage(pageIndex + 1);
                    });
                  },
                  onDuplicate: () {
                    widget.duplicatePage(pageIndex);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      widget.scrollToPage(pageIndex + 1);
                    });
                  },
                  onClear: isEmptyLastPage ? null : () {
                    widget.clearPage(pageIndex);
                  },
                  onDelete: isEmptyLastPage ? null : () {
                    widget.deletePage(pageIndex);
                    // 如果删除当前页，滚动到前一页
                    if (isCurrentPage && pageIndex > 0) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        widget.scrollToPage(pageIndex - 1);
                      });
                    }
                  },
                );
              },
              onReorder: (oldIndex, newIndex) {
                if (oldIndex == newIndex) return;
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                
                // 移动页面
                final page = widget.coreInfo.pages.removeAt(oldIndex);
                widget.coreInfo.pages.insert(newIndex, page);
                
                // ✅ 页面索引已通过列表顺序隐式确定
                // 注意：当前实现中笔迹和图片不单独存储 pageIndex，
                // 而是通过它们在页面列表中的位置来确定所属页面
                
                widget.redrawAndSave();
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个页面项
class _PageItem extends StatelessWidget {
  const _PageItem({
    super.key,
    required this.pageIndex,
    required this.totalPages,
    required this.coreInfo,
    required this.isCurrentPage,
    required this.isEmptyLastPage,
    required this.onTap,
    required this.onInsert,
    required this.onDuplicate,
    this.onClear,
    this.onDelete,
  });

  final int pageIndex;
  final int totalPages;
  final EditorCoreInfo coreInfo;
  final bool isCurrentPage;
  final bool isEmptyLastPage;
  final VoidCallback onTap;
  final VoidCallback onInsert;
  final VoidCallback onDuplicate;
  final VoidCallback? onClear;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: isCurrentPage 
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrentPage 
                    ? colorScheme.primary
                    : colorScheme.outline.withValues(alpha: 0.2),
                width: isCurrentPage ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 页码和拖拽手柄
                Row(
                  children: [
                    Text(
                      '${pageIndex + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isCurrentPage 
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: isCurrentPage ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      ' / $totalPages',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    const Spacer(),
                    // 拖拽手柄
                    ReorderableDragStartListener(
                      index: pageIndex,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 页面预览
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CanvasPreview(
                    pageIndex: pageIndex,
                    height: 120,
                    coreInfo: coreInfo,
                  ),
                ),
                const SizedBox(height: 8),
                // 操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.add,
                      tooltip: '在此后插入新页',
                      onPressed: onInsert,
                      colorScheme: colorScheme,
                    ),
                    _ActionButton(
                      icon: Icons.content_copy,
                      tooltip: '复制此页',
                      onPressed: onDuplicate,
                      colorScheme: colorScheme,
                    ),
                    _ActionButton(
                      icon: Icons.cleaning_services,
                      tooltip: '清空此页',
                      onPressed: onClear,
                      colorScheme: colorScheme,
                    ),
                    _ActionButton(
                      icon: Icons.delete_outline,
                      tooltip: '删除此页',
                      onPressed: onDelete,
                      colorScheme: colorScheme,
                      isDestructive: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 操作按钮
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    required this.colorScheme,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled
        ? (isDestructive ? colorScheme.error : colorScheme.onSurfaceVariant)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3);
    
    return IconButton(
      icon: Icon(icon, size: 16, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(
        minWidth: 28,
        minHeight: 28,
      ),
    );
  }
}
