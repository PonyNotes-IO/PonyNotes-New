import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:flutter/material.dart';

/// AI会话使用情况显示组件
class AIChatUsageIndicator extends StatelessWidget {
  const AIChatUsageIndicator({
    super.key,
    required this.usage,
  });

  final WorkspaceUsagePB? usage;

  @override
  Widget build(BuildContext context) {
    if (usage == null) {
      // 数据未加载，不显示
      return const SizedBox.shrink();
    }

    // 如果无限制，不显示
    if (usage!.aiResponsesUnlimited) {
      return const SizedBox.shrink();
    }

    final used = usage!.aiResponsesCount.toInt();
    final total = usage!.aiResponsesCountLimit.toInt();
    final remaining = total - used;

    // 验证数据有效性（确保不是默认值）
    if (total == 0) {
      // 限制为0且非无限制，可能是数据未正确加载，不显示
      return const SizedBox.shrink();
    }

    // 根据剩余次数选择颜色
    final textColor = _getTextColor(context, remaining);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        _getDisplayText(used, total, remaining),
        style: TextStyle(
          fontSize: 12,
          color: textColor,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _getDisplayText(int used, int total, int remaining) {
    if (remaining <= 0) {
      return '$used/$total 0次可用';
    }
    return '$used/$total $remaining次可用';
  }

  Color _getTextColor(BuildContext context, int remaining) {
    if (remaining <= 0) {
      return Theme.of(context).colorScheme.error;
    } else if (remaining <= 5) {
      return Colors.orange.shade700;
    } else {
      return Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    }
  }
}

