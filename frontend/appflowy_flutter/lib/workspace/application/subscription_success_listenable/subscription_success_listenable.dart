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

  Future<void> _fetchAndNotify(String? fallbackPlan) async {
    try {
      final userService = getIt<AuthService>();
      final userResult = await userService.getUser();
      
      final user = userResult.fold(
        (user) => user,
        (_) => null,
      );
      
      if (user == null) {
        Log.warn('[SubscriptionSuccessListenable] user is null, using fallback plan');
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
        Log.info('[SubscriptionSuccessListenable] fetched planCode from server: $planCode');
        _notifyWithPlan(planCode);
      } else {
        Log.warn('[SubscriptionSuccessListenable] failed to fetch subscription, using fallback plan: $fallbackPlan');
        _notifyWithPlan(fallbackPlan);
      }
    } catch (e, s) {
      Log.error('[SubscriptionSuccessListenable] error fetching subscription: $e', e, s);
      _notifyWithPlan(fallbackPlan);
    }
  }

  void _notifyWithPlan(String? plan) {
    if (plan == null) {
      Log.warn('[SubscriptionSuccessListenable] plan is null, skipping notification');
      return;
    }
    
    if (_plan == plan) {
      Log.info('[SubscriptionSuccessListenable] plan is same as current, skipping duplicate notification');
      return;
    }
    
    _plan = plan;
    Log.info('[SubscriptionSuccessListenable] notifying listeners with plan: $plan, message: $upgradeSuccessMessage');
    notifyListeners();
  }
}
