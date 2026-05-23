import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    _endTime = TimeOfDay(hour: _startTime.hour + 1, minute: _startTime.minute);
    _startDate = widget.selectedDate;
    _endDate = widget.selectedDate;
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final today = DateTime.now();
    if (date.year == today.year && date.month == today.month && date.day == today.day) {
      return '今天';
    }
    return '${date.month}月${date.day}日';
  }

  String _getReminderOptionLabel() {
    if (_reminderOption == ReminderOption.none) {
      return '准时提醒';
    }
    return _reminderOption.name;
  }

  String _getRepeatLabel() {
    if (_repeatType == 0) return '任务重复';
    if (_repeatType == 99) return _repeatCustomSummary ?? '自定义';
    switch (_repeatType) {
      case 1:
        return '每天';
      case 2:
        return '每周';
      case 3:
        return '每月';
      case 4:
        return '每年';
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
          onPressed: () => Navigator.of(context).pop(),
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
                          onTap: () => _showRepeatDialog(),
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

    return GestureDetector(
      onTap: () => _showTimePickerDialog(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 开始时间
            _buildTimeButton(
              time: _formatTime(_startTime),
              label: '开始',
              theme: theme,
              isDark: isDark,
            ),
            const SizedBox(width: 20),
            Icon(
              Icons.arrow_forward,
              color: isDark ? Colors.white54 : Colors.black54,
              size: 20,
            ),
            const SizedBox(width: 20),
            // 结束时间
            _buildTimeButton(
              time: _formatTime(_endTime),
              label: '结束',
              theme: theme,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllDayDatePicker(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showDatePickerDialog(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatDate(_startDate),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.keyboard_arrow_down,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeButton({
    required String time,
    required String label,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
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
    return Switch(
      value: value,
      onChanged: onChanged,
    );
  }

  void _showTimePickerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TimePickerDialog(
        initialStartTime: _startTime,
        initialEndTime: _endTime,
        onSave: (startTime, endTime) {
          setState(() {
            _startTime = startTime;
            _endTime = endTime;
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReminderDialog(
        initialOption: _reminderOption,
        onSave: (option) {
          setState(() {
            _reminderOption = option;
          });
        },
      ),
    );
  }

  void _showRepeatDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RepeatDialog(
        initialType: _repeatType,
        initialCustomSummary: _repeatCustomSummary,
        onSave: (type, customSummary) {
          setState(() {
            _repeatType = type;
            _repeatCustomSummary = customSummary;
            _repeatLabel = _getRepeatLabel();
          });
        },
      ),
    );
  }

  void _showDescriptionDialog() {
    final controller = TextEditingController(text: _description);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('添加说明'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入日程说明...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _description = controller.text;
              });
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// 时间选择器对话框
class _TimePickerDialog extends StatefulWidget {
  final TimeOfDay initialStartTime;
  final TimeOfDay initialEndTime;
  final void Function(TimeOfDay start, TimeOfDay end) onSave;

  const _TimePickerDialog({
    required this.initialStartTime,
    required this.initialEndTime,
    required this.onSave,
  });

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialStartTime;
    _endTime = widget.initialEndTime;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择时间'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('开始时间'),
            trailing: Text(
              '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: _startTime,
              );
              if (time != null) {
                setState(() => _startTime = time);
              }
            },
          ),
          ListTile(
            title: const Text('结束时间'),
            trailing: Text(
              '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: _endTime,
              );
              if (time != null) {
                setState(() => _endTime = time);
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
            widget.onSave(_startTime, _endTime);
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

// 提醒选择对话框
class _ReminderDialog extends StatefulWidget {
  final ReminderOption initialOption;
  final void Function(ReminderOption option) onSave;

  const _ReminderDialog({
    required this.initialOption,
    required this.onSave,
  });

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late ReminderOption _option;

  @override
  void initState() {
    super.initState();
    _option = widget.initialOption;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择提醒'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: ReminderOption.values.map((option) {
          return RadioListTile<ReminderOption>(
            title: Text(option == ReminderOption.none ? '无' : option.name),
            value: option,
            groupValue: _option,
            onChanged: (value) {
              if (value != null) {
                setState(() => _option = value);
              }
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_option);
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
    {'type': 0, 'label': '无'},
    {'type': 1, 'label': '每天'},
    {'type': 2, 'label': '每周'},
    {'type': 3, 'label': '每月'},
    {'type': 4, 'label': '每年'},
    {'type': 5, 'label': '工作日'},
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _customSummary = widget.initialCustomSummary;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择重复'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _repeatOptions.map((option) {
          return RadioListTile<int>(
            title: Text(option['label'] as String),
            value: option['type'] as int,
            groupValue: _type,
            onChanged: (value) {
              if (value != null) {
                setState(() => _type = value);
              }
            },
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(_type, _customSummary);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
