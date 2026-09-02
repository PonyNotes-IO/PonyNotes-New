import 'dart:async';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/foundation.dart';

import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

class SubscriptionSuccessListenable extends ChangeNotifier {
  SubscriptionSuccessListenable();

  String? _plan;
  bool _isProcessing = false;

  SubscriptionPlanPB? get subscribedPlan => switch (_plan?.toLowerCase()) {
        'free' => SubscriptionPlanPB.Free,
        // 服务端真实免费版 plan_code 是 "mfb"，此前只写了顺序颠倒的 "fmb"。
        'mfb' => SubscriptionPlanPB.Free,
        'fmb' => SubscriptionPlanPB.Free,
        'standard' => SubscriptionPlanPB.Stand,
        'stand' => SubscriptionPlanPB.Stand,
        'professor' => SubscriptionPlanPB.Pro,
        'pro' => SubscriptionPlanPB.Pro,
        'profersor' => SubscriptionPlanPB.Pro,
        'hiclass' => SubscriptionPlanPB.Hiclass,
        'team' => SubscriptionPlanPB.Hiclass,
        'ai_max' => SubscriptionPlanPB.AiMax,
        'ai_local' => SubscriptionPlanPB.AiLocal,
        _ => null,
      };

  String get upgradeSuccessMessage {
    final planCode = _plan?.toLowerCase();
    return switch (planCode) {
      'standard' => '您已升级到小马笔记标准版',
      'stand' => '您已升级到小马笔记标准版',
      'professor' => '您已升级到小马笔记专业版',
      'pro' => '您已升级到小马笔记专业版',
      'profersor' => '您已升级到小马笔记专业版',
      'hiclass' => '您已升级到小马笔记高级版',
      'team' => '您已升级到小马笔记高级版',
      _ => '您已成功升级会员',
    };
  }

  void onPaymentSuccess(String? plan) {
    Log.info("[SubscriptionSuccessListenable] onPaymentSuccess: $plan");

    if (_isProcessing) {
      Log.info('[SubscriptionSuccessListenable] already processing, skipping');
      return;
    }

    _isProcessing = true;

    _fetchAndNotify(plan).whenComplete(() {
      _isProcessing = false;
    });
  }

  /// 同步当前会员版本到内部去重基线（不触发通知）。
  ///
  /// 在用户订阅信息加载时调用，将当前 planCode 设置为 `_plan`，
  /// 这样后续 `onPaymentSuccess` 如果返回的是同一个 planCode，
  /// `_notifyWithPlan` 的去重逻辑会正确跳过，避免对已持有套餐
  /// 重复弹出"升级成功"提示（典型场景：苹果内购 restored 事件
  /// 对已有套餐重复 verify 后误弹）。
  void syncCurrentPlan(String? plan) {
    if (plan == null || plan.isEmpty) return;
    if (_plan == plan) return;
    _plan = plan;
    Log.info(
        '[SubscriptionSuccessListenable] synced current plan: $plan (no notification)');
  }

  Future<void> _fetchAndNotify(String? fallbackPlan) async {
    try {
      final userService = getIt<AuthService>();
      final userResult = await userService.getUser();

      final user = userResult.fold(
        (user) => user,
        (_) => null,
      );

      if (user == null) {
        Log.warn(
            '[SubscriptionSuccessListenable] user is null, using fallback plan');
        _notifyWithPlan(fallbackPlan);
        return;
      }

      final subscriptionService = SubscriptionService();
      final subscription = await subscriptionService.getCurrentSubscription(
        userProfile: user,
        forceRefresh: true,
        caller: 'SubscriptionSuccessListenable',
      );

      if (subscription != null &&
          subscription.subscription != null &&
          subscription.subscription!.planCode != null) {
        final planCode = subscription.subscription!.planCode!;
        Log.info(
            '[SubscriptionSuccessListenable] fetched planCode from server: $planCode');
        _notifyWithPlan(planCode);
      } else {
        Log.warn(
            '[SubscriptionSuccessListenable] failed to fetch subscription, using fallback plan: $fallbackPlan');
        _notifyWithPlan(fallbackPlan);
      }
    } catch (e, s) {
      Log.error(
          '[SubscriptionSuccessListenable] error fetching subscription: $e',
          e,
          s);
      _notifyWithPlan(fallbackPlan);
    }
  }

  void _notifyWithPlan(String? plan) {
    if (plan == null) {
      Log.warn(
          '[SubscriptionSuccessListenable] plan is null, skipping notification');
      return;
    }

    if (_plan == plan) {
      Log.info(
          '[SubscriptionSuccessListenable] plan is same as current, skipping duplicate notification');
      return;
    }

    _plan = plan;
    Log.info(
        '[SubscriptionSuccessListenable] notifying listeners with plan: $plan, message: $upgradeSuccessMessage');
    notifyListeners();
  }
}
