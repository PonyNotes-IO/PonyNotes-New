import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_context_menu.dart';
import 'package:appflowy/user/application/reminder/recurring_reminder.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_backend/protobuf/flowy-user/reminder.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toastification/toastification.dart';

import 'test_material_app.dart';

ReminderPB _series(
  int type,
  DateTime start, {
  String rule = '',
  int offset = 0,
}) {
  return ReminderPB(
    objectId: 'calendar',
    title: '日程',
    meta: {
      ReminderMetaKeys.rowId: 'row',
      'recurrence_start': start.millisecondsSinceEpoch.toString(),
      'recurrence_type': '$type',
      'recurrence_rule': rule,
      'recurrence_offset': '$offset',
    },
  );
}

DateTime _date(ReminderPB reminder) => reminder.date!;

class _Schedules extends Fake implements ScheduleModel {
  Map<Symbol, dynamic>? saved;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createSchedule) {
      saved = invocation.namedArguments;
      return Future<String?>.value('row');
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  test('保存和续排串行执行，失败不会阻塞后续提醒', () async {
    final gate = Completer<void>();
    final order = <int>[];
    final saving = runScheduleReminderTask(() async {
      order.add(1);
      await gate.future;
      throw StateError('save failed');
    });
    final failed = expectLater(saving, throwsStateError);
    final renewing = runScheduleReminderTask(() async => order.add(2));
    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);
    gate.complete();
    await failed;
    await renewing;
    expect(order, [1, 2]);
  });

  test('重复类型正确匹配，周末跳过，每周保留星期，每月处理月末', () {
    final now = DateTime(2026, 1, 30, 8);
    final start = DateTime(2026, 1, 30, 10);
    expect(upcomingRecurringReminders(_series(0, start), now), isEmpty);
    expect(
      upcomingRecurringReminders(_series(1, start), now).take(3).map(_date),
      [start, DateTime(2026, 1, 31, 10), DateTime(2026, 2, 1, 10)],
    );
    expect(
      upcomingRecurringReminders(_series(4, start), now).take(3).map(_date),
      [start, DateTime(2026, 2, 2, 10), DateTime(2026, 2, 3, 10)],
    );
    expect(
      upcomingRecurringReminders(_series(2, start), now).take(2).map(_date),
      [start, DateTime(2026, 2, 6, 10)],
    );
    expect(
      upcomingRecurringReminders(
        _series(99, DateTime(2026, 1, 31, 10), rule: '{"unit":2,"interval":1}'),
        now,
      ).take(3).map(_date),
      [
        DateTime(2026, 1, 31, 10),
        DateTime(2026, 2, 28, 10),
        DateTime(2026, 3, 31, 10),
      ],
    );
    expect(
      upcomingRecurringReminders(_series(3, start), now).take(2).map(_date),
      [start, DateTime(2027, 1, 30, 10)],
    );
  });

  test('未来日程不限30天，重启后续排且保持提前量，不重复注册', () {
    final start = DateTime(2027, 3, 1, 10);
    final template = _series(1, start, offset: -300000);
    final initial =
        upcomingRecurringReminders(template, DateTime(2026, 11, 11));
    expect(initial, hasLength(10));
    expect(initial.first.date, start);
    expect(
      initial.first.scheduledAt.toInt(),
      DateTime(2027, 3, 1, 9, 55).millisecondsSinceEpoch,
    );
    expect(
      missingRecurringReminders(initial, DateTime(2027, 3, 1, 9)),
      isEmpty,
    );
    final renewed =
        missingRecurringReminders(initial, DateTime(2027, 3, 10, 11));
    expect(renewed, hasLength(10));
    expect(renewed.first.date, DateTime(2027, 3, 11, 10));
    expect(
      missingRecurringReminders(
        [...initial, ...renewed],
        DateTime(2027, 3, 10, 11),
      ),
      isEmpty,
    );
    expect(missingRecurringReminders([], DateTime(2027)), isEmpty);
  });

  test('全天提醒在9点触发，无效规则不创建任务', () {
    final start = DateTime(2026, 11, 11);
    final reminders = upcomingRecurringReminders(
      _series(4, start, offset: const Duration(hours: 9).inMilliseconds),
      DateTime(2026, 11, 11, 8),
    );
    expect(
      reminders.first.scheduledAt.toInt(),
      DateTime(2026, 11, 11, 9).millisecondsSinceEpoch,
    );
    expect(
      upcomingRecurringReminders(_series(99, start, rule: 'broken'), start),
      isEmpty,
    );
    expect(
      upcomingRecurringReminders(
        _series(99, start, rule: '{"unit":2,"interval":0}'),
        start,
      ),
      isEmpty,
    );
  });

  testWidgets('浮窗提供六种重复选项，保存规则并默认开启提醒', (tester) async {
    await initializeDateFormatting('zh_CN');
    final schedules = _Schedules();
    await tester.pumpWidget(
      AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: ToastificationWrapper(
          child: WidgetTestApp(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => CalendarContextMenu.show(
                  context: context,
                  position: const Offset(100, 80),
                  date: DateTime(2026, 11, 11),
                  scheduleModel: schedules,
                ),
                child: const Text('新建'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永不'));
    await tester.pumpAndSettle();
    for (final label in ['永不', '每天', '周一至周五', '每周', '每月', '每年']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.ensureVisible(find.text('每月').last);
    await tester.tap(find.text('每月').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '月度回顾');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(schedules.saved?[#repeatType], 99);
    expect(
      jsonDecode(schedules.saved?[#repeatRuleJson] as String),
      containsPair('unit', 2),
    );
    expect(schedules.saved?[#reminderOption], ReminderOption.atTimeOfEvent);
    expect(tester.takeException(), isNull);
    toastification.dismissAll();
    await tester.pumpAndSettle();
  });
}
