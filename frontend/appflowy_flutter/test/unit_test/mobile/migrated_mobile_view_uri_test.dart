import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/application/mobile_view_migration_handoff.dart';
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
          oldViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.replace,
      );
    });

    test('删除通知已返回首页时不再压入新白板', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(path: '/home'),
          oldViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.none,
      );
    });

    test('移动菜单造成首页过渡态且交接已登记时重建为新白板', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(path: '/home'),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'old-private-whiteboard',
          hasExpectedHandoff: true,
        ),
        MigratedMobileViewNavigationAction.resetToReplacement,
      );
    });

    test('首页过渡态没有交接门闩时不自动打开白板', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(path: '/home'),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.none,
      );
    });

    test('首页过渡态 latestOpen 已变化时不打断当前页面', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(path: '/home'),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'another-whiteboard',
          hasExpectedHandoff: true,
        ),
        MigratedMobileViewNavigationAction.none,
      );
    });

    test('当前 URI 不是源白板时不打断当前页面', () {
      expect(
        migratedMobileViewNavigationAction(
          currentUri: Uri(
            path: MobileDocumentScreen.routeName,
            queryParameters: const {
              MobileDocumentScreen.viewId: 'another-whiteboard',
            },
          ),
          oldViewId: 'old-private-whiteboard',
        ),
        MigratedMobileViewNavigationAction.none,
      );
    });
  });

  group('shouldPrepareCurrentMobileViewReplacement', () {
    test('源白板 URI 可登记交接', () {
      expect(
        shouldPrepareCurrentMobileViewReplacement(
          currentUri: Uri(
            path: MobileDocumentScreen.routeName,
            queryParameters: const {
              MobileDocumentScreen.viewId: 'old-private-whiteboard',
            },
          ),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'old-private-whiteboard',
        ),
        isTrue,
      );
    });

    test('移动菜单造成首页过渡态但源白板仍是 latestOpen 时可登记交接', () {
      expect(
        shouldPrepareCurrentMobileViewReplacement(
          currentUri: Uri(path: '/home'),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'old-private-whiteboard',
        ),
        isTrue,
      );
    });

    test('普通首页或其他页面不能登记源白板交接', () {
      expect(
        shouldPrepareCurrentMobileViewReplacement(
          currentUri: Uri(path: '/home'),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'another-whiteboard',
        ),
        isFalse,
      );
      expect(
        shouldPrepareCurrentMobileViewReplacement(
          currentUri: Uri(
            path: MobileDocumentScreen.routeName,
            queryParameters: const {
              MobileDocumentScreen.viewId: 'another-whiteboard',
            },
          ),
          oldViewId: 'old-private-whiteboard',
          latestOpenViewId: 'old-private-whiteboard',
        ),
        isFalse,
      );
    });
  });

  group('MobileViewMigrationHandoff', () {
    tearDown(MobileViewMigrationHandoff.reset);

    test('登记后只把源视图删除识别为预期迁移', () {
      MobileViewMigrationHandoff.begin(
        oldViewId: 'old-private-whiteboard',
        newViewId: 'new-shared-whiteboard',
      );

      expect(
        MobileViewMigrationHandoff.isExpectedRemoval(
          'old-private-whiteboard',
        ),
        isTrue,
      );
      expect(
        MobileViewMigrationHandoff.replacementViewId(
          'old-private-whiteboard',
        ),
        'new-shared-whiteboard',
      );
      expect(
        MobileViewMigrationHandoff.isExpectedRemoval('another-whiteboard'),
        isFalse,
      );
    });

    test('迁移完成或失败后清理门闩', () {
      MobileViewMigrationHandoff.begin(
        oldViewId: 'old-private-whiteboard',
        newViewId: 'new-shared-whiteboard',
      );

      MobileViewMigrationHandoff.finish('old-private-whiteboard');

      expect(
        MobileViewMigrationHandoff.isExpectedRemoval(
          'old-private-whiteboard',
        ),
        isFalse,
      );
      expect(
        MobileViewMigrationHandoff.replacementViewId(
          'old-private-whiteboard',
        ),
        isNull,
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
