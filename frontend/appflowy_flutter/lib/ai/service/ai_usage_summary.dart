import 'dart:math' as math;

import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';

/// Shared AI usage summary / 共享 AI 使用次数口径
class AiUsageSummary {
  const AiUsageSummary._({
    required this.hasUsage,
    required this.isUnlimited,
    required this.isUnsubscribed,
    required this.used,
    required this.total,
    required this.remaining,
  });

  factory AiUsageSummary.fromUsage(WorkspaceUsagePB? usage) {
    if (usage == null) {
      return const AiUsageSummary._(
        hasUsage: false,
        isUnlimited: false,
        isUnsubscribed: false,
        used: 0,
        total: 0,
        remaining: 0,
      );
    }

    final total = usage.aiResponsesCountLimit.toInt();
    final used = usage.aiResponsesCount.toInt();
    final isUnlimited = usage.aiResponsesUnlimited;
    final isUnsubscribed = total == -1;
    final remaining =
        isUnlimited || isUnsubscribed ? 0 : math.max(0, total - used);

    return AiUsageSummary._(
      hasUsage: true,
      isUnlimited: isUnlimited,
      isUnsubscribed: isUnsubscribed,
      used: used,
      total: total,
      remaining: remaining,
    );
  }

  final bool hasUsage;
  final bool isUnlimited;
  final bool isUnsubscribed;
  final int used;
  final int total;
  final int remaining;

  bool get hasLimitedQuota => hasUsage && !isUnlimited && !isUnsubscribed;

  String remainingAvailableText() {
    if (isUnlimited) {
      return '不限次数';
    }
    if (isUnsubscribed) {
      return '未订阅，不可用';
    }
    if (!hasUsage) {
      return '--';
    }
    return '$remaining次可用';
  }

  String monthlyRemainingText() {
    if (isUnlimited) {
      return '不限次数';
    }
    if (isUnsubscribed) {
      return '未订阅，不可用';
    }
    if (!hasUsage) {
      return '--';
    }
    return '本月剩余$remaining次';
  }
}
