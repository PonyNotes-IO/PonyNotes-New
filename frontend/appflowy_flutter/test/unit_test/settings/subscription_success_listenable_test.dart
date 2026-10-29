import 'dart:convert';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/workspace/application/settings/account/account_management_bloc.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _AuthService extends Mock implements AuthService {}

void main() {
  final originalEnd = DateTime.utc(2030, 1, 31);
  late SubscriptionSuccessListenable listenable;
  late DateTime serverEnd;
  late String serverPlan;
  late int notifications;

  setUp(() async {
    Log.shared.disableLog = true;
    await getIt.reset();
    final auth = _AuthService();
    when(auth.getUser).thenAnswer(
      (_) async => FlowyResult.success(UserProfilePB()..token = 'test-token'),
    );
    getIt.registerSingleton<AuthService>(auth);
    getIt.registerSingleton<AppFlowyCloudSharedEnv>(
      AppFlowyCloudSharedEnv(
        authenticatorType: AuthenticatorType.appflowyCloudSelfHost,
        appflowyCloudConfig: AppFlowyCloudConfiguration(
          base_url: 'https://membership.test',
          ws_base_url: 'wss://membership.test/ws',
          gotrue_url: 'https://auth.membership.test',
          base_web_domain: 'https://membership.test',
          enable_sync_trace: false,
        ),
      ),
    );
    serverEnd = originalEnd;
    serverPlan = 'profersor';
    SubscriptionService().clearCache();
    SubscriptionService().httpClientForTesting = MockClient((request) async {
      expect(request.url.path, '/api/subscription/current');
      return http.Response(
        jsonEncode({
          'data': {
            'subscription': {
              'plan_code': serverPlan,
              'status': 'active',
              'end_date': serverEnd.toIso8601String(),
            },
            'plan_details': {'id': 3, 'plan_code': serverPlan},
          },
        }),
        200,
      );
    });
    listenable = SubscriptionSuccessListenable()
      ..syncCurrentPlan('profersor', endDate: originalEnd);
    getIt.registerSingleton<SubscriptionSuccessListenable>(listenable);
    notifications = 0;
    listenable.addListener(() => notifications++);
  });

  tearDown(() async {
    listenable.dispose();
    SubscriptionService().httpClientForTesting = http.Client();
    SubscriptionService().clearCache();
    await getIt.reset();
    Log.shared.disableLog = false;
  });

  Future<void> paymentSuccess() async {
    listenable.onPaymentSuccess(null);
    await pumpEventQueue();
  }

  for (final duration in PurchaseDurationOption.values) {
    blocTest<AccountManagementBloc, AccountManagementState>(
      'same tier ${duration.name} purchase enters the payment flow',
      build: () => AccountManagementBloc(
        workspaceId: 'workspace',
        userProfile: UserProfilePB()..token = 'test-token',
        currentSubscription: null,
      ),
      seed: () => AccountManagementState.ready(
        subscriptionInfo: WorkspaceSubscriptionInfoPB()
          ..plan = WorkspacePlanPB.ProPlan,
        planConfigs: {
          WorkspacePlanPB.ProPlan: RemotePlan.fromJson({
            'id': 3,
            'plan_code': 'profersor',
            'monthly_price_yuan': 15,
            'yearly_price_yuan': 150,
          }),
        },
        selectedPlan: WorkspacePlanPB.ProPlan,
        selectedDuration: duration,
        agreedProtocols: true,
      ),
      act: (bloc) => bloc.add(const AccountManagementEvent.handleUpgradePay()),
      expect: () => [
        predicate<AccountManagementState>(
          (state) => state.maybeMap(
            ready: (state) => state.isProcessingPayment && state.error == null,
            orElse: () => false,
          ),
        ),
        predicate<AccountManagementState>(
          (state) => state.maybeMap(
            ready: (state) => state.paymentResult == 'PAYMENT_INITIATED',
            orElse: () => false,
          ),
        ),
      ],
    );
  }

  test('same tier renewal refreshes expiry and repeated callbacks stay silent',
      () async {
    for (final end in [DateTime.utc(2030, 2, 28), DateTime.utc(2031, 2, 28)]) {
      serverEnd = end;
      final previousNotifications = notifications;
      await paymentSuccess();
      expect(notifications, previousNotifications + 1);
      expect(listenable.upgradeSuccessMessage, '会员续费成功，有效期已延长');
      expect(
        SubscriptionService().cachedCurrentSubscription?.subscription?.endDate,
        end,
      );
      await paymentSuccess();
      expect(notifications, previousNotifications + 1);
    }
  });

  test('restoring the same tier and expiry does not announce a purchase',
      () async {
    await paymentSuccess();
    expect(notifications, 0);
  });

  test('upgrading the tier still notifies listeners', () async {
    serverPlan = 'hiclass';
    await paymentSuccess();
    expect(notifications, 1);
    expect(listenable.upgradeSuccessMessage, '您已升级到小马笔记高级版');
  });
}
