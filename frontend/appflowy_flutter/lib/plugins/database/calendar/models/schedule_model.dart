import 'dart:convert';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/calendar_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/cell/cell_data_loader.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:nanoid/nanoid.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:collection/collection.dart';

import '../../application/field/field_info.dart';
import 'package:appflowy_backend/log.dart';

// 日程数据模型 - 基于 AppFlowy 数据库行
class ScheduleItem {
  final String id; // 数据库行ID
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay; // 全天事件，根据 includeTime 和 isRange 自动判断
  final bool isImportant;
  final String category;
  final Color color;
  final String? reminderId; // AppFlowy 提醒ID
  final ReminderOption reminderOption; // 提醒选项
  final DateTime? dueDate; // 截止日期
  final int repeatType; // 0=无 1=每天 2=每周 3=每年 4=法定工作日 99=自定义
  final String? repeatRuleJson; // 自定义重复规则JSON（如"每1周的周一"）

  ScheduleItem({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    this.isImportant = false,
    this.category = '默认',
    this.color = Colors.blue,
    this.reminderId,
    this.reminderOption = ReminderOption.none,
    this.dueDate,
    this.repeatType = 0,
    this.repeatRuleJson,
  });

  // 根据当前时间自动判断是否完成
  bool get isCompleted {
    final now = DateTime.now();
    return now.isAfter(endTime);
  }

  // 根据 includeTime 和 isRange 判断是否为全天事件
  // 全天事件：includeTime == false 且 isRange == false（只有单个日期，不包含时分）
  static bool _isAllDayEvent({
    bool? includeTime,
    bool? isRange,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    // 优先使用 includeTime 和 isRange 判断
    if (includeTime != null && isRange != null) {
      return !includeTime && !isRange;
    }
    
    // 备用判断：根据开始和结束时间判断
    // 如果开始和结束时间在同一天，且都是 00:00，则可能是全天事件
    if (startTime != null && endTime != null) {
      return startTime.year == endTime.year &&
          startTime.month == endTime.month &&
          startTime.day == endTime.day &&
          startTime.hour == 0 &&
          startTime.minute == 0 &&
          endTime.hour == 0 &&
          endTime.minute == 0;
    }
    
    return false;
  }

  // 从CalendarEventPB创建ScheduleItem
  factory ScheduleItem.fromCalendarEventPB(CalendarEventPB eventPB) {
    final timestamp = eventPB.timestamp;
    
    DateTime startTime;
    DateTime endTime;
    
    if (timestamp != null && timestamp != 0) {
      startTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
      // AppFlowy原版CalendarEventPB没有endTimestamp字段，默认设置为开始时间后1小时
      endTime = startTime.add(const Duration(hours: 1));
    } else {
      // 如果没有开始时间戳，使用当前时间
      startTime = DateTime.now();
      endTime = startTime.add(const Duration(hours: 1));
    }
    
    return ScheduleItem(
      id: eventPB.rowMeta.id,
      title: eventPB.title.isNotEmpty ? eventPB.title : '无标题事件',
      description: '来自数据库的日程',
      startTime: startTime,
      endTime: endTime,
      isAllDay: false,
      // 默认值，后续会从数据库读取时更新
      isImportant: false,
      category: '数据库',
      color: Colors.blue,
      dueDate: endTime, // 使用结束时间作为截止日期
      repeatType: 0,
      repeatRuleJson: "",
    );
  }

  ScheduleItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    bool? isAllDay,
    bool? isImportant,
    String? category,
    Color? color,
    String? reminderId,
    ReminderOption? reminderOption,
    DateTime? dueDate,
    int? repeatType,
    String? repeatRuleJson,
  }) {
    return ScheduleItem(
      id: this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      isImportant: isImportant ?? this.isImportant,
      category: category ?? this.category,
      color: color ?? this.color,
      reminderId: reminderId ?? this.reminderId,
      reminderOption: reminderOption ?? this.reminderOption,
      dueDate: dueDate ?? this.dueDate,
      repeatType: repeatType ?? this.repeatType,
      repeatRuleJson: repeatRuleJson ?? this.repeatRuleJson,
    );
  }
}

// 重复规则处理类
class RecurrenceRule {
  final int repeatType; // 0=无 1=每天 2=每周 3=每年 4=法定工作日 99=自定义
  final String? repeatRuleJson; // 自定义规则JSON
  final DateTime startDate; // 原始开始日期
  /// 勿将日程单次结束时间当作重复截止；仅 JSON 中 until/endDate 表示「重复截止到某日」
  final DateTime? endDate;

  RecurrenceRule({
    required this.repeatType,
    this.repeatRuleJson,
    required this.startDate,
    this.endDate,
  });

  // 判断某个日期是否匹配重复规则
  bool matchesDate(DateTime date) {
    if (repeatType == 0) {
      return false;
    }

    final dateOnly = _getDateOnly(date);
    final startDateOnly = _getDateOnly(startDate);
    // 仅使用重复规则 JSON 里的截止日期；不用日程 endTime（跨天日程的结束日会错误截断整段重复）
    final repeatUntil = _getRuleEndDate();

    // 如果日期在原始日期之前，不匹配（每周在下面单独处理）
    if (repeatType != 2 && dateOnly.isBefore(startDateOnly)) {
      return false;
    }

    if (repeatUntil != null &&
        dateOnly.isAfter(_getDateOnly(repeatUntil))) {
      return false;
    }

    switch (repeatType) {
      case 1: // 每天
        return true;

      case 2: // 每周：仅「周期锚点日」（与开始日同一星期几），且与开始日相差整周
        if (repeatRuleJson != null && repeatRuleJson!.isNotEmpty) {
          try {
            final rule = jsonDecode(repeatRuleJson!) as Map<String, dynamic>;
            final weekdays = rule['weekdays'] as List<dynamic>?;
            if (weekdays != null && weekdays.isNotEmpty) {
              final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
              if (!weekdayList.contains(date.weekday)) return false;
              final diff = dateOnly.difference(startDateOnly).inDays;
              return diff % 7 == 0;
            }
          } catch (_) {}
        }
        if (date.weekday != startDate.weekday) return false;
        final d = dateOnly.difference(startDateOnly).inDays;
        return d % 7 == 0;

      case 3: // 每年
        return date.month == startDate.month && date.day == startDate.day;

      case 4: // 法定工作日（需要节假日库）
        if (date.weekday == 6 || date.weekday == 7) {
          return false;
        }
        return true;

      case 99: // 自定义
        return _matchesCustomRule(date);

      default:
        return false;
    }
  }

  // 解析自定义规则（如"每1周的周一"）
  bool _matchesCustomRule(DateTime date) {
    if (repeatRuleJson == null || repeatRuleJson!.isEmpty) {
      return false;
    }

    try {
      // 解析规则：如"每1周的周一、周三" -> {"unit": 1, "interval": 1, "weekdays": [1, 3]}
      final rule = jsonDecode(repeatRuleJson!);
      final unit = rule['unit'] ?? 1; // 0=天 1=周 2=月 3=年
      final interval = rule['interval'] ?? 1;
      final weekdays = rule['weekdays'] as List<dynamic>?;

      final dateOnly = _getDateOnly(date);
      final startDateOnly = _getDateOnly(startDate);
      final daysDiff = dateOnly.difference(startDateOnly).inDays;

      switch (unit) {
        case 0: // 每 N 天
          // 每 interval 天重复一次
          return daysDiff >= 0 && daysDiff % interval == 0;

        case 1: // 每 N 周的特定星期几
          if (weekdays == null || weekdays.isEmpty) {
            return false;
          }
          // 自定义对话框保存的 weekday 索引为 0..6（周一..周日），
          // 而 DateTime.weekday 为 1..7（周一..周日）。需要做 +1 映射。
          final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
          if (!weekdayList.contains(date.weekday)) {
            return false;
          }
          
          // 如果间隔为1，只要星期几匹配且日期在开始日期之后即可
          if (interval == 1) {
            return daysDiff >= 0;
          }
          
          // 对于间隔大于1的情况，需要计算周数差是否能被间隔整除
          // 找到第一个匹配的星期几（从开始日期所在周开始）
          final weeksDiff = daysDiff ~/ 7;
          return weeksDiff >= 0 && weeksDiff % interval == 0;

        case 2: // 每 N 月
          // 计算月份差
          final monthsDiff = (date.year - startDate.year) * 12 + (date.month - startDate.month);
          if (monthsDiff < 0 || monthsDiff % interval != 0) {
            return false;
          }
          // 在同一个月内，日期应该相同或接近（处理月末情况）
          // 如果开始日期是月末（如31日），目标月份可能没有31日，则使用该月最后一天
          final targetDay = _getDayInMonth(date.year, date.month, startDate.day);
          return date.day == targetDay;

        case 3: // 每 N 年
          // 计算年份差
          final yearsDiff = date.year - startDate.year;
          if (yearsDiff < 0 || yearsDiff % interval != 0) {
            return false;
          }
          // 在同一年内，月份和日期应该相同
          // 处理闰年2月29日的情况：如果开始日期是2月29日，目标年份不是闰年，则使用2月28日
          if (startDate.month == 2 && startDate.day == 29) {
            // 闰年2月29日的情况
            final isLeapYear = _isLeapYear(date.year);
            if (isLeapYear) {
              return date.month == 2 && date.day == 29;
            } else {
              return date.month == 2 && date.day == 28;
            }
          }
          return date.month == startDate.month && date.day == startDate.day;

        default:
          return false;
      }
    } catch (e) {
      print('⚠️ [RecurrenceRule] 解析自定义规则失败: $e');
      return false;
    }
  }

  DateTime? _getRuleEndDate() {
    if (repeatRuleJson == null || repeatRuleJson!.isEmpty) {
      return null;
    }
    try {
      final rule = jsonDecode(repeatRuleJson!);
      if (rule is! Map<String, dynamic>) {
        return null;
      }
      final raw = rule['endDate'] ??
          rule['until'] ??
          rule['untilDate'] ??
          rule['end_at'] ??
          rule['endTimestamp'];
      if (raw == null) {
        return null;
      }
      if (raw is int) {
        final millis = raw > 1000000000000 ? raw : raw * 1000;
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
      if (raw is String && raw.isNotEmpty) {
        final asInt = int.tryParse(raw);
        if (asInt != null) {
          final millis = asInt > 1000000000000 ? asInt : asInt * 1000;
          return DateTime.fromMillisecondsSinceEpoch(millis);
        }
        return DateTime.tryParse(raw);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 获取日期部分（去除时分秒）
  DateTime _getDateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  // 获取月份中的有效日期（处理月末情况）
  int _getDayInMonth(int year, int month, int day) {
    // 获取该月的最大天数
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 如果指定的日期超过该月的最大天数，返回该月的最后一天
    return day > daysInMonth ? daysInMonth : day;
  }

  // 判断是否为闰年
  bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }
}

// 日程管理模型 - 基于 AppFlowy 数据库
class ScheduleModel extends ChangeNotifier {
  final List<ScheduleItem> _schedules = [];
  String? _selectedScheduleId; // 当前选中的日程ID
  bool _isLoading = false;
  bool _isDisposed = false; // 跟踪对象是否已被销毁
  String? _currentViewId; // 当前使用的视图ID
  DatabaseController? _databaseController; // 数据库控制器
  DatabaseCallbacks? _databaseCallbacks; // 数据库回调
  static const Duration _reminderUpdateWaitTimeout = Duration(seconds: 1);
  static const Duration _reminderUpdatePollInterval =
      Duration(milliseconds: 50);
  
  // 展开/收起状态管理
  bool _isIncompleteExpanded = true; // 未完成区域是否展开
  bool _isCompletedExpanded = true; // 已完成区域是否展开
  
  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);

  bool get isLoading => _isLoading;
  
  // 获取当前选中的日程ID
  String? get selectedScheduleId => _selectedScheduleId;
  
  // 检查指定日程是否被选中
  bool isScheduleSelected(String scheduleId) =>
      _selectedScheduleId == scheduleId;
  
  // 设置选中的日程
  void selectSchedule(String? scheduleId) {
    if (_selectedScheduleId != scheduleId) {
      _selectedScheduleId = scheduleId;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }
  
  // 获取当前视图ID
  String? get currentViewId => _currentViewId;
  
  // 展开/收起状态的getter
  bool get isIncompleteExpanded => _isIncompleteExpanded;

  bool get isCompletedExpanded => _isCompletedExpanded;
  
  // 切换未完成区域的展开状态
  void toggleIncompleteExpanded() {
    _isIncompleteExpanded = !_isIncompleteExpanded;
    if (!_isDisposed) {
      notifyListeners();
    }
  }
  
  // 切换已完成区域的展开状态
  void toggleCompletedExpanded() {
    _isCompletedExpanded = !_isCompletedExpanded;
    if (!_isDisposed) {
      notifyListeners();
    }
  }
  
  // 设置视图ID
  void setViewId(String viewId) {
    final viewIdChanged = _currentViewId != viewId;
    _currentViewId = viewId;

    // 视图ID未变化且已有数据，只通知UI更新
    if (!viewIdChanged && _schedules.isNotEmpty) {
      if (!_isDisposed) notifyListeners();
      return;
    }

    // 数据为空或视图ID变化：清空旧数据并重新初始化
    if (viewIdChanged || _schedules.isEmpty) {
      _schedules.clear();
      if (!_isDisposed) notifyListeners();
    }

    // 初始化数据库监听器（异步，不等待完成）
    _initializeDatabaseListener(viewId).then((_) {
      if (!_isDisposed) refresh();
    }).catchError((e) {
      Log.error('❌ [ScheduleModel] 数据库监听器初始化失败: $e');
      if (!_isDisposed) refresh();
    });
  }

  // 等待 ReminderBloc 将指定提醒更新为目标时间（避免刷新读到旧值）
  Future<void> _waitReminderUpdated(
      String reminderId, DateTime expected) async {
    try {
      final deadline = DateTime.now().add(_reminderUpdateWaitTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final reminderBloc = getIt<ReminderBloc>();
        final r = reminderBloc.state.reminders
                .firstWhereOrNull((e) => e.id == reminderId) ??
            reminderBloc.state.allReminders
                .firstWhereOrNull((e) => e.id == reminderId);
        if (r != null) {
          final scheduled = r.scheduledAt.toDateTime();
          if ((scheduled.millisecondsSinceEpoch ~/ 1000) ==
              (expected.millisecondsSinceEpoch ~/ 1000)) {
            return; // 已更新
          }
        }
        await Future.delayed(_reminderUpdatePollInterval);
      }
    } catch (_) {}
  }

  // 刷新日程数据（带防抖机制，避免重复调用）
  Future<void>? _refreshFuture;
  DateTime? _lastRefreshAt;
  static const Duration _refreshThrottleDuration = Duration(milliseconds: 500);
  
  Future<void> refresh() async {
    if (_isDisposed) return;
    // 如果正在加载，直接返回
    if (_isLoading) {
      // 调试输出已移除
      return;
    }
    
    // 防抖：如果距离上次刷新时间太短，跳过
    final now = DateTime.now();
    if (_lastRefreshAt != null && 
        now.difference(_lastRefreshAt!) < _refreshThrottleDuration) {
      // 调试输出已移除
      return;
    }
    
    // 如果已有待处理的刷新请求，等待它完成
    if (_refreshFuture != null) {
      // 调试输出已移除
      try {
        await _refreshFuture;
      } catch (_) {}
      return;
    }
    
    _lastRefreshAt = now;
    _refreshFuture = _loadSchedulesFromDatabase();
    try {
      await _refreshFuture;
    } finally {
      _refreshFuture = null;
    }
  }

  // 从 AppFlowy 数据库加载日程
  Future<void> _loadSchedulesFromDatabase() async {
    if (_isDisposed) return;
    // 如果已经在加载，直接返回
    if (_isLoading) {
      // 调试输出已移除
      return;
    }
    
    _setLoading(true);
    
    try {
      // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
      final viewId = _currentViewId ?? _newScheduleViewId;
      // 调试输出已移除
      
      // 获取所有日历事件
      final payload = CalendarEventRequestPB.create()..viewId = viewId;
      final result = await DatabaseEventGetAllCalendarEvents(payload).send();
      
      await result.fold(
        (events) async {
          // 调试输出已移除
          
          // 先构建最小集，再用 cells 补齐其它字段
          try {
            await _ensureDatabaseReadyInternal(viewId);
          } catch (_) {}

          final fieldInfos =
              _databaseController?.fieldController.fieldInfos ?? [];
          // 调试输出已移除
          for (final f in fieldInfos) {
            // 调试输出已移除
          }
          
          final Map<String, FieldInfo> fieldById = {
            for (final f in fieldInfos) f.field.id: f,
          };

          final newSchedules = <ScheduleItem>[];
          for (int i = 0; i < events.items.length; i++) {
            final eventPB = events.items[i];
            // 调试输出已移除
            
            var item = ScheduleItem.fromCalendarEventPB(eventPB);
            // 调试输出已移除
            
            if (fieldInfos.isNotEmpty) {
              try {
                // 调试输出已移除
                item = await _enrichFromCells(
                    viewId, fieldInfos, fieldById, item, eventPB);
              } catch (e, stackTrace) {
                Log.error('  ❌ 丰富数据时出错: $e');
                // 堆栈信息已降级/移除
              }
            }
            newSchedules.add(item);
          }

          // 调试输出已移除
          _schedules.clear();
          _schedules.addAll(newSchedules);

          if (!_isDisposed) {
            notifyListeners();
          }
        },
        (error) {
          Log.error('❌ [ScheduleModel] 加载日程失败: ${error.msg}');
          // 如果加载失败，清空列表
          _schedules.clear();
          if (!_isDisposed) {
            notifyListeners();
          }
        },
      );
    } catch (e) {
      // 如果出现异常，清空列表
      _schedules.clear();
      if (!_isDisposed) {
        notifyListeners();
      }
    } finally {
      _setLoading(false);
    }
  }

  // 固定的日历视图ID，专门用于独立的新建日程功能
  // 使用fixedUuid确保每次运行都生成相同的UUID，避免与随机生成的UUID冲突
  static final String _newScheduleViewId =
      fixedUuid(12345, UuidType.privateSpace);
  
  // 初始化独立的日历视图
  Future<bool> initializeCalendarView() async {
    try {
      // 先检查视图是否已存在
      final result = await ViewBackendService.getView(_newScheduleViewId);
      
      return result.fold(
        (view) async {
          if (_isDisposed) return false;
          // 视图已存在，设置视图ID并初始化数据库监听器
          _currentViewId = _newScheduleViewId;
          if (!_isDisposed) notifyListeners();
          
          // 初始化数据库监听器（确保 _databaseController 被创建）
          try {
            await _initializeDatabaseListener(_newScheduleViewId);
            return !_isDisposed;
          } catch (e) {
            print('⚠️ [ScheduleModel] initializeCalendarView 初始化数据库监听器失败: $e');
            return false;
          }
        },
        (error) async {
          if (_isDisposed) return false;
          // 视图不存在，需要创建新视图
          final createResult = await ViewBackendService.createOrphanView(
            viewId: _newScheduleViewId,
            name: '新建日程日历',
            layoutType: ViewLayoutPB.Calendar,
          );
          
          if (_isDisposed) return false;
          return createResult.fold(
            (view) async {
              if (_isDisposed) return false;
              _currentViewId = _newScheduleViewId;
              if (!_isDisposed) notifyListeners();
              
              // 初始化数据库监听器（确保 _databaseController 被创建）
              try {
                await _initializeDatabaseListener(_newScheduleViewId);
                return !_isDisposed;
              } catch (e) {
                print('⚠️ [ScheduleModel] initializeCalendarView 初始化数据库监听器失败: $e');
                return false;
              }
            },
            (createError) {
              return false;
            },
          );
        },
      );
    } catch (e) {
      print('❌ [ScheduleModel] initializeCalendarView 异常: $e');
      return false;
    }
  }

  // 创建新的日程（直接保存到 AppFlowy 数据库）
  Future<String?> createSchedule({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    bool isImportant = false,
    String category = '默认',
    Color color = Colors.blue,
    bool isAllDay = false,
    ReminderOption reminderOption = ReminderOption.none,
    DateTime? dueDate,
    int repeatType = 0,
    String? repeatRuleJson,
  }) async {
    // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
    final viewId = _currentViewId ?? _newScheduleViewId;
    
    print('📅 开始创建日程:');
    print('  - 标题: $title');
    print('  - 描述: $description');
    print('  - 开始时间: $startTime');
    print('  - 结束时间: $endTime');
    print('  - 视图ID: $viewId');
    print('  - 传入的 isAllDay 参数: $isAllDay');

    // 判断是否为全天事件：优先使用传入的 isAllDay 参数
    // 如果 isAllDay 为 true，直接使用；否则根据时间判断
    final isAllDayEvent = isAllDay 
        ? true 
        : ScheduleItem._isAllDayEvent(
      startTime: startTime,
      endTime: endTime,
    );
    
    print('  - 最终判断的全天事件: $isAllDayEvent');
    print('  - 提醒选项: $reminderOption');
    
    try {
      // 1) 确保数据库控制器已就绪（带重试）
      await _ensureDatabaseReadyInternal(viewId);
      if (_databaseController == null) {
        throw Exception('数据库控制器初始化失败');
      }
      
      // 获取数据库字段信息
      final databaseController = _databaseController!;
      
      final fieldController = databaseController.fieldController;
      if (fieldController == null) {
        throw Exception('字段控制器未初始化');
      }

      // 优先从控制器读取
      var fieldInfos = fieldController.fieldInfos;

      // 如果控制器为空，直接从后端拉取一次字段，并构建 FieldInfo 列表
      if (fieldInfos.isEmpty) {
        final fetched = await FieldBackendService.getFields(viewId: viewId);
        fieldInfos = fetched.fold(
          (list) => list.map((f) => FieldInfo.initial(f)).toList(),
          (_) => <FieldInfo>[],
        );
      }

      // 若仍为空，则自动创建最小字段集后再次拉取
      if (fieldInfos.isEmpty) {
        try {
          await FieldBackendService.createField(
            viewId: viewId,
            fieldType: FieldType.RichText,
            fieldName: 'Title',
          );
          await FieldBackendService.createField(
            viewId: viewId,
            fieldType: FieldType.DateTime,
            fieldName: 'Date',
          );

          // 等待后端落地
          await Future.delayed(const Duration(milliseconds: 200));

          final fetched = await FieldBackendService.getFields(viewId: viewId);
          fieldInfos = fetched.fold(
            (list) => list.map((f) => FieldInfo.initial(f)).toList(),
            (_) => <FieldInfo>[],
          );
        } catch (_) {}

        if (fieldInfos.isEmpty) {
          throw Exception('数据库中没有可用的字段');
        }
      }
      
      // 使用 AppFlowy 标准的创建行方法
      print('🔄 调用 RowBackendService.createRow...');

      Future<FlowyResult<RowMetaPB, FlowyError>> _create() {
        return RowBackendService.createRow(
          viewId: viewId,
          withCells: (builder) {
            // 仅在创建时设置：标题 + 一个日期字段的开始时间
            final primaryField = fieldInfos.firstWhere(
              (field) => field.isPrimary,
              orElse: () => fieldInfos.first,
            );
            if (primaryField.fieldType == FieldType.RichText) {
              builder.insertText(primaryField, title);
            } else {
              final textField = fieldInfos.firstWhere(
                (field) => field.fieldType == FieldType.RichText,
                orElse: () => primaryField,
              );
              builder.insertText(textField, title);
            }

            // 选择第一个 DateTime 字段作为日历日期字段
            final firstDateTimeField = fieldInfos.firstWhere(
              (f) => f.fieldType == FieldType.DateTime,
              orElse: () => primaryField,
            );
            if (firstDateTimeField.fieldType == FieldType.DateTime) {
              builder.insertDate(firstDateTimeField, startTime);
            }
          },
        );
      }

      // 2) 尝试创建，遇到“Cancel database operation”进行恢复并重试
      Future<RowMetaPB> _attemptCreateWithRecovery() async {
        final first = await _create();
        return first.fold(
          (ok) async => ok,
          (err) async {
            if (err.msg.contains('Cancel database operation')) {
              // 可能是打开阶段与创建竞争，重建监听器并重试
              await Future.delayed(const Duration(milliseconds: 200));
              try {
                _disposeDatabaseListener();
                await _initializeDatabaseListener(viewId);
                await _ensureDatabaseReadyInternal(viewId);
              } catch (_) {}
              final retry = await _create();
              return retry.fold((ok2) => ok2, (e2) => throw Exception(e2.msg));
            }
            throw Exception(err.msg);
          },
        );
      }

      final createdRowMeta = await _attemptCreateWithRecovery();

      // 直接使用已得到的 RowMetaPB 继续流程
      final rowMeta = createdRowMeta;
      {
          print('✅ 行创建成功，ID: ${rowMeta.id}');
          print('📅 [createSchedule] 准备更新日期字段，包含重复信息:');
          print('  - repeatType: $repeatType');
          print('  - repeatRuleJson: $repeatRuleJson');
          
      // 更新日期字段（包含重复信息）
      final dateUpdated = await _updateDateField(
              viewId: viewId,
              rowId: rowMeta.id,
        fieldInfos: fieldInfos,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDayEvent,
        repeatType: repeatType,
        repeatRuleJson: repeatRuleJson,
      );
      
      if (!dateUpdated) {
        print('⚠️ [createSchedule] 日期字段更新失败，但继续执行后续流程');
      } else {
        print('✅ [createSchedule] 日期字段更新成功，包含重复信息');
      }

          // 更新其他字段
          await _updateOtherFields(
            viewId: viewId,
            rowId: rowMeta.id,
            fieldInfos: fieldInfos,
            description: description,
            isImportant: isImportant,
            category: category,
          );

          // 获取日期服务用于提醒处理
          DateCellBackendService? dateService;
          final dateField = fieldInfos.firstWhere(
            (f) => f.fieldType == FieldType.DateTime,
            orElse: () => fieldInfos.first,
          );
          if (dateField.fieldType == FieldType.DateTime) {
            dateService = DateCellBackendService(
                  viewId: viewId,
              fieldId: dateField.field.id,
              rowId: rowMeta.id,
            );
          }
          
          // 重复信息不再使用自定义字段保存，改由日期单元格的 repeatType/repeatRuleJson 承载
          
          // 创建对应的本地 ScheduleItem
          final newSchedule = ScheduleItem(
            id: rowMeta.id,
            title: title,
            description: description,
            startTime: isAllDayEvent ? startTime.withoutTime : startTime,
            endTime: isAllDayEvent ? endTime.withoutTime : endTime,
            isAllDay: isAllDayEvent,
            // 设置 isAllDay 属性
            isImportant: isImportant,
            category: category,
            color: color,
            reminderOption: reminderOption,
            dueDate: dueDate ?? endTime, // 如果没有指定截止日期，使用结束时间
            repeatType: repeatType,
            repeatRuleJson: repeatRuleJson,
          );
          
          // 添加到本地列表
          _schedules.add(newSchedule);
          
          // 检查对象是否已被销毁，避免在 dispose 后调用 notifyListeners
          if (!_isDisposed) {
            notifyListeners();
          }
          
          // 处理提醒
          if (reminderOption != ReminderOption.none && dateService != null) {
            try {
              await _handleReminder(
                viewId: viewId,
                rowId: rowMeta.id,
                schedule: newSchedule,
                reminderOption: reminderOption,
                dateService: dateService,
                existingReminderId: null,
              );
              
              // 更新本地 ScheduleItem 的 reminderId（从 ReminderBloc 获取）
              final reminderBloc = getIt<ReminderBloc>();
              final reminder = reminderBloc.state.allReminders.firstWhereOrNull(
                (r) => r.meta[ReminderMetaKeys.rowId] == rowMeta.id,
              );
              if (reminder != null) {
                final updatedSchedule = newSchedule.copyWith(reminderId: reminder.id);
              final index = _schedules.indexWhere((s) => s.id == rowMeta.id);
              if (index != -1) {
                _schedules[index] = updatedSchedule;
              if (!_isDisposed) {
                    notifyListeners();
              }
            }
              }
            } catch (e) {
            print('⚠️ [ScheduleModel] createSchedule 设置提醒失败: $e');
          }
        }
          return rowMeta.id;
      }
    } catch (e, stackTrace) {
      print('❌ createSchedule 异常:');
      print('  - 异常: $e');
      print('  - 堆栈: $stackTrace');
      
      // 重新抛出异常
      rethrow;
    }
  }

  // 确保数据库控制器与字段控制器就绪（带轮询等待）
  Future<void> _ensureDatabaseReadyInternal(String viewId) async {
    if (_databaseController == null) {
      await _initializeDatabaseListener(viewId);
    }
    // 等待字段控制器就绪，并确保字段已加载
    const int maxAttempts = 60; // 最长约3秒
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final controller = _databaseController;
      if (controller != null && controller.fieldController.fieldInfos.isNotEmpty) {
        // 字段已加载完成
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 超时仍未就绪
    throw Exception('数据库控制器初始化失败或字段未加载完成');
  }

  // 确保有最小字段集（Title + Date）
  Future<void> _ensureMinimumFields(String viewId) async {
    try {
      // 检查是否已有字段
      final fetched = await FieldBackendService.getFields(viewId: viewId);
      final existingFields = fetched.fold(
        (list) => list,
        (_) => <dynamic>[],
      );
      
      if (existingFields.isNotEmpty) {
        return;
      }
      
      // 创建最小字段集
      await FieldBackendService.createField(
        viewId: viewId,
        fieldType: FieldType.RichText,
        fieldName: 'Title',
      );
      
      await FieldBackendService.createField(
        viewId: viewId,
        fieldType: FieldType.DateTime,
        fieldName: 'Date',
      );
    } catch (e) {
      // 忽略错误
    }
  }

  // 不再创建或依赖自定义 Repeat 字段，重复信息由日期字段承载

  // 更新日期字段的公共方法
  Future<bool> _updateDateField({
    required String viewId,
    required String rowId,
    required List<FieldInfo> fieldInfos,
    required DateTime startTime,
    required DateTime endTime,
    required bool isAllDay,
    required int repeatType,
    String? repeatRuleJson,
  }) async {
    print('🔄 [_updateDateField] 开始更新日期字段:');
    print('  - viewId: $viewId');
    print('  - rowId: $rowId');
    print('  - repeatType: $repeatType');
    print('  - repeatRuleJson: $repeatRuleJson');
    
    // 查找第一个日期时间字段
    FieldInfo? dateField;
    for (final f in fieldInfos) {
      if (f.fieldType == FieldType.DateTime) {
        dateField = f;
        break;
      }
    }

    if (dateField == null) {
      print('❌ [_updateDateField] 未找到日期时间字段');
      return false;
    }

    print('✅ [_updateDateField] 找到日期字段: ${dateField.name} (${dateField.field.id})');

    try {
      final dateService = DateCellBackendService(
        viewId: viewId,
        fieldId: dateField.field.id,
        rowId: rowId,
      );

      print('📤 [_updateDateField] 调用 dateService.update，参数:');
      print('  - date: ${isAllDay ? startTime.withoutTime : startTime}');
      print('  - endDate: ${isAllDay ? null : endTime}');
      print('  - isRange: ${!isAllDay}');
      print('  - includeTime: ${!isAllDay}');
      print('  - repeatType: $repeatType');
      print('  - repeatRuleJson: ${repeatRuleJson ?? ''}');

      final updateResult = await dateService.update(
        date: isAllDay ? startTime.withoutTime : startTime,
        endDate: isAllDay ? null : endTime,
        isRange: !isAllDay,
        includeTime: !isAllDay,
        repeatType: repeatType,
        repeatRuleJson: repeatRuleJson ?? '',
      );

      return updateResult.fold(
        (_) {
          print('✅ [_updateDateField] 日期字段更新成功');
          return true;
        },
        (error) {
          print('❌ [_updateDateField] 日期字段更新失败: ${error.msg}');
          return false;
        },
      );
    } catch (e, stackTrace) {
      print('❌ [_updateDateField] 日期字段更新异常: $e');
      print('📍 堆栈: $stackTrace');
      return false;
    }
  }

  // 更新其他字段的公共方法
  Future<void> _updateOtherFields({
    required String viewId,
    required String rowId,
    required List<FieldInfo> fieldInfos,
    String? description,
    bool? isImportant,
    String? category,
  }) async {
    for (final field in fieldInfos) {
      if (field.fieldType == FieldType.DateTime) {
        continue; // 跳过日期字段
      }

      try {
        final name = field.name.toLowerCase();
        if (field.fieldType == FieldType.RichText && 
            name.contains('description') && 
            description != null) {
          await CellBackendService.updateCell(
            viewId: viewId,
            cellContext: CellContext(fieldId: field.field.id, rowId: rowId),
            data: description,
          );
        } else if (field.fieldType == FieldType.Checkbox &&
            (name.contains('important') || name.contains('重要')) &&
            isImportant != null) {
          await CellBackendService.updateCell(
            viewId: viewId,
            cellContext: CellContext(fieldId: field.field.id, rowId: rowId),
            data: isImportant ? "Yes" : "No",
          );
        } else if (field.fieldType == FieldType.RichText &&
            (name.contains('category') || name.contains('分类')) &&
            category != null) {
          await CellBackendService.updateCell(
            viewId: viewId,
            cellContext: CellContext(fieldId: field.field.id, rowId: rowId),
            data: category,
          );
        }
      } catch (e) {
        // 忽略字段更新失败
      }
    }
  }

  // 处理提醒的公共方法
  Future<void> _handleReminder({
    required String viewId,
    required String rowId,
    required ScheduleItem schedule,
    required ReminderOption reminderOption,
    required DateCellBackendService? dateService,
    String? existingReminderId,
  }) async {
    if (reminderOption == ReminderOption.none) {
      // 移除提醒
      if (existingReminderId != null && existingReminderId.isNotEmpty) {
        final reminderBloc = getIt<ReminderBloc>();
        reminderBloc.add(ReminderEvent.removeReminder(reminderId: existingReminderId));
        if (dateService != null) {
          await dateService.update(reminderId: '');
        }
      }
      return;
    }

    final reminderBloc = getIt<ReminderBloc>();
    
    // 处理单次日程
    if (schedule.repeatType == 0) {
      final baseTime = schedule.isAllDay ? schedule.startTime.withoutTime : schedule.startTime;
      final scheduledAt = reminderOption.getNotificationDateTime(baseTime);

      if (existingReminderId == null || existingReminderId.isEmpty) {
        // 创建新提醒
        final reminderId = nanoid();
        if (dateService != null) {
          await dateService.update(reminderId: reminderId);
        }

        reminderBloc.add(
          ReminderEvent.addById(
            reminderId: reminderId,
            objectId: viewId,
            meta: {
              ReminderMetaKeys.includeTime: (!schedule.isAllDay).toString(),
              ReminderMetaKeys.rowId: rowId,
              ReminderMetaKeys.date: baseTime.millisecondsSinceEpoch.toString(),
              ReminderMetaKeys.notificationType: 'reminder',
            },
            scheduledAt: Int64(scheduledAt.millisecondsSinceEpoch),
          ),
        );

        await _waitReminderUpdated(reminderId, scheduledAt);
      } else {
        // 更新现有提醒
        reminderBloc.add(
          ReminderEvent.update(
            ReminderUpdate(
              id: existingReminderId,
              scheduledAt: scheduledAt,
              includeTime: !schedule.isAllDay,
              date: schedule.startTime,
            ),
          ),
        );

        await _waitReminderUpdated(existingReminderId, scheduledAt);
      }
    } else {
      // 处理重复日程，为未来N个实例创建提醒
      await _handleRecurringScheduleReminders(
        viewId: viewId,
        rowId: rowId,
        schedule: schedule,
        reminderOption: reminderOption,
      );
    }
  }

  // 处理重复日程的提醒
  Future<void> _handleRecurringScheduleReminders({
    required String viewId,
    required String rowId,
    required ScheduleItem schedule,
    required ReminderOption reminderOption,
  }) async {
    final reminderBloc = getIt<ReminderBloc>();
    final recurrenceRule = RecurrenceRule(
      repeatType: schedule.repeatType,
      repeatRuleJson: schedule.repeatRuleJson,
      startDate: schedule.startTime,
    );

    // 生成未来30天的提醒
    final now = DateTime.now();
    final endDate = now.add(Duration(days: 30));
    DateTime currentDate = schedule.startTime;
    int instanceCount = 0;

    while (currentDate.isBefore(endDate) && instanceCount < 10) { // 限制最多10个实例
      if (recurrenceRule.matchesDate(currentDate)) {
        final baseTime = schedule.isAllDay ? currentDate.withoutTime : currentDate;
        final scheduledAt = reminderOption.getNotificationDateTime(baseTime);
        
        if (scheduledAt.isAfter(now)) {
          // 为每个重复实例创建单独的提醒
          final reminderId = '${nanoid()}_${currentDate.millisecondsSinceEpoch}';
          
          reminderBloc.add(
            ReminderEvent.addById(
              reminderId: reminderId,
              objectId: viewId,
              meta: {
                ReminderMetaKeys.includeTime: (!schedule.isAllDay).toString(),
                ReminderMetaKeys.rowId: rowId,
                ReminderMetaKeys.date: baseTime.millisecondsSinceEpoch.toString(),
                ReminderMetaKeys.notificationType: 'reminder',
                ReminderMetaKeys.isRecurring: 'true',
                ReminderMetaKeys.recurrenceInstanceId: currentDate.millisecondsSinceEpoch.toString(),
              },
              scheduledAt: Int64(scheduledAt.millisecondsSinceEpoch),
            ),
          );
          
          await _waitReminderUpdated(reminderId, scheduledAt);
          instanceCount++;
        }
      }
      
      // 下一天
      currentDate = currentDate.add(Duration(days: 1));
    }
  }

  // 更新日程
  Future<bool> updateSchedule(ScheduleItem schedule) async {
    print('🔄 [ScheduleModel] updateSchedule 开始更新日程: ${schedule.id}');
    print('  - 标题: ${schedule.title}');
    print('  - 开始时间: ${schedule.startTime}');
    print('  - 结束时间: ${schedule.endTime}');
    print('  - 全天: ${schedule.isAllDay}');
    
    try {
      // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
      final viewId = _currentViewId ?? _newScheduleViewId;
      
      // 确保数据库控制器已初始化
      if (_databaseController == null) {
        try {
          await _initializeDatabaseListener(viewId);
        } catch (e) {
          print('❌ [ScheduleModel] updateSchedule 初始化数据库监听器失败: $e');
          return false;
        }
        
        if (_databaseController == null) {
          print('❌ [ScheduleModel] updateSchedule 数据库控制器为 null');
          return false;
        }
      }
      
      // 获取字段信息
      final databaseController = _databaseController!;
      final fieldController = databaseController.fieldController;
      if (fieldController == null) {
        print('❌ [ScheduleModel] updateSchedule 字段控制器为 null');
        return false;
      }
      
      final fieldInfos = fieldController.fieldInfos;
      if (fieldInfos.isEmpty) {
        print('❌ [ScheduleModel] updateSchedule 字段列表为空');
        return false;
      }
      
      // 查找主字段（标题字段）
      final primaryField = fieldInfos.firstWhere(
        (field) => field.field.isPrimary,
        orElse: () => fieldInfos.first,
      );
      
      // 更新标题（关键字段）
      bool titleUpdated = false;
      if (primaryField.fieldType == FieldType.RichText) {
        final title =
            schedule.title.isNotEmpty ? schedule.title : schedule.description;
        final result = await CellBackendService.updateCell(
          viewId: viewId,
          cellContext: CellContext(
            fieldId: primaryField.field.id,
            rowId: schedule.id,
          ),
          data: title,
        );
        
        result.fold(
          (_) {
            titleUpdated = true;
          },
          (error) {
            print('❌ [ScheduleModel] updateSchedule 标题更新失败: ${error.msg}');
          },
        );
      } else {
        titleUpdated = true; // 如果没有标题字段，跳过
      }
      
      // 更新日期字段
            final isAllDayEvent = schedule.isAllDay ||
                ScheduleItem._isAllDayEvent(
              startTime: schedule.startTime,
              endTime: schedule.endTime,
            );
      final dateUpdated = await _updateDateField(
              viewId: viewId,
                rowId: schedule.id,
        fieldInfos: fieldInfos,
        startTime: schedule.startTime,
        endTime: schedule.endTime,
        isAllDay: isAllDayEvent,
        repeatType: schedule.repeatType,
        repeatRuleJson: schedule.repeatRuleJson,
      );

      // 更新其他字段
      await _updateOtherFields(
              viewId: viewId,
                rowId: schedule.id,
        fieldInfos: fieldInfos,
        description: schedule.description,
        isImportant: schedule.isImportant,
        category: schedule.category,
      );

      // 获取日期服务和 reminderId
      DateCellBackendService? dateService;
      final dateField = fieldInfos.firstWhere(
        (f) => f.fieldType == FieldType.DateTime,
        orElse: () => fieldInfos.first,
      );
      if (dateField.fieldType == FieldType.DateTime) {
        dateService = DateCellBackendService(
              viewId: viewId,
          fieldId: dateField.field.id,
                rowId: schedule.id,
        );
      }

      String? existingReminderId = schedule.reminderId?.isNotEmpty == true
          ? schedule.reminderId
          : _schedules.firstWhereOrNull((s) => s.id == schedule.id)?.reminderId;
      
      // 重复信息不再使用自定义字段保存，改由日期单元格的 repeatType/repeatRuleJson 承载
      
      // 如果关键字段（日期或标题）更新成功，则认为整体更新成功
      // 日期字段是最重要的，如果日期更新成功，即使其他字段失败也返回成功
      if (dateUpdated || titleUpdated) {
        final index = _schedules.indexWhere((s) => s.id == schedule.id);
        // 尽力同步本地列表，但不要把提醒更新依赖于本地是否命中
        if (index != -1) {
          _schedules[index] = schedule;
          }

          // 处理提醒
          try {
            await _handleReminder(
              viewId: viewId,
              rowId: schedule.id,
              schedule: schedule,
              reminderOption: schedule.reminderOption,
              dateService: dateService,
              existingReminderId: existingReminderId,
            );
            
            // 更新本地 ScheduleItem 的 reminderId
            final reminderBloc = getIt<ReminderBloc>();
            final reminder = reminderBloc.state.allReminders.firstWhereOrNull(
              (r) => r.id == existingReminderId || 
                     r.meta[ReminderMetaKeys.rowId] == schedule.id,
            );
            if (reminder != null) {
              final updatedSchedule = schedule.copyWith(
                reminderId: reminder.id,
                reminderOption: schedule.reminderOption,
              );
              final index = _schedules.indexWhere((s) => s.id == schedule.id);
              if (index != -1) {
                _schedules[index] = updatedSchedule;
              }
            } else if (schedule.reminderOption == ReminderOption.none) {
              final updatedSchedule = schedule.copyWith(
                  reminderId: '',
                reminderOption: ReminderOption.none,
              );
              final index = _schedules.indexWhere((s) => s.id == schedule.id);
              if (index != -1) {
                _schedules[index] = updatedSchedule;
              }
            }
          } catch (e) {
            print('⚠️ [ScheduleModel] updateSchedule 更新提醒失败: $e');
          }

        // 如果本地列表中没有该日程，进行一次乐观插入
        if (index == -1) {
          _schedules.add(schedule);
        }
        
        // 通知UI更新（数据库回调会自动触发 refresh，这里只做本地状态同步）
        if (!_isDisposed) {
          notifyListeners();
          }
          
          print('✅ [ScheduleModel] updateSchedule 更新成功');
        // 注意：不在此处调用 refresh()，数据库回调会自动触发刷新
        // 这样可以避免重复刷新，同时确保数据一致性
          return true;
      } else {
        print('❌ [ScheduleModel] updateSchedule 关键字段（日期和标题）都更新失败');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ [ScheduleModel] updateSchedule 异常: $e');
      print('📍 堆栈: $stackTrace');
      return false;
    }
  }

  // 删除日程
  Future<bool> deleteSchedule(String scheduleId) async {
    try {
      // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
      final viewId = _currentViewId ?? _newScheduleViewId;
      
      // 先查找要删除的日程（用于处理提醒）
      final scheduleToDelete =
          _schedules.where((s) => s.id == scheduleId).firstOrNull;
      
      // 从数据库删除
      await RowBackendService.deleteRows(viewId, [scheduleId]);

      // 如果找到了日程并且有提醒，则移除提醒
      if (scheduleToDelete?.reminderId != null) {
        _removeReminder(scheduleToDelete!.reminderId!);
      }

      // 从本地列表删除
      _schedules.removeWhere((s) => s.id == scheduleId);
      
      if (!_isDisposed) {
        notifyListeners();
      }
      
      return true;
    } catch (e) {
      // 即使本地操作失败，如果数据库删除成功，我们仍然应该刷新数据
      if (e.toString().contains('Bad state: No element')) {
        await refresh(); // 刷新数据以保持同步
        return true; // 数据库删除可能已经成功了
      }
      throw Exception('删除日程失败');
    }
  }

  // 读取单元格补齐：描述/全天/重要/分类/提醒/结束时间
  Future<ScheduleItem> _enrichFromCells(
    String viewId,
    List<FieldInfo> fieldInfos,
    Map<String, FieldInfo> fieldById,
    ScheduleItem schedule,
    CalendarEventPB eventPB,
  ) async {
    var enriched = schedule;
    print('    🔍 [enrichFromCells] 开始丰富日程 ID: ${schedule.id}');

    Future<String?> _getString(FieldInfo f) async {
      final r = await CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: f.field.id, rowId: schedule.id),
      );
      return r.fold(
        (cell) => StringCellDataParser().parserData(cell.data),
        (_) => null,
      );
    }

    Future<bool?> _getCheckbox(FieldInfo f) async {
      final r = await CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: f.field.id, rowId: schedule.id),
      );
      return r.fold(
        (cell) {
          final s = StringCellDataParser().parserData(cell.data)?.trim();
          if (s == null || s.isEmpty) return null;
          final v = s.toLowerCase();
          return v == 'yes' || v == 'true' || v == '1';
        },
        (_) => null,
      );
    }

    Future<(DateTime?, DateTime?, bool?, bool?, String?,int?,String?)>
        _getDateRangeWithExtra(FieldInfo f) async {
      final r = await CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: f.field.id, rowId: schedule.id),
      );
      return r.fold(
        (cell) {
          // 只在调试模式下打印详细日志
          if (kDebugMode) {
            print('    🔍 [_getDateRangeWithExtra] 原始 cell.data 长度: ${cell.data.length}');
          }
          final pb = DateCellDataParser().parserData(cell.data);
          if (pb == null) {
            if (kDebugMode) {
              print('    ❌ [_getDateRangeWithExtra] DateCellDataParser 返回 null');
            }
            return (null, null, null, null, null,0,"");
          }
          
          if (kDebugMode) {
            print('    🔍 [_getDateRangeWithExtra] 解析后的 DateCellDataPB:');
            print('      - hasTimestamp: ${pb.hasTimestamp()}');
            print('      - hasEndTimestamp: ${pb.hasEndTimestamp()}');
            print('      - includeTime: ${pb.includeTime}');
            print('      - isRange: ${pb.isRange}');
            print('      - reminderId: ${pb.reminderId}');
            print('      - hasRepeatType: ${pb.hasRepeatType()}');
            print('      - repeatType: ${pb.repeatType}');
            print('      - hasRepeatRuleJson: ${pb.hasRepeatRuleJson()}');
            print('      - repeatRuleJson: ${pb.repeatRuleJson}');
          }
          
          DateTime? s;
          DateTime? e;
          bool? includeTime;
          bool? isRange;
          String? reminderId;
          int? repeatType;
          String? repeatRuleJson;

          if (pb.hasTimestamp()) {
            s = DateTime.fromMillisecondsSinceEpoch(
                pb.timestamp.toInt() * 1000);
          }
          
          // 读取 isRange
          isRange = pb.isRange;
          
          // 如果是范围（isRange=true），读取结束时间；如果是全天（isRange=false），结束时间等于开始时间
          if (pb.isRange && pb.hasEndTimestamp()) {
            e = DateTime.fromMillisecondsSinceEpoch(
                pb.endTimestamp.toInt() * 1000);
          } else if (!pb.isRange && s != null) {
            // 全天事件：结束时间等于开始时间（同一天）
            e = s;
          }
          
          // includeTime 和 reminderId 可以直接访问，参考 DateCellData.fromPB 的实现
          includeTime = pb.includeTime;
          if (pb.reminderId.isNotEmpty) {
            reminderId = pb.reminderId;
          }
          
          // 读取 repeatType 和 repeatRuleJson
          // 注意：repeatType 和 repeatRuleJson 是 one_of 字段，需要先检查 hasXxx()
          // 如果 hasXxx() 返回 true，说明字段存在，直接读取值（即使值是默认值 0 或空字符串）
          // 如果 hasXxx() 返回 false，说明字段不存在（可能是旧数据或未设置），使用默认值
          // 这与 reminderId 的处理方式类似：reminderId 是普通字段，总是存在，所以直接检查 isNotEmpty
          if (pb.hasRepeatType()) {
            repeatType = pb.repeatType;
            if (kDebugMode) {
              print('    ✅ [_getDateRangeWithExtra] 读取到 repeatType: $repeatType (hasRepeatType=true)');
            }
          } else {
            // 字段不存在，使用默认值（这是正常的，旧数据可能没有这个字段）
            repeatType = 0; // 默认值：无重复
            // 移除警告信息，因为这是正常的处理逻辑，不是错误
          }
          
          if (pb.hasRepeatRuleJson()) {
            // 字段存在，读取值（即使是空字符串也要读取）
            final ruleJson = pb.repeatRuleJson;
            repeatRuleJson = ruleJson.isEmpty ? null : ruleJson;
            if (kDebugMode) {
              print('    ✅ [_getDateRangeWithExtra] 读取到 repeatRuleJson: "$repeatRuleJson" (hasRepeatRuleJson=true)');
            }
          } else {
            // 字段不存在，使用默认值（这是正常的，旧数据可能没有这个字段）
            repeatRuleJson = null; // 默认值：无自定义规则
            // 移除警告信息，因为这是正常的处理逻辑，不是错误
          }
          
          return (s, e, includeTime, isRange, reminderId,repeatType,repeatRuleJson);
        },
        (_) {
          print('    ❌ [_getDateRangeWithExtra] CellBackendService.getCell 失败');
          return (null, null, null, null, null,0,"");
        },
      );
    }

    // 先优先用 calendar 的日期字段读取范围、includeTime 和 reminderId
    final df = fieldById[eventPB.dateFieldId];
    if (df != null && df.fieldType == FieldType.DateTime) {
      print('    📅 [enrichFromCells] 读取日期字段: ${df.name} (${df.field.id})');
      final (s, e, includeTime, isRange, reminderId,repeatType,repeatRuleJson) =
          await _getDateRangeWithExtra(df);
      print(
          '    📅 [enrichFromCells] 日期数据: 开始=$s, 结束=$e, includeTime=$includeTime, isRange=$isRange, reminderId=$reminderId,repeatType=$repeatType,repeatRuleJson=$repeatRuleJson');
      
      if (s != null) {
        // 如果有结束时间则使用，否则结束时间等于开始时间（全天事件）
        final endTime = e ?? s;
        
        // 根据 includeTime 和 isRange 判断是否为全天事件
        final isAllDayEvent = ScheduleItem._isAllDayEvent(
          includeTime: includeTime,
          isRange: isRange,
          startTime: s,
          endTime: endTime,
        );
        
        // 如果是全天事件，去掉时分秒；否则保留时间
        final finalStartTime = isAllDayEvent ? s.withoutTime : s;
        final finalEndTime = isAllDayEvent ? (endTime.withoutTime) : endTime;
        
        enriched = enriched.copyWith(
          startTime: finalStartTime,
          endTime: finalEndTime,
          isAllDay: isAllDayEvent, // 设置 isAllDay 属性
          repeatType: repeatType ?? 0, // 更新重复类型
          repeatRuleJson: repeatRuleJson, // 更新重复规则
        );
        
        print(
            '    ✅ [enrichFromCells] 更新了开始时间和结束时间: $finalStartTime -> $finalEndTime');
        print(
            '    📅 [enrichFromCells] 全天事件: $isAllDayEvent (includeTime=$includeTime, isRange=$isRange)');
        print(
            '    🔁 [enrichFromCells] 重复类型: $repeatType, 重复规则: $repeatRuleJson');
      }

      // 如果日期单元格有 reminderId，推断 ReminderOption
      if (reminderId != null && reminderId.isNotEmpty) {
        print('    🔔 [enrichFromCells] 找到提醒ID: $reminderId');
        print('    🔔 [enrichFromCells] 当前日程的 reminderOption: ${enriched.reminderOption.name}');
        // 只从 ReminderBloc 获取（权威源）；避免读取本地旧缓存造成回退为老选项
          try {
            final reminderBloc = getIt<ReminderBloc>();
          final reminder = reminderBloc.state.reminders.firstWhereOrNull(
                (r) => r.id == reminderId,
              ) ??
              reminderBloc.state.allReminders.firstWhereOrNull(
              (r) => r.id == reminderId,
            );
            if (reminder != null && s != null) {
              final scheduledAt = reminder.scheduledAt.toDateTime();
            final optionFromBloc =
                ReminderOption.fromDateDifference(s, scheduledAt);
            print(
                '    🔔 [enrichFromCells] 从 ReminderBloc 找到提醒，映射为: ${optionFromBloc.name}');
            // 统一使用 ReminderBloc 推导结果作为权威来源
              enriched = enriched.copyWith(
                reminderId: reminderId,
              reminderOption: optionFromBloc,
              );
            } else {
            // ReminderBloc 中未找到，但保留已有的 reminderOption（如果存在）
            // 这样可以避免在刷新时丢失刚刚创建的提醒选项
            if (enriched.reminderOption != ReminderOption.none) {
              print(
                  '    ⚠️ [enrichFromCells] ReminderBloc 未命中，但保留已有的 reminderOption: ${enriched.reminderOption.name}');
              enriched = enriched.copyWith(reminderId: reminderId);
            } else {
              print(
                  '    ⚠️ [enrichFromCells] ReminderBloc 未命中，且没有已有的 reminderOption，仅设置 reminderId');
              enriched = enriched.copyWith(reminderId: reminderId);
            }
            }
          } catch (e) {
            print('    ❌ [enrichFromCells] 处理提醒时出错: $e');
          // 出错时也保留已有的 reminderOption
          if (enriched.reminderOption != ReminderOption.none) {
            print('    ⚠️ [enrichFromCells] 保留已有的 reminderOption: ${enriched.reminderOption.name}');
            enriched = enriched.copyWith(reminderId: reminderId);
          } else {
            enriched = enriched.copyWith(reminderId: reminderId);
          }
        }
      }
    } else {
      print(
          '    ⚠️ [enrichFromCells] 未找到日期字段 (dateFieldId: ${eventPB.dateFieldId})');
    }

    print('    🔍 [enrichFromCells] 遍历 ${fieldInfos.length} 个字段查找其他数据...');
    for (final f in fieldInfos) {
      final name = f.name.toLowerCase();
      try {
        if (f.fieldType == FieldType.DateTime) {
          // 已通过 dateFieldId 优先补齐，这里可跳过其它日期字段，除非需要特定 end 字段
          continue;
        } else if (f.fieldType == FieldType.RichText) {
          if (name.contains('description') || name.contains('描述')) {
            final v = await _getString(f);
            print('    📝 [enrichFromCells] 读取描述字段 "${f.name}": $v');
            if (v != null && v.isNotEmpty) {
              enriched = enriched.copyWith(description: v);
              print('    ✅ [enrichFromCells] 更新了描述');
            }
          } else if (name.contains('category') || name.contains('分类')) {
            final v = await _getString(f);
            print('    🏷️ [enrichFromCells] 读取分类字段 "${f.name}": $v');
            if (v != null && v.isNotEmpty) {
              enriched = enriched.copyWith(category: v);
              print('    ✅ [enrichFromCells] 更新了分类');
            }
          }
          // 注意：重复信息（repeatType 和 repeatRuleJson）现在存储在日期字段中，
          // 不再从单独的 "Repeat" 字段读取。已在日期字段读取时更新（见第 1609-1610 行）。
          // 注意：提醒选项不再从单独的字段读取，而是从日期单元格的 reminderId 读取
          // 这与 calendar_event_editor 的处理方式一致（见 DateCellEditorState.initial）
        } else if (f.fieldType == FieldType.Checkbox) {
          if (name.contains('important') || name.contains('重要')) {
            final v = await _getCheckbox(f);
            print('    ⭐ [enrichFromCells] 读取重要字段 "${f.name}": $v');
            if (v != null) {
              enriched = enriched.copyWith(isImportant: v);
              print('    ✅ [enrichFromCells] 更新了重要: $v');
            }
          }
        } else if (f.fieldType == FieldType.Number) {
          // 可按需扩展，如 priority/repeatType 等
          continue;
        } else if (f.fieldType == FieldType.SingleSelect ||
            f.fieldType == FieldType.MultiSelect) {
          // 可按需解析 SelectOptionCellDataPB 获取选项名称列表
          continue;
        }
      } catch (e) {
        print('    ❌ [enrichFromCells] 处理字段 "${f.name}" 时出错: $e');
      }
    }
    
    print('    ✅ [enrichFromCells] 数据丰富完成');

    return enriched;
  }

  // 移除提醒
  void _removeReminder(String reminderId) async {
    try {
      final reminderBloc = getIt<ReminderBloc>();
      reminderBloc.add(ReminderEvent.removeReminder(reminderId: reminderId));
    } catch (e) {}
  }

  /// 每周重复 + 跨日历多日：求 target 落在哪一周期的「锚点日」（与原始开始日同星期几）
  DateTime? _weeklySpanOccurrenceAnchor(ScheduleItem schedule, DateTime targetDate) {
    final t = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final sd = DateTime(
      schedule.startTime.year,
      schedule.startTime.month,
      schedule.startTime.day,
    );
    final ed = DateTime(
      schedule.endTime.year,
      schedule.endTime.month,
      schedule.endTime.day,
    );
    final spanDays = ed.difference(sd).inDays + 1;
    if (spanDays < 1) return null;

    var anchorWeekday = schedule.startTime.weekday;
    if (schedule.repeatRuleJson != null && schedule.repeatRuleJson!.isNotEmpty) {
      try {
        final m = jsonDecode(schedule.repeatRuleJson!) as Map<String, dynamic>;
        final wd = m['weekdays'] as List<dynamic>?;
        if (wd != null && wd.isNotEmpty) {
          anchorWeekday = (wd.first as int) + 1;
        }
      } catch (_) {}
    }

    for (var back = 0; back < spanDays; back++) {
      final cand = t.subtract(Duration(days: back));
      if (cand.weekday != anchorWeekday) continue;
      final lastDay = cand.add(Duration(days: spanDays - 1));
      if (t.isBefore(cand) || t.isAfter(lastDay)) continue;
      final diffDays = cand.difference(sd).inDays;
      if (diffDays % 7 != 0) continue;
      return DateTime(cand.year, cand.month, cand.day);
    }
    return null;
  }

  // 获取指定日期的日程（支持重复规则展开）
  List<ScheduleItem> getSchedulesForDate(DateTime date) {
    final result = <ScheduleItem>[];
    final targetDate = DateTime(date.year, date.month, date.day);

    for (final schedule in _schedules) {
      final scheduleStartDate = DateTime(
        schedule.startTime.year,
        schedule.startTime.month,
        schedule.startTime.day,
      );
      final scheduleEndDate = DateTime(
        schedule.endTime.year,
        schedule.endTime.month,
        schedule.endTime.day,
      );

      final isInRange = (targetDate.isAtSameMomentAs(scheduleStartDate) ||
              targetDate.isAfter(scheduleStartDate)) &&
          (targetDate.isAtSameMomentAs(scheduleEndDate) ||
              targetDate.isBefore(scheduleEndDate));

      // 每周重复：按「整段跨天」为周期，锚点=开始日星期几；避免 3/20 既显示 3/19 段又生成 3/20 新段
      if (schedule.repeatType == 2) {
        final anchor = _weeklySpanOccurrenceAnchor(schedule, targetDate);
        if (anchor == null) continue;
        final isOriginalSeries = anchor.year == scheduleStartDate.year &&
            anchor.month == scheduleStartDate.month &&
            anchor.day == scheduleStartDate.day;
        if (isOriginalSeries) {
          if (!targetDate.isBefore(scheduleStartDate) &&
              !targetDate.isAfter(scheduleEndDate)) {
            result.add(schedule);
          }
        } else {
          final adjustedStart =
              _adjustTimeForRecurrence(schedule.startTime, anchor);
          final adjustedEnd = _preserveDuration(
              schedule.startTime, anchor, schedule.endTime);
          result.add(schedule.copyWith(
            id: '${schedule.id}_${anchor.year}_${anchor.month}_${anchor.day}',
            startTime: adjustedStart,
            endTime: adjustedEnd,
          ));
        }
        continue;
      }

      if (schedule.repeatType == 0) {
        if (isInRange) result.add(schedule);
        continue;
      }

      if (isInRange) {
        result.add(schedule);
      }

      final rule = RecurrenceRule(
        repeatType: schedule.repeatType,
        repeatRuleJson: schedule.repeatRuleJson,
        startDate: schedule.startTime,
      );

      if (rule.matchesDate(targetDate)) {
        // 目标日已在原始日程的任一天内：只显示原始记录，勿再生成从 target 起的新虚拟段
        if (isInRange) continue;
        final adjustedStartTime =
            _adjustTimeForRecurrence(schedule.startTime, targetDate);
        final adjustedEndTime = _preserveDuration(
            schedule.startTime, targetDate, schedule.endTime);
        result.add(schedule.copyWith(
          id: '${schedule.id}_${date.year}_${date.month}_${date.day}',
          startTime: adjustedStartTime,
          endTime: adjustedEndTime,
        ));
      }
    }

    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  // 调整重复日程的时间
  DateTime _adjustTimeForRecurrence(DateTime originalTime, DateTime targetDate) {
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      originalTime.hour,
      originalTime.minute,
      originalTime.second,
      originalTime.millisecond,
      originalTime.microsecond,
    );
  }

  // 计算重复实例的结束时间：保持原始日程的时长不变
  // 例如：原始日程 3/15 10:00 → 3/25 12:00（持续10天+2小时）
  // 生成 3/22 的重复实例：3/22 10:00 → 4/1 12:00（保持相同时长）
  DateTime _preserveDuration(DateTime startTime, DateTime targetStartDate, DateTime originalEndTime) {
    final originalDuration = originalEndTime.difference(startTime);
    final adjustedStart = _adjustTimeForRecurrence(startTime, targetStartDate);
    return adjustedStart.add(originalDuration);
  }

  // 已创建的重复实例记录，防止重复创建
  // Key: 原始日程ID, Value: 已创建实例的目标日期集合
  final Map<String, Set<String>> _createdRepeatInstances = {};

  /// 为指定日期创建缺失的重复实例（自动补全历史重复）
  /// 当用户访问过去日期时，从日程开始日期起，回溯扫描每一天，
  /// 将所有匹配重复规则且尚未创建的实例批量创建到数据库
  Future<int> createMissingRepeatInstancesForDate(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    // 只处理今天及之前的日期
    if (targetDate.isAfter(todayDateOnly)) {
      return 0;
    }

    int createdCount = 0;

    for (final schedule in _schedules) {
      // 只处理有重复规则的日程
      if (schedule.repeatType == 0) {
        continue;
      }

      final scheduleStartDateOnly = DateTime(
        schedule.startTime.year,
        schedule.startTime.month,
        schedule.startTime.day,
      );

      // 跳过目标日期在日程开始日期之前的情况
      if (targetDate.isBefore(scheduleStartDateOnly)) {
        continue;
      }

      // 🔧 关键：从日程开始日期 + 1天 开始，逐日回溯扫描到目标日期
      // 这样可以发现并创建从开始日期到目标日期之间所有缺失的重复实例
      final rule = RecurrenceRule(
        repeatType: schedule.repeatType,
        repeatRuleJson: schedule.repeatRuleJson,
        startDate: schedule.startTime,
      );

      // 从 schedule.startDate 的下一天开始扫描（开始日本身就是原始日程，不需要创建重复实例）
      var scanDate = scheduleStartDateOnly.add(const Duration(days: 1));
      while (!scanDate.isAfter(targetDate)) {
        // 检查该日期是否匹配重复规则
        if (rule.matchesDate(scanDate)) {
          // 生成唯一标识符，与 getSchedulesForDate 中的虚拟实例 ID 格式保持一致
          final instanceKey = '${schedule.id}_${scanDate.year}_${scanDate.month}_${scanDate.day}';
          _createdRepeatInstances[schedule.id] ??= {};
          if (!_createdRepeatInstances[schedule.id]!.contains(instanceKey)) {
            // 计算该重复实例的时间
            final adjustedStartTime = _adjustTimeForRecurrence(schedule.startTime, scanDate);
            // 保持原始日程的时长不变
            final adjustedEndTime = _preserveDuration(
                schedule.startTime, scanDate, schedule.endTime);

            try {
              // 创建实际的重复实例到数据库
              final newId = await createSchedule(
                title: schedule.title,
                description: schedule.description,
                startTime: adjustedStartTime,
                endTime: adjustedEndTime,
                isImportant: schedule.isImportant,
                category: schedule.category,
                color: schedule.color,
                isAllDay: schedule.isAllDay,
                reminderOption: ReminderOption.none, // 重复实例不继承提醒
              );

              if (newId != null && newId.isNotEmpty) {
                _createdRepeatInstances[schedule.id]!.add(instanceKey);
                createdCount++;
                print('✅ [ScheduleModel] 已为 $scanDate 创建重复实例: ${schedule.title} (ID: $newId)');
              }
            } catch (e) {
              print('❌ [ScheduleModel] 创建重复实例失败: $e');
            }
          }
        }
        scanDate = scanDate.add(const Duration(days: 1));
      }
    }

    if (createdCount > 0) {
      // 刷新日程列表以加载新创建的实例
      await refresh();
    }

    return createdCount;
  }

  /// 加载指定日期时自动创建缺失的重复实例
  Future<void> loadDateWithAutoCreate(DateTime date) async {
    await createMissingRepeatInstancesForDate(date);
  }

  // 获取日期范围内的日程
  List<ScheduleItem> getSchedulesInRange(DateTime start, DateTime end) {
    return _schedules.where((schedule) {
      return schedule.startTime.isAfter(start.subtract(Duration(days: 1))) &&
             schedule.startTime.isBefore(end.add(Duration(days: 1)));
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  // 切换日程完成状态（现在基于时间自动判断，此方法用于UI兼容性）
  Future<bool> toggleScheduleCompletion(String scheduleId) async {
    // 由于完成状态现在基于时间自动计算，这里只是触发UI更新
    // 实际的完成状态由 isCompleted getter 根据当前时间和结束时间计算
    try {
      if (!_isDisposed) {
        notifyListeners(); // 触发UI更新以反映最新的完成状态
      }
      return true;
    } catch (e) {}
    return false;
  }

  // 获取未完成的日程
  List<ScheduleItem> get incompleteSchedules => 
      _schedules.where((schedule) => !schedule.isCompleted).toList();

  // 获取已完成的日程
  List<ScheduleItem> get completedSchedules => 
      _schedules.where((schedule) => schedule.isCompleted).toList();

  void _setLoading(bool loading) {
    _isLoading = loading;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // 初始化数据库监听器
  Future<void> _initializeDatabaseListener(String viewId) async {
    try {
      // 清理之前的监听器
      _disposeDatabaseListener();
      
      // 获取ViewPB对象
      final viewResult = await ViewBackendService.getView(viewId);
      if (_isDisposed) return;
      await viewResult.fold(
        (view) async {
          if (_isDisposed) return;
          // 正常路径：视图存在
          await _setupDatabaseWithView(view);
        },
        (error) async {
          if (_isDisposed) return;
          // 恢复路径：尝试用相同ID创建孤儿视图（处理在回收站/私有分区/不存在等情况）
          bool recovered = false;
          try {
            final createOrphan = await ViewBackendService.createOrphanView(
              viewId: viewId,
              name: '新建日程日历',
              layoutType: ViewLayoutPB.Calendar,
            );
            if (_isDisposed) return;
            await createOrphan.fold(
              (v) async {
                if (_isDisposed) return;
                await _setupDatabaseWithView(v);
                _currentViewId = v.id;
                if (!_isDisposed) notifyListeners();
                recovered = true;
              },
              (e) async {
                recovered = false;
              },
            );
          } catch (_) {
            recovered = false;
          }

          if (_isDisposed) return;
          // 再次回退：使用固定的新建视图ID创建
          if (!recovered) {
            try {
              final fallbackId = _newScheduleViewId;
              final createFallback = await ViewBackendService.createOrphanView(
                viewId: fallbackId,
                name: '新建日程日历',
                layoutType: ViewLayoutPB.Calendar,
              );
              if (_isDisposed) return;
              await createFallback.fold(
                (v) async {
                  if (_isDisposed) return;
                  await _setupDatabaseWithView(v);
                  _currentViewId = v.id;
                  if (!_isDisposed) notifyListeners();
                },
                (e) async {
                  // 最终失败则静默返回，避免抛异常导致上层未捕获
                },
              );
            } catch (_) {
              // 静默返回
            }
          }
        },
      );
    } catch (e) {
      // 清理失败的状态
      _databaseController = null;
      _databaseCallbacks = null;
      if (_isDisposed) return;
      rethrow; // 重新抛出异常，让调用者知道初始化失败
    }
  }

  // 清理数据库监听器
  void _disposeDatabaseListener() {
    if (_databaseController != null && _databaseCallbacks != null) {
      _databaseController?.removeListener(
          onDatabaseChanged: _databaseCallbacks);
      // 异步清理，避免阻塞
      _databaseController?.dispose().ignore();
    }
    _databaseController = null;
    _databaseCallbacks = null;
  }

  @override
  void dispose() {
    // 防止重复 dispose
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _disposeDatabaseListener();
    super.dispose();
  }
} 

extension _ScheduleModelSetup on ScheduleModel {
  Future<void> _setupDatabaseWithView(ViewPB view) async {
    // 创建数据库控制器
    try {
      _databaseController = DatabaseController(view: view);
    } catch (e) {
      throw Exception('创建数据库控制器失败: $e');
    }

    // 设置数据库回调（延迟刷新，避免初始化时立即触发）
    _databaseCallbacks = DatabaseCallbacks(
      onRowsCreated: (rows) async {
        if (_isDisposed) return;
        print('📢 [ScheduleModel] 数据库回调: onRowsCreated (${rows.length} 行)');
        await refresh();
      },
      onRowsUpdated: (rowIds, reason) async {
        if (_isDisposed) return;
        print(
            '📢 [ScheduleModel] 数据库回调: onRowsUpdated (${rowIds.length} 行, reason: $reason)');
        await refresh();
      },
      onRowsDeleted: (rowIds) async {
        if (_isDisposed) return;
        print('📢 [ScheduleModel] 数据库回调: onRowsDeleted (${rowIds.length} 行)');
        await refresh();
      },
    );

    // 添加监听器
    if (_databaseController != null) {
      _databaseController!.addListener(onDatabaseChanged: _databaseCallbacks);
    }

    // 打开数据库连接
    final openResult = await _databaseController!.open();
    if (_isDisposed) return;
    await openResult.fold(
      (success) async {
        if (_isDisposed) return;
        // 等待字段控制器初始化
        await Future.delayed(const Duration(milliseconds: 150));
        if (_isDisposed) return;
        // 检查字段是否为空（新创建的视图通常没有字段）
        final fieldController = _databaseController?.fieldController;
        if (fieldController != null && fieldController.fieldInfos.isEmpty) {
          await _ensureMinimumFields(view.id);
          if (_isDisposed) return;
          await Future.delayed(const Duration(milliseconds: 200));
        }
      },
      (error) {
        throw Exception('无法打开数据库连接: $error');
      },
    );
  }
}
