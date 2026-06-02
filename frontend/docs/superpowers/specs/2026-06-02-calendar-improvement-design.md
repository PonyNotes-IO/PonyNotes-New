# Calendar System Improvement Design

**Date:** 2026-06-02
**Branch:** dev_mobile

## Problem Statement

The current calendar system has two major issues:

1. **Calendar grid layout is broken** — The month view treats the 1st of every month as Monday and counts forward, ignoring the actual day-of-week. Missing previous/next month fill days.
2. **Right-side panel is incomplete** — No event detail panel or todo list when clicking dates/events.

## Requirements

- Calendar week starts on **Sunday** (user preference)
- Month grid must correctly align each month's 1st to its actual weekday
- Fill previous/next month days (greyed out) to complete the grid
- Right-side: event detail panel on click
- Right-side: todo list for selected date
- Left-right calendar sync — right-side big calendar month change syncs to left-side small calendar
- Smooth slide animation on month transition
- "Today" button to jump back to current date

## Design

### 1. Custom Month Grid (Approach A)

Replace `calendar_view`'s `MonthView` with a custom grid widget.

**Algorithm:**
```
Given: year, month, startDayOfWeek (Sunday=0)

1. Compute weekday of the 1st: weekday = DateTime(year, month, 1).weekday
   (Dart: Monday=1, Sunday=7)
2. Convert to 0-indexed from Sunday: adjustedWeekday = (weekday % 7)
3. Leading fill days = adjustedWeekday (days from previous month)
4. Total cells = 42 (6 rows x 7 columns) — ensures all months fit
5. Generate date matrix:
   - Leading: previous month tail days (grey)
   - Middle: current month days (normal)
   - Trailing: next month head days (grey)
```

**Example (June 2026, Sunday start):**
```
Sun  Mon  Tue  Wed  Thu  Fri  Sat
 31   1    2    3    4    5    6     ← 31 is May (grey)
  7   8    9   10   11   12   13
 14  15   16   17   18   19   20
 21  22   23   24   25   26   27
 28  29   30    1    2    3    4     ← 1-4 are July (grey)
  5   6    7    8    9   10   11
```

**Files:**
- `calendar_grid_view.dart` — Replace `_buildMonthView()` with custom grid
- New: `custom_month_grid.dart` — Pure display widget

### 2. Right-Side Event Detail Panel

**Interaction:** Click event in calendar → right panel shows full details

**Panel content:**
- Title (editable)
- Date + time range (start ~ end)
- All-day event flag
- Description/notes
- Importance flag
- Reminder setting
- Repeat rule
- Edit / Delete buttons

**Files:**
- New: `event_detail_panel.dart`
- `calendar_grid_view.dart` — Wire click events
- `calendar.dart` — Integrate panel in `_buildDefaultView()`

### 3. Right-Side Todo List

**Interaction:** Below event detail panel, show todo items for selected date

**List content:**
- Todo title
- Completion status (checkbox)
- Due time
- Priority marker
- Quick add new todo

**Files:**
- New: `todo_list_panel.dart`
- `calendar.dart` — Integrate in right panel

### 4. Left-Right Calendar Sync + Animation + Today Button

**Sync logic:**
- Right-side big calendar has month navigation (prev/next arrows)
- When user navigates on right side, left-side small `DatePicker` follows to the same month
- Use a shared `ValueNotifier<DateTime>` for `_focusedDay` — both calendars read from it
- `CalendarMainPanel._changeMonth()` already exists — wire it to both sides

**Slide animation:**
- Wrap the month grid in `AnimatedSwitcher` or custom `SlideTransition`
- Direction: slide left for next month, slide right for previous month
- Duration: ~250ms, ease-in-out curve
- Implementation: `PageView`-style swipe or `AnimatedSwitcher` with `SlideTransition`

**Today button:**
- Located in the right-side toolbar (next to month navigation)
- Click → sets `_focusedDay` to `DateTime.now()`, `_selectedDay` to today
- Triggers sync to left sidebar + reload events
- Style: outlined pill button, same as existing sidebar "今天" button

**Files:**
- `calendar.dart` — Wire `_focusedDay` sync between left DatePicker and right grid
- `calendar_grid_view.dart` — Add animation wrapper + Today button in toolbar

## File Change Summary

| File | Action | Description |
|------|--------|-------------|
| `calendar_grid_view.dart` | Modify | Replace MonthView with custom grid, wire click events |
| `custom_month_grid.dart` | Create | Custom month grid widget |
| `event_detail_panel.dart` | Create | Right-side event detail panel |
| `todo_list_panel.dart` | Create | Right-side todo list panel |
| `calendar.dart` | Modify | Integrate new panels, update layout, wire left-right sync |

## Non-Goals

- Replacing `calendar_view` for Day/Week views (keep as-is)
- Redesigning the left sidebar
- Changing the event creation flow (context menu stays)
