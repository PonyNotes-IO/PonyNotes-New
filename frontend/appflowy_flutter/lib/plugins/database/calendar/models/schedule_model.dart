import 'dart:convert';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
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

  RecurrenceRule({
    required this.repeatType,
    this.repeatRuleJson,
    required this.startDate,
  });

  // 判断某个日期是否匹配重复规则
  bool matchesDate(DateTime date) {
    if (repeatType == 0) {
      return false;
    }

    final dateOnly = _getDateOnly(date);
    final startDateOnly = _getDateOnly(startDate);

    // 如果日期在原始日期之前，不匹配
    if (dateOnly.isBefore(startDateOnly)) {
      return false;
    }

    switch (repeatType) {
      case 1: // 每天
        return true;

      case 2: // 每周
        // 每周的同一星期几
        final matches = date.weekday == startDate.weekday;
        print('    📅 [RecurrenceRule] 每周匹配: 目标日期 weekday=${date.weekday}, 开始日期 weekday=${startDate.weekday}, 匹配=$matches');
        return matches;

      case 3: // 每年
        // 每年的同月同日
        return date.month == startDate.month &&
            date.day == startDate.day;

      case 4: // 法定工作日（需要节假日库）
        // 跳过周末
        if (date.weekday == 6 || date.weekday == 7) {
          return false;
        }
        // TODO: 检查法定节假日（需要节假日数据）
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

      if (unit == 1 && weekdays != null && weekdays.isNotEmpty) {
        // 每周的特定星期几
        // 注意：自定义对话框保存的 weekday 索引为 0..6（周一..周日），
        // 而 DateTime.weekday 为 1..7（周一..周日）。需要做 +1 映射。
        final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
        if (!weekdayList.contains(date.weekday)) {
          return false;
        }

        // 计算间隔周数
        final dateOnly = _getDateOnly(date);
        final startDateOnly = _getDateOnly(startDate);
        final daysDiff = dateOnly.difference(startDateOnly).inDays;
        
        // 如果间隔为1，只要星期几匹配且日期在开始日期之后即可
        if (interval == 1) {
          return daysDiff >= 0;
        }
        
        // 对于间隔大于1的情况，需要计算周数差是否能被间隔整除
        // 找到第一个匹配的星期几（从开始日期所在周开始）
        final weeksDiff = daysDiff ~/ 7;
        return weeksDiff >= 0 && weeksDiff % interval == 0;
      }

      // TODO: 处理其他自定义规则（每月、每年等）


      return false;
    } catch (e) {
      print('⚠️ [RecurrenceRule] 解析自定义规则失败: $e');
      return false;
    }
  }

  // 获取日期部分（去除时分秒）
  DateTime _getDateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
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
    if (_currentViewId == viewId) {
      print('⏸️ [ScheduleModel] setViewId() 跳过：视图ID未变化 ($viewId)');
      return;
    }
    
    print('🔄 [ScheduleModel] setViewId() 切换到新视图: $viewId');
    _currentViewId = viewId;
    notifyListeners();
    
    // 初始化数据库监听器（异步，不等待完成）
    _initializeDatabaseListener(viewId).then((_) {
      // 监听器初始化完成后再刷新数据，避免重复调用
      print('✅ [ScheduleModel] 数据库监听器初始化完成，开始刷新数据');
      refresh();
    }).catchError((e) {
      print('❌ [ScheduleModel] 数据库监听器初始化失败: $e');
      // 即使初始化失败，也尝试刷新一次
      refresh();
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
    // 如果正在加载，直接返回
    if (_isLoading) {
      print('⏸️ [ScheduleModel] refresh() 跳过：正在加载中');
      return;
    }
    
    // 防抖：如果距离上次刷新时间太短，跳过
    final now = DateTime.now();
    if (_lastRefreshAt != null && 
        now.difference(_lastRefreshAt!) < _refreshThrottleDuration) {
      print(
          '⏸️ [ScheduleModel] refresh() 跳过：距离上次刷新仅 ${now.difference(_lastRefreshAt!).inMilliseconds}ms');
      return;
    }
    
    // 如果已有待处理的刷新请求，等待它完成
    if (_refreshFuture != null) {
      print('⏸️ [ScheduleModel] refresh() 跳过：已有待处理的刷新请求');
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
    // 如果已经在加载，直接返回
    if (_isLoading) {
      print('⏸️ [ScheduleModel] _loadSchedulesFromDatabase() 跳过：正在加载中');
      return;
    }
    
    _setLoading(true);
    
    try {
      // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
      final viewId = _currentViewId ?? _newScheduleViewId;
      print('📋 [ScheduleModel] 开始加载日程数据, viewId: $viewId');
      
      // 获取所有日历事件
      final payload = CalendarEventRequestPB.create()..viewId = viewId;
      final result = await DatabaseEventGetAllCalendarEvents(payload).send();
      
      await result.fold(
        (events) async {
          print('📋 [ScheduleModel] 从数据库获取到 ${events.items.length} 个事件');
          
          // 先构建最小集，再用 cells 补齐其它字段
          try {
            await _ensureDatabaseReadyInternal(viewId);
          } catch (_) {}

          final fieldInfos =
              _databaseController?.fieldController.fieldInfos ?? [];
          print('📋 [ScheduleModel] 数据库字段数量: ${fieldInfos.length}');
          for (final f in fieldInfos) {
            print(
                '  - 字段: ${f.name} (${f.fieldType.toString().split('.').last}), ID: ${f.field.id}');
          }
          
          final Map<String, FieldInfo> fieldById = {
            for (final f in fieldInfos) f.field.id: f,
          };

          final newSchedules = <ScheduleItem>[];
          for (int i = 0; i < events.items.length; i++) {
            final eventPB = events.items[i];
            print('\n📅 [ScheduleModel] 处理日程 #${i + 1}/${events.items.length}');
            print('  - 行ID: ${eventPB.rowMeta.id}');
            print('  - 日期字段ID: ${eventPB.dateFieldId}');
            print('  - 标题: ${eventPB.title}');
            print('  - 时间戳: ${eventPB.timestamp}');
            
            var item = ScheduleItem.fromCalendarEventPB(eventPB);
            print('  📦 初始 ScheduleItem:');
            print('    - ID: ${item.id}');
            print('    - 标题: ${item.title}');
            print('    - 描述: ${item.description}');
            print('    - 开始时间: ${item.startTime}');
            print('    - 结束时间: ${item.endTime}');
            print('    - 全天: ${item.isAllDay}');
            print('    - 重要: ${item.isImportant}');
            print('    - 分类: ${item.category}');
            print('    - 提醒ID: ${item.reminderId}');
            print('    - 提醒选项: ${item.reminderOption}');
            print('    - 重复类型: ${item.repeatType}');
            print('    - 重复规则: ${item.repeatRuleJson}');
            
            if (fieldInfos.isNotEmpty) {
              try {
                print('  🔄 开始从 cells 丰富数据...');
                item = await _enrichFromCells(
                    viewId, fieldInfos, fieldById, item, eventPB);
                print('  ✅ 丰富后的 ScheduleItem:');
                print('    - ID: ${item.id}');
                print('    - 标题: ${item.title}');
                print('    - 描述: ${item.description}');
                print('    - 开始时间: ${item.startTime}');
                print('    - 结束时间: ${item.endTime}');
                print('    - 全天: ${item.isAllDay}');
                print('    - 重要: ${item.isImportant}');
                print('    - 分类: ${item.category}');
                print('    - 提醒ID: ${item.reminderId}');
                print('    - 提醒选项: ${item.reminderOption}');
                print('    - 截止日期: ${item.dueDate}');
                print('    - 重复类型: ${item.repeatType}');
                print('    - 重复规则: ${item.repeatRuleJson}');
              } catch (e, stackTrace) {
                print('  ❌ 丰富数据时出错: $e');
                print('  📍 堆栈: $stackTrace');
              }
            }
            newSchedules.add(item);
          }

          print('\n📋 [ScheduleModel] 加载完成，共 ${newSchedules.length} 个日程');
          _schedules.clear();
          _schedules.addAll(newSchedules);

          if (!_isDisposed) {
            notifyListeners();
          }
        },
        (error) {
          print('❌ [ScheduleModel] 加载日程失败: ${error.msg}');
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
          // 视图已存在，设置视图ID并初始化数据库监听器
          _currentViewId = _newScheduleViewId;
          notifyListeners();
          
          // 初始化数据库监听器（确保 _databaseController 被创建）
          try {
            await _initializeDatabaseListener(_newScheduleViewId);
            return true;
          } catch (e) {
            print('⚠️ [ScheduleModel] initializeCalendarView 初始化数据库监听器失败: $e');
            return false;
          }
        },
        (error) async {
          // 视图不存在，需要创建新视图
          final createResult = await ViewBackendService.createOrphanView(
            viewId: _newScheduleViewId,
            name: '新建日程日历',
            layoutType: ViewLayoutPB.Calendar,
          );
          
          return createResult.fold(
            (view) async {
              _currentViewId = _newScheduleViewId;
              notifyListeners();
              
              // 初始化数据库监听器（确保 _databaseController 被创建）
              try {
                await _initializeDatabaseListener(_newScheduleViewId);
                return true;
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
          
          // 现在需要设置结束时间到日期字段
          // 查找第一个日期时间字段（避免使用 firstOrNull 以兼容性更好）
          FieldInfo? dateField;
          for (final f in fieldInfos) {
            if (f.fieldType == FieldType.DateTime) {
              dateField = f;
              break;
            }
          }
          
          // 将 dateService 定义在更外层，以便后续提醒处理可以使用
          DateCellBackendService? dateService;
          if (dateField != null) {
          print('📅 [ScheduleModel] createSchedule 找到日期字段: ${dateField.name} (${dateField.field.id})');
            dateService = DateCellBackendService(
              viewId: viewId,
              fieldId: dateField.field.id,
              rowId: rowMeta.id,
            );
        } else {
          print('⚠️ [ScheduleModel] createSchedule 未找到日期字段，无法设置提醒');
        }
            
        // 更新日期字段（如果 dateService 已初始化）
        if (dateService != null) {
            try {
              // 使用 DateCellBackendService 设置日期
              // 全天事件：isRange=false, includeTime=false，只保存日期，不传 endDate
              // 非全天事件：isRange=true, includeTime=true，保存日期和时间范围
            print('📅 [ScheduleModel] createSchedule 更新日期字段');
              final updateResult = await dateService.update(
                date: isAllDayEvent ? startTime.withoutTime : startTime,
                endDate: isAllDayEvent ? null : endTime, // 全天不传 endDate
                isRange: !isAllDayEvent, // 全天为 false，非全天为 true
                includeTime: !isAllDayEvent, // 全天为 false，非全天为 true
              );
              
              updateResult.fold(
              (_) => print('✅ [ScheduleModel] createSchedule 日期字段更新成功'),
              (error) => print('⚠️ [ScheduleModel] createSchedule 日期字段更新失败: $error'),
              );
            } catch (e) {
            print('⚠️ [ScheduleModel] createSchedule 更新日期单元格失败: $e');
            }
          }

          // 对除日期范围外的其他字段，按照编辑器逻辑逐一更新到单元格
          for (final field in fieldInfos) {
            final name = field.name.toLowerCase();
            try {
            if (field.fieldType == FieldType.RichText &&
                name.contains('description')) {
                await CellBackendService.updateCell(
                  viewId: viewId,
                cellContext:
                    CellContext(fieldId: field.field.id, rowId: rowMeta.id),
                  data: description,
                );
            } else if (field.fieldType == FieldType.Checkbox &&
                (name.contains('important') || name.contains('重要'))) {
                await CellBackendService.updateCell(
                  viewId: viewId,
                cellContext:
                    CellContext(fieldId: field.field.id, rowId: rowMeta.id),
                  data: isImportant ? "Yes" : "No",
                );
            } else if (field.fieldType == FieldType.RichText &&
                (name.contains('category') || name.contains('分类'))) {
                await CellBackendService.updateCell(
                  viewId: viewId,
                cellContext:
                    CellContext(fieldId: field.field.id, rowId: rowMeta.id),
                  data: category,
                );
              }
              // 注意：提醒选项不再保存到单独的字段中，而是通过日期单元格的 reminderId 处理
              // 这与 calendar_event_editor 的处理方式一致
            } catch (e) {
              print('⚠️ [ScheduleModel] createSchedule 更新字段 "${field.name}" 失败: $e');
            }
          }
          
          // 单独处理重复字段：确保字段存在后再保存
          try {
            print('🔁 [ScheduleModel] createSchedule 开始保存重复信息');
            print('  - repeatType: $repeatType');
            print('  - repeatRuleJson: $repeatRuleJson');
            
            // 确保重复字段存在
            final repeatField = await _ensureRepeatField(viewId, fieldInfos);
            if (repeatField != null) {
              // 保存重复信息到数据库
              final repeatData = repeatType != 0 ? jsonEncode({
                'repeatType': repeatType,
                'repeatRuleJson': repeatRuleJson ?? '',
              }) : '';
              
              print('  - 重复数据JSON: $repeatData');
              
              final updateResult = await CellBackendService.updateCell(
                viewId: viewId,
                cellContext:
                    CellContext(fieldId: repeatField.field.id, rowId: rowMeta.id),
                data: repeatData,
              );
              
              updateResult.fold(
                (_) {
                  print('✅ [ScheduleModel] createSchedule 重复信息保存成功');
                },
                (error) {
                  print('❌ [ScheduleModel] createSchedule 重复信息保存失败: ${error.msg}');
                },
              );
            } else {
              print('⚠️ [ScheduleModel] createSchedule 无法创建或找到重复字段');
            }
          } catch (e, stackTrace) {
            print('❌ [ScheduleModel] createSchedule 保存重复信息异常: $e');
            print('📍 堆栈: $stackTrace');
          }
          
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
          
          // 如果设置了提醒选项，先写入日期单元格的 reminderId，再创建系统提醒
        print('🔔 [ScheduleModel] createSchedule 检查提醒设置:');
        print('  - reminderOption: $reminderOption');
        print('  - dateService: ${dateService != null ? "已初始化" : "未初始化"}');
        print('  - isAllDayEvent: $isAllDayEvent');
        
          if (reminderOption != ReminderOption.none && dateService != null) {
            final reminderId = nanoid();
          print('🔔 [ScheduleModel] createSchedule 开始创建提醒: $reminderId');
            try {
              // 先将 reminderId 写入日期单元格
            print('  📝 写入 reminderId 到日期单元格: $reminderId');
            final reminderUpdateResult = await dateService.update(reminderId: reminderId);
            reminderUpdateResult.fold(
              (_) => print('  ✅ reminderId 写入成功'),
              (error) => print('  ❌ reminderId 写入失败: $error'),
            );

            // 计算提醒时间
            final baseTime = isAllDayEvent ? startTime.withoutTime : startTime;
            final scheduledAt = reminderOption.getNotificationDateTime(baseTime);
            print('  ⏰ 提醒时间计算:');
            print('    - 基础时间: $baseTime');
            print('    - 提醒选项: $reminderOption');
            print('    - 计算后的提醒时间: $scheduledAt');

            // 创建系统提醒（与 DateCellEditorBloc 和 updateSchedule 逻辑一致）
            print('  📢 创建 ReminderBloc 提醒事件');
              final reminderBloc = getIt<ReminderBloc>();
            final includeTime = !isAllDayEvent;
            final dateForMeta = isAllDayEvent ? startTime.withoutTime : startTime;
            print('  📋 提醒元数据:');
            print('    - includeTime: $includeTime');
            print('    - rowId: ${rowMeta.id}');
            print('    - date: $dateForMeta');
            print('    - scheduledAt: $scheduledAt');
            
              reminderBloc.add(
                ReminderEvent.addById(
                  reminderId: reminderId,
                  objectId: viewId,
                  meta: {
                  ReminderMetaKeys.includeTime: includeTime.toString(),
                  ReminderMetaKeys.rowId: rowMeta.id,
                  ReminderMetaKeys.date: dateForMeta.millisecondsSinceEpoch.toString(),
                  },
                  scheduledAt: Int64(
                  scheduledAt.millisecondsSinceEpoch ~/ 1000,
                  ),
                ),
              );

            // 等待 ReminderBloc 状态落地，避免刷新读取旧值
            print('  ⏳ 等待 ReminderBloc 状态落地...');
            await _waitReminderUpdated(reminderId, scheduledAt);
            print('  ✅ ReminderBloc 状态已落地');
              
              // 更新本地 ScheduleItem 的 reminderId
            final updatedSchedule =
                newSchedule.copyWith(reminderId: reminderId);
              final index = _schedules.indexWhere((s) => s.id == rowMeta.id);
              if (index != -1) {
                _schedules[index] = updatedSchedule;
              if (!_isDisposed) {
                notifyListeners(); // 立即通知UI更新
              }
              print('  ✅ 本地 ScheduleItem 已更新 reminderId: $reminderId');
            } else {
              print('  ⚠️ 本地列表中未找到日程，无法更新 reminderId');
            }
            print('✅ [ScheduleModel] createSchedule 创建提醒成功: $reminderId');
          } catch (e, stackTrace) {
            print('⚠️ [ScheduleModel] createSchedule 设置提醒失败: $e');
            print('  📍 堆栈: $stackTrace');
          }
        } else {
          if (reminderOption == ReminderOption.none) {
            print('ℹ️ [ScheduleModel] createSchedule 提醒选项为 none，跳过提醒创建');
          } else if (dateService == null) {
            print('⚠️ [ScheduleModel] createSchedule dateService 为 null，无法创建提醒');
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

  // 确保重复字段存在（如果不存在则创建）
  Future<FieldInfo?> _ensureRepeatField(String viewId, List<FieldInfo> fieldInfos) async {
    // 先查找是否已存在重复字段
    try {
      final existingRepeatField = fieldInfos.firstWhere(
        (f) {
          final name = f.name.toLowerCase();
          return f.fieldType == FieldType.RichText && 
                 (name.contains('repeat') || name.contains('重复'));
        },
      );
      // 如果找到了，直接返回
      print('✅ [ScheduleModel] 找到已存在的重复字段: ${existingRepeatField.name}');
      return existingRepeatField;
    } catch (_) {
      // 字段不存在，需要创建
      print('📋 [ScheduleModel] 重复字段不存在，开始创建...');
      try {
        final createResult = await FieldBackendService.createField(
          viewId: viewId,
          fieldType: FieldType.RichText,
          fieldName: 'Repeat',
        );
        
        return createResult.fold(
          (field) {
            print('✅ [ScheduleModel] 重复字段创建成功: ${field.name} (${field.id})');
            // 创建字段后，等待一小段时间让后端同步
            // 然后从后端重新获取字段列表，确保字段信息完整
            return FieldInfo.initial(field);
          },
          (error) {
            print('❌ [ScheduleModel] 重复字段创建失败: ${error.msg}');
            return null;
          },
        );
      } catch (e, stackTrace) {
        print('❌ [ScheduleModel] 创建重复字段异常: $e');
        print('📍 堆栈: $stackTrace');
        return null;
      }
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
      
      // 分别跟踪关键字段和可选字段的更新状态
      bool hasCriticalErrors = false; // 关键字段（标题、日期）更新失败
      bool hasOptionalErrors = false; // 可选字段（描述、重要标记）更新失败
      
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
            print('✅ [ScheduleModel] updateSchedule 标题更新成功');
          },
          (error) {
            hasCriticalErrors = true;
            print('❌ [ScheduleModel] updateSchedule 标题更新失败: ${error.msg}');
          },
        );
      } else {
        titleUpdated = true; // 如果没有标题字段，跳过
      }
      
      // 查找并更新日期时间字段（关键字段）
      bool dateUpdated = false;
      DateCellBackendService? dateService;
      
      // 提前获取当前的 reminderId：优先从传入的 schedule 获取，如果为空则从本地列表获取
      // 传入的 schedule.reminderId 应该是从数据库加载的最新值（通过 _enrichFromCells）
      String? existingReminderId;
      final currentScheduleInList =
          _schedules.firstWhereOrNull((s) => s.id == schedule.id);

      // 优先使用传入的 schedule.reminderId（应该是数据库中的最新值）
      if (schedule.reminderId != null && schedule.reminderId!.isNotEmpty) {
        existingReminderId = schedule.reminderId;
      } else if (currentScheduleInList?.reminderId != null &&
          currentScheduleInList!.reminderId!.isNotEmpty) {
        existingReminderId = currentScheduleInList.reminderId;
      }

      print('🔍 [ScheduleModel] updateSchedule 获取 reminderId:');
      print('  - 传入的 schedule.reminderId: ${schedule.reminderId}');
      print('  - 本地列表中的 reminderId: ${currentScheduleInList?.reminderId}');
      print('  - 使用的 existingReminderId: $existingReminderId');
      
      for (var field in fieldInfos) {
        if (field.fieldType == FieldType.DateTime) {
          try {
            dateService = DateCellBackendService(
              viewId: viewId,
              fieldId: field.field.id,
              rowId: schedule.id,
            );
            
            // 判断是否为全天事件：使用 schedule.isAllDay 或根据时间判断
            final isAllDayEvent = schedule.isAllDay ||
                ScheduleItem._isAllDayEvent(
              startTime: schedule.startTime,
              endTime: schedule.endTime,
            );
            
            print('📅 [ScheduleModel] updateSchedule 更新日期字段:');
            print('  - 全天事件: $isAllDayEvent');
            print('  - 开始时间: ${schedule.startTime}');
            print('  - 结束时间: ${schedule.endTime}');
            print('  - 提醒选项: ${schedule.reminderOption}');
            print('  - 当前 reminderId: $existingReminderId');
            
            // 重要：更新日期字段时，不传入 reminderId 参数（与 DateCellEditorBloc._updateDateData 逻辑一致）
            // DateCellEditorBloc 在更新日期时不会更新 reminderId，reminderId 只在创建/删除提醒时更新
            // 这样可以避免意外覆盖或清空现有的 reminderId
            final updateResult = await dateService.update(
              date: isAllDayEvent
                  ? schedule.startTime.withoutTime
                  : schedule.startTime,
              endDate: isAllDayEvent ? null : schedule.endTime, // 全天不传 endDate
              isRange: !isAllDayEvent, // 全天为 false，非全天为 true
              includeTime: !isAllDayEvent, // 全天为 false，非全天为 true
              // 不传入 reminderId，让现有的 reminderId 保持不变
            );
            
            updateResult.fold(
              (_) {
                dateUpdated = true;
                print('✅ [ScheduleModel] updateSchedule 日期字段更新成功');
              },
              (error) {
                hasCriticalErrors = true;
                print(
                    '❌ [ScheduleModel] updateSchedule 日期字段更新失败: ${error.msg}');
              },
            );
          } catch (e, stackTrace) {
            hasCriticalErrors = true;
            print('❌ [ScheduleModel] updateSchedule 日期字段更新异常: $e');
            print('📍 堆栈: $stackTrace');
          }
          break; // 只更新第一个日期字段
        }
      }
      
      // 更新可选字段（描述、重要标记等）
      for (var field in fieldInfos) {
        try {
          // 更新描述字段
          if (field.fieldType == FieldType.RichText && 
              field.name.toLowerCase().contains('description')) {
            final result = await CellBackendService.updateCell(
              viewId: viewId,
              cellContext: CellContext(
                fieldId: field.field.id,
                rowId: schedule.id,
              ),
              data: schedule.description,
            );
            
            result.fold(
              (_) {
                print('✅ [ScheduleModel] updateSchedule 描述字段更新成功');
              },
              (error) {
                hasOptionalErrors = true;
                print(
                    '⚠️ [ScheduleModel] updateSchedule 描述字段更新失败: ${error.msg}');
              },
            );
          }
          // 更新重要字段
          else if (field.fieldType == FieldType.Checkbox && 
                   (field.name.toLowerCase().contains('important') || 
                    field.name.toLowerCase().contains('重要'))) {
            final result = await CellBackendService.updateCell(
              viewId: viewId,
              cellContext: CellContext(
                fieldId: field.field.id,
                rowId: schedule.id,
              ),
              data: schedule.isImportant ? "Yes" : "No",
            );
            
            result.fold(
              (_) {
                print('✅ [ScheduleModel] updateSchedule 重要字段更新成功');
              },
              (error) {
                hasOptionalErrors = true;
                print(
                    '⚠️ [ScheduleModel] updateSchedule 重要字段更新失败: ${error.msg}');
              },
            );
          }
          // 更新分类字段
          else if (field.fieldType == FieldType.RichText &&
                   (field.name.toLowerCase().contains('category') || 
                    field.name.toLowerCase().contains('分类'))) {
            final result = await CellBackendService.updateCell(
              viewId: viewId,
              cellContext: CellContext(
                fieldId: field.field.id,
                rowId: schedule.id,
              ),
              data: schedule.category,
            );
            
            result.fold(
              (_) {
                print('✅ [ScheduleModel] updateSchedule 分类字段更新成功');
              },
              (error) {
                hasOptionalErrors = true;
                print(
                    '⚠️ [ScheduleModel] updateSchedule 分类字段更新失败: ${error.msg}');
              },
            );
          }
        } catch (e) {
          hasOptionalErrors = true;
          print(
              '⚠️ [ScheduleModel] updateSchedule 字段 "${field.name}" 更新异常: $e');
        }
      }
      
      // 单独处理重复字段：确保字段存在后再保存
      try {
        print('🔁 [ScheduleModel] updateSchedule 开始更新重复信息');
        print('  - repeatType: ${schedule.repeatType}');
        print('  - repeatRuleJson: ${schedule.repeatRuleJson}');
        
        // 确保重复字段存在
        final repeatField = await _ensureRepeatField(viewId, fieldInfos);
        if (repeatField != null) {
          // 保存重复信息到数据库
          final repeatData = schedule.repeatType != 0 ? jsonEncode({
            'repeatType': schedule.repeatType,
            'repeatRuleJson': schedule.repeatRuleJson ?? '',
          }) : '';
          
          print('  - 重复数据JSON: $repeatData');
          
          final updateResult = await CellBackendService.updateCell(
            viewId: viewId,
            cellContext: CellContext(
              fieldId: repeatField.field.id,
              rowId: schedule.id,
            ),
            data: repeatData,
          );
          
          updateResult.fold(
            (_) {
              print('✅ [ScheduleModel] updateSchedule 重复信息更新成功');
            },
            (error) {
              hasOptionalErrors = true;
              print('❌ [ScheduleModel] updateSchedule 重复信息更新失败: ${error.msg}');
            },
          );
        } else {
          print('⚠️ [ScheduleModel] updateSchedule 无法创建或找到重复字段');
          hasOptionalErrors = true;
        }
      } catch (e, stackTrace) {
        hasOptionalErrors = true;
        print('❌ [ScheduleModel] updateSchedule 更新重复信息异常: $e');
        print('📍 堆栈: $stackTrace');
      }
      
      // 如果关键字段（日期或标题）更新成功，则认为整体更新成功
      // 日期字段是最重要的，如果日期更新成功，即使其他字段失败也返回成功
      if (dateUpdated || titleUpdated) {
        final index = _schedules.indexWhere((s) => s.id == schedule.id);
        // 尽力同步本地列表，但不要把提醒更新依赖于本地是否命中
        if (index != -1) {
          _schedules[index] = schedule;
          }

          // 更新提醒系统（与 DateCellEditorBloc._setReminderOption 逻辑一致）
          try {
            final reminderBloc = getIt<ReminderBloc>();
            // 复用之前获取的 existingReminderId（已经在日期字段更新前获取）
            
            print('🔔 [ScheduleModel] updateSchedule 处理提醒系统');
            print('  - 新的提醒选项: ${schedule.reminderOption}');
            print('  - 本地列表中的 reminderId: ${currentScheduleInList?.reminderId}');
            print('  - 传入的 schedule.reminderId: ${schedule.reminderId}');
            print('  - 使用的 existingReminderId: $existingReminderId');
            
            if (schedule.reminderOption != ReminderOption.none) {
              // 如果设置了提醒选项
              if (existingReminderId == null || existingReminderId.isEmpty) {
                // 如果没有 reminderId，创建新的提醒（与 DateCellEditorBloc 逻辑一致）
                final reminderId = nanoid();
                
                // 先将 reminderId 写入日期单元格
                if (dateService != null) {
                  await dateService.update(reminderId: reminderId);
                }
                
                // 创建系统提醒
                reminderBloc.add(
                  ReminderEvent.addById(
                    reminderId: reminderId,
                    objectId: viewId,
                    meta: {
                      'rowId': schedule.id,
                      'title': schedule.title,
                    },
                    scheduledAt: Int64(
                    schedule.reminderOption
                            .getNotificationDateTime(schedule.startTime)
                            .millisecondsSinceEpoch ~/
                        1000,
                    ),
                  ),
                );
                
              // 等待落地，避免刷新读取旧值
              await _waitReminderUpdated(
                  reminderId,
                  schedule.reminderOption
                      .getNotificationDateTime(schedule.startTime));
                
                // 重要：同步更新本地 ScheduleItem 的 reminderId 和 reminderOption
                final updatedScheduleWithReminder = schedule.copyWith(
                  reminderId: reminderId,
                  reminderOption: schedule.reminderOption, // 使用新的提醒选项
                );
              final reminderIndex =
                  _schedules.indexWhere((s) => s.id == schedule.id);
                if (reminderIndex != -1) {
                  _schedules[reminderIndex] = updatedScheduleWithReminder;
                  if (!_isDisposed) {
                    notifyListeners(); // 立即通知UI更新
                  }
                  print('  ✅ 更新了本地 ScheduleItem 的 reminderId 和 reminderOption');
                }
                
                print('✅ [ScheduleModel] updateSchedule 创建新提醒成功: $reminderId');
              } else {
              // 如果已有 reminderId，更新现有提醒的时间（与 DateCellEditorBloc._setReminderOption 逻辑一致）
              // 注意：DateCellEditorBloc 在更新现有提醒时，不需要再次更新单元格的 reminderId
              // 因为它已经存在了，只需要更新 ReminderBloc 中的提醒时间
                print('🔔 [ScheduleModel] updateSchedule 更新现有提醒时间');
                
              // 使用已经更新后的开始时间来计算提醒时间（与 DateCellEditorBloc 逻辑一致）
              // 注意：这里使用的是 schedule.startTime，应该已经是更新后的时间
              final scheduledAt =
                  schedule.reminderOption.getNotificationDateTime(
                  schedule.startTime,
                );
              print('  - reminderId: $existingReminderId');
                print('  - 新的提醒时间: $scheduledAt');
              print('  - 事件开始时间: ${schedule.startTime}');
                print('  - 包含时间: ${!schedule.isAllDay}');
                
              // 直接更新 ReminderBloc 中的提醒时间（与 DateCellEditorBloc 逻辑一致）
              // 不需要再次更新单元格的 reminderId，因为它在之前的日期字段更新时已经保留了
                reminderBloc.add(
                  ReminderEvent.update(
                    ReminderUpdate(
                      id: existingReminderId,
                      scheduledAt: scheduledAt,
                      includeTime: !schedule.isAllDay,
                    // 同步事件基准时间，便于其他位置基于 meta/日期映射提醒选项
                    date: schedule.startTime,
                    ),
                  ),
                );

              // 等待 ReminderBloc 状态落地，避免随后的 refresh 读取到旧值
              await _waitReminderUpdated(existingReminderId, scheduledAt);
                
                // 重要：同步更新本地 ScheduleItem 的 reminderId 和 reminderOption
                // 这样即使立即刷新，也能显示正确的提醒选项
                final updatedScheduleWithReminder = schedule.copyWith(
                  reminderId: existingReminderId,
                  reminderOption: schedule.reminderOption, // 使用新的提醒选项
                );
              final reminderIndex =
                  _schedules.indexWhere((s) => s.id == schedule.id);
                if (reminderIndex != -1) {
                  _schedules[reminderIndex] = updatedScheduleWithReminder;
                }
                
              print(
                  '✅ [ScheduleModel] updateSchedule 更新提醒时间成功: $existingReminderId');
                print('  - 提醒选项: ${schedule.reminderOption}');
                print('  - 提醒时间: $scheduledAt');
              }
            } else {
              // 如果移除了提醒选项（与 DateCellEditorBloc 逻辑一致）
              if (existingReminderId != null && existingReminderId.isNotEmpty) {
                // 删除系统提醒
                reminderBloc.add(
                  ReminderEvent.removeReminder(reminderId: existingReminderId),
                );
                
                // 清除日期单元格中的 reminderId
                if (dateService != null) {
                  await dateService.update(reminderId: '');
                }
                
                // 重要：同步更新本地 ScheduleItem，清除 reminderId 和 reminderOption
                final updatedScheduleWithoutReminder = schedule.copyWith(
                  reminderId: '',
                  reminderOption: ReminderOption.none, // 清除提醒选项
                );
              final reminderIndex =
                  _schedules.indexWhere((s) => s.id == schedule.id);
                if (reminderIndex != -1) {
                  _schedules[reminderIndex] = updatedScheduleWithoutReminder;
                  if (!_isDisposed) {
                    notifyListeners(); // 立即通知UI更新
                  }
                  print('  ✅ 更新了本地 ScheduleItem，清除了 reminderId 和 reminderOption');
                }
                
              print(
                  '✅ [ScheduleModel] updateSchedule 提醒已移除: $existingReminderId');
              }
            }
          } catch (e, stackTrace) {
            print('⚠️ [ScheduleModel] updateSchedule 更新提醒失败: $e');
            print('📍 堆栈: $stackTrace');
          }
          
          if (hasOptionalErrors) {
            print('⚠️ [ScheduleModel] updateSchedule 部分可选字段更新失败，但关键字段更新成功');
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

      // 从本地列表删除（使用removeWhere更安全）
      final removedCount = _schedules.length;
      _schedules.removeWhere((s) => s.id == scheduleId);
      final newCount = _schedules.length;
      
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
          final pb = DateCellDataParser().parserData(cell.data);
          if (pb == null) return (null, null, null, null, null,0,"");
          DateTime? s;
          DateTime? e;
          bool? includeTime;
          bool? isRange;
          String? reminderId;
          int? repeatType;
          String? repeatCustomSummary;

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
          // 读取 repeatType
          repeatType = pb.repeatType;
          // 读取 repeatCustomSummary
          repeatCustomSummary = pb.repeatRuleJson;
          return (s, e, includeTime, isRange, reminderId,repeatType,repeatCustomSummary);
        },
        (_) => (null, null, null, null, null,0,""),
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
        );
        
        print(
            '    ✅ [enrichFromCells] 更新了开始时间和结束时间: $finalStartTime -> $finalEndTime');
        print(
            '    📅 [enrichFromCells] 全天事件: $isAllDayEvent (includeTime=$includeTime, isRange=$isRange)');
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
          } else if (name.contains('repeat') || name.contains('重复')) {
            // 读取重复信息
            final v = await _getString(f);
            print('    🔁 [enrichFromCells] 读取重复字段 "${f.name}": $v');
            if (v != null && v.isNotEmpty) {
              try {
                final repeatData = jsonDecode(v) as Map<String, dynamic>;
                final repeatType = repeatData['repeatType'] as int? ?? 0;
                final repeatRuleJson = repeatData['repeatRuleJson'] as String?;
                enriched = enriched.copyWith(
                  repeatType: repeatType,
                  repeatRuleJson: repeatRuleJson,
                );
                print('    ✅ [enrichFromCells] 更新了重复信息: repeatType=$repeatType');
              } catch (e) {
                print('    ⚠️ [enrichFromCells] 解析重复信息失败: $e');
              }
            }
          }
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

  // 设置提醒（使用 AppFlowy 提醒系统）
  void _setReminder(ScheduleItem schedule) async {
    try {
      final reminderBloc = getIt<ReminderBloc>();
      final reminderId = schedule.reminderId ?? nanoid();
      
      // 如果schedule没有reminderId，需要更新本地列表中的schedule
      if (schedule.reminderId == null) {
        final updatedSchedule = schedule.copyWith(reminderId: reminderId);
        final index = _schedules.indexWhere((s) => s.id == schedule.id);
        if (index != -1) {
          _schedules[index] = updatedSchedule;
          if (!_isDisposed) {
            notifyListeners();
          }
        }
      }
      
      // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
      final viewId = _currentViewId ?? _newScheduleViewId;
      
      reminderBloc.add(
        ReminderEvent.addById(
          reminderId: reminderId,
          objectId: viewId,
          meta: {
            'rowId': schedule.id,
            'title': schedule.title,
          },
          scheduledAt: Int64(
            schedule.reminderOption
                    .getNotificationDateTime(schedule.startTime)
                    .millisecondsSinceEpoch ~/
                1000,
          ),
        ),
      );
    } catch (e) {}
  }

  // 移除提醒
  void _removeReminder(String reminderId) async {
    try {
      final reminderBloc = getIt<ReminderBloc>();
      reminderBloc.add(ReminderEvent.removeReminder(reminderId: reminderId));
    } catch (e) {}
  }

  // 获取指定日期的日程（支持重复规则展开）
  List<ScheduleItem> getSchedulesForDate(DateTime date) {
    final result = <ScheduleItem>[];
    final targetDate = DateTime(date.year, date.month, date.day);
    
    print('🔍 [ScheduleModel] getSchedulesForDate 查询日期: $targetDate');
    print('  - 总日程数: ${_schedules.length}');

    for (final schedule in _schedules) {
      // 检查是否在原始日期
      final scheduleDate = DateTime(
        schedule.startTime.year,
        schedule.startTime.month,
        schedule.startTime.day,
      );
      final isOriginalDate = scheduleDate.isAtSameMomentAs(targetDate);

      if (isOriginalDate) {
        print('  ✅ 找到原始日期的日程: ${schedule.title} (${schedule.id})');
        result.add(schedule);
        continue;
      }

      // 如果日程设置了重复，检查是否匹配重复规则
      if (schedule.repeatType != 0) {
        print('  🔁 检查重复日程: ${schedule.title}');
        print('    - 开始日期: $scheduleDate');
        print('    - 重复类型: ${schedule.repeatType}');
        print('    - 目标日期: $targetDate');
        
        final rule = RecurrenceRule(
          repeatType: schedule.repeatType,
          repeatRuleJson: schedule.repeatRuleJson,
          startDate: schedule.startTime,
        );

        if (rule.matchesDate(targetDate)) {
          print('    ✅ 匹配重复规则，添加到结果');
          // 创建一个虚拟的日程实例，用于显示
          // 注意：这里的 ID 可以添加日期后缀来区分，但实际编辑时应该使用原始ID
          final adjustedStartTime = _adjustTimeForRecurrence(
              schedule.startTime, targetDate);
          final adjustedEndTime = _adjustTimeForRecurrence(
              schedule.endTime, targetDate);

          result.add(schedule.copyWith(
            id: '${schedule.id}_${date.year}_${date.month}_${date.day}',
            startTime: adjustedStartTime,
            endTime: adjustedEndTime,
          ));
        } else {
          print('    ❌ 不匹配重复规则');
        }
      }
    }

    print('  📋 返回 ${result.length} 个日程');
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

  // 更新数据库中的完成状态
  Future<void> _updateScheduleCompletionInDatabase(
      String scheduleId, bool isCompleted) async {
    try {
      // 使用当前视图ID，如果没有设置则使用默认的新建日程视图ID
      final viewId = _currentViewId ?? _newScheduleViewId;
      
      // TODO: 这里需要找到checkbox类型的字段ID，然后更新单元格数据
      // 目前作为占位符，在实际实现中需要：
      // 1. 获取视图的字段信息
      // 2. 找到类型为Checkbox的字段
      // 3. 使用CellBackendService更新该字段的值
      
      // 暂时不实际更新数据库，避免出错
      // 在需要真正的数据库集成时，这里需要实现具体的更新逻辑
    } catch (e) {}
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
      await viewResult.fold(
        (view) async {
          // 正常路径：视图存在
          await _setupDatabaseWithView(view);
        },
        (error) async {
          // 恢复路径：尝试用相同ID创建孤儿视图（处理在回收站/私有分区/不存在等情况）
          bool recovered = false;
          try {
            final createOrphan = await ViewBackendService.createOrphanView(
              viewId: viewId,
              name: '新建日程日历',
              layoutType: ViewLayoutPB.Calendar,
            );
            await createOrphan.fold(
              (v) async {
                await _setupDatabaseWithView(v);
                _currentViewId = v.id;
                notifyListeners();
                recovered = true;
              },
              (e) async {
                recovered = false;
              },
            );
          } catch (_) {
            recovered = false;
          }

          // 再次回退：使用固定的新建视图ID创建
          if (!recovered) {
            try {
              final fallbackId = _newScheduleViewId;
              final createFallback = await ViewBackendService.createOrphanView(
                viewId: fallbackId,
                name: '新建日程日历',
                layoutType: ViewLayoutPB.Calendar,
              );
              await createFallback.fold(
                (v) async {
                  await _setupDatabaseWithView(v);
                  _currentViewId = v.id;
                  notifyListeners();
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
    await openResult.fold(
      (success) async {
        // 等待字段控制器初始化
        await Future.delayed(const Duration(milliseconds: 150));
        
        // 检查字段是否为空（新创建的视图通常没有字段）
        final fieldController = _databaseController?.fieldController;
        if (fieldController != null && fieldController.fieldInfos.isEmpty) {
          await _ensureMinimumFields(view.id);
          await Future.delayed(const Duration(milliseconds: 200));
        }
      },
      (error) {
        throw Exception('无法打开数据库连接: $error');
      },
    );
  }
}
