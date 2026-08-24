import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/editor/mobile_editor_screen.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet/route.dart';

void main() {
  test('迁移后的移动端白板 URI 替换 viewId 并保留页面参数', () {
    final currentUri = Uri(
      path: MobileDocumentScreen.routeName,
      queryParameters: const {
        MobileDocumentScreen.viewId: 'old-private-whiteboard',
        MobileDocumentScreen.viewTitle: '旧白板',
        MobileDocumentScreen.viewShowMoreButton: 'true',
        MobileDocumentScreen.viewBlockId: 'block-1',
      },
    );
    final newView = ViewPB()
      ..id = 'new-shared-whiteboard'
      ..name = '迁移后的白板'
      ..layout = ViewLayoutPB.Whiteboard;

    final uri = buildMigratedMobileViewUri(currentUri, newView);

    expect(uri.path, MobileDocumentScreen.routeName);
    expect(
      uri.queryParameters[MobileDocumentScreen.viewId],
      'new-shared-whiteboard',
    );
    expect(
      uri.queryParameters[MobileDocumentScreen.viewTitle],
      '迁移后的白板',
    );
    expect(
      uri.queryParameters[MobileDocumentScreen.viewShowMoreButton],
      'true',
    );
    expect(
      uri.queryParameters[MobileDocumentScreen.viewBlockId],
      'block-1',
    );
  });

  group('migratedMobileViewNavigationAction', () {
    test('当前 URI 指向源白板时原子替换', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(
            path: MobileDocumentScreen.routeName,
            queryParameters: const {
              MobileDocumentScreen.viewId: 'old-private-whiteboard',
            },
          ),
          latestOpenViewId: null,
          oldViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.replace,
      );
    });

    test('删除通知已返回首页、但业务态仍打开源白板时从首页压入新白板', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(path: '/home'),
          latestOpenViewId: 'old-private-whiteboard',
          oldViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.push,
      );
    });

    test('URI 和业务态都不是源白板时不打断当前页面', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(
            path: MobileDocumentScreen.routeName,
            queryParameters: const {
              MobileDocumentScreen.viewId: 'another-whiteboard',
            },
          ),
          latestOpenViewId: 'another-whiteboard',
          oldViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.none,
      );
    });
  });

  test('移动端文档路由 key 按 viewId 隔离新旧白板 Route', () {
    expect(
      mobileDocumentRouteKey('same-go-router-page', 'old-private-whiteboard'),
      isNot(
        mobileDocumentRouteKey(
          'same-go-router-page',
          'new-public-whiteboard',
        ),
      ),
    );
    expect(
      mobileDocumentRouteKey('first-push', 'same-whiteboard'),
      isNot(mobileDocumentRouteKey('second-push', 'same-whiteboard')),
    );
  });

  testWidgets('同一路由实例替换 viewId 时销毁旧页面 State', (tester) async {
    final viewId = ValueNotifier<String>('old-private-whiteboard');
    var oldPageDisposed = false;
    addTearDown(viewId.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: viewId,
          builder: (context, id, _) {
            return Navigator(
              pages: [
                MaterialExtendedPage<void>(
                  key: mobileDocumentRouteKey('same-go-router-page', id),
                  child: _DisposeProbe(
                    onDispose: id == 'old-private-whiteboard'
                        ? () => oldPageDisposed = true
                        : () {},
                  ),
                ),
              ],
              onPopPage: (route, result) => route.didPop(result),
            );
          },
        ),
      ),
    );

    viewId.value = 'new-public-whiteboard';
    await tester.pumpAndSettle();

    expect(oldPageDisposed, isTrue);
  });
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
