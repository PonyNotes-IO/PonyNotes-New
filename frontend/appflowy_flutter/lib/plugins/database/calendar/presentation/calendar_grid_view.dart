import 'package:calendar_view/calendar_view.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

import '../models/schedule_model.dart';
import 'calendar_context_menu.dart';
import 'calendar_view_mode.dart';
import 'custom_month_grid.dart';

/// 飞书风格的三视图网格日历组件
///
/// 支持日/周/月三种视图模式，点击格子可呼出上下文菜单新建日程。
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

  @override
  State<CalendarGridView> createState() => CalendarGridViewState();
}

class CalendarGridViewState extends State<CalendarGridView> {
  CalendarViewMode _viewMode = CalendarViewMode.month;
  late DateTime _currentDate;
  late final EventController<CalendarDayEvent> _eventController;
  Offset? _lastTapPosition;
  // Animation for month transitions
  int _animationDirection = 0; // -1 = left, 0 = none, 1 = right

  @override
  void initState() {
    super.initState();
    _currentDate = widget.selectedDate;
    _eventController = EventController<CalendarDayEvent>();
    _loadEvents();
  }

  @override
  void didUpdateWidget(CalendarGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _currentDate = widget.selectedDate;
    }
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  /// 供父级调用：在指定日期弹出新建日程菜单
  void showCreateMenuForDate(DateTime date) {
    // 使用屏幕中心偏左上方作为默认位置
    final size = MediaQuery.of(context).size;
    final position = Offset(size.width * 0.4, size.height * 0.3);
    _showContextMenu(date, position);
  }

  /// 从 ScheduleModel 加载当前日期范围内的日程
  Future<void> _loadEvents() async {
    DateTime start, end;
    switch (_viewMode) {
      case CalendarViewMode.day:
        start = DateTime(
          _currentDate.year,
          _currentDate.month,
          _currentDate.day,
        );
        end = start.add(const Duration(days: 1));
        break;
      case CalendarViewMode.week:
        start = _currentDate.subtract(
          Duration(days: _currentDate.weekday - 1),
        );
        start = DateTime(start.year, start.month, start.day);
        end = start.add(const Duration(days: 7));
        break;
      case CalendarViewMode.month:
        start = DateTime(_currentDate.year, _currentDate.month, 1);
        end = DateTime(_currentDate.year, _currentDate.month + 1, 1);
        break;
    }

    _eventController.removeWhere((_) => true);

    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      final schedules = widget.scheduleModel.getSchedulesForDate(d);
      for (final s in schedules) {
        _eventController.add(
          CalendarEventData<CalendarDayEvent>(
            title: s.title,
            date: d,
            startTime: s.startTime,
            endTime: s.endTime,
            event: CalendarDayEvent(
              eventId: s.id,
              title: s.title,
              timestamp: s.startTime.millisecondsSinceEpoch,
              schedule: s,
            ),
          ),
        );
      }
    }

    // Force rebuild for month view (CustomMonthGrid reads events on build)
    if (_viewMode == CalendarViewMode.month && mounted) {
      setState(() {});
    }
  }

  void _navigateDate(int delta) {
    setState(() {
      _animationDirection = delta;
      switch (_viewMode) {
        case CalendarViewMode.day:
          _currentDate = _currentDate.add(Duration(days: delta));
          break;
        case CalendarViewMode.week:
          _currentDate = _currentDate.add(Duration(days: delta * 7));
          break;
        case CalendarViewMode.month:
          _currentDate = DateTime(
            _currentDate.year,
            _currentDate.month + delta,
            1,
          );
          break;
      }
    });
    _loadEvents();
    if (widget.onMonthChanged != null) {
      widget.onMonthChanged!(_currentDate);
    }
    // Reset animation direction after transition
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _animationDirection = 0);
    });
  }

  void _goToToday() {
    setState(() {
      _animationDirection = 0;
      _currentDate = DateTime.now();
    });
    _loadEvents();
    if (widget.onMonthChanged != null) {
      widget.onMonthChanged!(_currentDate);
    }
  }

  String get _dateTitle {
    switch (_viewMode) {
      case CalendarViewMode.day:
        return DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(_currentDate);
      case CalendarViewMode.week:
        final weekStart = _currentDate.subtract(
          Duration(days: _currentDate.weekday - 1),
        );
        final weekEnd = weekStart.add(const Duration(days: 6));
        return '${DateFormat('M月d日').format(weekStart)} - ${DateFormat('M月d日').format(weekEnd)}';
      case CalendarViewMode.month:
        return DateFormat('yyyy年M月').format(_currentDate);
    }
  }

  // ==================== 点击事件 ====================

  /// 空白格子点击 → 新建日程菜单
  void _onDateTap(DateTime date) {
    final position = _lastTapPosition ?? const Offset(400, 300);
    _showContextMenu(date, position);
  }

  void _showContextMenu(DateTime date, Offset position) {
    CalendarContextMenu.show(
      context: context,
      position: position,
      date: date,
      scheduleModel: widget.scheduleModel,
      onEventCreated: () {
        _loadEvents();
        widget.onEventCreated?.call();
      },
    );
  }

  /// 日程事件点击 → 内联详情弹窗
  void _onEventTap(ScheduleItem schedule) {
    final position = _lastTapPosition ?? const Offset(400, 300);
    _EventDetailPopup.show(
      context: context,
      position: position,
      schedule: schedule,
      scheduleModel: widget.scheduleModel,
      onDeleted: () {
        _loadEvents();
        widget.onEventDeleted?.call();
      },
      onUpdated: () {
        _loadEvents();
        widget.onEventCreated?.call();
      },
    );
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    return CalendarControllerProvider(
      controller: _eventController,
      child: Column(
        children: [
          _buildToolbar(context),
          Expanded(child: _buildCalendarContent()),
        ],
      ),
    );
  }

  // ---------- 工具栏 ----------

  Widget _buildToolbar(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);
    final appflowyTheme = AppFlowyTheme.of(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: appflowyTheme.backgroundColorScheme.primary,
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _buildViewModeToggle(context),
          const SizedBox(width: 16),
          _NavButton(
            icon: Icons.chevron_left,
            tooltip: '上一${_viewMode.label}',
            onTap: () => _navigateDate(-1),
          ),
          _NavButton(
            icon: Icons.chevron_right,
            tooltip: '下一${_viewMode.label}',
            onTap: () => _navigateDate(1),
          ),
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _dateTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: af.onBackground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: af.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: CalendarViewMode.values.map((mode) {
          final isSelected = _viewMode == mode;
          return InkWell(
            onTap: () {
              setState(() => _viewMode = mode);
              _loadEvents();
            },
            borderRadius: BorderRadius.circular(5),
            hoverColor: af.lightGreyHover,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                mode.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : af.textColor,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------- 日历内容 ----------

  Widget _buildCalendarContent() {
    final af = AFThemeExtension.of(context);

    return GestureDetector(
      onTapDown: (details) => _lastTapPosition = details.globalPosition,
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        color: af.background,
        child: switch (_viewMode) {
          CalendarViewMode.day => _buildDayView(),
          CalendarViewMode.week => _buildWeekView(),
          CalendarViewMode.month => _buildAnimatedMonthView(),
        },
      ),
    );
  }

  Widget _buildDayView() {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return DayView<CalendarDayEvent>(
      key: ValueKey(
        'day_${_currentDate.year}_${_currentDate.month}_${_currentDate.day}',
      ),
      controller: _eventController,
      showVerticalLine: true,
      showLiveTimeLineInAllDays: true,
      minDay: DateTime(1970),
      maxDay: DateTime(2050),
      initialDay: _currentDate,
      heightPerMinute: 1.0,
      timeLineWidth: 60,
      // 格子背景色：跟随项目主题
      backgroundColor: af.background,
      // 网格线：淡灰色调
      hourIndicatorSettings: HourIndicatorSettings(
        color: af.borderColor,
        height: 0.5,
      ),
      halfHourIndicatorSettings: HourIndicatorSettings.none(),
      liveTimeIndicatorSettings: HourIndicatorSettings(
        color: theme.colorScheme.primary,
        height: 1.5,
      ),
      timeLineBuilder: _buildTimeLine,
      dayTitleBuilder: _buildDayTitle,
      eventTileBuilder: _buildEventTile,
      onDateTap: _onDateTap,
      onPageChange: (date, page) {
        setState(() => _currentDate = date);
        _loadEvents();
      },
    );
  }

  Widget _buildWeekView() {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return WeekView<CalendarDayEvent>(
      key: ValueKey(
        'week_${_currentDate.year}_${_currentDate.month}_${_currentDate.day}',
      ),
      controller: _eventController,
      showVerticalLines: true,
      showLiveTimeLineInAllDays: true,
      minDay: DateTime(1970),
      maxDay: DateTime(2050),
      initialDay: _currentDate,
      heightPerMinute: 0.8,
      timeLineWidth: 60,
      // 格子背景色：跟随项目主题
      backgroundColor: af.background,
      // 网格线：淡灰色调
      hourIndicatorSettings: HourIndicatorSettings(
        color: af.borderColor,
        height: 0.5,
      ),
      liveTimeIndicatorSettings: HourIndicatorSettings(
        color: theme.colorScheme.primary,
        height: 1.5,
      ),
      timeLineBuilder: _buildTimeLine,
      weekDayStringBuilder: (day) {
        const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        return weekdays[day % 7];
      },
      eventTileBuilder: _buildEventTile,
      onDateTap: _onDateTap,
      onPageChange: (date, page) {
        setState(() => _currentDate = date);
        _loadEvents();
      },
      // 自定义周头部：使用主题色适配黑暗/白色模式
      weekPageHeaderBuilder: (startDate, endDate) {
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: af.borderColor, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              _NavButton(
                icon: Icons.chevron_left,
                tooltip: '上一周',
                onTap: () => _navigateDate(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${DateFormat('M月d日').format(startDate)} - ${DateFormat('M月d日').format(endDate)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              _NavButton(
                icon: Icons.chevron_right,
                tooltip: '下一周',
                onTap: () => _navigateDate(1),
              ),
            ],
          ),
        );
      },
    );
  }

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

  Widget _buildMonthView() {
    // Build events map for the grid
    final eventsMap = <DateTime, List<CalendarEventItem>>{};
    final start = DateTime(_currentDate.year, _currentDate.month, 1);
    final end = DateTime(_currentDate.year, _currentDate.month + 1, 1);
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      final schedules = widget.scheduleModel.getSchedulesForDate(d);
      if (schedules.isNotEmpty) {
        eventsMap[DateTime(d.year, d.month, d.day)] = schedules.map(
          (s) => CalendarEventItem(id: s.id, title: s.title, schedule: s),
        ).toList();
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
        if (ev.schedule != null) {
          widget.onEventTap?.call(ev.schedule!);
        }
      },
    );
  }

  // ---------- 共用子组件 ----------

  Widget _buildTimeLine(DateTime time) {
    final af = AFThemeExtension.of(context);

    return Container(
      color: af.background,
      padding: const EdgeInsets.only(right: 8),
      alignment: Alignment.centerRight,
      child: Text(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        style: TextStyle(fontSize: 11, color: af.secondaryTextColor),
      ),
    );
  }

  Widget _buildDayTitle(DateTime date) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('E', 'zh_CN').format(date),
            style: TextStyle(fontSize: 12, color: af.secondaryTextColor),
          ),
          const SizedBox(height: 2),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isToday ? theme.colorScheme.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isToday ? theme.colorScheme.onPrimary : af.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(
    DateTime date,
    List<CalendarEventData<CalendarDayEvent>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    if (events.isEmpty) return const SizedBox.shrink();

    final event = events.first;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        final schedule = event.event?.schedule;
        if (schedule != null) {
          _onEventTap(schedule);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AFThemeExtension.of(context).tint1,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AFThemeExtension.of(context).borderColor,
            width: 0.5,
          ),
        ),
        child: Text(
          event.title,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }
}

// ==================== 导航按钮 ====================

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: af.lightGreyHover,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 18, color: af.lightIconColor),
        ),
      ),
    );
  }
}

// ==================== 日程详情弹窗 ====================

/// 点击日程事件后弹出的详情浮层，含编辑/删除按钮。
class _EventDetailPopup {
  _EventDetailPopup._();

  static void show({
    required BuildContext context,
    required Offset position,
    required ScheduleItem schedule,
    required ScheduleModel scheduleModel,
    VoidCallback? onDeleted,
    VoidCallback? onUpdated,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _EventDetailOverlay(
        position: position,
        schedule: schedule,
        scheduleModel: scheduleModel,
        onDismiss: () => entry.remove(),
        onDeleted: () {
          entry.remove();
          onDeleted?.call();
        },
        onUpdated: onUpdated,
      ),
    );

    overlay.insert(entry);
  }
}

class _EventDetailOverlay extends StatefulWidget {
  const _EventDetailOverlay({
    required this.position,
    required this.schedule,
    required this.scheduleModel,
    required this.onDismiss,
    this.onDeleted,
    this.onUpdated,
  });

  final Offset position;
  final ScheduleItem schedule;
  final ScheduleModel scheduleModel;
  final VoidCallback onDismiss;
  final VoidCallback? onDeleted;
  final VoidCallback? onUpdated;

  @override
  State<_EventDetailOverlay> createState() => _EventDetailOverlayState();
}

class _EventDetailOverlayState extends State<_EventDetailOverlay> {
  static const double _popupWidth = 280;
  static const double _popupMaxHeight = 340;

  bool _isEditing = false;
  bool _isDeleting = false;

  // 编辑态
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TimeOfDay _editStart;
  late TimeOfDay _editEnd;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.schedule.title);
    _descCtrl = TextEditingController(text: widget.schedule.description);
    _editStart = TimeOfDay.fromDateTime(widget.schedule.startTime);
    _editEnd = TimeOfDay.fromDateTime(widget.schedule.endTime);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Offset _calcPos(BuildContext context) {
    final size = MediaQuery.of(context).size;
    double x = widget.position.dx;
    double y = widget.position.dy;
    if (x + _popupWidth > size.width) x = size.width - _popupWidth - 16;
    if (y + _popupMaxHeight > size.height) y = size.height - _popupMaxHeight - 16;
    if (x < 16) x = 16;
    if (y < 16) y = 16;
    return Offset(x, y);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) => DateFormat('M月d日 EEEE', 'zh_CN').format(d);

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _editStart : _editEnd,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _editStart = picked;
        } else {
          _editEnd = picked;
        }
      });
    }
  }

  Future<void> _saveEdit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      showToastNotification(
        message: '标题不能为空',
        type: ToastificationType.warning,
      );
      return;
    }
    try {
      final s = widget.schedule;
      final newStart = DateTime(
        s.startTime.year, s.startTime.month, s.startTime.day,
        _editStart.hour, _editStart.minute,
      );
      final newEnd = DateTime(
        s.endTime.year, s.endTime.month, s.endTime.day,
        _editEnd.hour, _editEnd.minute,
      );
      final updated = ScheduleItem(
        id: s.id,
        title: title,
        description: _descCtrl.text.trim(),
        startTime: newStart,
        endTime: newEnd,
        isAllDay: s.isAllDay,
        isImportant: s.isImportant,
        category: s.category,
        color: s.color,
        reminderId: s.reminderId,
        reminderOption: s.reminderOption,
        dueDate: s.dueDate,
        repeatType: s.repeatType,
        repeatRuleJson: s.repeatRuleJson,
      );
      await widget.scheduleModel.updateSchedule(updated);
      if (mounted) {
        showToastNotification(
          message: '日程已更新',
          type: ToastificationType.success,
        );
        widget.onUpdated?.call();
        widget.onDismiss();
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: '更新失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    try {
      await widget.scheduleModel.deleteSchedule(widget.schedule.id);
      if (mounted) {
        showToastNotification(
          message: '日程已删除',
          type: ToastificationType.success,
        );
        widget.onDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        showToastNotification(
          message: '删除失败: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);
    final pos = _calcPos(context);
    final s = widget.schedule;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: af.background,
            shadowColor: af.scrollbarColor,
            child: Container(
              width: _popupWidth,
              constraints: const BoxConstraints(maxHeight: _popupMaxHeight),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: af.borderColor, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(af, theme),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: _isEditing
                          ? _buildEditBody(af, theme)
                          : _buildViewBody(af, theme, s),
                    ),
                  ),
                  _buildFooter(af, theme),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AFThemeExtension af, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: af.borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.event, size: 16, color: af.lightIconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEditing ? '编辑日程' : widget.schedule.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: af.onBackground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: widget.onDismiss,
            borderRadius: BorderRadius.circular(4),
            hoverColor: af.lightGreyHover,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: af.lightIconColor),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 查看态 ----------

  Widget _buildViewBody(
    AFThemeExtension af,
    ThemeData theme,
    ScheduleItem s,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期
        _infoRow(af, Icons.calendar_today, _fmtDate(s.startTime)),
        const SizedBox(height: 8),
        // 时间
        _infoRow(
          af,
          Icons.access_time,
          '${_fmtTime(TimeOfDay.fromDateTime(s.startTime))} - '
              '${_fmtTime(TimeOfDay.fromDateTime(s.endTime))}',
        ),
        if (s.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          _infoRow(af, Icons.notes, s.description, maxLines: 3),
        ],
        if (s.isImportant) ...[
          const SizedBox(height: 8),
          _infoRow(af, Icons.star, '重要', iconColor: theme.colorScheme.primary),
        ],
        if (s.isAllDay) ...[
          const SizedBox(height: 8),
          _infoRow(af, Icons.wb_sunny, '全天事件'),
        ],
      ],
    );
  }

  Widget _infoRow(
    AFThemeExtension af,
    IconData icon,
    String text, {
    int maxLines = 1,
    Color? iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor ?? af.lightIconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: af.onBackground),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ---------- 编辑态 ----------

  Widget _buildEditBody(AFThemeExtension af, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        TextField(
          controller: _titleCtrl,
          style: TextStyle(fontSize: 13, color: af.onBackground),
          decoration: InputDecoration(
            hintText: '日程标题',
            hintStyle: TextStyle(color: af.secondaryTextColor),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: af.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: af.borderColor),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 时间行
        Row(
          children: [
            Text('开始', style: TextStyle(fontSize: 12, color: af.secondaryTextColor)),
            const SizedBox(width: 8),
            _timeChip(af, theme, _editStart, () => _pickTime(true)),
            const SizedBox(width: 12),
            Text('结束', style: TextStyle(fontSize: 12, color: af.secondaryTextColor)),
            const SizedBox(width: 8),
            _timeChip(af, theme, _editEnd, () => _pickTime(false)),
          ],
        ),
        const SizedBox(height: 10),
        // 描述
        TextField(
          controller: _descCtrl,
          style: TextStyle(fontSize: 13, color: af.onBackground),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: '描述',
            hintStyle: TextStyle(color: af.secondaryTextColor),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: af.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: af.borderColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeChip(
    AFThemeExtension af,
    ThemeData theme,
    TimeOfDay time,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      hoverColor: af.lightGreyHover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: af.borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _fmtTime(time),
          style: TextStyle(fontSize: 12, color: af.onBackground),
        ),
      ),
    );
  }

  // ---------- 底部按钮 ----------

  Widget _buildFooter(AFThemeExtension af, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: af.borderColor, width: 0.5)),
      ),
      child: _isEditing
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () => setState(() => _isEditing = false),
                  borderRadius: BorderRadius.circular(4),
                  hoverColor: af.lightGreyHover,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 12,
                        color: af.secondaryTextColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveEdit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  child: Text(
                    '保存',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // 删除
                InkWell(
                  onTap: _isDeleting
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('确认删除'),
                              content: Text(
                                '确定要删除日程「${widget.schedule.title}」吗？',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _delete();
                                  },
                                  child: Text(
                                    '删除',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                  borderRadius: BorderRadius.circular(4),
                  hoverColor: af.lightGreyHover,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: _isDeleting
                              ? af.lightIconColor
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '删除',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isDeleting
                                ? af.lightIconColor
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // 编辑
                ElevatedButton(
                  onPressed: () => setState(() => _isEditing = true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  child: Text(
                    '编辑',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ==================== 日历事件数据模型 ====================

class CalendarDayEvent {
  CalendarDayEvent({
    required this.eventId,
    required this.title,
    required this.timestamp,
    this.schedule,
  });

  final String eventId;
  final String title;
  final int timestamp;
  final ScheduleItem? schedule;
}
