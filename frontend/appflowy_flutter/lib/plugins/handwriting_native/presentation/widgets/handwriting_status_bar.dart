import 'package:flutter/material.dart';

/// 底部状态栏：页面信息 / 图层占位 / 缩放控制
class HandwritingStatusBar extends StatelessWidget {
  const HandwritingStatusBar({
    super.key,
    required this.currentPageIndex,
    required this.pageCount,
    required this.zoom,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onZoomChanged,
  });

  final int currentPageIndex;
  final int pageCount;
  final double zoom;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
        ),
      ),
      child: Row(
        children: [
          // 页面信息
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            tooltip: '上一页',
            onPressed: currentPageIndex > 0 ? onPrevPage : null,
          ),
          Text(
            '页面 ${currentPageIndex + 1} / $pageCount',
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            tooltip: '下一页',
            onPressed: currentPageIndex < pageCount - 1 ? onNextPage : null,
          ),
          const VerticalDivider(width: 12),

          // 图层信息占位
          Text(
            '图层 1',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const VerticalDivider(width: 12),

          // 缩放控制
          SizedBox(
            width: 180,
            child: Row(
              children: [
                Text(
                  '${(zoom * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall,
                ),
                Expanded(
                  child: Slider(
                    min: 0.5,
                    max: 3.0,
                    divisions: 25,
                    value: zoom.clamp(0.5, 3.0),
                    onChanged: onZoomChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

