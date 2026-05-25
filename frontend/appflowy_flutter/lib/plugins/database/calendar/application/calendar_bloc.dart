import 'package:appflowy/plugins/database/application/cell/cell_cache.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/defines.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/application/cell/cell_data_loader.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/cell_entities.pb.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'dart:convert';

import '../../application/database_controller.dart';
import '../../application/row/row_cache.dart';

part 'calendar_bloc.freezed.dart';

class CalendarBloc extends Bloc<CalendarEvent, CalendarState> {
  CalendarBloc({required this.databaseController})
      : super(CalendarState.initial()) {
    _dispatch();
  }

  final DatabaseController databaseController;
  Map<String, FieldInfo> fieldInfoByFieldId = {};

  // Getters
  String get viewId => databaseController.viewId;
  FieldController get fieldController => databaseController.fieldController;
  CellMemCache get cellCache => databaseController.rowCache.cellCache;
  RowCache get rowCache => databaseController.rowCache;

  UserProfilePB? _userProfile;
  UserProfilePB? get userProfile => _userProfile;

  DatabaseCallbacks? _databaseCallbacks;
  DatabaseLayoutSettingCallbacks? _layoutSettingCallbacks;

  @override
  Future<void> close() async {
    databaseController.removeListener(
      onDatabaseChanged: _databaseCallbacks,
      onLayoutSettingsChanged: _layoutSettingCallbacks,
    );
    _databaseCallbacks = null;
    _layoutSettingCallbacks = null;
    await super.close();
  }

  void _dispatch() {
    on<CalendarEvent>(
      (event, emit) async {
        await event.when(
          initial: () async {
            final result = await UserEventGetUserProfile().send();
            result.fold(
              (profile) => _userProfile = profile,
              (err) => Log.error('Failed to get user profile: $err'),
            );

            _startListening();
            await _openDatabase(emit);
            _loadAllEvents();
          },
          didReceiveCalendarSettings: (CalendarLayoutSettingPB settings) {
            // If the field id changed, reload all events
            if (state.settings?.fieldId != settings.fieldId) {
              _loadAllEvents();
            }
            emit(state.copyWith(settings: settings));
          },
          didReceiveDatabaseUpdate: (DatabasePB database) {
            emit(state.copyWith(database: database));
          },
          didLoadAllEvents: (events) {
            final calenderEvents = _calendarEventDataFromEventPBs(events);
            emit(
              state.copyWith(
                initialEvents: calenderEvents,
                allEvents: calenderEvents,
              ),
            );
          },
          createEvent: (DateTime date) async {
            await _createEvent(date);
          },
          duplicateEvent: (String viewId, String rowId) async {
            final result = await RowBackendService.duplicateRow(viewId, rowId);
            result.fold(
              (_) => null,
              (e) => Log.error('Failed to duplicate event: $e', e),
            );
          },
          deleteEvent: (String viewId, String rowId) async {
            final result = await RowBackendService.deleteRows(viewId, [rowId]);
            result.fold(
              (_) => null,
              (e) => Log.error('Failed to delete event: $e', e),
            );
          },
          newEventPopupDisplayed: () {
            emit(state.copyWith(editingEvent: null));
          },
          moveEvent: (CalendarDayEvent event, DateTime date) async {
            await _moveEvent(event, date);
          },
          didCreateEvent: (CalendarEventData<CalendarDayEvent> event) {
            emit(state.copyWith(editingEvent: event));
          },
          updateCalendarLayoutSetting:
              (CalendarLayoutSettingPB layoutSetting) async {
            await _updateCalendarLayoutSetting(layoutSetting);
          },
          didUpdateEvent: (CalendarEventData<CalendarDayEvent> eventData) {
            final allEvents = [...state.allEvents];
            final index = allEvents.indexWhere(
              (element) => element.event!.eventId == eventData.event!.eventId,
            );
            if (index != -1) {
              allEvents[index] = eventData;
            }
            emit(state.copyWith(allEvents: allEvents, updateEvent: eventData));
          },
          didDeleteEvents: (List<RowId> deletedRowIds) {
            final events = [...state.allEvents];
            events.retainWhere(
              (element) => !deletedRowIds.contains(element.event!.eventId),
            );
            emit(
              state.copyWith(
                allEvents: events,
                deleteEventIds: deletedRowIds,
              ),
            );
            emit(state.copyWith(deleteEventIds: const []));
          },
          didReceiveEvent: (CalendarEventData<CalendarDayEvent> event) {
            emit(
              state.copyWith(
                allEvents: [...state.allEvents, event],
                newEvent: event,
              ),
            );
            emit(state.copyWith(newEvent: null));
          },
          openRowDetail: (row) {
            emit(state.copyWith(openRow: row));
            emit(state.copyWith(openRow: null));
          },
        );
      },
    );
  }

  FieldInfo? _getCalendarFieldInfo(String fieldId) {
    final fieldInfos = databaseController.fieldController.fieldInfos;
    final index = fieldInfos.indexWhere(
      (element) => element.field.id == fieldId,
    );
    if (index != -1) {
      return fieldInfos[index];
    } else {
      return null;
    }
  }

  Future<void> _openDatabase(Emitter<CalendarState> emit) async {
    final result = await databaseController.open();
    result.fold(
      (database) {
        databaseController.setIsLoading(false);
        emit(
          state.copyWith(
            loadingState: LoadingState.finish(FlowyResult.success(null)),
          ),
        );
      },
      (err) => emit(
        state.copyWith(
          loadingState: LoadingState.finish(FlowyResult.failure(err)),
        ),
      ),
    );
  }

  Future<void> _createEvent(DateTime date) async {
    final settings = state.settings;
    if (settings == null) {
      Log.warn('Calendar settings not found');
      return;
    }
    final dateField = _getCalendarFieldInfo(settings.fieldId);
    if (dateField != null) {
      final newRow = await RowBackendService.createRow(
        viewId: viewId,
        withCells: (builder) => builder.insertDate(dateField, date),
      ).then(
        (result) => result.fold(
          (newRow) => newRow,
          (err) {
            Log.error(err);
            return null;
          },
        ),
      );

      if (newRow != null) {
        final event = await _loadEvent(newRow.id);
        if (event != null && !isClosed) {
          add(CalendarEvent.didCreateEvent(event));
        }
      }
    }
  }

  Future<void> _moveEvent(CalendarDayEvent event, DateTime date) async {
    final timestamp = _eventTimestamp(event, date);
    final payload = MoveCalendarEventPB(
      cellPath: CellIdPB(
        viewId: viewId,
        rowId: event.eventId,
        fieldId: event.dateFieldId,
      ),
      timestamp: timestamp,
    );
    return DatabaseEventMoveCalendarEvent(payload).send().then((result) {
      return result.fold(
        (_) async {
          final modifiedEvent = await _loadEvent(event.eventId);
          add(CalendarEvent.didUpdateEvent(modifiedEvent!));
        },
        (err) {
          Log.error(err);
          return null;
        },
      );
    });
  }

  Future<void> _updateCalendarLayoutSetting(
    CalendarLayoutSettingPB layoutSetting,
  ) async {
    return databaseController.updateLayoutSetting(
      calendarLayoutSetting: layoutSetting,
    );
  }

  Future<CalendarEventData<CalendarDayEvent>?> _loadEvent(RowId rowId) async {
    final eventPB = await _loadEventPB(rowId);
    if (eventPB == null) {
      return null;
    }
    return _calendarEventDataFromEventPB(eventPB);
  }

  Future<CalendarEventPB?> _loadEventPB(RowId rowId) async {
    final payload = DatabaseViewRowIdPB(viewId: viewId, rowId: rowId);
    return DatabaseEventGetCalendarEvent(payload).send().fold(
      (eventPB) => eventPB,
      (r) {
        Log.error(r);
        return null;
      },
    );
  }

  void _loadAllEvents() async {
    final payload = CalendarEventRequestPB.create()..viewId = viewId;
    final result = await DatabaseEventGetAllCalendarEvents(payload).send();
    result.fold(
      (events) async {
        if (!isClosed) {
          // 展开重复事件
          final expandedEvents = await _expandRecurringEvents(events.items);
          add(CalendarEvent.didLoadAllEvents(expandedEvents));
        }
      },
      (r) => Log.error(r),
    );
  }

  // 展开重复事件：为每个重复事件生成未来几个月的实例
  Future<List<CalendarEventPB>> _expandRecurringEvents(
    List<CalendarEventPB> eventPBs,
  ) async {
    final expandedEvents = <CalendarEventPB>[];
    final now = DateTime.now();
    // 生成未来6个月的事件
    final endDate = DateTime(now.year, now.month + 6, 1);

    for (final eventPB in eventPBs) {
      // 添加原始事件
      expandedEvents.add(eventPB);

      // 读取重复信息
      final repeatInfo = await _getRepeatInfo(eventPB);
      if (repeatInfo == null || repeatInfo['repeatType'] == 0) {
        continue; // 没有重复，跳过
      }

      final startDate = DateTime.fromMillisecondsSinceEpoch(
        eventPB.timestamp.toInt() * 1000,
      );
      final repeatType = repeatInfo['repeatType'] as int;
      final repeatRuleJson = repeatInfo['repeatRuleJson'] as String?;

      // 生成重复事件实例（未来6个月）
      var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
      while (currentDate.isBefore(endDate)) {
        currentDate = currentDate.add(const Duration(days: 1));

        // 检查是否匹配重复规则
        if (_matchesRepeatRule(currentDate, startDate, repeatType, repeatRuleJson)) {
          // 创建重复事件的副本
          final repeatedEvent = CalendarEventPB()
            ..rowMeta = eventPB.rowMeta.clone()
            ..dateFieldId = eventPB.dateFieldId
            ..title = eventPB.title
            ..timestamp = Int64((currentDate.millisecondsSinceEpoch ~/ 1000));
          
          // 修改事件ID以区分重复实例（使用日期后缀）
          repeatedEvent.rowMeta.id = '${eventPB.rowMeta.id}_${currentDate.year}_${currentDate.month}_${currentDate.day}';
          
          expandedEvents.add(repeatedEvent);
        }
      }
    }

    return expandedEvents;
  }

  // 从数据库读取重复信息
  Future<Map<String, dynamic>?> _getRepeatInfo(CalendarEventPB eventPB) async {
    try {
      final fieldInfos = fieldController.fieldInfos;
      final fieldById = {for (final f in fieldInfos) f.field.id: f};

      // 优先从日期字段读取 repeatType / repeatRuleJson
      // 这与 ScheduleModel._enrichFromCells 的逻辑一致
      final dateField = fieldById[eventPB.dateFieldId];
      if (dateField != null && dateField.fieldType == FieldType.DateTime) {
        final dateCellResult = await CellBackendService.getCell(
          viewId: viewId,
          cellContext: CellContext(
            fieldId: dateField.field.id,
            rowId: eventPB.rowMeta.id,
          ),
        );

        final pb = dateCellResult.fold(
          (cell) => DateCellDataParser().parserData(cell.data),
          (_) => null,
        );

        if (pb != null) {
          int repeatType = 0;
          if (pb.hasRepeatType()) {
            repeatType = pb.repeatType;
          }
          String? repeatRuleJson;
          if (pb.hasRepeatRuleJson()) {
            final json = pb.repeatRuleJson;
            repeatRuleJson = json.isEmpty ? null : json;
          }
          if (repeatType != 0 || repeatRuleJson != null) {
            return {
              'repeatType': repeatType,
              'repeatRuleJson': repeatRuleJson,
            };
          }
        }
      }

      // 兼容旧逻辑：如果日期字段没有，再尝试找自定义 RichText Repeat 字段
      FieldInfo? repeatField;
      for (final field in fieldInfos) {
        final name = field.name.toLowerCase();
        if (field.fieldType == FieldType.RichText &&
            (name.contains('repeat') || name.contains('重复'))) {
          repeatField = field;
          break;
        }
      }

      if (repeatField == null) {
        return null;
      }

      final cellContext = CellContext(
        fieldId: repeatField.field.id,
        rowId: eventPB.rowMeta.id,
      );
      final cellResult = await CellBackendService.getCell(
        viewId: viewId,
        cellContext: cellContext,
      );

      return cellResult.fold(
        (cell) {
          final jsonString = StringCellDataParser().parserData(cell.data);
          if (jsonString == null || jsonString.isEmpty) {
            return null;
          }
          try {
            return jsonDecode(jsonString) as Map<String, dynamic>;
          } catch (e) {
            Log.error('Failed to parse repeat info: $e');
            return null;
          }
        },
        (_) => null,
      );
    } catch (e) {
      Log.error('Failed to get repeat info: $e');
      return null;
    }
  }

  // 判断日期是否匹配重复规则（与 ScheduleModel 中的逻辑一致）
  bool _matchesRepeatRule(
    DateTime date,
    DateTime startDate,
    int repeatType,
    String? repeatRuleJson,
  ) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);

    // 如果日期在开始日期之前，不匹配（所有重复类型都允许匹配过去日期）

    // 如果日期正好是开始日期，不匹配（已经在原始事件中）
    if (dateOnly.isAtSameMomentAs(startDateOnly)) {
      return false;
    }

    switch (repeatType) {
      case 1: // 每天
        return true;

      case 2: // 每周
        if (repeatRuleJson != null && repeatRuleJson!.isNotEmpty) {
          try {
            final rule = jsonDecode(repeatRuleJson!) as Map<String, dynamic>;
            final weekdays = rule['weekdays'] as List<dynamic>?;
            if (weekdays != null && weekdays.isNotEmpty) {
              final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
              return weekdayList.contains(date.weekday);
            }
          } catch (_) {}
        }
        return date.weekday == startDate.weekday;

      case 3: // 每年
        return date.month == startDate.month && date.day == startDate.day;

      case 4: // 法定工作日
        // 跳过周末
        if (date.weekday == 6 || date.weekday == 7) {
          return false;
        }
        return true;

      case 99: // 自定义
        return _matchesCustomRule(date, startDate, repeatRuleJson);

      default:
        return false;
    }
  }

  // 匹配自定义规则
  bool _matchesCustomRule(DateTime date, DateTime startDate, String? repeatRuleJson) {
    if (repeatRuleJson == null || repeatRuleJson.isEmpty) {
      return false;
    }

    try {
      final rule = jsonDecode(repeatRuleJson) as Map<String, dynamic>;
      final unit = rule['unit'] ?? 1; // 0=天 1=周 2=月 3=年
      final interval = rule['interval'] ?? 1;
      final weekdays = rule['weekdays'] as List<dynamic>?;

      final dateOnly = DateTime(date.year, date.month, date.day);
      final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
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
          // Dart DateTime.weekday 为 1..7（周一..周日），需要 +1 映射
          final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
          if (!weekdayList.contains(date.weekday)) {
            return false;
          }

          // 计算从开始日期所在周（周一为起点）到目标日期所在周的天数
          // 先把两个日期都对齐到各自的周一
          final startWeekday = startDateOnly.weekday; // 1=周一
          final dateWeekday = dateOnly.weekday;         // 1=周一
          final daysToStartMonday = startDateOnly.day - startWeekday;
          final daysToDateMonday = dateOnly.day - dateWeekday;
          final startMonday = startDateOnly.subtract(Duration(days: daysToStartMonday));
          final dateMonday = dateOnly.subtract(Duration(days: daysToDateMonday));
          // 两个周一之间的天数差，再除以7得到周数差
          final weeksDiff = dateMonday.difference(startMonday).inDays ~/ 7;

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
      Log.error('Failed to parse custom repeat rule: $e');
      return false;
    }
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

  List<CalendarEventData<CalendarDayEvent>> _calendarEventDataFromEventPBs(
    List<CalendarEventPB> eventPBs,
  ) {
    final calendarEvents = <CalendarEventData<CalendarDayEvent>>[];
    for (final eventPB in eventPBs) {
      final event = _calendarEventDataFromEventPB(eventPB);
      if (event != null) {
        calendarEvents.add(event);
      }
    }
    return calendarEvents;
  }

  CalendarEventData<CalendarDayEvent>? _calendarEventDataFromEventPB(
    CalendarEventPB eventPB,
  ) {
    final fieldInfo = fieldInfoByFieldId[eventPB.dateFieldId];
    if (fieldInfo == null) {
      return null;
    }

    // timestamp is stored as seconds, but constructor requires milliseconds
    final date = DateTime.fromMillisecondsSinceEpoch(
      eventPB.timestamp.toInt() * 1000,
    );

    final eventData = CalendarDayEvent(
      event: eventPB,
      eventId: eventPB.rowMeta.id,
      dateFieldId: eventPB.dateFieldId,
      date: date,
    );

    return CalendarEventData(
      title: eventPB.title,
      date: date,
      event: eventData,
    );
  }

  void _startListening() {
    _databaseCallbacks = DatabaseCallbacks(
      onDatabaseChanged: (database) {
        if (isClosed) return;
      },
      onFieldsChanged: (fieldInfos) {
        if (isClosed) {
          return;
        }
        fieldInfoByFieldId = {
          for (final fieldInfo in fieldInfos) fieldInfo.field.id: fieldInfo,
        };
      },
      onRowsCreated: (rows) async {
        if (isClosed) {
          return;
        }
        // 当创建新事件时，重新加载所有事件以包含重复展开
        _loadAllEvents();
      },
      onRowsDeleted: (rowIds) {
        if (isClosed) {
          return;
        }
        add(CalendarEvent.didDeleteEvents(rowIds));
      },
      onRowsUpdated: (rowIds, reason) async {
        if (isClosed) {
          return;
        }
        // 当更新事件时，重新加载所有事件以包含重复展开
        // 这样可以确保重复事件的更新也能正确显示
        _loadAllEvents();
      },
      onNumOfRowsChanged: (rows, rowById, reason) {
        reason.maybeWhen(
          updateRowsVisibility: (changeset) async {
            if (isClosed) {
              return;
            }
            for (final id in changeset.invisibleRows) {
              if (_containsEvent(id)) {
                add(CalendarEvent.didDeleteEvents([id]));
              }
            }
            for (final row in changeset.visibleRows) {
              final id = row.rowMeta.id;
              if (!_containsEvent(id)) {
                final event = await _loadEvent(id);
                if (event != null) {
                  add(CalendarEvent.didReceiveEvent(event));
                }
              }
            }
          },
          orElse: () {},
        );
      },
    );

    _layoutSettingCallbacks = DatabaseLayoutSettingCallbacks(
      onLayoutSettingsChanged: _didReceiveLayoutSetting,
    );

    databaseController.addListener(
      onDatabaseChanged: _databaseCallbacks,
      onLayoutSettingsChanged: _layoutSettingCallbacks,
    );
  }

  void _didReceiveLayoutSetting(DatabaseLayoutSettingPB layoutSetting) {
    if (layoutSetting.hasCalendar()) {
      if (isClosed) {
        return;
      }
      add(CalendarEvent.didReceiveCalendarSettings(layoutSetting.calendar));
    }
  }

  bool isEventDayChanged(CalendarEventData<CalendarDayEvent> event) {
    final index = state.allEvents.indexWhere(
      (element) => element.event!.eventId == event.event!.eventId,
    );
    if (index == -1) {
      return false;
    }
    return state.allEvents[index].date.day != event.date.day;
  }

  bool _containsEvent(String rowId) {
    return state.allEvents.any((element) => element.event!.eventId == rowId);
  }

  Int64 _eventTimestamp(CalendarDayEvent event, DateTime date) {
    final time =
        event.date.hour * 3600 + event.date.minute * 60 + event.date.second;
    return Int64(date.millisecondsSinceEpoch ~/ 1000 + time);
  }
}

typedef Events = List<CalendarEventData<CalendarDayEvent>>;

@freezed
class CalendarEvent with _$CalendarEvent {
  const factory CalendarEvent.initial() = _InitialCalendar;

  // Called after loading the calendar layout setting from the backend
  const factory CalendarEvent.didReceiveCalendarSettings(
    CalendarLayoutSettingPB settings,
  ) = _ReceiveCalendarSettings;

  // Called after loading all the current evnets
  const factory CalendarEvent.didLoadAllEvents(List<CalendarEventPB> events) =
      _ReceiveCalendarEvents;

  // Called when specific event was updated
  const factory CalendarEvent.didUpdateEvent(
    CalendarEventData<CalendarDayEvent> event,
  ) = _DidUpdateEvent;

  // Called after creating a new event
  const factory CalendarEvent.didCreateEvent(
    CalendarEventData<CalendarDayEvent> event,
  ) = _DidReceiveNewEvent;

  // Called after creating a new event
  const factory CalendarEvent.newEventPopupDisplayed() =
      _NewEventPopupDisplayed;

  // Called when receive a new event
  const factory CalendarEvent.didReceiveEvent(
    CalendarEventData<CalendarDayEvent> event,
  ) = _DidReceiveEvent;

  // Called when deleting events
  const factory CalendarEvent.didDeleteEvents(List<RowId> rowIds) =
      _DidDeleteEvents;

  // Called when creating a new event
  const factory CalendarEvent.createEvent(DateTime date) = _CreateEvent;

  // Called when moving an event
  const factory CalendarEvent.moveEvent(CalendarDayEvent event, DateTime date) =
      _MoveEvent;

  // Called when updating the calendar's layout settings
  const factory CalendarEvent.updateCalendarLayoutSetting(
    CalendarLayoutSettingPB layoutSetting,
  ) = _UpdateCalendarLayoutSetting;

  const factory CalendarEvent.didReceiveDatabaseUpdate(DatabasePB database) =
      _ReceiveDatabaseUpdate;

  const factory CalendarEvent.duplicateEvent(String viewId, String rowId) =
      _DuplicateEvent;

  const factory CalendarEvent.deleteEvent(String viewId, String rowId) =
      _DeleteEvent;

  const factory CalendarEvent.openRowDetail(RowMetaPB row) = _OpenRowDetail;
}

@freezed
class CalendarState with _$CalendarState {
  const factory CalendarState({
    required DatabasePB? database,
    // events by row id
    required Events allEvents,
    required Events initialEvents,
    CalendarEventData<CalendarDayEvent>? editingEvent,
    CalendarEventData<CalendarDayEvent>? newEvent,
    CalendarEventData<CalendarDayEvent>? updateEvent,
    required List<String> deleteEventIds,
    required CalendarLayoutSettingPB? settings,
    required RowMetaPB? openRow,
    required LoadingState loadingState,
    required FlowyError? noneOrError,
  }) = _CalendarState;

  factory CalendarState.initial() => const CalendarState(
        database: null,
        allEvents: [],
        initialEvents: [],
        deleteEventIds: [],
        settings: null,
        openRow: null,
        noneOrError: null,
        loadingState: LoadingState.loading(),
      );
}

@freezed
class CalendarDayEvent with _$CalendarDayEvent {
  const factory CalendarDayEvent({
    required CalendarEventPB event,
    required String dateFieldId,
    required String eventId,
    required DateTime date,
  }) = _CalendarDayEvent;
}
