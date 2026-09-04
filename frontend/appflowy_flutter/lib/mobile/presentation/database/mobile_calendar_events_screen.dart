import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/database/card/card_detail/mobile_card_detail_screen.dart';
import 'package:appflowy/mobile/presentation/database/mobile_calendar_events_empty.dart';
import 'package:appflowy/plugins/database/application/row/row_cache.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_bloc.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_card.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class MobileCalendarEventsScreen extends StatefulWidget {
  const MobileCalendarEventsScreen({
    super.key,
    required this.calendarBloc,
    required this.date,
    required this.events,
    required this.rowCache,
    required this.viewId,
  });

  final CalendarBloc calendarBloc;
  final DateTime date;
  final List<CalendarDayEvent> events;
  final RowCache rowCache;
  final String viewId;

  static const routeName = '/calendar_events';

  // GoRouter Arguments
  static const calendarBlocKey = 'calendar_bloc';
  static const calendarDateKey = 'date';
  static const calendarEventsKey = 'events';
  static const calendarRowCacheKey = 'row_cache';
  static const calendarViewIdKey = 'view_id';

  @override
  State<MobileCalendarEventsScreen> createState() =>
      _MobileCalendarEventsScreenState();
}

class _MobileCalendarEventsScreenState
    extends State<MobileCalendarEventsScreen> {
  late final List<CalendarDayEvent> _events = List.of(widget.events);

  bool _isSelectedDate(DateTime date) =>
      date.withoutTime == widget.date.withoutTime;

  void _addEvent(CalendarDayEvent? event) {
    if (event == null || _events.any((e) => e.eventId == event.eventId)) {
      return;
    }
    _events.add(event);
  }

  Future<void> _openCreatedEvent(CalendarDayEvent event) async {
    await context.push(
      MobileRowDetailPage.routeName,
      extra: {
        MobileRowDetailPage.argRowId: event.eventId,
        MobileRowDetailPage.argDatabaseController:
            widget.calendarBloc.databaseController,
      },
    );

    if (mounted) {
      widget.calendarBloc.add(const CalendarEvent.newEventPopupDisplayed());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('add_event_fab'),
        elevation: 6,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: () =>
            widget.calendarBloc.add(CalendarEvent.createEvent(widget.date)),
        child: const Text('+'),
      ),
      appBar: MobileAppBar(
        title: DateFormat.yMMMMd(context.locale.toLanguageTag())
            .format(widget.date),
      ),
      body: BlocProvider<CalendarBloc>.value(
        value: widget.calendarBloc,
        child: BlocConsumer<CalendarBloc, CalendarState>(
          listenWhen: (previous, current) =>
              previous.editingEvent != current.editingEvent &&
              current.editingEvent?.event != null &&
              _isSelectedDate(current.editingEvent!.date),
          listener: (context, state) {
            _openCreatedEvent(state.editingEvent!.event!);
          },
          buildWhen: (p, c) =>
              (p.newEvent != c.newEvent &&
                  c.newEvent != null &&
                  _isSelectedDate(c.newEvent!.date)) ||
              (p.editingEvent != c.editingEvent &&
                  c.editingEvent != null &&
                  _isSelectedDate(c.editingEvent!.date)),
          builder: (context, state) {
            if (state.newEvent != null &&
                _isSelectedDate(state.newEvent!.date)) {
              _addEvent(state.newEvent!.event);
            }
            if (state.editingEvent != null &&
                _isSelectedDate(state.editingEvent!.date)) {
              _addEvent(state.editingEvent!.event);
            }

            if (_events.isEmpty) {
              return const MobileCalendarEventsEmpty();
            }

            return SingleChildScrollView(
              child: Column(
                children: [
                  const VSpace(10),
                  ..._events.map((event) {
                    return EventCard(
                      databaseController:
                          widget.calendarBloc.databaseController,
                      event: event,
                      constraints: const BoxConstraints.expand(),
                      autoEdit: false,
                      isDraggable: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                    );
                  }),
                  const VSpace(24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
