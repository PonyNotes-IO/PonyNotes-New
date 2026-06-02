import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flowy_infra/theme_extension.dart';

import '../models/schedule_model.dart';

/// 右侧事件详情面板
///
/// 展示日程的标题、日期时间、描述等详细信息，并提供编辑和删除操作。
/// 颜色全部使用 AFThemeExtension / ColorScheme，适配亮/暗主题。
class EventDetailPanel extends StatelessWidget {
  final ScheduleItem schedule;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onClose;

  const EventDetailPanel({
    super.key,
    required this.schedule,
    this.onEdit,
    this.onDelete,
    this.onClose,
  });

  /// 将 repeatType 数字映射为可读文本
  String _repeatTypeLabel(int repeatType) {
    switch (repeatType) {
      case 1:
        return '每天';
      case 2:
        return '每周';
      case 3:
        return '每年';
      case 4:
        return '法定工作日';
      case 99:
        return '自定义';
      default:
        return '无';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AFThemeExtension.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          left: BorderSide(
            color: theme.onBackground.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Header ──
          _buildHeader(context, theme, colorScheme),
          // ── Body (scrollable) ──
          Expanded(
            child: _buildBody(context, theme, colorScheme),
          ),
          // ── Footer ──
          _buildFooter(context, theme, colorScheme),
        ],
      ),
    );
  }

  // ==========================================================================
  // Header
  // ==========================================================================

  Widget _buildHeader(
    BuildContext context,
    AFThemeExtension theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.onBackground.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              schedule.title.isNotEmpty ? schedule.title : '日程详情',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.onBackground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.onBackground.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Body
  // ==========================================================================

  Widget _buildBody(
    BuildContext context,
    AFThemeExtension theme,
    ColorScheme colorScheme,
  ) {
    final infoTextStyle = TextStyle(
      fontSize: 14,
      color: theme.onBackground,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 日期 ──
          _InfoRow(
            icon: Icons.calendar_today,
            iconColor: theme.onBackground.withValues(alpha: 0.7),
            child: Text(
              DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(schedule.startTime),
              style: infoTextStyle,
            ),
          ),
          const SizedBox(height: 12),

          // ── 时间 / 全天 ──
          if (schedule.isAllDay)
            _InfoRow(
              icon: Icons.wb_sunny,
              iconColor: theme.onBackground.withValues(alpha: 0.7),
              child: Text('全天事件', style: infoTextStyle),
            )
          else
            _InfoRow(
              icon: Icons.access_time,
              iconColor: theme.onBackground.withValues(alpha: 0.7),
              child: Text(
                '${DateFormat('HH:mm').format(schedule.startTime)}'
                ' - '
                '${DateFormat('HH:mm').format(schedule.endTime)}',
                style: infoTextStyle,
              ),
            ),
          const SizedBox(height: 12),

          // ── 描述 ──
          if (schedule.description.isNotEmpty) ...[
            Text(
              '描述',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.onBackground.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              schedule.description,
              style: infoTextStyle.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
          ],

          // ── 重要 ──
          if (schedule.isImportant) ...[
            _InfoRow(
              icon: Icons.star,
              iconColor: colorScheme.primary,
              child: Text(
                '重要',
                style: infoTextStyle.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── 重复 ──
          if (schedule.repeatType != 0) ...[
            _InfoRow(
              icon: Icons.repeat,
              iconColor: theme.onBackground.withValues(alpha: 0.7),
              child: Text(
                '重复: ${_repeatTypeLabel(schedule.repeatType)}',
                style: infoTextStyle,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // Footer
  // ==========================================================================

  Widget _buildFooter(
    BuildContext context,
    AFThemeExtension theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.onBackground.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // ── 删除按钮（左侧） ──
          if (onDelete != null)
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: colorScheme.error,
                ),
              ),
            ),
          const Spacer(),
          // ── 编辑按钮（右侧） ──
          if (onEdit != null)
            ElevatedButton(
              onPressed: onEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                '编辑',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================================================
// InfoRow helper widget
// ==========================================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}
