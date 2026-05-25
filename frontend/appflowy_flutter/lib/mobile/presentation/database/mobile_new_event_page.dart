import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/mobile_reminder_page.dart';
import 'package:appflowy/mobile/presentation/database/mobile_repeat_page.dart';
import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmText;
  final String cancelText;

  const MobileConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    required this.cancelText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(
                fontSize: 15,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    cancelText,
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    confirmText,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MobileNewEventPage extends StatefulWidget {
  final DateTime selectedDate;
  final ScheduleModel scheduleModel;
  final VoidCallback? onEventCreated;

  const MobileNewEventPage({
    super.key,
    required this.selectedDate,
    required this.scheduleModel,
    this.onEventCreated,
  });

  @override
  State<MobileNewEventPage> createState() => _MobileNewEventPageState();
}

class _MobileNewEventPageState extends State<MobileNewEventPage> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isAllDay = false;
  String _description = '';
  ReminderOption _reminderOption = ReminderOption.none;
  int _repeatType = 0;
  String _repeatLabel = '任务重复';
  String? _repeatCustomSummary;

  // 初始状态快照，用于检测未保存更改
  TimeOfDay _initialStartTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _initialEndTime = const TimeOfDay(hour: 0, minute: 0);
  DateTime _initialStartDate = DateTime.now();
  DateTime _initialEndDate = DateTime.now();
  bool _initialIsAllDay = false;
  String _initialDescription = '';
  ReminderOption _initialReminderOption = ReminderOption.none;
  int _initialRepeatType = 0;
  String? _initialRepeatCustomSummary;

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    _endTime = TimeOfDay(hour: _startTime.hour + 1, minute: _startTime.minute);
    _startDate = widget.selectedDate;
    _endDate = widget.selectedDate;
    _captureInitialSnapshot();
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
      final theme = AppFlowyTheme.of(context);
      await showDialog(
        context: context,
        barrierColor: theme.surfaceColorScheme.overlay,
        builder: (ctx) {
          return AFModal(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AFModalHeader(
                  leading: const Text(
                    '确认退出',
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
                AFModalBody(
                  child: Text(
                    '还有未保存的设置，确定要退出吗？',
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.primary,
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
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
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
      final resultId = await widget.scheduleModel.createSchedule(
        title: _description,
        description: _description,
        startTime: startDateTime,
        endTime: endDateTime,
        isAllDay: _isAllDay,
        isImportant: false,
        category: '我的日历',
        reminderOption: _reminderOption,
        dueDate: endDateTime,
        repeatType: _repeatType,
        repeatRuleJson: _repeatCustomSummary,
      );

      if (resultId != null && mounted) {
        showToastNotification(
          message: '日程已创建',
          type: ToastificationType.success,
        );
        widget.onEventCreated?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: '创建日程失败',
          type: ToastificationType.error,
        );
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
          '新建日程',
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
                                _startTime = TimeOfDay.now();
                                _endTime = TimeOfDay(hour: _startTime.hour + 1, minute: _startTime.minute);
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
                    _formatAllDayDate(_startDate),
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
              color: isDark ? Colors.grey[600]!.withValues(alpha: 0.4) : Colors.grey[400]!.withValues(alpha: 0.4),
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
              color: theme.iconTheme.color,
              size: const Size.square(24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: title == '添加说明' && _description.isNotEmpty
                      ? theme.textTheme.bodyLarge?.color
                      : theme.textTheme.bodyLarge?.color,
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
        _repeatLabel = _getRepeatLabel();
      });
    }
  }

  void _showDescriptionDialog() {
    final controller = TextEditingController(text: _description);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '添加说明',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.titleLarge?.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 输入框
              TextField(
                controller: controller,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyMedium?.color,
                ),
                decoration: InputDecoration(
                  hintText: '请输入日程说明...',
                  hintStyle: TextStyle(
                    color: theme.hintColor,
                    fontSize: 16,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 24),
              // 按钮栏
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _description = controller.text;
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      '保存',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 时间选择器对话框
class _TimePickerDialog extends StatefulWidget {
  final TimeOfDay initialStartTime;
  final TimeOfDay initialEndTime;
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final bool isStartTime;
  final void Function(TimeOfDay start, TimeOfDay end, DateTime startDate, DateTime endDate) onSave;

  const _TimePickerDialog({
    required this.initialStartTime,
    required this.initialEndTime,
    required this.initialStartDate,
    required this.initialEndDate,
    this.isStartTime = true,
    required this.onSave,
  });

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isStartTime;

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialStartTime;
    _endTime = widget.initialEndTime;
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
    _isStartTime = widget.isStartTime;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isStartTime ? '开始时间' : '结束时间'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 日期选择
          ListTile(
            title: const Text('日期'),
            trailing: Text(
              '${_isStartTime ? _startDate.month : _endDate.month}月${_isStartTime ? _startDate.day : _endDate.day}日',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _isStartTime ? _startDate : _endDate,
                firstDate: DateTime(2000),
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

// 重复选择对话框
class _RepeatDialog extends StatefulWidget {
  final int initialType;
  final String? initialCustomSummary;
  final void Function(int type, String? customSummary) onSave;

  const _RepeatDialog({
    required this.initialType,
    this.initialCustomSummary,
    required this.onSave,
  });

  @override
  State<_RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<_RepeatDialog> {
  late int _type;
  String? _customSummary;

  final _repeatOptions = [
    const MapEntry(0, '无'),
    const MapEntry(1, '每天'),
    const MapEntry(2, '每周'),
    const MapEntry(3, '每年'),
    const MapEntry(4, '法定工作日'),
  ];

  String _getCustomSummaryLabel() {
    if (_customSummary == null || _customSummary!.isEmpty) return '';
    try {
      return _customSummary!;
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _customSummary = widget.initialCustomSummary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(
                  Icons.repeat,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '任务重复',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_type, _customSummary);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 选项列表
            ..._repeatOptions.map((entry) {
              final isSelected = _type == entry.key;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _type = entry.key);
                    },
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Radio<int>(
                            value: entry.key,
                            groupValue: _type,
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _type = value);
                              }
                            },
                            activeColor: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 16,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
