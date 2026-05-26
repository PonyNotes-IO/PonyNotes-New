import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/database/mobile_reminder_page.dart';
import 'package:appflowy/mobile/presentation/database/mobile_repeat_page.dart';
import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileEditEventPage extends StatefulWidget {
  final ScheduleItem schedule;
  final ScheduleModel scheduleModel;
  final VoidCallback? onEventUpdated;
  final VoidCallback? onEventDeleted;

  const MobileEditEventPage({
    super.key,
    required this.schedule,
    required this.scheduleModel,
    this.onEventUpdated,
    this.onEventDeleted,
  });

  @override
  State<MobileEditEventPage> createState() => _MobileEditEventPageState();
}

class _MobileEditEventPageState extends State<MobileEditEventPage> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isAllDay;
  late String _description;
  late ReminderOption _reminderOption;
  late int _repeatType;
  String? _repeatCustomSummary;

  // 初始状态快照，用于检测未保存更改
  late TimeOfDay _initialStartTime;
  late TimeOfDay _initialEndTime;
  late DateTime _initialStartDate;
  late DateTime _initialEndDate;
  late bool _initialIsAllDay;
  late String _initialDescription;
  late ReminderOption _initialReminderOption;
  late int _initialRepeatType;
  String? _initialRepeatCustomSummary;

  @override
  void initState() {
    super.initState();
    _initializeFromSchedule();
    _captureInitialSnapshot();
  }

  void _initializeFromSchedule() {
    final schedule = widget.schedule;
    _startTime = TimeOfDay.fromDateTime(schedule.startTime);
    _endTime = TimeOfDay.fromDateTime(schedule.endTime);
    _startDate = schedule.startTime;
    _endDate = schedule.endTime;
    _isAllDay = schedule.isAllDay;
    _description = schedule.description.isNotEmpty ? schedule.description : '';
    _reminderOption = schedule.reminderOption;
    _repeatType = schedule.repeatType;
    _repeatCustomSummary = schedule.repeatRuleJson;
  }

  void _captureInitialSnapshot() {
    _initialStartTime = _startTime;
    _initialEndTime = _endTime;
    _initialStartDate = _startDate;
    _initialEndDate = _endDate;
    _initialIsAllDay = _isAllDay;
    _initialDescription = _description;
    _initialReminderOption = _reminderOption;
    _initialRepeatType = _repeatType;
    _initialRepeatCustomSummary = _repeatCustomSummary;
  }

  bool _hasUnsavedChanges() {
    final startTimeChanged = _startTime.hour != _initialStartTime.hour ||
        _startTime.minute != _initialStartTime.minute;
    final endTimeChanged = _endTime.hour != _initialEndTime.hour ||
        _endTime.minute != _initialEndTime.minute;
    final startDateChanged = _startDate.year != _initialStartDate.year ||
        _startDate.month != _initialStartDate.month ||
        _startDate.day != _initialStartDate.day;
    final endDateChanged = _endDate.year != _initialEndDate.year ||
        _endDate.month != _initialEndDate.month ||
        _endDate.day != _initialEndDate.day;

    return _description != _initialDescription ||
        _repeatType != _initialRepeatType ||
        (_repeatCustomSummary ?? '') != (_initialRepeatCustomSummary ?? '') ||
        _reminderOption != _initialReminderOption ||
        startDateChanged ||
        endDateChanged ||
        startTimeChanged ||
        endTimeChanged ||
        _isAllDay != _initialIsAllDay;
  }

  void _handleClose() async {
    if (_hasUnsavedChanges()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('确认退出'),
          content: const Text('还有未保存的设置，确定要退出吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getWeekday(int weekday) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return weekdays[weekday - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.month}月${date.day}日';
  }

  String _formatAllDayDate(DateTime date) {
    final today = DateTime.now();
    if (date.year == today.year && date.month == today.month && date.day == today.day) {
      return '今天';
    }
    return '${date.month}月${date.day}日';
  }

  String _getReminderOptionLabel() {
    if (_reminderOption == ReminderOption.none) {
      return '无';
    }
    return _reminderOption.label;
  }

  String _extractSummaryFromJson(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return '自定义';
    }
    try {
      final data = jsonDecode(jsonStr);
      if (data is Map && data.containsKey('summary')) {
        final summary = data['summary'];
        if (summary is String && summary.isNotEmpty) {
          return summary;
        }
      }
      return '自定义';
    } catch (e) {
      return jsonStr;
    }
  }

  String _getRepeatLabel() {
    if (_repeatType == 0) return '任务重复';
    if (_repeatType == 99) return _extractSummaryFromJson(_repeatCustomSummary);
    switch (_repeatType) {
      case 1:
        return '每天';
      case 2:
        return '每周';
      case 3:
        return '每年';
      case 4:
        return '法定工作日';
      case 5:
        return '工作日';
      default:
        return '任务重复';
    }
  }

  bool saveEvent() {
    if (_description.trim().isEmpty) {
      showToastNotification(
        message: '请添加日程描述',
        type: ToastificationType.error,
      );
      return false;
    }

    final startDateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final endDateTime = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (endDateTime.isBefore(startDateTime)) {
      showToastNotification(
        message: '结束时间不能早于开始时间',
        type: ToastificationType.error,
      );
      return false;
    }

    _saveEventAsync(startDateTime, endDateTime);
    return true;
  }

  Future<void> _saveEventAsync(DateTime startDateTime, DateTime endDateTime) async {
    try {
      // 创建更新后的 ScheduleItem
      final updatedSchedule = widget.schedule.copyWith(
        title: _description,
        description: _description,
        startTime: startDateTime,
        endTime: endDateTime,
        isAllDay: _isAllDay,
        reminderOption: _reminderOption,
        repeatType: _repeatType,
        repeatRuleJson: _repeatCustomSummary,
      );

      final success = await widget.scheduleModel.updateSchedule(updatedSchedule);

      if (success && mounted) {
        showToastNotification(
          message: '日程已更新',
          type: ToastificationType.success,
        );
        widget.onEventUpdated?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: '更新日程失败',
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _deleteEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('删除日程'),
        content: const Text('确定要删除这个日程吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.scheduleModel.deleteSchedule(widget.schedule.id);
        if (mounted) {
          showToastNotification(
            message: '日程已删除',
            type: ToastificationType.success,
          );
          widget.onEventDeleted?.call();
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          showToastNotification(
            message: '删除日程失败',
            type: ToastificationType.error,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: AppFlowyTheme.of(context).iconColorScheme.primary,
          ),
          onPressed: () => _handleClose(),
        ),
        leadingWidth: 56,
        automaticallyImplyLeading: false,
        title: Text(
          '编辑日程',
          style: AppFlowyTheme.of(context).textStyle.heading4.standard(
            color: AppFlowyTheme.of(context).textColorScheme.primary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                children: [
                  // 顶部时间选择区域
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        // 时间选择器
                        _isAllDay ? _buildAllDayDatePicker(theme) : _buildTimeRangePicker(theme),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),

                  // 选项列表
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        // 全天选项
                        _buildOptionItem(
                          icon: FlowySvgs.icon_time_calendar_lg,
                          title: '全天',
                          value: '',
                          trailing: _buildSwitch(value: _isAllDay, onChanged: (value) {
                            setState(() {
                              _isAllDay = value;
                              if (_isAllDay) {
                                _startDate = _endDate;
                                _startTime = const TimeOfDay(hour: 0, minute: 0);
                                _endTime = const TimeOfDay(hour: 23, minute: 59);
                              } else {
                                _startTime = TimeOfDay.fromDateTime(widget.schedule.startTime);
                                _endTime = TimeOfDay.fromDateTime(widget.schedule.endTime);
                              }
                            });
                          }),
                          onTap: null,
                        ),

                        // 准时选项
                        _buildOptionItem(
                          icon: FlowySvgs.icon_alarm_clock_m,
                          title: _getReminderOptionLabel(),
                          value: '',
                          onTap: () => _showReminderDialog(),
                        ),

                        // 日程重复选项
                        _buildOptionItem(
                          icon: FlowySvgs.icon_repeat_calender_m,
                          title: _getRepeatLabel(),
                          value: '',
                          onTap: () => _showRepeatPage(),
                        ),

                        // 添加说明选项
                        _buildOptionItem(
                          icon: FlowySvgs.icon_edit_m,
                          title: _description.isEmpty ? '添加说明' : _description,
                          value: '',
                          onTap: () => _showDescriptionDialog(),
                        ),

                        const SizedBox(height: 40),

                        // 删除按钮
                        _buildOptionItem(
                          icon: FlowySvgs.close_s,
                          title: '删除日程',
                          value: '',
                          titleColor: Colors.red,
                          onTap: _deleteEvent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 底部保存按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    if (saveEvent()) {
                      // saveEvent will handle navigation
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangePicker(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 80,
      child: Row(
        children: [
          // 开始时间
          Expanded(
            child: GestureDetector(
              onTap: () => _showTimePickerDialog(isStartTime: true),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatTime(_startTime),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(_startDate),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 箭头
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              Icons.arrow_forward,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
              size: 24,
            ),
          ),

          // 结束时间
          Expanded(
            child: GestureDetector(
              onTap: () => _showTimePickerDialog(isStartTime: false),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatTime(_endTime),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(_endDate),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllDayDatePicker(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 80,
      child: Row(
        children: [
          // 左侧占位，保持与时间区间选择器布局一致
          const Expanded(
            child: SizedBox(),
          ),
          // 中间显示内容，居中展示
          Expanded(
            child: GestureDetector(
              onTap: () => _showDatePickerDialog(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatAllDayDate(_startDate),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    softWrap: false,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '周${_getWeekday(_startDate.weekday)}  全天',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右侧占位，保持对称
          const Expanded(
            child: SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem({
    required FlowySvgData icon,
    required String title,
    required String value,
    required VoidCallback? onTap,
    Widget? trailing,
    Color? titleColor,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            FlowySvg(
              icon,
              color: titleColor ?? theme.iconTheme.color,
              size: const Size.square(24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: titleColor ?? theme.textTheme.bodyLarge?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.iconTheme.color?.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch({required bool value, required ValueChanged<bool> onChanged}) {
    return Toggle(
      value: value,
      onChanged: onChanged,
      style: const ToggleStyle.mobile(),
      activeBackgroundColor: Theme.of(context).colorScheme.primary,
      padding: EdgeInsets.zero,
    );
  }

  void _showTimePickerDialog({bool isStartTime = true}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TimePickerDialog(
        initialStartTime: _startTime,
        initialEndTime: _endTime,
        initialStartDate: _startDate,
        initialEndDate: _endDate,
        isStartTime: isStartTime,
        onSave: (startTime, endTime, startDate, endDate) {
          setState(() {
            _startTime = startTime;
            _endTime = endTime;
            _startDate = startDate;
            _endDate = endDate;
          });
        },
      ),
    );
  }

  void _showDatePickerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DatePickerDialog(
        initialDate: _startDate,
        onSave: (date) {
          setState(() {
            _startDate = date;
            _endDate = date;
          });
        },
      ),
    );
  }

  void _showReminderDialog() {
    Navigator.of(context).push<ReminderOption>(
      MaterialPageRoute(
        builder: (context) => MobileReminderPage(
          initialOption: _reminderOption,
        ),
      ),
    ).then((result) {
      if (result != null) {
        setState(() {
          _reminderOption = result;
        });
      }
    });
  }

  void _showRepeatPage() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MobileRepeatPage(
          initialType: _repeatType,
          initialCustomSummary: _repeatCustomSummary,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _repeatType = result['type'] as int;
        _repeatCustomSummary = result['customSummary'] as String?;
      });
    }
  }

  void _showDescriptionDialog() {
    final controller = TextEditingController(text: _description);
    final theme = AppFlowyTheme.of(context);
    final materialTheme = Theme.of(context);

    showDialog(
      context: context,
      barrierColor: theme.surfaceColorScheme.overlay,
      builder: (ctx) => AFModal(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AFModalHeader(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FlowySvg(
                    FlowySvgs.icon_edit_m,
                    size: const Size.square(20),
                  ),
                  const SizedBox(width: 8),
                  const Text('添加说明'),
                ],
              ),
              trailing: [
                AFGhostButton.normal(
                  onTap: () => Navigator.of(ctx).pop(),
                  padding: EdgeInsets.all(theme.spacing.xs),
                  builder: (context, isHovering, disabled) {
                    return FlowySvg(
                      FlowySvgs.toast_close_s,
                      size: const Size.square(20),
                    );
                  },
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                style: TextStyle(
                  fontSize: 16,
                  color: materialTheme.textTheme.bodyLarge?.color,
                ),
                decoration: InputDecoration(
                  hintText: '输入日程说明...',
                  hintStyle: TextStyle(
                    color: materialTheme.hintColor,
                  ),
                  filled: true,
                  fillColor: materialTheme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: materialTheme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            AFModalFooter(
              trailing: [
                AFOutlinedTextButton.normal(
                  text: '取消',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
                const SizedBox(width: 8),
                AFFilledTextButton.primary(
                  text: '确定',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      _description = controller.text;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 时间选择对话框
class _TimePickerDialog extends StatefulWidget {
  final TimeOfDay initialStartTime;
  final TimeOfDay initialEndTime;
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final bool isStartTime;
  final Function(TimeOfDay, TimeOfDay, DateTime, DateTime) onSave;

  const _TimePickerDialog({
    required this.initialStartTime,
    required this.initialEndTime,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.isStartTime,
    required this.onSave,
  });

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late bool _isStartTime;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _isStartTime = widget.isStartTime;
    _startTime = widget.initialStartTime;
    _endTime = widget.initialEndTime;
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isStartTime = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _isStartTime ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  '开始',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isStartTime ? Theme.of(context).colorScheme.primary : null,
                    fontWeight: _isStartTime ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isStartTime = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: !_isStartTime ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  '结束',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: !_isStartTime ? Theme.of(context).colorScheme.primary : null,
                    fontWeight: !_isStartTime ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 日期选择
          ListTile(
            title: const Text('日期'),
            trailing: Text(
              '${(_isStartTime ? _startDate : _endDate).month}/${(_isStartTime ? _startDate : _endDate).day}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _isStartTime ? _startDate : _endDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                setState(() {
                  if (_isStartTime) {
                    _startDate = date;
                  } else {
                    _endDate = date;
                  }
                });
              }
            },
          ),
          // 时间选择
          ListTile(
            title: const Text('时间'),
            trailing: Text(
              '${(_isStartTime ? _startTime : _endTime).hour.toString().padLeft(2, '0')}:${(_isStartTime ? _startTime : _endTime).minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: _isStartTime ? _startTime : _endTime,
              );
              if (time != null) {
                setState(() {
                  if (_isStartTime) {
                    _startTime = time;
                  } else {
                    _endTime = time;
                  }
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_startTime, _endTime, _startDate, _endDate);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// 日期选择器对话框
class _DatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final void Function(DateTime date) onSave;

  const _DatePickerDialog({
    required this.initialDate,
    required this.onSave,
  });

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: const Text('选择日期'),
      content: SizedBox(
        width: 300,
        height: 300,
        child: CalendarDatePicker(
          initialDate: _date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          onDateChanged: (date) {
            setState(() => _date = date);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_date);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
