import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import '../models/schedule_model.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/repeat_selector.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'widgets/reminder_selection_dialog.dart';

class NewEventPage extends StatefulWidget {
  final DateTime selectedDate;
  final Function(Map<String, dynamic>) onEventCreated;
  final VoidCallback onCancel;
  final Function(bool Function())? onSaveRequested;
  final ScheduleModel scheduleModel; // 外层传入的 ScheduleModel
  /// 当日程有变更时回调（用于离开前弹窗提示）
  final void Function(bool hasUnsaved)? onHasUnsavedConfigChanged;

  const NewEventPage({
    Key? key,
    required this.scheduleModel,
    required this.selectedDate,
    required this.onEventCreated,
    required this.onCancel,
    this.onSaveRequested,
    this.onHasUnsavedConfigChanged,
  }) : super(key: key);

  @override
  State<NewEventPage> createState() => _NewEventPageState();
}

class _NewEventPageState extends State<NewEventPage> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isAllDay = false;
  bool _isImportant = false;
  String _repeatLabel = '任务重复'; // 无时显示“任务重复”
  int _repeatType = 0; // 0=无 1=每天 2=每周 3=每年 4=法定工作日 99=自定义
  String? _repeatCustomSummary; // 自定义选项摘要，如“每1周的周二”
  String _calendar = '我的日历';
  String _description = '';
  ReminderOption _reminderOption = ReminderOption.none;
  // 使用ScheduleModel来管理日程
  late ScheduleModel _scheduleModel;

  /// 与打开新建页时的初始值对比，用于显示/隐藏顶部取消·保存
  late String _initialDescription;
  late int _initialRepeatType;
  late String? _initialRepeatCustomSummary;
  late ReminderOption _initialReminderOption;
  late DateTime _initialStartDate;
  late DateTime _initialEndDate;
  late TimeOfDay _initialStartTime;
  late TimeOfDay _initialEndTime;
  late bool _initialIsAllDay;
  late bool _initialIsImportant;

  @override
  void initState() {
    super.initState();
    _scheduleModel = widget.scheduleModel;
    // 初始化日历视图
    _initializeCalendarView();
    
    _startTime = TimeOfDay.now();
    _endTime = TimeOfDay(hour: _startTime.hour + 1, minute: _startTime.minute);
    _startDate = widget.selectedDate;
    _endDate = widget.selectedDate;
    _captureInitialSnapshot();
    
    // 设置保存回调
    if (widget.onSaveRequested != null) {
      widget.onSaveRequested!(saveEvent);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyUnsavedConfig());
  }

  void _captureInitialSnapshot() {
    _initialDescription = _description;
    _initialRepeatType = _repeatType;
    _initialRepeatCustomSummary = _repeatCustomSummary;
    _initialReminderOption = _reminderOption;
    _initialStartDate = DateTime(_startDate.year, _startDate.month, _startDate.day);
    _initialEndDate = DateTime(_endDate.year, _endDate.month, _endDate.day);
    _initialStartTime = _startTime;
    _initialEndTime = _endTime;
    _initialIsAllDay = _isAllDay;
    _initialIsImportant = _isImportant;
  }

  bool _hasUnsavedConfigChanges() {
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
        _isAllDay != _initialIsAllDay ||
        _isImportant != _initialIsImportant;
  }

  void _notifyUnsavedConfig() {
    if (!mounted) return;
    widget.onHasUnsavedConfigChanged?.call(_hasUnsavedConfigChanges());
  }

  // 初始化日历视图
  Future<void> _initializeCalendarView() async {
    try {
      final success = await _scheduleModel.initializeCalendarView();
      if (success) {
      } else {
        // 在界面上显示警告，但不阻止用户继续操作
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
    // 注意：_scheduleModel 是从外部传入的共享实例，不应该在这里 dispose
    // ScheduleModel 的生命周期应该由创建它的地方（calendar.dart）管理
    super.dispose();
  }

  bool saveEvent() {
    // 验证输入
    if (_description.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请添加日程描述'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
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

    // 验证时间合法性
    final now = DateTime.now();
    
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

    // 移除过去时间检查 - 允许用户自由设置任何时间

    // 检查结束时间不能小于开始时间
    if (endDateTime.isBefore(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('结束时间不能小于开始时间'),
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
    String? resultId; // 新增
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
      if (!mounted) return;
      if (_scheduleModel.currentViewId == null) {
        // 尝试初始化日历视图
        final initialized = await _scheduleModel.initializeCalendarView();
        if (!initialized) {
          throw Exception('无法初始化日历视图，请检查 AppFlowy 数据库连接');
        }
      }
      // 使用ScheduleModel创建日程
      resultId = await _scheduleModel.createSchedule(
        title: _description.isNotEmpty ? _description : '无标题日程',
        description: _description,
        startTime: startDateTime,
        endTime: endDateTime,
        isAllDay: _isAllDay,
        isImportant: _isImportant,
        category: _calendar,
        reminderOption: _reminderOption,
        dueDate: endDateTime,
        repeatType: _repeatType,
        repeatRuleJson: _repeatCustomSummary,
      );
      if (!mounted) return;
      // 创建成功
      if (resultId != null) {
        final eventData = {
          'id': resultId,
          'date': _startDate,
          'startTime': _startTime,
          'endTime': _endTime,
          'startDate': _startDate,
          'endDate': _endDate,
          'isAllDay': _isAllDay,
          'isImportant': _isImportant,
          'calendar': _calendar,
          'description': _description,
          'repeatType':_repeatType,
          'repeatRuleJson': _repeatCustomSummary,
        };
        widget.onEventCreated(eventData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 日程创建成功！'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      } else {
        throw Exception('创建日程失败：未返回有效ID');
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      // 只要 resultId 有值，实际后台一定已创建成功，这里不再弹出红色失败提示
      if (resultId != null) {
        print('⚠️ 日程实际已创建（ID=$resultId），后续异常如下: $e');
        return;
      }
      String errorMessage = '创建日程失败';
      String detailedError = e.toString();
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
          action: SnackBarAction(
            label: '详情',
            textColor: Colors.white,
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      Text('错误详情'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          detailedError,
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '故障排除建议:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. 检查 AppFlowy 应用是否正在运行\n'
                          '2. 确认数据库服务状态正常\n'
                          '3. 检查网络连接\n'
                          '4. 重启应用程序\n'
                          '5. 查看控制台日志了解详细信息',
                          style: TextStyle(fontSize: 12),
                        ),
                        if (detailedError.length > 100) ...[
                          SizedBox(height: 16),
                          Text(
                            '完整错误信息:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              e.toString(),
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('关闭'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // 可以在这里添加重试逻辑
                        _saveEventAsync();
                      },
                      child: Text('重试'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
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
          // 左侧占位，保持与时间区间选择器布局一致
          Expanded(
            child: Container(), // 空容器保持对称
          ),
          
          // 中间显示内容，居中展示
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
          
          // 右侧占位，保持布局对称
          Expanded(
            child: Container(), // 空容器保持对称
          ),
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

  // 显示日期选择器（使用自定义时间选择器，但只显示日历部分）
  Future<void> _showDatePicker() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false, // 阻止点击外部区域关闭弹窗
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: CustomTimePickerBottomSheet(
          initialDate: _startDate,
          initialTime: _startTime,
          title: '选择日期',
          showTimePicker: false, // 只显示日历，不显示时间选择器
        ),
      ),
    );

    if (result != null) {
      final selectedDate = result['date'] as DateTime;
      setState(() {
        _startDate = selectedDate;
        _endDate = selectedDate; // 全天模式下结束日期等于开始日期
      });
      _notifyUnsavedConfig();
    }
  }

  // 显示自定义时间选择器
  Future<void> _showCustomTimePicker({
    required bool isStartTime,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false, // 阻止点击外部区域关闭弹窗
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: CustomTimePickerBottomSheet(
          initialDate: isStartTime ? _startDate : _endDate,
          initialTime: isStartTime ? _startTime : _endTime,
          title: isStartTime ? '开始时间' : '结束时间',
          showTimePicker: !_isAllDay, // 根据是否勾选全天决定是否显示时间选择器
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
        }
      });
      _notifyUnsavedConfig();
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
                            // 切换到全天模式时，设置结束日期等于开始日期
                            _endDate = _startDate;
                            // 设置默认时间为全天
                            _startTime = const TimeOfDay(hour: 0, minute: 0);
                            _endTime = const TimeOfDay(hour: 23, minute: 59);
                          }
                        });
                        _notifyUnsavedConfig();
                      },
                      style: const ToggleStyle.mobile(),
                      activeBackgroundColor: Theme.of(context).colorScheme.primary,
                      padding: EdgeInsets.zero,
                    ),
                    onTap: () {
                      setState(() {
                        _isAllDay = !_isAllDay;
                      });
                      _notifyUnsavedConfig();
                    },
                    horizontalTitleGap: 8.0, // 默认值通常是16.0
                    minLeadingWidth: 0, // 关键：设置为0
                  ),
                  
                  // 准时选项
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
                    horizontalTitleGap: 8.0, // 默认值通常是16.0
                    minLeadingWidth: 0, // 关键：设置为0
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
                          : _repeatLabel,
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  onTap: () {
                    _showRepeatDialog();
                    },
                    horizontalTitleGap: 8.0, // 默认值通常是16.0
                    minLeadingWidth: 0, // 关键：设置为0
                  ),
                 // 我的日历选项
                 // ListTile(
                 //   leading: FlowySvg(
                 //     FlowySvgs.icon_calendar_m,
                 //     color: theme.iconTheme.color,
                 //     size: const Size.square(24),
                 //   ),
                 //   title: Text(
                 //     '我的日历',
                 //     style: TextStyle(
                 //       fontSize: 16,
                 //       color: theme.textTheme.bodyLarge?.color,
                 //     ),
                 //   ),
                 //   onTap: () {
                 //     // 显示日历选择器
                 //   },
                 //   horizontalTitleGap: 8.0, // 默认值通常是16.0
                 //   minLeadingWidth: 0, // 关键：设置为0
                 // ),
                 
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
                   horizontalTitleGap: 8.0, // 默认值通常是16.0
                   minLeadingWidth: 0, // 关键：设置为0
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRepeatDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RepeatSelectionDialog(
        currentType: _repeatType,
        currentCustomSummary: _repeatCustomSummary,
        onSave: ({required int type, String? customSummary}) {
          setState(() {
            if (type == 0) {
              _repeatType = 0;
              _repeatLabel = '任务重复';
              _repeatCustomSummary = null;
            } else if (type == 99) {
              _repeatType = 99;
              _repeatCustomSummary = customSummary;
              // 从 JSON 中提取显示文本
              _repeatLabel = _extractSummaryFromJson(customSummary ?? '自定义');
            } else {
              _repeatType = type;
              _repeatCustomSummary = null;
              _repeatLabel = _repeatTypeName(type);
            }
          });
          _notifyUnsavedConfig();
        },
      ),
    );
  }

  String? _buildCustomSummary(int unit, int interval, Set<int> weekdays) {
    switch (unit) {
      case 0:
        return '每$interval天';
      case 1:
        if (weekdays.isEmpty) return null;
        const names = ['周一','周二','周三','周四','周五','周六','周日'];
        final days = weekdays.toList()..sort();
        final joined = days.map((i) => names[i]).join('、');
        return '每$interval周的$joined';
      case 2:
        return '每$interval月';
      case 3:
        return '每$interval年';
    }
    return null;
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

  // 从 JSON 中提取显示摘要
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
      // 如果没有 summary 字段，尝试从其他字段构建显示文本
      return '自定义';
    } catch (e) {
      // 如果不是有效的 JSON，返回默认值
      return '自定义';
    }
  }

  void _showDescriptionDialog() {
    final controller = TextEditingController(text: _description);
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false, // 防止误触关闭
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), // 更大的圆角
        ),
        child: Container(
          width: 400, // 固定宽度
          padding: const EdgeInsets.all(24), // 增加内边距
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
                maxLines: 4, // 增加行数
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
                autofocus: true, // 自动聚焦
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
                      _notifyUnsavedConfig();
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
      // 使用24小时制（与弹框中的 timeFormat 保持一致）
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
      barrierDismissible: false, // 阻止点击外部区域关闭弹窗
      builder: (BuildContext context) {
        return ReminderSelectionDialog(
          currentOption: _reminderOption,
          hasTime: !_isAllDay, // 如果不是全天，则包含时间
          timeFormat: TimeFormatPB.TwentyFourHour, // 默认使用24小时制
          onSave: (selectedOption) {
            setState(() {
              _reminderOption = selectedOption;
            });
            _notifyUnsavedConfig();
          },
        );
      },
    );
  }
}

// 自定义时间选择器底部弹窗
class CustomTimePickerBottomSheet extends StatefulWidget {
  final DateTime initialDate;
  final TimeOfDay initialTime;
  final String title;
  final bool showTimePicker; // 新增参数控制是否显示时间选择器

  const CustomTimePickerBottomSheet({
    Key? key,
    required this.initialDate,
    required this.initialTime,
    required this.title,
    this.showTimePicker = true, // 默认显示时间选择器
  }) : super(key: key);

  @override
  State<CustomTimePickerBottomSheet> createState() => _CustomTimePickerBottomSheetState();
}

class _CustomTimePickerBottomSheetState extends State<CustomTimePickerBottomSheet> {
  late DateTime selectedDate;
  late int selectedHour;
  late int selectedMinute;
  late DateTime currentMonth;
  
  final FixedExtentScrollController hourController = FixedExtentScrollController();
  final FixedExtentScrollController minuteController = FixedExtentScrollController();

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate;
    selectedHour = widget.initialTime.hour;
    selectedMinute = widget.initialTime.minute;
    currentMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    
    // 设置初始滚动位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hourController.jumpToItem(selectedHour);
      minuteController.jumpToItem(selectedMinute);
    });
  }

  // 允许鼠标滚轮和拖拽的滚动行为，提升桌面端可用性
  // 并开启常用指针设备支持
  static const Set<PointerDeviceKind> _pointerKinds = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
  
  ScrollBehavior get _pickerScrollBehavior => const _CupertinoPickerScrollBehavior();

  @override
  void dispose() {
    hourController.dispose();
    minuteController.dispose();
    super.dispose();
  }

  // 获取月份的天数
  int getDaysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  // 获取月份第一天是星期几（0=周日，1=周一，...，6=周六）
  int getFirstDayOfWeek(DateTime date) {
    return DateTime(date.year, date.month, 1).weekday % 7;
  }

  // 生成日历网格
  Widget buildCalendar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final daysInMonth = getDaysInMonth(currentMonth);
    final firstDayOfWeek = getFirstDayOfWeek(currentMonth);
    final today = DateTime.now();
    
    return Column(
      children: [
        // 月份导航
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    currentMonth = DateTime(currentMonth.year, currentMonth.month - 1, 1);
                  });
                },
                icon: Icon(
                  Icons.chevron_left,
                  color: isDark ? Colors.white : Colors.black87,
                  size: 20,
                ),
              ),
              Text(
                '${currentMonth.year}年${currentMonth.month}月',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
                  });
                },
                icon: Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white : Colors.black87,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        
        // 星期标题
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: ['日', '一', '二', '三', '四', '五', '六'].map((day) {
              return Expanded(
                child: Container(
                  height: 25,
                  alignment: Alignment.center,
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        
        // 日历网格
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 42, // 6周 x 7天
            itemBuilder: (context, index) {
              final dayNumber = index - firstDayOfWeek + 1;
              
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return Container(); // 空白日期
              }
              
              final date = DateTime(currentMonth.year, currentMonth.month, dayNumber);
              final isSelected = date.year == selectedDate.year && 
                                date.month == selectedDate.month && 
                                date.day == selectedDate.day;
              final isToday = date.year == today.year && 
                             date.month == today.month && 
                             date.day == today.day;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedDate = date;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected 
                      ? const Color(0xFFFF6B35)
                      : isToday
                        ? (isDark ? Colors.grey[700] : Colors.grey[200])
                        : Colors.transparent,
                    border: isToday && !isSelected
                      ? Border.all(
                          color: isDark ? Colors.grey[600]! : Colors.grey[400]!,
                          width: 1,
                        )
                      : null,
                  ),
                  child: Center(
                    child: Text(
                      dayNumber.toString(),
                      style: TextStyle(
                        fontSize: 16,
                        color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                        fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      height: widget.showTimePicker ? 700 : 500, // 根据是否显示时间选择器调整高度
      width: 400,  // 增加宽度给日历更多空间
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 头部
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  width: 0.5,
                ),
              ),
            ),
            child: Stack(
              children: [
                // 居中的标题
                Center(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                // 左上角的关闭按钮
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context); // 关闭弹窗，不返回任何数据
                      },
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 20,
                      ),
                      splashColor: Colors.transparent, // 禁用点击波纹效果
                      highlightColor: Colors.transparent, // 禁用高亮效果
                      hoverColor: Colors.transparent, // 禁用悬停效果
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ),
                ),
                
                // 右侧的确认按钮
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context, {
                            'date': selectedDate,
                            'time': TimeOfDay(hour: selectedHour, minute: selectedMinute),
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                        child: const Text(
                          '确认',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 日历和时间选择器
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 日历部分
                  Expanded(
                    flex: widget.showTimePicker ? 4 : 1, // 根据是否显示时间选择器调整比例
                    child: buildCalendar(),
                  ),
                  
                  // 只有在显示时间选择器时才显示时间相关部分
                  if (widget.showTimePicker) ...[
                    const SizedBox(height: 12),
                    
                    // 时间标签
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '时间',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // 时间选择器
                    SizedBox(
                      height: 140,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            // 小时选择器
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    height: 30,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '时',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ScrollConfiguration(
                                      behavior: _pickerScrollBehavior,
                                      child: CupertinoPicker(
                                      scrollController: hourController,
                                      itemExtent: 28,
                                      onSelectedItemChanged: (index) {
                                        setState(() {
                                          selectedHour = index;
                                        });
                                      },
                                      children: List.generate(24, (index) {
                                        return Center(
                                          child: Text(
                                            index.toString().padLeft(2, '0'),
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        );
                                      }),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // 分隔线
                            Container(
                              width: 1,
                              height: 60,
                              color: isDark ? Colors.grey[600] : Colors.grey[300],
                            ),
                            
                            // 分钟选择器
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    height: 30,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '分',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ScrollConfiguration(
                                      behavior: _pickerScrollBehavior,
                                      child: CupertinoPicker(
                                      scrollController: minuteController,
                                      itemExtent: 28,
                                      onSelectedItemChanged: (index) {
                                        setState(() {
                                          selectedMinute = index;
                                        });
                                      },
                                      children: List.generate(60, (index) {
                                        return Center(
                                          child: Text(
                                            index.toString().padLeft(2, '0'),
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                        );
                                      }),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
} 

// 自定义滚动行为：允许鼠标、触控板、触屏等设备拖拽/滚轮滚动 CupertinoPicker
class _CupertinoPickerScrollBehavior extends ScrollBehavior {
  const _CupertinoPickerScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => _CustomTimePickerBottomSheetState._pointerKinds;

  @override
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) {
    return child;
  }
}
