import 'dart:async';

import 'calendar_event.dart';

/// Simple calendar service that returns calendar events for a workspace.
/// Currently returns stub/mock data; later this should call the real calendar backend.
class CalendarService {
  static Future<List<CalendarEvent>> getEvents(String workspaceId) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 200));

    // Return mock events for now
    final now = DateTime.now();
    return [
      CalendarEvent(
        id: 'e1',
        title: '团队会议',
        start: DateTime(now.year, now.month, now.day, 10, 0),
        end: DateTime(now.year, now.month, now.day, 11, 0),
      ),
      CalendarEvent(
        id: 'e2',
        title: '产品评审',
        start: DateTime(now.year, now.month, now.day + 1, 15, 0),
        end: DateTime(now.year, now.month, now.day + 1, 16, 0),
      ),
      CalendarEvent(
        id: 'e3',
        title: '全天：公司休假',
        start: DateTime(now.year, now.month, now.day + 3),
        end: null,
        isAllDay: true,
      ),
    ];
  }
}


