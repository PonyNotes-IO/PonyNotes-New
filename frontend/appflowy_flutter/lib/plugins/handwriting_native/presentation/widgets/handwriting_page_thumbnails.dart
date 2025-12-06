import 'package:flutter/material.dart';

/// 左侧页面缩略图栏
class HandwritingPageThumbnails extends StatelessWidget {
  const HandwritingPageThumbnails({
    super.key,
    required this.pageCount,
    required this.currentPageIndex,
    required this.onPageSelected,
    required this.onAddPage,
    required this.onRemovePage,
    required this.renderThumbnail,
  });

  final int pageCount;
  final int currentPageIndex;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAddPage;
  final VoidCallback onRemovePage;
  final Future<ImageProvider?> Function(int pageIndex) renderThumbnail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      child: Column(
        children: [
          // 顶部操作按钮：添加 / 删除
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: '添加页面',
                  icon: const Icon(Icons.add),
                  onPressed: onAddPage,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: '删除页面',
                  icon: const Icon(Icons.remove),
                  onPressed: onRemovePage,
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                Text(
                  '$pageCount 页',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: pageCount,
              itemBuilder: (context, index) {
                return _ThumbnailItem(
                  index: index,
                  selected: index == currentPageIndex,
                  renderThumbnail: () => renderThumbnail(index),
                  onTap: () => onPageSelected(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailItem extends StatefulWidget {
  const _ThumbnailItem({
    required this.index,
    required this.selected,
    required this.renderThumbnail,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final Future<ImageProvider?> Function() renderThumbnail;
  final VoidCallback onTap;

  @override
  State<_ThumbnailItem> createState() => _ThumbnailItemState();
}

class _ThumbnailItemState extends State<_ThumbnailItem> {
  ImageProvider? _thumb;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final img = await widget.renderThumbnail();
      if (mounted) {
        setState(() {
          _thumb = img;
        });
      }
    } catch (_) {
      // ignore errors for thumbnail rendering
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: widget.selected
              ? theme.colorScheme.primary.withOpacity(0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withOpacity(0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 210 / 297, // A4 约等于 1:1.414
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                  ),
                ),
                child: _buildThumbContent(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '第 ${widget.index + 1} 页',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbContent() {
    if (_loading) {
      return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_thumb != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image(
          image: _thumb!,
          fit: BoxFit.cover,
        ),
      );
    }
    return const Center(
      child: Icon(Icons.image_not_supported_outlined, size: 22, color: Colors.grey),
    );
  }
}

