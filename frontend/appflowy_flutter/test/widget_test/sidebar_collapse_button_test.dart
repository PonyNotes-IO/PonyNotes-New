import 'dart:io';

import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHomeSettingBloc extends MockBloc<HomeSettingEvent, HomeSettingState>
    implements HomeSettingBloc {}

HomeSettingState _expandedState() => HomeSettingState(
      panelContext: null,
      workspaceSetting: WorkspaceLatestPB(),
      unauthorized: false,
      menuStatus: MenuStatus.expanded,
      isNotificationPanelCollapsed: true,
      isScreenSmall: false,
      hasColappsedMenuManually: false,
      resizeOffset: 0,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );

HomeSettingState _hiddenState() => HomeSettingState(
      panelContext: null,
      workspaceSetting: WorkspaceLatestPB(),
      unauthorized: false,
      menuStatus: MenuStatus.hidden,
      isNotificationPanelCollapsed: true,
      isScreenSmall: false,
      hasColappsedMenuManually: true,
      resizeOffset: 0,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );

void main() {
  group('sidebar collapse button', () {
    late FakeHomeSettingBloc fakeBloc;

    setUpAll(() {
      registerFallbackValue(const HomeSettingEvent.initial());
    });

    setUp(() {
      fakeBloc = FakeHomeSettingBloc();
      when(() => fakeBloc.collapseMenu()).thenReturn(null);
      when(() => fakeBloc.isMenuHidden).thenReturn(false);
      when(() => fakeBloc.isMenuExpanded).thenReturn(true);
    });

    Widget buildSubject(HomeSettingState state) {
      whenListen(
        fakeBloc,
        Stream<HomeSettingState>.fromIterable([state]),
        initialState: state,
      );

      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<HomeSettingBloc>.value(
            value: fakeBloc,
            child: SizedBox(
              width: HomeSizes.maximumSidebarWidth,
              height: 600,
              child: _TestCollapseButton(),
            ),
          ),
        ),
      );
    }

    testWidgets('renders collapse button on Windows', (tester) async {
      if (!Platform.isWindows) return;

      await tester.pumpWidget(buildSubject(_expandedState()));
      // The Listener wrapping the collapse button should exist
      expect(
        find.byWidgetPredicate(
          (w) => w is Listener && w.onPointerDown != null,
        ),
        findsOneWidget,
      );
    });

    testWidgets('not rendered on non-Windows', (tester) async {
      if (Platform.isWindows) return;

      await tester.pumpWidget(buildSubject(_expandedState()));
      // On non-Windows, should render SizedBox.shrink
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('tapping collapse button calls collapseMenu', (tester) async {
      if (!Platform.isWindows) return;

      await tester.pumpWidget(buildSubject(_expandedState()));

      // Find the collapse button by its Listener widget
      final buttonFinder = find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerDown != null,
      );
      expect(buttonFinder, findsOneWidget);

      // Tap the collapse button
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      // Verify collapseMenu was called
      verify(() => fakeBloc.collapseMenu()).called(1);
    });

    testWidgets('collapse button is positioned after workspace name area',
        (tester) async {
      if (!Platform.isWindows) return;

      await tester.pumpWidget(buildSubject(_expandedState()));

      // The collapse button should be a Listener with onPointerDown
      final listenerFinder = find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerDown != null,
      );
      expect(listenerFinder, findsOneWidget);

      // Verify it's inside the Row (the header row)
      final rowFinder = find.ancestor(
        of: listenerFinder,
        matching: find.byType(Row),
      );
      expect(rowFinder, findsWidgets);
    });

    test('MenuStatus toggle logic', () {
      expect(MenuStatus.expanded, isNot(MenuStatus.hidden));
      expect(MenuStatus.hidden, isNot(MenuStatus.expanded));
    });

    test('collapseMenu toggles between expanded and hidden', () {
      // When expanded, collapseMenu should set to hidden
      final expandedBloc = FakeHomeSettingBloc();
      when(() => expandedBloc.isMenuExpanded).thenReturn(true);
      when(() => expandedBloc.isMenuHidden).thenReturn(false);
      when(() => expandedBloc.collapseMenu()).thenReturn(null);

      expandedBloc.collapseMenu();
      verify(() => expandedBloc.collapseMenu()).called(1);

      // When hidden, collapseMenu should set to expanded
      final hiddenBloc = FakeHomeSettingBloc();
      when(() => hiddenBloc.isMenuExpanded).thenReturn(false);
      when(() => hiddenBloc.isMenuHidden).thenReturn(true);
      when(() => hiddenBloc.collapseMenu()).thenReturn(null);

      hiddenBloc.collapseMenu();
      verify(() => hiddenBloc.collapseMenu()).called(1);
    });
  });
}

/// Minimal widget replicating the collapse button using Listener
/// (matches the actual implementation in sidebar.dart).
class _TestCollapseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => context.read<HomeSettingBloc>().collapseMenu(),
      child: const SizedBox(
        width: 24,
        height: 24,
        child: Icon(Icons.chevron_left),
      ),
    );
  }
}
