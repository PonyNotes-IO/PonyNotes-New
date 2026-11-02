import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/workspace_notifier.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_item_v2.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'widget_test_wrapper.dart';

class _MockReminderBloc extends MockBloc<ReminderEvent, ReminderState>
    implements ReminderBloc {}

class _MockHomeSettingBloc extends MockBloc<HomeSettingEvent, HomeSettingState>
    implements HomeSettingBloc {}

class _MockAppearanceCubit extends MockCubit<AppearanceSettingsState>
    implements AppearanceSettingsCubit {}

class _MockAppearanceState extends Mock implements AppearanceSettingsState {}

void main() {
  late _MockReminderBloc reminderBloc;
  late _MockHomeSettingBloc homeSettingBloc;
  late _MockAppearanceCubit appearanceCubit;

  setUpAll(() {
    registerFallbackValue(const ReminderEvent.refresh());
    registerFallbackValue(const HomeSettingEvent.initial());
  });

  setUp(() {
    openWorkspaceNotifier.value = null;
    reminderBloc = _MockReminderBloc();
    homeSettingBloc = _MockHomeSettingBloc();
    appearanceCubit = _MockAppearanceCubit();
    final appearance = _MockAppearanceState();
    when(() => appearanceCubit.state).thenReturn(appearance);
    when(() => appearance.dateFormat).thenReturn(UserDateFormatPB.ISO);
    when(() => appearance.timeFormat)
        .thenReturn(UserTimeFormatPB.TwentyFourHour);
  });

  tearDown(() {
    openWorkspaceNotifier.value = null;
  });

  Future<void> tapNotification(
    WidgetTester tester, {
    bool isRead = false,
    String workspaceId = 'target-workspace',
    bool isArchived = false,
  }) async {
    final reminder = ReminderPB(
      id: 'joined-notification',
      objectId: workspaceId,
      title: '成功加入工作区',
      message: '你已通过邀请链接成功加入工作区',
      scheduledAt: Int64(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      isRead: isRead,
      meta: {
        'cloud_notification_type': 'workspace_joined_via_code',
        'payload': '{}',
        if (isArchived) 'is_archived': 'true',
      },
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ReminderBloc>.value(value: reminderBloc),
          BlocProvider<HomeSettingBloc>.value(value: homeSettingBloc),
          BlocProvider<AppearanceSettingsCubit>.value(value: appearanceCubit),
        ],
        child: WidgetTestWrapper(
          child: SizedBox(
            width: 320,
            child: NotificationItemV2(tabType: null, reminder: reminder),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('成功加入工作区'));
    await tester.pumpAndSettle();
  }

  testWidgets('点击未读加入通知跳转来源工作区并标记已读', (tester) async {
    await tapNotification(tester);

    expect(openWorkspaceNotifier.value?.workspaceId, 'target-workspace');
    final event = verify(() => reminderBloc.add(captureAny())).captured.single
        as ReminderEvent;
    final update = event.mapOrNull(update: (event) => event.update);
    expect(update?.id, 'joined-notification');
    expect(update?.isRead, isTrue);
    verify(
      () => homeSettingBloc.add(
        const HomeSettingEvent.collapseNotificationPanel(),
      ),
    ).called(1);
  });

  testWidgets('已读和已归档通知仍可跳转且不重复更新已读', (tester) async {
    await tapNotification(tester, isRead: true, isArchived: true);

    expect(openWorkspaceNotifier.value?.workspaceId, 'target-workspace');
    verifyNever(() => reminderBloc.add(any()));
  });

  testWidgets('没有来源工作区的系统通知只标记已读', (tester) async {
    await tapNotification(tester, workspaceId: '');

    expect(openWorkspaceNotifier.value, isNull);
    verify(() => reminderBloc.add(any())).called(1);
    verifyNever(() => homeSettingBloc.add(any()));
  });
}
