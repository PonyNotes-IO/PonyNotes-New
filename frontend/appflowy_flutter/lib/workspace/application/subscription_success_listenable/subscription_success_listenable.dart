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

  void onPaymentSuccess(String? plan) {
    Log.info("Payment success: generated random plan: $plan");
    _plan = plan;
    notifyListeners();
  }
}
