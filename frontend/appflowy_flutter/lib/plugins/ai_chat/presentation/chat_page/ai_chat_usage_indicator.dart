import 'package:appflowy/ai/service/ai_usage_summary.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:flutter/material.dart';

/// AI chat usage indicator / AI 会话使用情况显示组件
class AIChatUsageIndicator extends StatelessWidget {
  const AIChatUsageIndicator({
    super.key,
    required this.usage,
  });

  final WorkspaceUsagePB? usage;

  @override
  Widget build(BuildContext context) {
    final summary = AiUsageSummary.fromUsage(usage);
    if (!summary.hasUsage || summary.isUnlimited) {
      return const SizedBox.shrink();
    }

    if (summary.isUnsubscribed) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          summary.remainingAvailableText(),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!summary.hasLimitedQuota || summary.total == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        summary.remainingAvailableText(),
        style: TextStyle(
          fontSize: 12,
          color: _getTextColor(context, summary.remaining),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Color _getTextColor(BuildContext context, int remaining) {
    if (remaining <= 0) {
      return Theme.of(context).colorScheme.error;
    }
    if (remaining <= 5) {
      return Colors.orange.shade700;
    }
    return Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
  }
}
