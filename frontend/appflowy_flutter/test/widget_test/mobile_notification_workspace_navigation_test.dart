import 'dart:async';

import 'package:appflowy/mobile/presentation/home/mobile_home_page.dart';
import 'package:appflowy/mobile/presentation/notifications/mobile_notifications_screen.dart';
import 'package:appflowy/mobile/presentation/notifications/widgets/notification_item.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/workspace_notifier.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_tab_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockReminderBloc extends MockBloc<ReminderEvent, ReminderState>
    implements ReminderBloc {}

class _MockAppearanceCubit extends MockCubit<AppearanceSettingsState>
    implements AppearanceSettingsCubit {}

class _MockAppearanceState extends Mock implements AppearanceSettingsState {}

void main() {
  late _MockReminderBloc reminderBloc;
  late _MockAppearanceCubit appearanceCubit;
  String? workspaceOnHomeEntry;

  setUpAll(() {
    registerFallbackValue(const ReminderEvent.refresh());
  });

  setUp(() {
    openWorkspaceNotifier.value = null;
    workspaceOnHomeEntry = null;
    reminderBloc = _MockReminderBloc();
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

  Future<GoRouter> showNotification(
    WidgetTester tester, {
    bool isRead = false,
    String workspaceId = 'target-workspace',
    bool pushFromHome = false,
    bool legacyPayload = false,
  }) async {
    final reminder = ReminderPB(
      id: 'joined-notification',
      objectId: workspaceId,
      title: '成功加入工作区',
      message: '你已通过邀请链接成功加入工作区',
      scheduledAt: Int64(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      isRead: isRead,
      meta: {
        if (!legacyPayload)
          'cloud_notification_type': 'workspace_joined_via_code',
        'payload': '{}',
      },
    );
    final router = GoRouter(
      initialLocation: pushFromHome
          ? MobileHomeScreen.routeName
          : MobileNotificationsScreenV2.routeName,
      routes: [
        GoRoute(
          path: MobileHomeScreen.routeName,
          builder: (_, __) {
            workspaceOnHomeEntry = openWorkspaceNotifier.value?.workspaceId;
            return const Scaffold(body: Text('工作区首页'));
          },
        ),
        GoRoute(
          path: MobileNotificationsScreenV2.routeName,
          builder: (_, __) => Scaffold(
            body: NotificationItem(
              tabType: NotificationTabType.system,
              reminder: reminder,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ReminderBloc>.value(value: reminderBloc),
          BlocProvider<AppearanceSettingsCubit>.value(value: appearanceCubit),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (pushFromHome) {
      unawaited(router.push<void>(MobileNotificationsScreenV2.routeName));
      await tester.pumpAndSettle();
    }
    expect(find.text('成功加入工作区'), findsOneWidget);
    await tester.tap(find.text('成功加入工作区'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('手机点击未读加入通知先传递工作区目标再进入首页', (tester) async {
    final router = await showNotification(tester);

    expect(
      router.routeInformationProvider.value.uri.path,
      MobileHomeScreen.routeName,
    );
    expect(workspaceOnHomeEntry, 'target-workspace');
    expect(find.text('工作区首页'), findsOneWidget);
    final event = verify(() => reminderBloc.add(captureAny())).captured.single
        as ReminderEvent;
    final update = event.mapOrNull(update: (event) => event.update);
    expect(update?.id, 'joined-notification');
    expect(update?.isRead, isTrue);
  });

  testWidgets('手机已读通知仍可跳转，关闭从首页打开的通知路由', (tester) async {
    final router =
        await showNotification(tester, isRead: true, pushFromHome: true);

    expect(
      router.routeInformationProvider.value.uri.path,
      MobileHomeScreen.routeName,
    );
    expect(openWorkspaceNotifier.value?.workspaceId, 'target-workspace');
    expect(router.canPop(), isFalse);
    expect(find.text('成功加入工作区'), findsNothing);
    verifyNever(() => reminderBloc.add(any()));
  });

  testWidgets('手机无来源工作区的系统通知只标记已读，停留通知页', (tester) async {
    final router = await showNotification(tester, workspaceId: '');

    expect(
      router.routeInformationProvider.value.uri.path,
      MobileNotificationsScreenV2.routeName,
    );
    expect(openWorkspaceNotifier.value, isNull);
    verify(() => reminderBloc.add(any())).called(1);
  });

  testWidgets('手机兼容只有 payload 元数据的历史系统通知', (tester) async {
    final router = await showNotification(tester, legacyPayload: true);

    expect(
      router.routeInformationProvider.value.uri.path,
      MobileHomeScreen.routeName,
    );
    expect(workspaceOnHomeEntry, 'target-workspace');
  });
}
