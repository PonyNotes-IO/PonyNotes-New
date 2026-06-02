# Calendar System Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the broken calendar month grid, add right-side event detail panel and todo list, and sync left-right calendars with smooth animation.

**Architecture:** Replace `calendar_view`'s `MonthView` with a custom grid widget that correctly computes day-of-week alignment. Add right-side panels for event details and todos. Wire left-right calendar sync via shared `ValueNotifier<DateTime>`.

**Tech Stack:** Flutter/Dart, `calendar_view` (kept for Day/Week views), `intl` for date formatting, `flowy_infra` for theming

**Spec:** `docs/superpowers/specs/2026-06-02-calendar-improvement-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `custom_month_grid.dart` (NEW) | Pure widget: 6×7 date grid with correct day-of-week alignment, prev/next month fill, slide animation |
| `event_detail_panel.dart` (NEW) | Right-side panel showing event details (title, time, description, edit/delete) |
| `todo_list_panel.dart` (NEW) | Right-side panel showing todo items for selected date |
| `calendar_grid_view.dart` (MODIFY) | Replace `MonthView` with `CustomMonthGrid`, wire click events, add Today button |
| `calendar.dart` (MODIFY) | Integrate new panels, wire left-right sync via `_focusedDay` |

All files live under:
`appflowy_flutter/lib/plugins/database/calendar/presentation/`

---

### Task 1: Create `CustomMonthGrid` widget

**Files:**
- Create: `appflowy_flutter/lib/plugins/database/calendar/presentation/custom_month_grid.dart`

- [ ] **Step 1: Create the date computation utility**

```dart
// custom_month_grid.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flowy_infra/theme_extension.dart';

/// Computes the 6×7 date matrix for a given month.
/// Returns 42 DateTime objects: leading prev-month days,
/// current month days, trailing next-month days.
List<List<DateTime>> computeMonthGrid(int year, int month) {
  final firstDay = DateTime(year, month, 1);
  // Dart weekday: Mon=1, Tue=2, ..., Sun=7
  // We want Sunday=0, so: (weekday % 7)
  final leadingDays = firstDay.weekday % 7;

  final grid = <List<DateTime>>[];
  var current = firstDay.subtract(Duration(days: leadingDays));

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
```

- [ ] **Step 2: Create the `CustomMonthGrid` widget with correct grid rendering**

```dart
/// A custom month grid widget that correctly aligns dates to weekdays.
/// Supports Sunday-start week, previous/next month fill days,
/// and slide animation on month transition.
class CustomMonthGrid extends StatelessWidget {
  const CustomMonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.events,
    required this.selectedDate,
    required this.onDateTap,
    required this.onEventTap,
    this.onPrevMonth,
    this.onNextMonth,
  });

  final int year;
  final int month;
  final Map<DateTime, List<dynamic>> events; // date → event list
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateTap;
  final ValueChanged<dynamic> onEventTap;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  static const _weekdays = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);
    final grid = computeMonthGrid(year, month);
    final now = DateTime.now();

    return Column(
      children: [
        // Weekday header row
        _buildWeekdayHeader(af, theme),
        // 6 rows of date cells
        Expanded(
          child: Column(
            children: grid.map((week) {
              return Expanded(
                child: Row(
                  children: week.map((date) {
                    return Expanded(
                      child: _buildCell(context, af, theme, date, now),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(AFThemeExtension af, ThemeData theme) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: _weekdays.map((day) {
          return Expanded(
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: af.secondaryTextColor,
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
    DateTime now,
  ) {
    final isInMonth = date.month == month;
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isSelected = selectedDate != null &&
        date.year == selectedDate!.year &&
        date.month == selectedDate!.month &&
        date.day == selectedDate!.day;
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;

    final dayEvents = events[_dateKey(date)] ?? [];
    final bgColor = isWeekend ? af.calendarWeekendBGColor : af.background;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => onDateTap(date),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: af.borderColor, width: 0.25),
        ),
        padding: const EdgeInsets.only(top: 4, right: 4, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Date number circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isToday
                    ? theme.colorScheme.primary
                    : isSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                  color: !isInMonth
                      ? af.secondaryTextColor.withValues(alpha: 0.4)
                      : isToday
                          ? theme.colorScheme.onPrimary
                          : af.onBackground,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Event list
            if (dayEvents.isNotEmpty && isInMonth)
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: dayEvents.length,
                  itemBuilder: (ctx, i) {
                    final ev = dayEvents[i];
                    return GestureDetector(
                      onTap: () => onEventTap(ev),
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
                          ev.title ?? '',
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

  DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);
}
```

- [ ] **Step 3: Verify the file compiles**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/presentation/custom_month_grid.dart`
Expected: No errors (warnings about unused imports are OK at this stage)

- [ ] **Step 4: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/presentation/custom_month_grid.dart
git commit -m "feat(calendar): add CustomMonthGrid widget with correct day-of-week alignment"
```

---

### Task 2: Integrate `CustomMonthGrid` into `CalendarGridView`

**Files:**
- Modify: `appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart`

- [ ] **Step 1: Add import for CustomMonthGrid**

At the top of `calendar_grid_view.dart`, add after existing imports:

```dart
import 'custom_month_grid.dart';
```

- [ ] **Step 2: Replace `_buildMonthView()` method**

Replace the entire `_buildMonthView()` method (lines ~419-547) with:

```dart
  Widget _buildMonthView() {
    final now = DateTime.now();

    // Build events map for the grid
    final eventsMap = <DateTime, List<ScheduleItem>>{};
    final start = DateTime(_currentDate.year, _currentDate.month, 1);
    final end = DateTime(_currentDate.year, _currentDate.month + 1, 1);
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      final schedules = widget.scheduleModel.getSchedulesForDate(d);
      if (schedules.isNotEmpty) {
        eventsMap[DateTime(d.year, d.month, d.day)] = schedules;
      }
    }

    return CustomMonthGrid(
      key: ValueKey('month_${_currentDate.year}_${_currentDate.month}'),
      year: _currentDate.year,
      month: _currentDate.month,
      events: eventsMap,
      selectedDate: _currentDate,
      onDateTap: _onDateTap,
      onEventTap: (ev) {
        if (ev is ScheduleItem) _onEventTap(ev);
      },
    );
  }
```

- [ ] **Step 3: Update `_loadEvents` to also refresh month view data**

The `_loadEvents()` method currently loads events into `_eventController` for `calendar_view`. For the month view, we need to call `setState` to rebuild with fresh data. Add at the end of `_loadEvents()`:

```dart
    // Force rebuild for month view (CustomMonthGrid reads events on build)
    if (_viewMode == CalendarViewMode.month && mounted) {
      setState(() {});
    }
```

- [ ] **Step 4: Verify compilation**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/presentation/calendar_grid_view.dart`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart
git commit -m "feat(calendar): replace MonthView with CustomMonthGrid in calendar grid view"
```

---

### Task 3: Add slide animation to month transitions

**Files:**
- Modify: `appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart`

- [ ] **Step 1: Add animation state variables to `CalendarGridViewState`**

Add after existing state variables (around line 36):

```dart
  // Animation for month transitions
  int _animationDirection = 0; // -1 = left, 0 = none, 1 = right
```

- [ ] **Step 2: Wrap `_buildMonthView()` in AnimatedSwitcher**

Replace the `_buildCalendarContent()` method's month case to wrap with animation:

Find this line in `_buildCalendarContent()`:
```dart
          CalendarViewMode.month => _buildMonthView(),
```

Replace with:
```dart
          CalendarViewMode.month => _buildAnimatedMonthView(),
```

Then add the new method:

```dart
  Widget _buildAnimatedMonthView() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: Offset(_animationDirection >= 0 ? 1.0 : -1.0, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ));
        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      child: _buildMonthView(),
    );
  }
```

- [ ] **Step 3: Set animation direction in `_navigateDate()`**

Update `_navigateDate()` to set direction before state change:

```dart
  void _navigateDate(int delta) {
    setState(() {
      _animationDirection = delta;
      // ... existing switch logic unchanged ...
    });
    _loadEvents();
    // Reset animation direction after transition
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _animationDirection = 0);
    });
  }
```

- [ ] **Step 4: Verify compilation**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/presentation/calendar_grid_view.dart`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart
git commit -m "feat(calendar): add slide animation to month transitions"
```

---

### Task 4: Add "Today" button to toolbar

**Files:**
- Modify: `appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart`

- [ ] **Step 1: Verify "Today" button already exists**

The `_buildToolbar()` method already has a "今天" button (around line 244-259). Verify it works correctly by reading the method. If it exists and calls `_goToToday()`, no changes needed — skip to Step 3.

- [ ] **Step 2: If missing, add "Today" button**

After the navigation arrows in `_buildToolbar()`, add:

```dart
          const SizedBox(width: 8),
          InkWell(
            onTap: _goToToday,
            borderRadius: BorderRadius.circular(4),
            hoverColor: af.lightGreyHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '今天',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: af.textColor,
                ),
              ),
            ),
          ),
```

- [ ] **Step 3: Update `_goToToday()` to also reset animation**

```dart
  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _animationDirection = 0;
      _currentDate = now;
    });
    _loadEvents();
  }
```

- [ ] **Step 4: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart
git commit -m "feat(calendar): ensure Today button resets to current date with no animation"
```

---

### Task 5: Create `EventDetailPanel` widget

**Files:**
- Create: `appflowy_flutter/lib/plugins/database/calendar/presentation/event_detail_panel.dart`

- [ ] **Step 1: Create the event detail panel widget**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';

import '../models/schedule_model.dart';

/// Right-side panel showing full event details.
/// Displays when user clicks an event in the calendar grid.
class EventDetailPanel extends StatelessWidget {
  const EventDetailPanel({
    super.key,
    required this.schedule,
    this.onEdit,
    this.onDelete,
    this.onClose,
  });

  final ScheduleItem schedule;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: af.background,
        border: Border(
          left: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(af, theme),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    af, theme, Icons.calendar_today,
                    _formatDate(schedule.startTime),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    af, theme, Icons.access_time,
                    '${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}',
                  ),
                  if (schedule.isAllDay) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(af, theme, Icons.wb_sunny, '全天事件'),
                  ],
                  if (schedule.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '描述',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: af.onBackground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      schedule.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: af.secondaryTextColor,
                      ),
                    ),
                  ],
                  if (schedule.isImportant) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      af, theme, Icons.star, '重要',
                      iconColor: theme.colorScheme.primary,
                    ),
                  ],
                  if (schedule.repeatType != null &&
                      schedule.repeatType != 'none') ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(af, theme, Icons.repeat, '重复: ${schedule.repeatType}'),
                  ],
                ],
              ),
            ),
          ),
          _buildFooter(af, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(AFThemeExtension af, ThemeData theme) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              schedule.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: af.onBackground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: af.lightIconColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    AFThemeExtension af,
    ThemeData theme,
    IconData icon,
    String text, {
    Color? iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? af.lightIconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: af.onBackground),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AFThemeExtension af, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Delete button
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(4),
            hoverColor: af.lightGreyHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 4),
                  Text(
                    '删除',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Edit button
          ElevatedButton(
            onPressed: onEdit,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('编辑', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(d);
  String _formatTime(DateTime d) => DateFormat('HH:mm').format(d);
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/presentation/event_detail_panel.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/presentation/event_detail_panel.dart
git commit -m "feat(calendar): add EventDetailPanel widget for right-side event details"
```

---

### Task 6: Create `TodoListPanel` widget

**Files:**
- Create: `appflowy_flutter/lib/plugins/database/calendar/presentation/todo_list_panel.dart`

- [ ] **Step 1: Create the todo list panel widget**

```dart
import 'package:flutter/material.dart';
import 'package:flowy_infra/theme_extension.dart';

/// A simple todo item model for the calendar todo list.
class CalendarTodoItem {
  CalendarTodoItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.dueTime,
  });

  final String id;
  final String title;
  bool isCompleted;
  final String? dueTime; // e.g. "14:00"
}

/// Right-side panel showing todo items for the selected date.
class TodoListPanel extends StatefulWidget {
  const TodoListPanel({
    super.key,
    required this.todos,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
  });

  final List<CalendarTodoItem> todos;
  final ValueChanged<String> onAdd; // title
  final ValueChanged<CalendarTodoItem> onToggle;
  final ValueChanged<CalendarTodoItem> onDelete;

  @override
  State<TodoListPanel> createState() => _TodoListPanelState();
}

class _TodoListPanelState extends State<TodoListPanel> {
  final _addController = TextEditingController();
  final _addFocusNode = FocusNode();
  bool _isAdding = false;

  @override
  void dispose() {
    _addController.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final title = _addController.text.trim();
    if (title.isNotEmpty) {
      widget.onAdd(title);
      _addController.clear();
    }
    setState(() => _isAdding = false);
  }

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.checklist, size: 18, color: af.lightIconColor),
              const SizedBox(width: 8),
              Text(
                '待办事项',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: af.onBackground,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  setState(() => _isAdding = true);
                  _addFocusNode.requestFocus();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18, color: af.lightIconColor),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: af.borderColor),
        // Add input
        if (_isAdding)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    focusNode: _addFocusNode,
                    style: TextStyle(fontSize: 13, color: af.onBackground),
                    decoration: InputDecoration(
                      hintText: '添加待办...',
                      hintStyle: TextStyle(color: af.secondaryTextColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: af.borderColor),
                      ),
                    ),
                    onSubmitted: (_) => _submitAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _submitAdd,
                  child: Icon(Icons.check, size: 20, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        // Todo list
        Expanded(
          child: widget.todos.isEmpty
              ? Center(
                  child: Text(
                    '暂无待办',
                    style: TextStyle(
                      fontSize: 13,
                      color: af.secondaryTextColor,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.todos.length,
                  itemBuilder: (ctx, i) => _buildTodoItem(af, theme, widget.todos[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildTodoItem(AFThemeExtension af, ThemeData theme, CalendarTodoItem todo) {
    return InkWell(
      onTap: () => widget.onToggle(todo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: todo.isCompleted,
                onChanged: (_) => widget.onToggle(todo),
                activeColor: theme.colorScheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                todo.title,
                style: TextStyle(
                  fontSize: 13,
                  color: todo.isCompleted
                      ? af.secondaryTextColor
                      : af.onBackground,
                  decoration: todo.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (todo.dueTime != null)
              Text(
                todo.dueTime!,
                style: TextStyle(
                  fontSize: 12,
                  color: af.secondaryTextColor,
                ),
              ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => widget.onDelete(todo),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: af.lightIconColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/presentation/todo_list_panel.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/presentation/todo_list_panel.dart
git commit -m "feat(calendar): add TodoListPanel widget for right-side todo list"
```

---

### Task 7: Integrate right-side panels and left-right sync in `calendar.dart`

**Files:**
- Modify: `appflowy_flutter/lib/plugins/database/calendar/calendar.dart`

- [ ] **Step 1: Add imports at the top of `calendar.dart`**

After existing imports, add:

```dart
import 'presentation/event_detail_panel.dart';
import 'presentation/todo_list_panel.dart';
```

- [ ] **Step 2: Add state variables for right-side panels**

In `_CalendarMainPanelState`, add after existing state variables:

```dart
  // Right-side event detail panel
  ScheduleItem? _detailPanelSchedule;
  // Todo list for selected date
  List<CalendarTodoItem> _todoItems = [];
```

- [ ] **Step 3: Add method to handle event tap from grid (show detail panel)**

```dart
  void _onGridEventTap(ScheduleItem schedule) {
    setState(() {
      _detailPanelSchedule = schedule;
    });
  }

  void _closeDetailPanel() {
    setState(() {
      _detailPanelSchedule = null;
    });
  }
```

- [ ] **Step 4: Add todo management methods**

```dart
  void _addTodo(String title) {
    setState(() {
      _todoItems.add(CalendarTodoItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
      ));
    });
  }

  void _toggleTodo(CalendarTodoItem todo) {
    setState(() {
      todo.isCompleted = !todo.isCompleted;
    });
  }

  void _deleteTodo(CalendarTodoItem todo) {
    setState(() {
      _todoItems.remove(todo);
    });
  }
```

- [ ] **Step 5: Wire `_focusedDay` sync from grid to sidebar**

The `CalendarGridView` already has `_currentDate` which tracks the displayed month. We need to expose it to `CalendarMainPanel` so the left sidebar `DatePicker` follows.

Update `_buildDefaultView()` to pass a callback:

```dart
  Widget _buildDefaultView() {
    return Row(
      children: [
        // Main calendar grid
        Expanded(
          child: CalendarGridView(
            key: _gridViewKey,
            scheduleModel: _scheduleModel,
            selectedDate: _selectedDay ?? _focusedDay,
            onEventCreated: () {
              context.read<CalendarContentCubit>().refresh();
            },
            onEventDeleted: () {
              context.read<CalendarContentCubit>().refresh();
            },
            onMonthChanged: (newDate) {
              // Sync left sidebar calendar
              setState(() {
                _focusedDay = newDate;
              });
            },
            onEventTap: _onGridEventTap,
          ),
        ),
        // Right-side detail panel (if event selected)
        if (_detailPanelSchedule != null) ...[
          VerticalDivider(width: 1),
          SizedBox(
            width: 320,
            child: EventDetailPanel(
              schedule: _detailPanelSchedule!,
              onClose: _closeDetailPanel,
              onEdit: () {
                _performScheduleTap(_detailPanelSchedule!);
                _closeDetailPanel();
              },
              onDelete: () async {
                await _scheduleModel.deleteSchedule(_detailPanelSchedule!.id);
                _closeDetailPanel();
                context.read<CalendarContentCubit>().refresh();
              },
            ),
          ),
        ],
      ],
    );
  }
```

- [ ] **Step 6: Update `CalendarGridView` to accept new callbacks**

In `calendar_grid_view.dart`, update the constructor:

```dart
class CalendarGridView extends StatefulWidget {
  const CalendarGridView({
    super.key,
    required this.scheduleModel,
    required this.selectedDate,
    this.onEventCreated,
    this.onEventDeleted,
    this.onMonthChanged,
    this.onEventTap,
  });

  final ScheduleModel scheduleModel;
  final DateTime selectedDate;
  final VoidCallback? onEventCreated;
  final VoidCallback? onEventDeleted;
  final ValueChanged<DateTime>? onMonthChanged;
  final ValueChanged<ScheduleItem>? onEventTap;
```

- [ ] **Step 7: Fire `onMonthChanged` when navigating months**

In `CalendarGridViewState._navigateDate()`, add after `_loadEvents()`:

```dart
    // Notify parent of month change for left-right sync
    if (widget.onMonthChanged != null) {
      widget.onMonthChanged!(_currentDate);
    }
```

Also in `_goToToday()`:

```dart
    if (widget.onMonthChanged != null) {
      widget.onMonthChanged!(_currentDate);
    }
```

- [ ] **Step 8: Wire `onEventTap` in CustomMonthGrid integration**

In `_buildMonthView()`, update the `onEventTap` callback:

```dart
      onEventTap: (ev) {
        if (ev is ScheduleItem) {
          widget.onEventTap?.call(ev);
        }
      },
```

- [ ] **Step 9: Verify compilation**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/calendar.dart`
Expected: No errors

- [ ] **Step 10: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/calendar.dart
git add appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_grid_view.dart
git commit -m "feat(calendar): integrate right-side event detail panel and left-right calendar sync"
```

---

### Task 8: Add todo list panel to right-side layout

**Files:**
- Modify: `appflowy_flutter/lib/plugins/database/calendar/calendar.dart`

- [ ] **Step 1: Add todo list below event detail panel in `_buildDefaultView()`**

Update `_buildDefaultView()` to include the todo panel:

```dart
  Widget _buildDefaultView() {
    return Row(
      children: [
        // Main calendar grid
        Expanded(
          child: CalendarGridView(
            key: _gridViewKey,
            scheduleModel: _scheduleModel,
            selectedDate: _selectedDay ?? _focusedDay,
            onEventCreated: () {
              context.read<CalendarContentCubit>().refresh();
            },
            onEventDeleted: () {
              context.read<CalendarContentCubit>().refresh();
            },
            onMonthChanged: (newDate) {
              setState(() {
                _focusedDay = newDate;
              });
            },
            onEventTap: _onGridEventTap,
          ),
        ),
        // Right-side panels
        VerticalDivider(width: 1),
        SizedBox(
          width: 320,
          child: Column(
            children: [
              // Event detail (if selected) or empty placeholder
              if (_detailPanelSchedule != null)
                Expanded(
                  flex: 2,
                  child: EventDetailPanel(
                    schedule: _detailPanelSchedule!,
                    onClose: _closeDetailPanel,
                    onEdit: () {
                      _performScheduleTap(_detailPanelSchedule!);
                      _closeDetailPanel();
                    },
                    onDelete: () async {
                      await _scheduleModel.deleteSchedule(_detailPanelSchedule!.id);
                      _closeDetailPanel();
                      context.read<CalendarContentCubit>().refresh();
                    },
                  ),
                ),
              // Todo list
              Expanded(
                flex: 1,
                child: TodoListPanel(
                  todos: _todoItems,
                  onAdd: _addTodo,
                  onToggle: _toggleTodo,
                  onDelete: _deleteTodo,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 2: Verify compilation**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/calendar.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add appflowy_flutter/lib/plugins/database/calendar/calendar.dart
git commit -m "feat(calendar): add todo list panel below event detail in right sidebar"
```

---

### Task 9: Final integration test and cleanup

- [ ] **Step 1: Run full analyze on all changed files**

Run: `cd appflowy_flutter && flutter analyze lib/plugins/database/calendar/`
Expected: No errors

- [ ] **Step 2: Manual verification checklist**

Test in the running app:
1. Open calendar → month grid shows correct day-of-week alignment (June 1 = Sunday)
2. Previous/next month days appear greyed out
3. Click left/right arrows → slide animation plays, left sidebar follows
4. Click "今天" → jumps to today
5. Click an event in grid → right-side detail panel appears
6. Click edit in detail panel → opens edit page
7. Add a todo → appears in list
8. Toggle todo → strikethrough appears
9. Delete todo → removed from list

- [ ] **Step 3: Final commit with all fixes**

```bash
git add -A
git commit -m "feat(calendar): complete calendar system improvement - grid, panels, sync, animation"
```
