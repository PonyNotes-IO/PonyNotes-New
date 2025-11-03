import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/repeat_selector.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import '../models/schedule_model.dart';
import 'new_event_page.dart'; // 重用一些组件

class EditEventPage extends StatefulWidget {
  final ScheduleItem schedule; // 要编辑的日程
  final Function(Map<String, dynamic>) onEventUpdated;
  final Function(String) onEventDeleted; // 删除回调
  final VoidCallback onCancel;
  final Function(bool Function())? onSaveRequested;
  final ScheduleModel scheduleModel; // 外层传入的 ScheduleModel

  const EditEventPage({
    Key? key,
    required this.schedule,
    required this.onEventUpdated,
    required this.onEventDeleted,
    required this.onCancel,
    required this.scheduleModel,
    this.onSaveRequested,
  }) : super(key: key);

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isAllDay;
  late bool _isImportant;
  late bool _isRepeat;
  String _repeatLabel = '任务重复';
  int _repeatType = 0; // 0=无 1=每天 2=每周 3=每年 4=法定工作日 99=自定义
  String? _repeatCustomSummary;
  late String _calendar;
  late String _description;
  ReminderOption _reminderOption = ReminderOption.none;
  
  // 使用外层传入的 ScheduleModel（不在本页创建/销毁）

  @override
  void initState() {
    super.initState();
    
    // 从传入的日程初始化数据
    _initializeFromSchedule();
    
    // 初始化日历视图
    _initializeCalendarView();
    
    // 设置保存回调
    if (widget.onSaveRequested != null) {
      widget.onSaveRequested!(saveEvent);
    }
  }

  // 从传入的日程初始化表单数据
  void _initializeFromSchedule() {
    final schedule = widget.schedule;
    
    _startDate = schedule.startTime;
    _endDate = schedule.endTime;
    _startTime = TimeOfDay.fromDateTime(schedule.startTime);
    _endTime = TimeOfDay.fromDateTime(schedule.endTime);
    _isAllDay = schedule.isAllDay;
    _isImportant = schedule.isImportant;
    _isRepeat = false; // 暂时不支持重复
    _calendar = schedule.category;
    _description = schedule.title; // 使用title作为description
    _reminderOption = schedule.reminderOption;
  }

  // 初始化日历视图
  Future<void> _initializeCalendarView() async {
    try {
      final success = await widget.scheduleModel.initializeCalendarView();
      if (success) {
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ 数据库连接失败，日程将无法保存'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ 初始化失败: ${e.toString()}'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool saveEvent() {
    // 验证输入
    if (_description.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请添加日程描述'),
          backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? Colors.grey[800] 
            : Colors.grey[900],
        ),
      );
      return false;
    }

    // 构建开始和结束时间进行验证
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
    
    // 检查时间是否在1970年之后
    if (startDateTime.year < 1970 || endDateTime.year < 1970) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 时间设置无效，请选择有效的时间'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }

    // 检查结束时间是否在开始时间之后
    if (!_isAllDay && (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 结束时间必须在开始时间之后'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }

    // 检查日程时长是否合理（不能超过30天）
    final duration = endDateTime.difference(startDateTime);
    if (duration.inDays > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 日程时长超过30天，请确认时间设置'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      // 不阻止保存，但给出警告
    }

    // 异步保存日程
    _saveEventAsync();
    return true;
  }

  Future<void> _saveEventAsync() async {
    
    try {
      // 构建开始和结束时间
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

      // 检查widget是否仍然挂载
      if (!mounted) {
        return;
      }

      // 检查ScheduleModel的状态
      
      if (widget.scheduleModel.currentViewId == null) {
        
        // 尝试初始化日历视图
        final initialized = await widget.scheduleModel.initializeCalendarView();
        if (!initialized) {
          throw Exception('无法初始化日历视图，请检查 AppFlowy 数据库连接');
        }
      }

      // 使用ScheduleModel更新日程
      
      // 创建更新后的ScheduleItem
      // 重要：显式保留原来的 reminderId，确保更新提醒时能找到原有的提醒ID
      final updatedSchedule = widget.schedule.copyWith(
        title: _description.isNotEmpty ? _description : '无标题日程',
        description: _description,
        startTime: startDateTime,
        endTime: endDateTime,
        isAllDay: _isAllDay,
        isImportant: _isImportant,
        reminderOption: _reminderOption, // 直接使用 ReminderOption
        // 显式保留原来的 reminderId，确保更新提醒时能找到原有的提醒ID
        reminderId: widget.schedule.reminderId,
      );
      
      final success = await widget.scheduleModel.updateSchedule(updatedSchedule);

      // 再次检查widget是否仍然挂载
      if (!mounted) {
        return;
      }

      // 更新成功
      if (success) {
        
        // 创建更新后的事件数据
        final eventData = {
          'id': widget.schedule.id,
          'date': _startDate,
          'startTime': _startTime,
          'endTime': _endTime,
          'startDate': _startDate,
          'endDate': _endDate,
          'isAllDay': _isAllDay,
          'isImportant': _isImportant,
          'isRepeat': _isRepeat,
          'calendar': _calendar,
          'description': _description,
        };

        widget.onEventUpdated(eventData);
        
        // 显示成功消息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 日程更新成功！'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('更新日程失败');
      }
    } catch (e, stackTrace) {
      // 异常处理
      
      if (mounted) {
        String errorMessage = '更新日程失败';
        String detailedError = e.toString();
        
        // 根据不同类型的错误提供不同的提示
        if (e.toString().contains('数据库未连接')) {
          errorMessage = '数据库连接失败';
          detailedError = '请确保 AppFlowy 数据库正在运行';
        } else if (e.toString().contains('初始化')) {
          errorMessage = '日历视图初始化失败';
          detailedError = '请检查数据库连接和权限设置';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMessage'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // 删除日程
  Future<void> _deleteEvent() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('确认删除'),
          ],
        ),
        content: Text('确定要删除这个日程吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      
      if (widget.scheduleModel.currentViewId == null) {
        final initialized = await widget.scheduleModel.initializeCalendarView();
        if (!initialized) {
          throw Exception('无法初始化日历视图，请检查 AppFlowy 数据库连接');
        }
      }

      final success = await widget.scheduleModel.deleteSchedule(widget.schedule.id);
      
      if (!mounted) return;

      if (success) {
        widget.onEventDeleted(widget.schedule.id);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 日程已删除'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // 使用 SchedulerBinding 确保在下一帧执行导航
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      } else {
        throw Exception('删除日程失败');
      }
    } catch (e) {
      
      if (mounted) {
        // 只要异常信息中明确说明已经没有元素，也判定为成功
        if (e.toString().contains('Bad state: No element') || 
            e.toString().contains('本地列表中未找到要删除的日程') || 
            e.toString().contains('Not found')) {
          widget.onEventDeleted(widget.schedule.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 日程已删除'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          // 使用 SchedulerBinding 确保在下一帧执行导航
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 日程删除失败'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  String _formatTime(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('H:mm').format(dt);
  }

  String _formatDate(DateTime date) {
    final today = DateTime.now();
    if (date.year == today.year && date.month == today.month && date.day == today.day) {
      return '今天 周${_getWeekday(date.weekday)}';
    }
    return '${date.month}月${date.day}日 周${_getWeekday(date.weekday)}';
  }

  String _getWeekday(int weekday) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return weekdays[weekday - 1];
  }

  // 构建全天日期选择器
  Widget _buildAllDayDatePicker(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () => _showDatePicker(),
      child: Row(
        children: [
          Expanded(child: Container()),
          Column(
            children: [
              Text(
                _formatAllDayDate(_startDate),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: theme.textTheme.headlineLarge?.color ?? (isDark ? Colors.white : Colors.black87),
                ),
              ),
              Text(
                '全天',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6) ?? (isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ),
            ],
          ),
          Expanded(child: Container()),
        ],
      ),
    );
  }

  // 构建时间区间选择器
  Widget _buildTimeRangePicker(ThemeData theme, bool isDark) {
    return Row(
      children: [
        // 开始时间
        Expanded(
          child: GestureDetector(
            onTap: () => _showCustomTimePicker(isStartTime: true),
            child: Column(
              children: [
                Text(
                  _formatTime(_startTime),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    color: theme.textTheme.headlineLarge?.color ?? (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                Text(
                  _formatDate(_startDate),
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6) ?? (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // 箭头
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Icon(
            Icons.arrow_forward,
            color: theme.iconTheme.color?.withOpacity(0.4) ?? (isDark ? Colors.grey[600] : Colors.grey[400]),
            size: 24,
          ),
        ),
        
        // 结束时间
        Expanded(
          child: GestureDetector(
            onTap: () => _showCustomTimePicker(isStartTime: false),
            child: Column(
              children: [
                Text(
                  _formatTime(_endTime),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    color: theme.textTheme.headlineLarge?.color ?? (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                Text(
                  _formatDate(_endDate),
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6) ?? (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 格式化全天日期显示
  String _formatAllDayDate(DateTime date) {
    final today = DateTime.now();
    if (date.year == today.year && date.month == today.month && date.day == today.day) {
      return '今天';
    }
    return '${date.month}月${date.day}日';
  }

  // 显示日期选择器
  Future<void> _showDatePicker() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: CustomTimePickerBottomSheet(
          initialDate: _startDate,
          initialTime: _startTime,
          title: '选择日期',
          showTimePicker: false,
        ),
      ),
    );

    if (result != null) {
      final selectedDate = result['date'] as DateTime;
      setState(() {
        _startDate = selectedDate;
        _endDate = selectedDate;
      });
    }
  }

  // 显示自定义时间选择器
  Future<void> _showCustomTimePicker({required bool isStartTime}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
          child: CustomTimePickerBottomSheet(
          initialDate: isStartTime ? _startDate : _endDate,
          initialTime: isStartTime ? _startTime : _endTime,
          title: isStartTime ? '开始时间' : '结束时间',
          showTimePicker: !_isAllDay,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (isStartTime) {
          _startDate = result['date'];
          _startTime = result['time'];
          // 确保结束时间在开始时间之后
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
          
          if (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime)) {
            _endDate = _startDate;
            _endTime = TimeOfDay(
              hour: (_startTime.hour + 1) % 24,
              minute: _startTime.minute,
            );
          }
        } else {
          _endDate = result['date'];
          _endTime = result['time'];
          // 确保开始时间在结束时间之前
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
          
          if (startDateTime.isAfter(endDateTime) || startDateTime.isAtSameMomentAs(endDateTime)) {
            _startDate = _endDate;
            _startTime = TimeOfDay(
              hour: (_endTime.hour - 1 + 24) % 24,
              minute: _endTime.minute,
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部时间选择区域
            Container(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(height: 20),
                  // 时间选择器
                  _isAllDay ? _buildAllDayDatePicker(theme, isDark) : _buildTimeRangePicker(theme, isDark),
                  SizedBox(height: 40),
                ],
              ),
            ),
            
            // 选项列表
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // 全天选项
                  ListTile(
                    leading: FlowySvg(
                      FlowySvgs.icon_time_calendar_lg,
                      color: theme.iconTheme.color,
                      size: const Size.square(24),
                    ),
                    title: Text(
                      '全天',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    trailing: Toggle(
                      value: _isAllDay,
                      onChanged: (value) {
                        setState(() {
                          _isAllDay = value;
                          if (_isAllDay) {
                            _endDate = _startDate;
                            _startTime = const TimeOfDay(hour: 0, minute: 0);
                            _endTime = const TimeOfDay(hour: 23, minute: 59);
                          }
                        });
                      },
                      style: const ToggleStyle.mobile(),
                      padding: EdgeInsets.zero,
                    ),
                    onTap: () {
                      setState(() {
                        _isAllDay = !_isAllDay;
                      });
                    },
                    horizontalTitleGap: 8.0,
                    minLeadingWidth: 0,
                  ),
                  
                  // 提醒选项
                  ListTile(
                    leading: FlowySvg(
                      FlowySvgs.icon_alarm_clock_m,
                      color: theme.iconTheme.color,
                      size: const Size.square(24),
                    ),
                    title: Text(
                      _getReminderOptionLabel(_reminderOption, !_isAllDay),
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    onTap: () {
                      _showReminderDialog();
                    },
                    horizontalTitleGap: 8.0,
                    minLeadingWidth: 0,
                  ),
                  
                  // 日程重复选项
                  ListTile(
                    leading: FlowySvg(
                      FlowySvgs.icon_repeat_calender_m,
                      color: theme.iconTheme.color,
                      size: const Size.square(24),
                    ),
                    title: Text(
                      _repeatType == 0
                          ? '任务重复'
                          : (_repeatType == 99
                              ? (_repeatCustomSummary ?? '自定义')
                              : _repeatLabel),
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    onTap: () {
                      _showRepeatDialog();
                    },
                    horizontalTitleGap: 8.0,
                    minLeadingWidth: 0,
                  ),
                  
                  // 我的日历选项
                  ListTile(
                    leading: FlowySvg(
                      FlowySvgs.icon_calendar_m,
                      color: theme.iconTheme.color,
                      size: const Size.square(24),
                    ),
                    title: Text(
                      '我的日历',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    onTap: () {
                      // 显示日历选择器
                    },
                    horizontalTitleGap: 8.0,
                    minLeadingWidth: 0,
                  ),
                  
                  // 添加说明选项
                  ListTile(
                    leading: FlowySvg(
                      FlowySvgs.icon_edit_m,
                      color: theme.iconTheme.color,
                      size: const Size.square(24),
                    ),
                    title: Text(
                      '添加说明',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    onTap: () {
                      _showDescriptionDialog();
                    },
                    horizontalTitleGap: 8.0,
                    minLeadingWidth: 0,
                  ),

                  // 分隔线
                  Divider(height: 40),

                  // 删除按钮
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 24,
                    ),
                    title: Text(
                      '删除日程',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.red,
                      ),
                    ),
                    onTap: _deleteEvent,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
          width: 400,
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
                      '编辑说明',
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
                  fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  hoverColor: Colors.transparent, // 禁用悬停时的背景颜色变化
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withOpacity(0.5),
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
                  // 取消按钮
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 确定按钮
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      '确定',
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


  // 获取提醒选项的显示标签（与 reminder_selector.dart 逻辑一致）
  String _getReminderOptionLabel(ReminderOption option, bool hasTime) {
    String label = option.label;
    // 对于 withoutTime 的选项，显示时间信息（与 reminder_selector.dart 逻辑一致）
    if (option.withoutTime && !option.timeExempt) {
      const time = "09:00";
      final t = TimeFormatPB.TwentyFourHour == TimeFormatPB.TwelveHour 
          ? "$time AM" 
          : time;
      label = "$label ($t)";
    }
    return label;
  }

  void _showReminderDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ReminderSelectionDialog(
          currentOption: _reminderOption,
          hasTime: !_isAllDay, // 如果不是全天，则包含时间
          timeFormat: TimeFormatPB.TwentyFourHour, // 默认使用24小时制
          onSave: (selectedOption) {
            setState(() {
              _reminderOption = selectedOption;
            });
          },
        );
      },
    );
  }

  void _showRepeatDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RepeatSelectionDialog(
        currentType: _repeatType,
        currentCustomSummary: _repeatCustomSummary,
        onSave: ({required int type, String? customSummary}) {
          setState(() {
            if (type == 0) {
              _isRepeat = false;
              _repeatType = 0;
              _repeatLabel = '任务重复';
              _repeatCustomSummary = null;
            } else if (type == 99) {
              _isRepeat = true;
              _repeatType = 99;
              _repeatCustomSummary = customSummary;
              _repeatLabel = customSummary ?? '自定义';
            } else {
              _isRepeat = true;
              _repeatType = type;
              _repeatCustomSummary = null;
              _repeatLabel = _repeatTypeName(type);
            }
          });
        },
      ),
    );
  }

  String _repeatTypeName(int t) {
    switch (t) {
      case 1:
        return '每天';
      case 2:
        return '每周';
      case 3:
        return '每年';
      case 4:
        return '法定工作日';
      default:
        return '任务重复';
    }
  }
}

// 提醒选择对话框（与 reminder_selector.dart 逻辑一致）
class ReminderSelectionDialog extends StatefulWidget {
  final ReminderOption currentOption;
  final bool hasTime;
  final TimeFormatPB timeFormat;
  final Function(ReminderOption) onSave;

  const ReminderSelectionDialog({
    Key? key,
    required this.currentOption,
    required this.hasTime,
    required this.timeFormat,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ReminderSelectionDialog> createState() => _ReminderSelectionDialogState();
}

class _ReminderSelectionDialogState extends State<ReminderSelectionDialog> {
  late ReminderOption _tempSelectedOption;

  @override
  void initState() {
    super.initState();
    _tempSelectedOption = widget.currentOption;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 获取可用选项（与 reminder_selector.dart 逻辑一致）
    final options = ReminderOption.values.toList();
    
    // 如果当前选项不是 custom，则移除 custom 选项
    if (widget.currentOption != ReminderOption.custom) {
      options.remove(ReminderOption.custom);
    }
    
    // 根据 hasTime 过滤选项（与 reminder_selector.dart 逻辑一致）
    options.removeWhere(
      (o) => !o.timeExempt && (!widget.hasTime ? !o.withoutTime : o.requiresNoTime),
    );
    
    // 构建选项列表
    final optionWidgets = options.map((o) {
      String label = o.label;
      // 对于 withoutTime 的选项，显示时间信息（与 reminder_selector.dart 逻辑一致）
      if (o.withoutTime && !o.timeExempt) {
        const time = "09:00";
        final t = widget.timeFormat == TimeFormatPB.TwelveHour ? "$time AM" : time;
        label = "$label ($t)";
      }
      
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _tempSelectedOption = o;
              });
            },
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Radio<ReminderOption>(
                    value: o,
                    groupValue: _tempSelectedOption,
                    onChanged: (value) {
                      setState(() {
                        _tempSelectedOption = value!;
                      });
                    },
                    activeColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  if (o == _tempSelectedOption)
                    Icon(
                      Icons.check,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 510,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            // 限制对话框最大高度，超过则滚动
            maxHeight: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close,
                    size: 24,
                    color: theme.iconTheme.color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '提醒时间',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // 保存按钮
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_tempSelectedOption);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
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

            // 选项列表（可滚动，避免超出边界）
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: optionWidgets,
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
          ),
        ),
      ),
    );
  }
} 