import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';

ReminderPB reminder({
  required String id,
  required bool isRead,
  bool isGlobal = false,
}) =>
    ReminderPB(
      id: id,
      isRead: isRead,
      scheduledAt: Int64(DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch),
      meta: isGlobal
          ? const [
              MapEntry<String, String>('cloud_notification_type', 'collab_shared'),
            ]
          : const <MapEntry<String, String>>[],
    );

void main() {
  test('keeps global notification read state across workspace refresh', () {
    final globalNotification = reminder(id: 'global', isRead: true);
    final workspaceAReminder = reminder(id: 'workspace-a', isRead: false);
    final workspaceBReminder = reminder(id: 'workspace-b', isRead: false);

    final workspaceAState = ReminderState(
      reminders: [workspaceAReminder],
      globalReminders: [globalNotification],
    );
    final workspaceBState = workspaceAState.copyWith(
      reminders: [workspaceBReminder],
    );

    expect(workspaceBState.reminders.map((item) => item.id), [
      'workspace-b',
      'global',
    ]);
    expect(
      workspaceBState.reminders
          .singleWhere((item) => item.id == 'global')
          .isRead,
      isTrue,
    );
  });

  test('uses global notification instead of workspace copy with same id', () {
    final globalNotification = reminder(
      id: 'global',
      isRead: true,
      isGlobal: true,
    );
    final staleWorkspaceCopy = reminder(
      id: 'global',
      isRead: false,
      isGlobal: true,
    );

    final state = ReminderState(
      reminders: [staleWorkspaceCopy],
      globalReminders: [globalNotification],
    );

    expect(state.reminders, hasLength(1));
    expect(state.reminders.single.isRead, isTrue);
  });

  test('does not retain global notification in workspace archive state', () {
    final archivedGlobalCopy = reminder(
      id: 'global',
      isRead: false,
      isGlobal: true,
    )..meta['is_archived'] = 'true';

    final state = ReminderState(
      reminders: const [],
      archivedReminders: [archivedGlobalCopy],
    );

    expect(
      state.archivedReminders.where(
        (item) => item.meta['cloud_notification_type']?.isNotEmpty ?? false,
      ),
      isEmpty,
    );
  });
}
