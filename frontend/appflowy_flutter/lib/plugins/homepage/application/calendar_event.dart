class CalendarEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool isAllDay;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.isAllDay = false,
  });
}


