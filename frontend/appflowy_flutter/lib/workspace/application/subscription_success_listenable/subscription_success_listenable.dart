import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

class SubscriptionSuccessListenable extends ChangeNotifier {
  SubscriptionSuccessListenable();

  String? _plan;

  SubscriptionPlanPB? get subscribedPlan => switch (_plan?.toLowerCase()) {
        'free' => SubscriptionPlanPB.Free,
        'fmb' => SubscriptionPlanPB.Free,
        'standard' => SubscriptionPlanPB.Stand,
        'stand' => SubscriptionPlanPB.Stand,
        'professor' => SubscriptionPlanPB.Pro,
        'pro' => SubscriptionPlanPB.Pro,
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
      'hiclass' => '您已升级到小马笔记高级版',
      'team' => '您已升级到小马笔记高级版',
      _ => '您已成功升级会员',
    };
  }

  void onPaymentSuccess(String? plan) {
    Log.info("Payment success: generated random plan: $plan");
    _plan = plan;
    notifyListeners();
  }
}
