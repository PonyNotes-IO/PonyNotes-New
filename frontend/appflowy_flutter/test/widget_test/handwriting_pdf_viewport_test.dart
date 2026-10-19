import 'package:appflowy/plugins/handwriting_saber/presentation/widgets/pdf_viewport_builder.dart';
import 'package:appflowy/plugins/handwriting_saber/presentation/widgets/canvas_preview.dart';
import 'package:appflowy/plugins/handwriting_saber/presentation/widgets/editor_page_manager.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/editor_core_info.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RenderedPdfPage extends StatefulWidget {
  const _RenderedPdfPage({required this.pageIndex, required this.activePages});

  final int pageIndex;
  final Set<int> activePages;

  @override
  State<_RenderedPdfPage> createState() => _RenderedPdfPageState();
}

class _RenderedPdfPageState extends State<_RenderedPdfPage> {
  @override
  void initState() {
    super.initState();
    widget.activePages.add(widget.pageIndex);
  }

  @override
  void dispose() {
    widget.activePages.remove(widget.pageIndex);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  testWidgets('手机页面管理保留16页并可单指滚动到第15页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coreInfo = EditorCoreInfo(
      pages: [
        ...List.generate(
          15,
          (index) => EditorPage(
            size: EditorPage.defaultSize,
            backgroundImage: PdfEditorImage(
              pdfFilePath: '/test/15pages.pdf',
              pdfPageIndex: index,
              naturalSize: EditorPage.defaultSize,
            ),
          ),
        ),
        EditorPage(size: EditorPage.defaultSize),
      ],
    );
    addTearDown(() {
      for (final page in coreInfo.pages) {
        page.backgroundImage?.dispose();
        page.quill.dispose();
      }
    });
    int? targetPage;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Row(
            children: [
              EditorPageManager(
                coreInfo: coreInfo,
                currentPageIndex: 0,
                redrawAndSave: () {},
                scrollToPage: (index, {constraints}) => targetPage = index,
                insertPageAfter: (_) {},
                duplicatePage: (_) {},
                clearPage: (_) {},
                deletePage: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('页面 (16)'), findsOneWidget);
    final lastPdf = find.byWidgetPredicate(
      (widget) => widget is CanvasPreview && widget.pageIndex == 14,
    );
    await tester.scrollUntilVisible(
      lastPdf,
      350,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(lastPdf);
    await tester.tap(lastPdf);
    expect(targetPage, 14);
    expect(coreInfo.pages.length, 16);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<void> showPages(
    WidgetTester tester, {
    required ValueNotifier<int> viewingPageIndex,
    required Set<int> activePages,
    ScrollController? scrollController,
    double pageHeight = 300,
    double viewportHeight = 300,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: viewportHeight,
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notification) {
                viewingPageIndex.value =
                    (notification.metrics.pixels / pageHeight)
                        .floor()
                        .clamp(0, 14);
                return false;
              },
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: List.generate(
                    15,
                    (pageIndex) => SizedBox(
                      height: pageHeight,
                      child: PdfViewportBuilder(
                        pageIndex: pageIndex,
                        viewingPageIndex: viewingPageIndex,
                        scrollController: scrollController,
                        pageTop: pageIndex * pageHeight,
                        pageHeight: pageHeight,
                        viewportHeight: viewportHeight,
                        builder: (context, renderPdf) => renderPdf
                            ? _RenderedPdfPage(
                                pageIndex: pageIndex,
                                activePages: activePages,
                              )
                            : const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('all 15 PDF pages activate when scrolling forward and back',
      (tester) async {
    final viewingPage = ValueNotifier(0);
    final scrollController = ScrollController();
    final activePages = <int>{};
    addTearDown(viewingPage.dispose);
    addTearDown(scrollController.dispose);

    await showPages(
      tester,
      viewingPageIndex: viewingPage,
      activePages: activePages,
      scrollController: scrollController,
    );
    expect(activePages, {0, 1});

    // 仅滚动触发通知，不重新 pumpWidget 或重建编辑器。
    for (final index in [...List.generate(15, (i) => i), 7, 2, 0]) {
      scrollController.jumpTo(index * 300.0);
      await tester.pump();
      expect(viewingPage.value, index);
      expect(activePages, contains(index), reason: 'PDF page ${index + 1}');
      expect(activePages.length, lessThanOrEqualTo(3));
      expect(activePages, everyElement(inInclusiveRange(index - 1, index + 1)));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar jumps activate distant pages and release old views',
      (tester) async {
    final viewingPage = ValueNotifier(0);
    final activePages = <int>{};
    addTearDown(viewingPage.dispose);
    await showPages(
      tester,
      viewingPageIndex: viewingPage,
      activePages: activePages,
    );

    for (final index in [7, 14, 0]) {
      viewingPage.value = index;
      await tester.pump();
      expect(activePages, contains(index));
      expect(activePages.length, lessThanOrEqualTo(3));
      expect(activePages, everyElement(inInclusiveRange(index - 1, index + 1)));
    }
    expect(activePages, {0, 1});
  });

  testWidgets('缩小与窗口变高后所有可见PDF页仍渲染，滚动更新范围', (tester) async {
    final viewingPage = ValueNotifier(0);
    final scrollController = ScrollController();
    final activePages = <int>{};
    addTearDown(viewingPage.dispose);
    addTearDown(scrollController.dispose);
    await showPages(
      tester,
      viewingPageIndex: viewingPage,
      activePages: activePages,
      scrollController: scrollController,
      pageHeight: 60,
    );
    expect(activePages, {0, 1, 2, 3, 4});
    scrollController.jumpTo(180);
    await tester.pump();
    expect(activePages, {2, 3, 4, 5, 6, 7});
    // 尺寸改变后，查看页码不变也必须重新计算所有可见页。
    await showPages(
      tester,
      viewingPageIndex: viewingPage,
      activePages: activePages,
      scrollController: scrollController,
      pageHeight: 60,
      viewportHeight: 420,
    );
    expect(activePages, {2, 3, 4, 5, 6, 7, 8, 9});
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the viewing notifier detaches the old listener',
      (tester) async {
    final previous = ValueNotifier(0);
    final current = ValueNotifier(14);
    final activePages = <int>{};
    addTearDown(previous.dispose);
    addTearDown(current.dispose);
    await showPages(
      tester,
      viewingPageIndex: previous,
      activePages: activePages,
    );
    await showPages(
      tester,
      viewingPageIndex: current,
      activePages: activePages,
    );
    expect(activePages, {13, 14});
    previous.value = 6;
    await tester.pump();
    expect(activePages, {13, 14});
    current.value = 4;
    await tester.pump();
    expect(activePages, {3, 4, 5});

    await tester.pumpWidget(const SizedBox.shrink());
    expect(activePages, isEmpty);
    current.value = 10;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
