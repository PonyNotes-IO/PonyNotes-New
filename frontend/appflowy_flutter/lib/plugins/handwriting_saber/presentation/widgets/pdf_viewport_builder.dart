import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 渲染视口中全部 PDF 底图，并预加载当前页及前后各一页。
///
/// 只让背景层订阅页码，避免滚动时重建笔迹、输入框和整个编辑器。
class PdfViewportBuilder extends StatelessWidget {
  const PdfViewportBuilder({
    super.key,
    required this.pageIndex,
    required this.viewingPageIndex,
    required this.builder,
    this.scrollController,
    this.pageTop = 0,
    this.pageHeight = 0,
    this.viewportHeight = 0,
  });

  final int pageIndex;
  final ValueListenable<int> viewingPageIndex;
  final Widget Function(BuildContext context, bool renderPdf) builder;
  final ScrollController? scrollController;
  final double pageTop;
  final double pageHeight;
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewingPageIndex,
        if (scrollController != null) scrollController!,
      ]),
      builder: (context, _) {
        final controller = scrollController;
        final offset = controller != null && controller.hasClients
            ? controller.offset
            : 0.0;
        final isVisible = controller != null &&
            viewportHeight > 0 &&
            pageTop < offset + viewportHeight &&
            pageTop + pageHeight > offset;
        return builder(
          context,
          isVisible || (pageIndex - viewingPageIndex.value).abs() <= 1,
        );
      },
    );
  }
}
