import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/home/af_focus_manager.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/widgets/cloud_sync_settings_panel.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/widgets/sidebar_cloud_sync_button.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _WorkspaceBloc extends MockBloc<UserWorkspaceEvent, UserWorkspaceState>
    implements UserWorkspaceBloc {}

class _NavigationObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  final popped = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

void main() {
  for (final inPopover in [false, true]) {
    testWidgets(
        'renew opens settings from ${inPopover ? 'closed popover' : 'inline button'}',
        (tester) async {
      Localization.load(
        const Locale('zh', 'CN'),
        translations: Translations(
          jsonDecode(
            File('../resources/translations/zh-CN.json').readAsStringSync(),
          ),
        ),
      );
      final bloc = _WorkspaceBloc();
      final state = UserWorkspaceState(
        userProfile: UserProfilePB()..userAuthType = AuthTypePB.Server,
        workspaceSubscriptionInfo: WorkspaceSubscriptionInfoPB(),
        currentSubscription: CurrentSubscription(
          subscription: SubscriptionSummary.fromJson({
            'plan_code': 'standard',
            'end_date':
                DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
          }),
          planDetails: null,
          usage: null,
        ),
      );
      when(() => bloc.state).thenReturn(state);
      final popover = PopoverController();
      final navigator = GlobalKey<NavigatorState>();
      final observer = _NavigationObserver();
      final button = BlocProvider<UserWorkspaceBloc>.value(
        value: bloc,
        child: SidebarCloudSyncButton(
          onBeforeAction: inPopover ? popover.close : null,
        ),
      );

      await tester.pumpWidget(
        AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            home: AFFocusManager(
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: inPopover
                      ? Popover(
                          controller: popover,
                          popupBuilder: (_) => button,
                          child: TextButton(
                            onPressed: popover.show,
                            child: const Text('More'),
                          ),
                        )
                      : button,
                ),
              ),
            ),
          ),
        ),
      );
      var focusNotifications = 0;
      tester
          .widget<AFFocusManager>(find.byType(AFFocusManager))
          .loseFocusNotifier
          .addListener(() => focusNotifications++);
      if (inPopover) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.descendant(
          of: find.byType(SidebarCloudSyncButton),
          matching: find.byType(FlowyButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(SidebarCloudSyncButton),
        inPopover ? findsNothing : findsOneWidget,
      );
      expect(find.byType(CloudSyncSettingsPanel), findsOneWidget);
      final cloudSyncRoute = observer.pushed.last;
      await tester
          .tap(find.text(LocaleKeys.newSettings_cloudSync_btnRenew.tr()));

      expect(tester.takeException(), isNull);
      expect(observer.popped, contains(cloudSyncRoute));
      expect(observer.pushed, hasLength(3));
      expect(observer.pushed.last, isA<DialogRoute<void>>());
      if (!inPopover) expect(focusNotifications, 1);

      // Only verify navigation here; building settings starts backend services.
      navigator.currentState!.removeRoute(observer.pushed.last);
      await tester.pumpAndSettle();
      expect(find.byType(CloudSyncSettingsPanel), findsNothing);
    });
  }
}
