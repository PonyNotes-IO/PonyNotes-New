import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _menuKey = ValueKey('workspace-menu');

Widget _buildPopover(
  PopoverController controller, {
  VoidCallback? onClose,
  VoidCallback? onTap,
  Duration animationDuration = Durations.short3,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Popover(
          controller: controller,
          direction: PopoverDirection.bottomWithCenterAligned,
          animationDuration: animationDuration,
          beginOpacity: 0.8,
          onClose: onClose,
          popupBuilder: (_) => const SizedBox(
            key: _menuKey,
            width: 200,
            height: 100,
            child: Text('工作区菜单'),
          ),
          child: GestureDetector(
            onTap: onTap ?? controller.show,
            child: const SizedBox(
              width: 150,
              height: 30,
              child: Text('工作区'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('连点入口时收起和展开均播放动画，反转时不误报关闭', (tester) async {
    final controller = PopoverController();
    var closeCount = 0;
    await tester.pumpWidget(
      _buildPopover(
        controller,
        onTap: controller.toggle,
        onClose: () => closeCount++,
      ),
    );

    await tester.tap(find.text('工作区'));
    await tester.pump();
    await tester.pump(Durations.short3);
    final expandedTop = tester.getTopLeft(find.byKey(_menuKey)).dy;

    await tester.tap(find.text('工作区'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(_menuKey), findsOneWidget);
    final closingTop = tester.getTopLeft(find.byKey(_menuKey)).dy;
    expect(closingTop, lessThan(expandedTop));
    expect(closeCount, 0);

    await tester.tap(find.text('工作区'));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(_menuKey)).dy,
      closeTo(closingTop, 0.01),
    );
    await tester.pump(const Duration(milliseconds: 15));
    expect(tester.getTopLeft(find.byKey(_menuKey)).dy, greaterThan(closingTop));
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      tester.getTopLeft(find.byKey(_menuKey)).dy,
      closeTo(expandedTop, 0.01),
    );
    expect(closeCount, 0);

    await tester.tap(find.text('工作区'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(_menuKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(_menuKey)).dy, lessThan(expandedTop));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(_menuKey), findsNothing);
    expect(closeCount, 1);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });

  testWidgets('快速重复打开后仅保留一个菜单，点击外部可完全关闭', (tester) async {
    final controller = PopoverController();
    var closeCount = 0;
    await tester.pumpWidget(
      _buildPopover(controller, onClose: () => closeCount++),
    );

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('工作区'));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(_menuKey), findsOneWidget);
    expect(closeCount, 0);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(_menuKey), findsNothing);
    expect(closeCount, 1);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });

  testWidgets('外部关闭动画尚未完成时重新打开，不残留旧菜单或误报关闭', (tester) async {
    final controller = PopoverController();
    var closeCount = 0;
    await tester.pumpWidget(
      _buildPopover(controller, onClose: () => closeCount++),
    );
    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 20));
    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(_menuKey), findsOneWidget);
    expect(closeCount, 0);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(_menuKey), findsNothing);
    expect(closeCount, 1);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });

  testWidgets('快速重复打开后控制器关闭不残留菜单', (tester) async {
    final controller = PopoverController();
    await tester.pumpWidget(_buildPopover(controller));

    controller.show();
    await tester.pump(const Duration(milliseconds: 20));
    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    controller.close();
    await tester.pumpAndSettle();

    expect(find.byKey(_menuKey), findsNothing);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });

  testWidgets('快速重复打开后 Esc 可完全关闭菜单', (tester) async {
    final controller = PopoverController();
    await tester.pumpWidget(_buildPopover(controller));

    controller.show();
    await tester.pump(const Duration(milliseconds: 20));
    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(_menuKey), findsNothing);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });

  testWidgets('无动画菜单重复打开和关闭仍保留原有通知次数', (tester) async {
    final controller = PopoverController();
    var closeCount = 0;
    await tester.pumpWidget(
      _buildPopover(
        controller,
        onClose: () => closeCount++,
        animationDuration: Duration.zero,
      ),
    );

    controller.show();
    await tester.pump();
    controller.show();
    await tester.pump();

    expect(find.byKey(_menuKey), findsOneWidget);
    expect(closeCount, 1);
    controller.close();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(_menuKey), findsNothing);
    expect(closeCount, 2);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });

  testWidgets('互斥菜单切换仍关闭前一个菜单并只通知一次', (tester) async {
    final controllers = [PopoverController(), PopoverController()];
    final closeCounts = [0, 0];
    final mutex = PopoverMutex();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < controllers.length; i++)
                Popover(
                  controller: controllers[i],
                  mutex: mutex,
                  animationDuration: Durations.short3,
                  onClose: () => closeCounts[i]++,
                  popupBuilder: (_) => SizedBox(
                    key: ValueKey('mutex-menu-$i'),
                    width: 100,
                    height: 100,
                  ),
                  child: const SizedBox(width: 100, height: 30),
                ),
            ],
          ),
        ),
      ),
    );

    controllers[0].show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    controllers[1].show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('mutex-menu-0')), findsNothing);
    expect(find.byKey(const ValueKey('mutex-menu-1')), findsOneWidget);
    expect(closeCounts, [1, 0]);
    controllers[1].close();
    await tester.pumpAndSettle();

    expect(closeCounts, [1, 1]);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
    mutex.dispose();
  });

  testWidgets('带动画的子菜单关闭边界仍保留父菜单，之后可关闭父菜单', (tester) async {
    final parentController = PopoverController();
    final childController = PopoverController();
    var parentCloseCount = 0;
    var childCloseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Popover(
              controller: parentController,
              animationDuration: Durations.short3,
              onClose: () => parentCloseCount++,
              popupBuilder: (_) => SizedBox(
                key: const ValueKey('parent-menu'),
                width: 150,
                height: 100,
                child: Popover(
                  controller: childController,
                  asBarrier: true,
                  animationDuration: Durations.short3,
                  onClose: () => childCloseCount++,
                  popupBuilder: (_) => const SizedBox(
                    key: ValueKey('child-menu'),
                    width: 100,
                    height: 100,
                  ),
                  child: const Text('子菜单入口'),
                ),
              ),
              child: const SizedBox(width: 100, height: 30),
            ),
          ),
        ),
      ),
    );

    parentController.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    childController.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-menu')), findsNothing);
    expect(find.byKey(const ValueKey('parent-menu')), findsOneWidget);
    expect(childCloseCount, 1);
    expect(parentCloseCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('parent-menu')), findsNothing);
    expect(parentCloseCount, 1);
    expect(PopoverState.rootEntry.isEmpty, isTrue);
  });
}
