# Calendar Improvement Design Spec

Date: 2026-06-02
Branch: dev_mobile

## Overview

Three improvements to the calendar module:
1. Fix time picker focus loss in CalendarContextMenu
2. Add back button + title/description fields to EditEventPage
3. Remove schedule list from mini calendar sidebar, update "+" menu

---

## Task 1: Embedded Time Picker in CalendarContextMenu

### Problem

`CalendarContextMenu` is a floating Overlay entry. When the user taps the time display chip, `showTimePicker()` opens a Material dialog, which steals focus and causes the Overlay to dismiss.

### Solution

Replace `showTimePicker()` with an inline `CupertinoPicker` that expands within the menu itself.

### Changes

**File:** `appflowy_flutter/lib/plugins/database/calendar/presentation/calendar_context_menu.dart`

1. Add state variables:
   - `bool _showStartTimePicker = false`
   - `bool _showEndTimePicker = false`

2. Modify `_buildTimePicker()` (lines 368-404):
   - Remove `showTimePicker()` call
   - On tap, toggle the corresponding `_showStartTimePicker` / `_showEndTimePicker` flag
   - When flag is true, render a 120px-high inline picker below the time row
   - Picker uses two `CupertinoPicker` widgets side by side (hour 0-23, minute 0-59 with 5-min steps)
   - Selecting a value updates `_startTime` / `_endTime` and auto-collapses the picker

3. Modify `_buildTimeSection()` (lines 310-346):
   - After each `_buildTimeRow()`, conditionally render the inline picker
   - Use `AnimatedSize` for smooth expand/collapse transition

4. Handle the reminder chip similarly: replace `showDialog` with `Navigator.push` to avoid overlay conflict, or keep the dialog since it's a separate interaction path (the reminder chip doesn't cause the same focus issue because the menu is already open and the dialog is a child route).

### UI Spec

```
┌──────────────────────────────┐
│ 新建日程           6月2日 周二 │
├──────────────────────────────┤
│ [日程标题          ]          │
│                              │
│ ⏱ 全天            [开关]     │
│ 开始  [14:00 ▼]              │
│ ┌──────────────────────────┐ │
│ │  13  14  15              │ │  ← inline CupertinoPicker
│ │  00  30                  │ │     (120px, shows on tap)
│ └──────────────────────────┘ │
│ 结束  [15:00 ▼]              │
│                              │
│ [添加描述...]                │
│ [标记重要] [提醒]            │
├──────────────────────────────┤
│           [取消] [创建]       │
└──────────────────────────────┘
```

---

## Task 2: EditEventPage Improvements

### Problem

- No back/close button on EditEventPage itself (relies on parent toolbar)
- No direct title or description input fields (description is in a dialog)
- Bug: `_description` is assigned from `schedule.title` (line 125), and on save `title` is set to `_description` (line 371) — title and description are conflated

### Solution

Add a back button bar, inline title/description fields, and fix the title/description separation.

### Changes

**File:** `appflowy_flutter/lib/plugins/database/calendar/presentation/edit_event_page.dart`

1. Add state variable:
   - `late String _title` (separate from `_description`)
   - Add `TextEditingController _titleController` and `_descriptionController`

2. Fix `_initializeFromSchedule()` (line 108-137):
   - `_title = schedule.title`
   - `_description = schedule.description`
   - Initialize controllers

3. Add back button bar at top of `build()` method (before time picker area):
   - Row with: back arrow (`Icons.arrow_back`) + "编辑日程" title + "保存" button
   - Back arrow calls `widget.onCancel()`
   - Save button calls `saveEvent()`

4. Add title TextField below time picker area:
   - Bound to `_titleController`
   - Placeholder: "日程标题"
   - OnChanged updates `_title` and calls `_notifyUnsavedConfig()`

5. Add description TextField below title:
   - Bound to `_descriptionController`
   - Placeholder: "添加说明..."
   - MaxLines: 3
   - OnChanged updates `_description` and calls `_notifyUnsavedConfig()`

6. Fix `saveEvent()` and `_saveEventAsync()`:
   - Validation: check `_title.trim().isEmpty` instead of `_description.trim().isEmpty`
   - `updatedSchedule.copyWith(title: _title, description: _description)`

7. Remove the "添加说明" ListTile from the options list (since description is now inline)

8. Update `_hasUnsavedConfigChanges()` to include `_title` comparison

9. Update `_markCurrentStateAsSaved()` to include `_title`

### UI Spec

```
┌──────────────────────────────┐
│ ←  编辑日程            [保存] │  ← new back button bar
├──────────────────────────────┤
│        14:00                 │
│    今天 周二                  │
│        ↓                     │
│        15:00                 │
│    今天 周二                  │
├──────────────────────────────┤
│ [日程标题          ]          │  ← new title field
│ [添加说明...       ]          │  ← new description field (inline)
│                              │
│ ⏱ 全天            [开关]     │
│ 🔔 提醒            [无]      │
│ 🔄 任务重复        [无]      │
│                              │
│ ──────────────────────────── │
│ 🗑 删除日程                  │
└──────────────────────────────┘
```

---

## Task 3: Mini Calendar Sidebar

### Problem

- Schedule list below mini calendar should be removed
- "+" menu text should be updated

### Solution

Remove `ScheduleSidebarContent` from `CalendarContent`, rename menu items.

### Changes

**File 1:** `appflowy_flutter/lib/plugins/database/calendar/presentation/widgets/calendar_content_widget.dart`

1. In `_buildBody()` (lines 114-183):
   - Remove all `ScheduleSidebarContent` widget instances (lines 147-151 and 169-172)
   - Keep the note tree (`_buildNoteTree`)
   - Keep the empty state message but update text to "当天暂无笔记"
   - Remove the `if (widget.viewId != null)` conditional blocks that render schedules

2. Remove the import of `schedule_sidebar_content.dart` if no longer used

**File 2:** `appflowy_flutter/lib/plugins/database/calendar/calendar.dart`

1. In `_buildAddMenu()` (lines 1104-1153):
   - Change "新建笔记页" to "新建日记"
   - Change icon from `Icons.book` to `Icons.edit_note`

2. In `_buildExpandedSidebar()` (lines 1391-1543):
   - No structural changes needed (CalendarContent is still used for the note tree)

---

## Files to Modify

| File | Task | Changes |
|------|------|---------|
| `calendar_context_menu.dart` | 1 | Replace showTimePicker with inline CupertinoPicker |
| `edit_event_page.dart` | 2 | Add back button, title/description fields, fix bug |
| `calendar_content_widget.dart` | 3 | Remove ScheduleSidebarContent |
| `calendar.dart` | 3 | Update "+" menu text |

## Dependencies

No new dependencies required. `CupertinoPicker` is from `package:flutter/cupertino.dart` which is already imported in `calendar_context_menu.dart` (indirectly via Material).

## Testing

- Task 1: Click calendar cell → context menu appears → tap time → inline picker expands → select time → picker collapses → create event → verify time is correct
- Task 2: Open edit event page → verify back button visible → verify title/description fields pre-filled → edit and save → verify data persisted correctly
- Task 3: Check sidebar → verify no schedule list below mini calendar → tap "+" → verify "新建日记" and "新建日程" options → test both options work
