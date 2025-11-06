import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

class SubscriptionSuccessListenable extends ChangeNotifier {
  SubscriptionSuccessListenable();

  String? _plan;

  SubscriptionPlanPB? get subscribedPlan => switch (_plan) {
        'free' => SubscriptionPlanPB.Free,
        'student' => SubscriptionPlanPB.Student,
        'standard' => SubscriptionPlanPB.Standard,
        'team' => SubscriptionPlanPB.Team,
        'ai_max' => SubscriptionPlanPB.AiMax,
        'ai_local' => SubscriptionPlanPB.AiLocal,
        // Legacy support: map 'pro' to 'standard' for backward compatibility
        'pro' => SubscriptionPlanPB.Standard,
        _ => null,
      };

  void onPaymentSuccess(String? plan) {
    Log.info("Payment success: $plan");
    _plan = plan;
    notifyListeners();
  }
}
