import 'dart:convert';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 覆盖 PonyNotes 新会员体系里 GET /api/subscription/current 在客户端的解析，
/// 对应 devops-docs 2026-07-07 会员测试方案里的用例 A/E/F 涉及的响应字段
/// （plan_code、status、grace_period_end、downgraded_from_plan_id）。
///
/// 只测"客户端把后端响应解析/展示成什么样"，不重复测后端业务规则本身
/// （规则判断权在后端，客户端只是原样透传/展示，见客户端对接测试规划文档）。
void main() {
  const testBaseUrl = 'https://api.xiaomabiji.com';

  late UserProfilePB userProfile;

  setUp(() {
    userProfile = UserProfilePB()
      ..token = jsonEncode({'access_token': 'mock-access-token'});

    getIt.reset();
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

  Map<String, dynamic> currentResponseBody({
    required String planCode,
    required String planNameCn,
    required String status,
    String? gracePeriodEnd,
    int? downgradedFromPlanId,
  }) {
    return {
      'code': 0,
      'data': {
        'subscription': {
          'plan_code': planCode,
          'plan_name_cn': planNameCn,
          'billing_type': 'monthly',
          'status': status,
          'start_date': '2026-07-07T00:00:00Z',
          'end_date': '2026-08-07T00:00:00Z',
          'grace_period_end': gracePeriodEnd,
          'downgraded_from_plan_id': downgradedFromPlanId,
        },
        'plan_details': {
          'id': 3,
          'plan_code': planCode,
          'plan_name': planCode,
          'plan_name_cn': planNameCn,
          'monthly_price_yuan': 8.0,
          'yearly_price_yuan': 80.0,
          'cloud_storage_gb': 100,
          'has_inbox': true,
          'has_multi_device_sync': true,
          'has_api_support': true,
          'version_history_days': 7,
          'ai_chat_count_per_month': 40,
          'ai_image_generation_per_month': 10,
          'has_share_link': true,
          'has_publish': true,
          'workspace_member_limit': 5,
          'collaborative_workspace_limit': -1,
          'page_permission_guest_editors': 10,
          'has_space_member_management': true,
          'has_space_member_grouping': false,
          'is_active': true,
        },
        'usage': {
          'ai_chat_used_this_month': 1,
          'ai_chat_remaining_this_month': 39,
          'ai_image_used_this_month': 0,
          'ai_image_remaining_this_month': 10,
          'storage_used': '10 MB',
          'storage_total': '100 MB',
          'storage_remaining': '90 MB',
          'storage_used_gb': 0.01,
          'storage_total_gb': 0.1,
        },
      },
    };
  }

  group('SubscriptionService.getCurrentSubscription 用例A/C：升级/续费后套餐展示', () {
    test('后端返回 profersor(专业版) 时，客户端应展示为专业版，非宽限期', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/subscription/current');
        expect(request.headers['Authorization'], 'Bearer mock-access-token');
        return http.Response(
          jsonEncode(
            currentResponseBody(
              planCode: 'profersor',
              planNameCn: '专业版',
              status: 'active',
            ),
          ),
          200,
        );
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final result = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: true,
      );

      expect(result, isNotNull);
      expect(result!.subscription!.planCode, 'profersor');
      expect(result.subscription!.planNameCn, '专业版');
      expect(result.subscription!.status, 'active');
      expect(result.subscription!.isInGracePeriod, isFalse);
      expect(result.subscription!.isDowngraded, isFalse);
    });
  });

  group('SubscriptionService.getCurrentSubscription 用例E：到期降级免费版', () {
    test('后端到期后返回 mfb(免费版)，客户端应展示为免费版', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(
            currentResponseBody(
              planCode: 'mfb',
              planNameCn: '免费版',
              status: 'active',
            ),
          ),
          200,
        );
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final result = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: true,
      );

      expect(result!.subscription!.planCode, 'mfb');
      expect(result.subscription!.planNameCn, '免费版');
    });
  });

  group('SubscriptionService.getCurrentSubscription 用例F：15天宽限期展示', () {
    test('grace_period_end 在未来时，isInGracePeriod 应为 true 且剩余天数为正', () async {
      final graceEnd = DateTime.now()
          .toUtc()
          .add(const Duration(days: 14))
          .toIso8601String();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(
            currentResponseBody(
              planCode: 'standard',
              planNameCn: '标准版',
              status: 'active',
              gracePeriodEnd: graceEnd,
              downgradedFromPlanId: 4,
            ),
          ),
          200,
        );
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final result = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: true,
      );

      final summary = result!.subscription!;
      expect(summary.isInGracePeriod, isTrue);
      expect(summary.isDowngraded, isTrue);
      expect(summary.downgradedFromPlanId, 4);
      // 允许 ±1 天误差（跨零点边界），核心是不应该是负数或远超15天
      expect(summary.daysUntilGracePeriodEnd, inInclusiveRange(12, 14));
    });

    test('grace_period_end 已过去时，isInGracePeriod 应为 false（对应宽限期已结束场景）',
        () async {
      final pastGraceEnd = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(
            currentResponseBody(
              planCode: 'mfb',
              planNameCn: '免费版',
              status: 'active',
              gracePeriodEnd: pastGraceEnd,
              downgradedFromPlanId: 4,
            ),
          ),
          200,
        );
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final result = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: true,
      );

      expect(result!.subscription!.isInGracePeriod, isFalse);
    });
  });

  group('SubscriptionService.getCurrentSubscription 异常路径', () {
    test('后端返回非0业务错误码时，data为null，客户端应返回null而不是抛异常', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 1, 'message': '订阅不存在', 'data': null}),
          200,
        );
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final result = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: true,
      );

      expect(result, isNull);
    });

    test('后端返回404时，客户端应返回null，不应抛异常', () async {
      final mockClient = MockClient((request) async {
        return http.Response('', 404);
      });
      SubscriptionService().httpClientForTesting = mockClient;

      final result = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: true,
      );

      expect(result, isNull);
    });

    test('10分钟缓存内不应重复发起网络请求', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode(
            currentResponseBody(
              planCode: 'standard',
              planNameCn: '标准版',
              status: 'active',
            ),
          ),
          200,
        );
      });
      SubscriptionService().httpClientForTesting = mockClient;

      await SubscriptionService()
          .getCurrentSubscription(userProfile: userProfile, forceRefresh: true);
      await SubscriptionService()
          .getCurrentSubscription(userProfile: userProfile);
      await SubscriptionService()
          .getCurrentSubscription(userProfile: userProfile);

      expect(requestCount, 1);
    });
  });
}
