import 'dart:convert';

import 'package:appflowy/plugins/database/calendar/models/recurrence_rule.dart';
import 'package:appflowy_backend/protobuf/flowy-user/reminder.pb.dart';
import 'package:fixnum/fixnum.dart';

import 'reminder_extension.dart';

Future<void> _pendingTask = Future.value();

// ponytail: serialize reminder writes; use per-series locks if saves become slow.
Future<T> runScheduleReminderTask<T>(Future<T> Function() task) {
  final result = _pendingTask.then((_) => task());
  _pendingTask =
      result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
  return result;
}

List<ReminderPB> missingRecurringReminders(
  List<ReminderPB> reminders,
  DateTime now,
) {
  final ids = reminders.map((r) => r.id).toSet();
  final series = <String>{};
  return [
    for (final reminder in reminders)
      if (reminder.meta.containsKey('recurrence_start') &&
          series.add('${reminder.objectId}:${reminder.rowId}'))
        for (final next in upcomingRecurringReminders(reminder, now))
          if (ids.add(next.id)) next,
  ];
}

/// Generate a small rolling queue; stable IDs prevent duplicates after sync.
List<ReminderPB> upcomingRecurringReminders(ReminderPB template, DateTime now) {
  final meta = template.meta;
  final startMillis = int.tryParse(meta['recurrence_start'] ?? '');
  final repeatType = int.tryParse(meta['recurrence_type'] ?? '');
  final offsetMillis = int.tryParse(meta['recurrence_offset'] ?? '');
  if (startMillis == null ||
      offsetMillis == null ||
      ![1, 2, 3, 4, 99].contains(repeatType) ||
      (template.rowId?.isEmpty ?? true)) {
    return [];
  }

  final start = DateTime.fromMillisecondsSinceEpoch(startMillis);
  final ruleJson = meta['recurrence_rule'];
  var interval = 1;
  if (repeatType == 99) {
    try {
      final custom = jsonDecode(ruleJson ?? '') as Map<String, dynamic>;
      interval = custom['interval'] as int? ?? 1;
      if (interval < 1 ||
          interval > 30 ||
          ![0, 1, 2, 3].contains(custom['unit'])) {
        return [];
      }
      if (custom['unit'] == 1) {
        final weekdays = custom['weekdays'];
        if (weekdays is! List ||
            weekdays.isEmpty ||
            weekdays.any((day) => day is! int || day < 0 || day > 6)) {
          return [];
        }
      }
    } catch (_) {
      return [];
    }
  }
  final rule = RecurrenceRule(
    repeatType: repeatType!,
    repeatRuleJson: ruleJson,
    startDate: start,
  );
  final offset = Duration(milliseconds: offsetMillis);
  final earliest = now.subtract(offset);
  final first = earliest.isAfter(start) ? earliest : start;
  var day = DateTime(first.year, first.month, first.day);
  // ponytail: reuse daily matching; jump by period if large series become slow.
  final limit = DateTime(day.year + 40 * interval + 1, day.month, day.day);
  final reminders = <ReminderPB>[];
  while (day.isBefore(limit) && reminders.length < 10) {
    final occurrence = DateTime(
      day.year,
      day.month,
      day.day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
    final scheduledAt = occurrence.add(offset);
    if (!occurrence.isBefore(start) &&
        scheduledAt.isAfter(now) &&
        rule.matchesDate(day)) {
      reminders.add(
        ReminderPB(
          id: '${template.objectId}:${template.rowId}:${occurrence.millisecondsSinceEpoch}',
          objectId: template.objectId,
          title: template.title,
          message: template.message,
          scheduledAt: Int64(scheduledAt.millisecondsSinceEpoch),
          meta: {
            ...meta,
            ReminderMetaKeys.date: occurrence.millisecondsSinceEpoch.toString(),
            ReminderMetaKeys.isRecurring: 'true',
            ReminderMetaKeys.recurrenceInstanceId:
                occurrence.millisecondsSinceEpoch.toString(),
          }..remove(ReminderMetaKeys.isArchived),
        ),
      );
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return reminders;
}
