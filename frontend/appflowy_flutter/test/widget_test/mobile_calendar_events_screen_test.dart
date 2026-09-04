import 'dart:async';

import 'package:appflowy/mobile/presentation/database/card/card_detail/mobile_card_detail_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_calendar_events_screen.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_cache.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

class _MockCalendarBloc extends MockBloc<CalendarEvent, CalendarState>
    implements CalendarBloc {}

class _MockDatabaseController extends Mock implements DatabaseController {}

class _MockRowCache extends Mock implements RowCache {}

void main() {
  final selectedDate = DateTime(2026, 9, 7);

  setUpAll(() async {
    registerFallbackValue(const CalendarEvent.initial());
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  late _MockCalendarBloc calendarBloc;
  late _MockDatabaseController databaseController;
  late _MockRowCache rowCache;
  late StreamController<CalendarState> stateController;
  late List<CalendarDayEvent> initialEvents;

  setUp(() {
    calendarBloc = _MockCalendarBloc();
    databaseController = _MockDatabaseController();
    rowCache = _MockRowCache();
    stateController = StreamController<CalendarState>.broadcast();
    initialEvents = [];

    when(() => calendarBloc.databaseController).thenReturn(databaseController);
    when(() => databaseController.rowCache).thenReturn(rowCache);
    when(() => rowCache.getRow(any())).thenReturn(null);
    whenListen(
      calendarBloc,
      stateController.stream,
      initialState: CalendarState.initial(),
    );
  });

  tearDown(() async {
    await stateController.close();
  });

  Widget buildApp() {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => MobileCalendarEventsScreen(
            calendarBloc: calendarBloc,
            date: selectedDate,
            events: initialEvents,
            rowCache: rowCache,
            viewId: 'calendar-view',
          ),
        ),
        GoRoute(
          path: MobileRowDetailPage.routeName,
          builder: (_, __) => const Scaffold(
            body: Text(
              'created event detail',
              key: Key('created_event_detail'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    return EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp.router(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          routerConfig: router,
          builder: (_, child) => AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: child!,
          ),
        ),
      ),
    );
  }

  testWidgets('plus button requests an event for the selected date', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_event_fab')));

    verify(
      () => calendarBloc.add(CalendarEvent.createEvent(selectedDate)),
    ).called(1);
  });

  testWidgets('created event opens its mobile detail page', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final eventPB = CalendarEventPB(
      rowMeta: RowMetaPB(id: 'new-event'),
      dateFieldId: 'date-field',
    );
    final event = CalendarDayEvent(
      event: eventPB,
      dateFieldId: 'date-field',
      eventId: 'new-event',
      date: selectedDate,
    );

    stateController.add(
      CalendarState.initial().copyWith(
        editingEvent: CalendarEventData<CalendarDayEvent>(
          title: '',
          date: selectedDate,
          event: event,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('created_event_detail')), findsOneWidget);
    expect(initialEvents, isEmpty);
  });
}
