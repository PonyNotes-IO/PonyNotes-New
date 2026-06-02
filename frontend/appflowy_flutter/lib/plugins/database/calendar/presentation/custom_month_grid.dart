import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';

import '../models/schedule_model.dart';

/// Computes a 6x7 grid of DateTime objects for a given month.
///
/// Week starts on Sunday. Leading days come from the previous month,
/// trailing days come from the next month.
List<List<DateTime>> computeMonthGrid(int year, int month) {
  // First day of the target month
  final firstDay = DateTime(year, month);
  // weekday: Mon=1 ... Sun=7. We want Sunday=0, so use weekday % 7.
  final startOffset = firstDay.weekday % 7;
  // The date of the first cell (may be in the previous month)
  final startDate = firstDay.subtract(Duration(days: startOffset));

  final grid = <List<DateTime>>[];
  var current = startDate;
  for (int row = 0; row < 6; row++) {
    final week = <DateTime>[];
    for (int col = 0; col < 7; col++) {
      week.add(current);
      current = current.add(const Duration(days: 1));
    }
    grid.add(week);
  }
  return grid;
}

/// A single event item for display in the calendar grid.
class CalendarEventItem {
  const CalendarEventItem({
    required this.id,
    required this.title,
    this.schedule,
  });

  final String id;
  final String title;
  final ScheduleItem? schedule;
}

/// A custom month grid widget that replaces the broken `calendar_view`
/// MonthView with correct Sunday-first day-of-week alignment.
///
/// Displays a 6-row x 7-column grid with weekday header, date numbers,
/// and event chips. Previous/next month days are greyed out, today is
/// highlighted, and selected date has a light primary background.
class CustomMonthGrid extends StatelessWidget {
  const CustomMonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.events,
    this.selectedDate,
    this.onDateTap,
    this.onEventTap,
  });

  /// The year to display.
  final int year;

  /// The month to display (1-12).
  final int month;

  /// Events keyed by date (year-month-day normalized to midnight).
  final Map<DateTime, List<CalendarEventItem>> events;

  /// The currently selected date, if any.
  final DateTime? selectedDate;

  /// Called when a date cell is tapped.
  final ValueChanged<DateTime>? onDateTap;

  /// Called when an event chip is tapped.
  final ValueChanged<CalendarEventItem>? onEventTap;

  static const List<String> _weekdayHeaders = [
    '日', '一', '二', '三', '四', '五', '六',
  ];

  /// Normalize a DateTime to midnight for map lookups.
  static DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isSelected(DateTime date) {
    if (selectedDate == null) return false;
    return date.year == selectedDate!.year &&
        date.month == selectedDate!.month &&
        date.day == selectedDate!.day;
  }

  bool _isCurrentMonth(DateTime date) => date.month == month && date.year == year;

  bool _isWeekend(DateTime date) =>
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);
    final grid = computeMonthGrid(year, month);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Weekday header row
        _buildWeekdayHeader(af),
        // 6 rows of date cells
        ...List.generate(6, (rowIndex) {
          return Expanded(
            child: Row(
              children: List.generate(7, (colIndex) {
                final date = grid[rowIndex][colIndex];
                return Expanded(
                  child: _buildCell(context, af, theme, date),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildWeekdayHeader(AFThemeExtension af) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: _weekdayHeaders.map((label) {
          return Expanded(
            child: SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: af.secondaryTextColor,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    AFThemeExtension af,
    ThemeData theme,
    DateTime date,
  ) {
    final inMonth = _isCurrentMonth(date);
    final today = _isToday(date);
    final selected = _isSelected(date);
    final weekend = _isWeekend(date);

    final bgColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : weekend
            ? af.calendarWeekendBGColor
            : af.background;

    final dateColor = !inMonth
        ? af.secondaryTextColor.withValues(alpha: 0.4)
        : today
            ? theme.colorScheme.onPrimary
            : af.onBackground;

    final dateBgColor = today ? theme.colorScheme.primary : Colors.transparent;

    final dayEvents = events[_normalize(date)] ?? const <CalendarEventItem>[];

    return GestureDetector(
      onTap: () => onDateTap?.call(date),
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: af.borderColor),
        ),
        padding: const EdgeInsets.only(top: 2, right: 2, left: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Date number circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: dateBgColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: today ? FontWeight.w600 : FontWeight.normal,
                  color: dateColor,
                ),
              ),
            ),
            const SizedBox(height: 1),
            // Event chips
            if (dayEvents.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: dayEvents.length,
                  itemBuilder: (ctx, i) {
                    final ev = dayEvents[i];
                    return GestureDetector(
                      onTap: () => onEventTap?.call(ev),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: af.tint1,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          ev.title,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
