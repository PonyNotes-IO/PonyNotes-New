import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';

/// [isCloud] 为 true 时带上 `cloud_notification_type` 元数据，
/// 与 ReminderBloc._cloudNotificationToReminder 对服务端通知的转换保持一致。
ReminderPB reminder({
  required String id,
  required bool isRead,
  bool isCloud = false,
  bool isArchived = false,
}) =>
    ReminderPB(
      id: id,
      isRead: isRead,
      scheduledAt: Int64(DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch),
      meta: <String, String>{
        if (isCloud) 'cloud_notification_type': 'collab_shared',
        if (isArchived) 'is_archived': 'true',
      },
    );

void main() {
  // 【回归防护 2026-07-30】以下用例针对一次真实故障：
  // 分享/邀请/权限变更通知在客户端一条都不显示。
  //
  // 成因是 ReminderState 里 workspaceReminders/globalReminders 双列表——
  // 前者用 `!_isGlobalReminder(...)` 把云通知全部滤掉，后者从未被填充。
  // 当时的单元测试构造的是**生产代码已不再使用**的 globalReminders 入参，
  // 因此全部通过，未能拦截。
  //
  // 这些用例改为断言唯一对外契约：**云通知必须出现在 state.reminders 里**。
  // 无论内部如何重构，只要通知不展示，它们就必须失败。
  group('云通知必须可见（回归防护）', () {
    test('云通知与本地日程提醒同时出现在 reminders 中', () {
      final cloudNotification = reminder(
        id: 'cloud-share',
        isRead: false,
        isCloud: true,
      );
      final localSchedule = reminder(id: 'local-schedule', isRead: false);

      final state = ReminderState(
        reminders: [cloudNotification, localSchedule],
      );

      expect(
        state.reminders.map((item) => item.id),
        containsAll(<String>['cloud-share', 'local-schedule']),
        reason: '云通知被过滤掉了——正是 2026-07-30 那次"没通知"的故障表现',
      );
    });

    test('仅有云通知时 reminders 不为空', () {
      final state = ReminderState(
        reminders: [
          reminder(id: 'n1', isRead: false, isCloud: true),
          reminder(id: 'n2', isRead: false, isCloud: true),
        ],
      );

      expect(state.reminders, hasLength(2));
    });

    test('copyWith 之后云通知依然保留', () {
      final state = ReminderState(
        reminders: [reminder(id: 'cloud', isRead: false, isCloud: true)],
      ).copyWith(
        reminders: [
          reminder(id: 'cloud', isRead: true, isCloud: true),
          reminder(id: 'local', isRead: false),
        ],
      );

      expect(state.reminders.map((item) => item.id), ['cloud', 'local']);
      expect(
        state.reminders.singleWhere((item) => item.id == 'cloud').isRead,
        isTrue,
      );
    });

    test('已归档的云通知出现在归档列表中', () {
      final archivedCloud = reminder(
        id: 'archived-cloud',
        isRead: true,
        isCloud: true,
        isArchived: true,
      );

      final state = ReminderState(
        reminders: const [],
        archivedReminders: [archivedCloud],
      );

      expect(
        state.archivedReminders.map((item) => item.id),
        contains('archived-cloud'),
        reason: '云通知同样可归档，归档页必须能看到',
      );
    });

    test('id 相同的重复项被去重', () {
      final state = ReminderState(
        reminders: [
          reminder(id: 'dup', isRead: true, isCloud: true),
          reminder(id: 'dup', isRead: false, isCloud: true),
        ],
      );

      expect(state.reminders, hasLength(1));
    });
  });
}
