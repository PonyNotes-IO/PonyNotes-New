import 'dart:convert';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/subscription/membership_checker_service.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 覆盖"功能受限"弹窗循环弹出问题的修复：
///
/// 1. 未登录（快速体验 Local）用户没有会员/存储配额概念，checkStorageLimit
///    应直接放行。此前 getCurrentSubscription 返回 null 时，(0+0)<0 恒为 false，
///    被误判为"空间已满"，导致生命周期检查反复触发"功能受限"弹窗。
/// 2. 登录用户无订阅数据（null）时同样不应误判为空间已满。
/// 3. 登录用户有订阅数据时，原有配额判断逻辑保持不变。
void main() {
  const testBaseUrl = 'https://api.xiaomabiji.com';

  late UserProfilePB serverUserProfile;

  http.Response jsonResponse(Object? body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() async {
    serverUserProfile = UserProfilePB()
      ..userAuthType = AuthTypePB.Server
      ..token = jsonEncode({'access_token': 'mock-access-token'});

    await getIt.reset();
    getIt.registerSingleton<AppFlowyCloudSharedEnv>(
      AppFlowyCloudSharedEnv(
        authenticatorType: AuthenticatorType.appflowyCloudSelfHost,
        appflowyCloudConfig: AppFlowyCloudConfiguration(
          base_url: testBaseUrl,
          ws_base_url: 'wss://api.xiaomabiji.com/ws/v1',
          gotrue_url: 'https://gotrue.xiaomabiji.com',
          enable_sync_trace: false,
          base_web_domain: 'https://xiaomabiji.com',
        ),
      ),
    );

    SubscriptionService().clearCache();
  });

  UserProfilePB quickEntryUserProfile() => UserProfilePB()
    ..userAuthType = AuthTypePB.Local;

  group('MembershipCheckerService.checkStorageLimit 未登录用户', () {
    test('快速体验（Local）用户直接放行，不发起任何网络请求', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return jsonResponse({'code': 0, 'data': null});
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final canUse = await MembershipCheckerService().checkStorageLimit(
        userProfile: quickEntryUserProfile(),
        requiredStorageMB: 0,
      );

      expect(canUse, isTrue);
      expect(requestCount, 0, reason: '未登录用户不应发起订阅请求');
    });
  });

  group('MembershipCheckerService.checkStorageLimit 登录用户无订阅数据', () {
    test('后端无订阅（返回 null）时不误判为空间已满', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse({'code': 0, 'data': null});
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final canUse = await MembershipCheckerService().checkStorageLimit(
        userProfile: serverUserProfile,
        requiredStorageMB: 0,
      );

      expect(canUse, isTrue);
    });
  });

  group('MembershipCheckerService.checkStorageLimit 登录用户有订阅数据', () {
    Map<String, dynamic> subscriptionBody({
      required double usedGb,
      required double totalGb,
    }) {
      return {
        'code': 0,
        'data': {
          'subscription': {
            'plan_code': 'profersor',
            'plan_name_cn': '专业版',
            'billing_type': 'monthly',
            'status': 'active',
            'start_date': '2026-07-07T00:00:00Z',
            'end_date': '2026-08-07T00:00:00Z',
          },
          'plan_details': {
            'id': 3,
            'plan_code': 'profersor',
            'plan_name': 'profersor',
            'cloud_storage_gb': 100,
            'is_active': true,
          },
          'usage': {
            'storage_used_gb': usedGb,
            'storage_total_gb': totalGb,
          },
        },
      };
    }

    test('剩余空间充足时返回 true', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(subscriptionBody(usedGb: 10, totalGb: 100));
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final canUse = await MembershipCheckerService().checkStorageLimit(
        userProfile: serverUserProfile,
        requiredStorageMB: 0,
      );

      expect(canUse, isTrue);
    });

    test('空间已满时返回 false（原有配额限制逻辑保持不变）', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(subscriptionBody(usedGb: 100, totalGb: 100));
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final canUse = await MembershipCheckerService().checkStorageLimit(
        userProfile: serverUserProfile,
        requiredStorageMB: 0,
      );

      expect(canUse, isFalse);
    });
  });
}
