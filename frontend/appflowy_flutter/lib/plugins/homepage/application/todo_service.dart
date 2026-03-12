import 'dart:async';
import 'dart:convert';
import 'package:appflowy/plugins/homepage/application/todo_models.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/cell/cell_data_loader.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/calendar_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:flowy_infra/uuid.dart';

class TodoService {
  static TodoService? _instance;
  
  static TodoService get instance => _instance ??= TodoService._();
  
  TodoService._();

  final StreamController<List<TodoItem>> _todosController = StreamController<List<TodoItem>>.broadcast();
  List<TodoItem> _todos = [];
  String? _calendarViewId; // 日历视图ID

  Stream<List<TodoItem>> get todosStream => _todosController.stream;
  List<TodoItem> get todos => List.unmodifiable(_todos);

  Future<void> initialize() async {
    // 初始化日历视图ID
    _calendarViewId = fixedUuid(12345, UuidType.privateSpace);
    // 确保日历视图存在
    await _ensureCalendarViewExists();
    await _loadTodos();
  }

  // 确保日历视图存在
  Future<void> _ensureCalendarViewExists() async {
    if (_calendarViewId == null) return;
    
    try {
      // 先检查视图是否已存在
      final result = await ViewBackendService.getView(_calendarViewId!);
      await result.fold(
        (view) async {
          // 视图已存在，无需操作
        },
        (error) async {
          // 视图不存在，尝试创建
      final createResult = await ViewBackendService.createOrphanView(
            viewId: _calendarViewId!,
            name: 'Todo Calendar View',
            layoutType: ViewLayoutPB.Calendar,
          );
          
          createResult.fold(
            (view) {
              // 视图创建成功
            },
            (createError) {
              // 创建失败，清空视图ID以避免后续错误
              _calendarViewId = null;
            },
          );
        },
      );
    } catch (e) {
      // 异常情况下，清空视图ID
      _calendarViewId = null;
    }
  }

  Future<List<TodoItem>> getAllTodos() async {
    return _loadCalendarTodos();
  }

  /// 按首页展示日期读取待办（日历事件），并展开符合该日期的重复日程。
  Future<List<TodoItem>> getTodosForDate(DateTime displayDate) async {
    final target = DateTime(displayDate.year, displayDate.month, displayDate.day);
    final todos = <TodoItem>[];
    final calendarViewIds = await _resolveCalendarViewIds();

    for (final viewId in calendarViewIds) {
      final payload = CalendarEventRequestPB.create()..viewId = viewId;
      final result = await DatabaseEventGetAllCalendarEvents(payload).send();

      await result.fold(
        (events) async {
          for (final eventPB in events.items) {
            final todo = _convertCalendarEventToTodo(eventPB);
            if (todo == null || todo.dueDate == null) {
              continue;
            }

            final recurrence = await _loadRecurrenceInfo(
              viewId: viewId,
              rowId: eventPB.rowMeta.id,
              dateFieldId: eventPB.dateFieldId,
            );

            final start = todo.dueDate!;
            final isMatch = _matchesDisplayDate(
              start: start,
              target: target,
              repeatType: recurrence.$1,
              repeatRuleJson: recurrence.$2,
            );
            if (!isMatch) {
              continue;
            }

            // 对重复实例，将时间映射到目标展示日期上，保持原有时分。
            final mappedDate = DateTime(
              target.year,
              target.month,
              target.day,
              start.hour,
              start.minute,
              start.second,
              start.millisecond,
              start.microsecond,
            );

            todos.add(
              todo.copyWith(
                dueDate: mappedDate,
                isCompleted: false,
                completedAt: null,
              ),
            );
          }
        },
        (error) async {},
      );
    }

    todos.sort((a, b) {
      final aDate = a.dueDate;
      final bDate = b.dueDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return todos;
  }

  Future<List<TodoItem>> getTodayTodos() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // 合并本地待办和日历日程
    final allTodos = await getAllTodos();
    
    return allTodos.where((todo) {
      if (todo.dueDate == null) return false;
      return todo.dueDate!.isAfter(today.subtract(const Duration(milliseconds: 1))) &&
             todo.dueDate!.isBefore(tomorrow) &&
             !todo.isCompleted;
    }).toList();
  }

  Future<List<TodoItem>> getUpcomingTodos() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextWeek = today.add(const Duration(days: 7));

    // 合并本地待办和日历日程
    final allTodos = await getAllTodos();
    
    return allTodos.where((todo) {
      if (todo.dueDate == null) return false;
      return todo.dueDate!.isAfter(today) &&
             todo.dueDate!.isBefore(nextWeek.add(const Duration(days: 1))) &&
             !todo.isCompleted;
    }).toList();
  }

  Future<List<TodoItem>> getCompletedTodos() async {
    final allTodos = await getAllTodos();
    return allTodos.where((todo) => todo.isCompleted).toList();
  }

  Future<List<TodoItem>> getIncompleteTodos() async {
    final allTodos = await getAllTodos();
    return allTodos.where((todo) => !todo.isCompleted).toList();
  }

  Future<void> addTodo(TodoItem todo) async {
    await _createCalendarTodo(todo);
    await _loadTodos();
    _todosController.add(List.unmodifiable(_todos));
  }

  Future<void> updateTodo(TodoItem updatedTodo) async {
    await _updateCalendarTodo(updatedTodo);
    await _loadTodos();
    _todosController.add(List.unmodifiable(_todos));
  }

  Future<void> deleteTodo(String id) async {
    await _deleteCalendarTodo(id);
    await _loadTodos();
    _todosController.add(List.unmodifiable(_todos));
  }

  Future<void> toggleComplete(String id) async {
    final allTodos = await getAllTodos();
    final index = allTodos.indexWhere((todo) => todo.id == id);
    if (index == -1) return;
    final todo = allTodos[index];
    // 日历事件没有独立完成字段：用时间前/后移动实现“完成/未完成”切换。
    final movedDueDate = todo.isCompleted
        ? DateTime.now().add(const Duration(hours: 1))
        : DateTime.now().subtract(const Duration(minutes: 1));
    await updateTodo(todo.copyWith(dueDate: movedDueDate));
  }

  List<TodoItem> sortTodos(List<TodoItem> todos, TodoSort sort) {
    final sortedTodos = List<TodoItem>.from(todos);
    
    switch (sort) {
      case TodoSort.dueDate:
        sortedTodos.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
      case TodoSort.priority:
        sortedTodos.sort((a, b) => b.priority.value.compareTo(a.priority.value));
        break;
      case TodoSort.createdAt:
        sortedTodos.sort((a, b) {
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return b.createdAt!.compareTo(a.createdAt!);
        });
        break;
      case TodoSort.alphabetical:
        sortedTodos.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    
    return sortedTodos;
  }

  Future<void> _loadTodos() async {
    try {
      _todos = await _loadCalendarTodos();
      _todosController.add(List.unmodifiable(_todos));
    } catch (e) {
      Log.error('加载待办事项时出错: $e');
      _todos = [];
      _todosController.add(List.unmodifiable(_todos));
    }
  }

  // 从日历加载待办事项
  Future<List<TodoItem>> _loadCalendarTodos() async {
    final calendarViewIds = await _resolveCalendarViewIds();
    if (calendarViewIds.isEmpty) return [];
    
    try {
      final calendarTodos = <TodoItem>[];
      for (final viewId in calendarViewIds) {
        final payload = CalendarEventRequestPB.create()..viewId = viewId;
        final result = await DatabaseEventGetAllCalendarEvents(payload).send();
        result.fold(
          (events) {
            for (final eventPB in events.items) {
              final todo = _convertCalendarEventToTodo(eventPB);
              if (todo != null) {
                calendarTodos.add(todo);
              }
            }
          },
          (error) {},
        );
      }
      return calendarTodos;
    } catch (e) {
      return <TodoItem>[];
    }
  }

  Future<List<String>> _resolveCalendarViewIds() async {
    try {
      final result = await ViewBackendService.getAllViews();
      final ids = result.fold(
        (views) => views.items
            .where((v) => v.layout == ViewLayoutPB.Calendar && v.id.isNotEmpty)
            .map((v) => v.id)
            .toSet()
            .toList(),
        (error) => <String>[],
      );
      if (ids.isNotEmpty) {
        return ids;
      }
    } catch (_) {}

    // 兼容旧逻辑：兜底固定日历视图
    if (_calendarViewId != null && _calendarViewId!.isNotEmpty) {
      return [_calendarViewId!];
    }
    return <String>[];
  }

  Future<(int, String?)> _loadRecurrenceInfo({
    required String viewId,
    required String rowId,
    required String dateFieldId,
  }) async {
    try {
      final cellResult = await CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(
          fieldId: dateFieldId,
          rowId: rowId,
        ),
      );

      return cellResult.fold(
        (cell) {
          final pb = DateCellDataParser().parserData(cell.data);
          if (pb == null) {
            return (0, null);
          }
          final repeatType = pb.hasRepeatType() ? pb.repeatType : 0;
          final repeatRuleJson = (pb.hasRepeatRuleJson() && pb.repeatRuleJson.isNotEmpty)
              ? pb.repeatRuleJson
              : null;
          return (repeatType, repeatRuleJson);
        },
        (error) => (0, null),
      );
    } catch (_) {
      return (0, null);
    }
  }

  bool _matchesDisplayDate({
    required DateTime start,
    required DateTime target,
    required int repeatType,
    required String? repeatRuleJson,
  }) {
    final startDay = DateTime(start.year, start.month, start.day);
    if (_isSameDay(startDay, target)) {
      return true;
    }
    if (target.isBefore(startDay) || repeatType == 0) {
      return false;
    }
    return _matchesRepeatRule(
      date: target,
      startDate: startDay,
      repeatType: repeatType,
      repeatRuleJson: repeatRuleJson,
    );
  }

  bool _matchesRepeatRule({
    required DateTime date,
    required DateTime startDate,
    required int repeatType,
    String? repeatRuleJson,
  }) {
    switch (repeatType) {
      case 1: // 每天
        return true;
      case 2: // 每周
        return date.weekday == startDate.weekday;
      case 3: // 每年
        return date.month == startDate.month && date.day == startDate.day;
      case 4: // 法定工作日（简化：过滤周末）
        return date.weekday != DateTime.saturday &&
            date.weekday != DateTime.sunday;
      case 99:
        return _matchesCustomRule(
          date: date,
          startDate: startDate,
          repeatRuleJson: repeatRuleJson,
        );
      default:
        return false;
    }
  }

  bool _matchesCustomRule({
    required DateTime date,
    required DateTime startDate,
    String? repeatRuleJson,
  }) {
    if (repeatRuleJson == null || repeatRuleJson.isEmpty) {
      return false;
    }

    try {
      final rule = jsonDecode(repeatRuleJson) as Map<String, dynamic>;
      final unit = rule['unit'] ?? 1; // 0=天 1=周 2=月 3=年
      final interval = rule['interval'] ?? 1;
      final weekdays = rule['weekdays'] as List<dynamic>?;
      final daysDiff = date.difference(startDate).inDays;

      switch (unit) {
        case 0: // 每N天
          return daysDiff >= 0 && daysDiff % interval == 0;
        case 1: // 每N周
          if (weekdays == null || weekdays.isEmpty) return false;
          final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
          if (!weekdayList.contains(date.weekday)) return false;
          if (interval == 1) return daysDiff >= 0;
          final weeksDiff = daysDiff ~/ 7;
          return weeksDiff >= 0 && weeksDiff % interval == 0;
        case 2: // 每N月
          final monthsDiff =
              (date.year - startDate.year) * 12 + (date.month - startDate.month);
          if (monthsDiff < 0 || monthsDiff % interval != 0) return false;
          final targetDay = _dayInMonth(date.year, date.month, startDate.day);
          return date.day == targetDay;
        case 3: // 每N年
          final yearsDiff = date.year - startDate.year;
          if (yearsDiff < 0 || yearsDiff % interval != 0) return false;
          if (startDate.month == 2 && startDate.day == 29 && !_isLeapYear(date.year)) {
            return date.month == 2 && date.day == 28;
          }
          return date.month == startDate.month && date.day == startDate.day;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  int _dayInMonth(int year, int month, int day) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return day > daysInMonth ? daysInMonth : day;
  }

  bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // 将日历事件转换为待办事项
  TodoItem? _convertCalendarEventToTodo(CalendarEventPB eventPB) {
    try {
      // 检查事件是否有有效的时间戳
      if (!eventPB.hasTimestamp() || eventPB.timestamp == 0) {
        return null;
      }
      
      final dueDate = DateTime.fromMillisecondsSinceEpoch(eventPB.timestamp.toInt() * 1000);
      
      // 日历事件默认为未完成状态
      final now = DateTime.now();
      final isCompleted = now.isAfter(dueDate);
      
      return TodoItem(
        id: eventPB.rowMeta.id,
        title: eventPB.title.isNotEmpty ? eventPB.title : '日历事件',
        description: '来自日历的日程安排',
        priority: TodoPriority.medium,
        dueDate: dueDate,
        createdAt: dueDate,
        isCompleted: isCompleted,
        completedAt: isCompleted ? dueDate : null,
        tags: ['日历', '日程'],
        source: TodoSource.calendar, // 标记来源为日历
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<FieldInfo>> _loadFieldInfos(String viewId) async {
    var fieldInfos = <FieldInfo>[];
    final fetched = await FieldBackendService.getFields(viewId: viewId);
    fieldInfos = fetched.fold(
      (list) => list.map((f) => FieldInfo.initial(f)).toList(),
      (_) => <FieldInfo>[],
    );

    if (fieldInfos.isEmpty) {
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
      final retry = await FieldBackendService.getFields(viewId: viewId);
      fieldInfos = retry.fold(
        (list) => list.map((f) => FieldInfo.initial(f)).toList(),
        (_) => <FieldInfo>[],
      );
    }
    return fieldInfos;
  }

  Future<void> _createCalendarTodo(TodoItem todo) async {
    if (_calendarViewId == null) {
      await _ensureCalendarViewExists();
      if (_calendarViewId == null) {
        throw Exception('日历视图不可用');
      }
    }
    final viewId = _calendarViewId!;
    final fields = await _loadFieldInfos(viewId);
    final primaryField = fields.firstWhere(
      (f) => f.isPrimary,
      orElse: () => fields.first,
    );
    final dateField = fields.firstWhere(
      (f) => f.fieldType == FieldType.DateTime,
      orElse: () => fields.first,
    );

    final dueDate = todo.dueDate ?? DateTime.now().add(const Duration(hours: 1));
    final createResult = await RowBackendService.createRow(
      viewId: viewId,
      withCells: (builder) {
        if (primaryField.fieldType == FieldType.RichText) {
          builder.insertText(primaryField, todo.title);
        }
        if (dateField.fieldType == FieldType.DateTime) {
          builder.insertDate(dateField, dueDate);
        }
      },
    );

    final rowMeta = await createResult.fold(
      (row) => row,
      (error) => throw Exception(error.msg),
    );

    if (dateField.fieldType == FieldType.DateTime) {
      final dateService = DateCellBackendService(
        viewId: viewId,
        fieldId: dateField.field.id,
        rowId: rowMeta.id,
      );
      await dateService.update(
        includeTime: !todo.isAllDay,
        isRange: false,
        date: dueDate,
      );
    }
  }

  Future<void> _updateCalendarTodo(TodoItem todo) async {
    if (_calendarViewId == null) return;
    final viewId = _calendarViewId!;
    final fields = await _loadFieldInfos(viewId);
    final primaryField = fields.firstWhere(
      (f) => f.isPrimary,
      orElse: () => fields.first,
    );
    final dateField = fields.firstWhere(
      (f) => f.fieldType == FieldType.DateTime,
      orElse: () => fields.first,
    );

    if (primaryField.fieldType == FieldType.RichText && todo.title.isNotEmpty) {
      await CellBackendService.updateCell(
        viewId: viewId,
        cellContext: CellContext(
          fieldId: primaryField.field.id,
          rowId: todo.id,
        ),
        data: todo.title,
      );
    }

    if (dateField.fieldType == FieldType.DateTime && todo.dueDate != null) {
      final dateService = DateCellBackendService(
        viewId: viewId,
        fieldId: dateField.field.id,
        rowId: todo.id,
      );
      await dateService.update(
        includeTime: !todo.isAllDay,
        isRange: false,
        date: todo.dueDate,
      );
    }
  }

  Future<void> _deleteCalendarTodo(String rowId) async {
    if (_calendarViewId == null) return;
    final result = await RowBackendService.deleteRows(_calendarViewId!, [rowId]);
    result.fold(
      (_) {},
      (error) => throw Exception(error.msg),
    );
  }

  void dispose() {
    _todosController.close();
  }
}

