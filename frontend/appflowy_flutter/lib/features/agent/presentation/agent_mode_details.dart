import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Shared mode information for the agent selector and the @ picker.
class AgentModeDetails extends StatelessWidget {
  const AgentModeDetails({
    super.key,
    required this.smart,
    required this.current,
    this.onSelected,
    this.startsNewConversation = false,
  });

  final bool smart;
  final bool current;
  final VoidCallback? onSelected;
  final bool startsNewConversation;

  static String label(bool smart) => smart ? '智能推理' : '快问快答';
  static IconData icon(bool smart) =>
      smart ? Icons.auto_awesome_outlined : Icons.bolt_outlined;

  @override
  Widget build(BuildContext context) {
    final foreground =
        AppFlowyTheme.maybeOf(context)?.textColorScheme.primary ??
            Theme.of(context).colorScheme.onSurface;
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return DefaultTextStyle.merge(
      style: textStyle?.copyWith(fontSize: 12, color: foreground),
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon(smart),
                  size: 30,
                  color: Colors.indigo.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label(smart),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        current
                            ? '当前模式'
                            : startsNewConversation
                                ? '新建此模式的对话'
                                : '点击切换',
                        style: TextStyle(
                          fontSize: 10,
                          color: foreground.withValues(alpha: .45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              smart ? '多步思考，深入分析与执行任务' : '检索相关资料，快速获得回答',
              style: TextStyle(
                fontSize: 11,
                color: foreground.withValues(alpha: .55),
              ),
            ),
            Divider(height: 22, color: foreground.withValues(alpha: .06)),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final label in [smart ? '多步推理' : '快速回答', '知识检索', '多轮对话'])
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 6,
                      ),
                      child: Text(label, style: const TextStyle(fontSize: 10)),
                    ),
                  ),
              ],
            ),
            Divider(height: 22, color: foreground.withValues(alpha: .06)),
            Text(
              '能力',
              style: TextStyle(
                fontSize: 10,
                color: foreground.withValues(alpha: .45),
              ),
            ),
            const SizedBox(height: 7),
            for (final label in ['资料引用', '附件上传'])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 13),
                    const SizedBox(width: 6),
                    Text(label, style: const TextStyle(fontSize: 11)),
                    const Spacer(),
                    Text(
                      '支持',
                      style: TextStyle(
                        fontSize: 10,
                        color: foreground.withValues(alpha: .45),
                      ),
                    ),
                  ],
                ),
              ),
            if (!current && onSelected != null)
              TextButton(
                onPressed: onSelected,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  textStyle: textStyle?.copyWith(fontSize: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(startsNewConversation ? '新建此模式的对话' : '使用此模式'),
              ),
          ],
        ),
      ),
    );
  }
}
