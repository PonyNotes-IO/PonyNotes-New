import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flowy_infra/theme_extension.dart';

import '../models/schedule_model.dart';

/// Right-side panel showing full event details.
/// Displays when user clicks an event in the calendar grid.
class EventDetailPanel extends StatelessWidget {
  const EventDetailPanel({
    super.key,
    required this.schedule,
    this.onEdit,
    this.onDelete,
    this.onClose,
  });

  final ScheduleItem schedule;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: af.background,
        border: Border(
          left: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(af, theme),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    af, theme, Icons.calendar_today,
                    _formatDate(schedule.startTime),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    af, theme, Icons.access_time,
                    '${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}',
                  ),
                  if (schedule.isAllDay) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(af, theme, Icons.wb_sunny, '全天事件'),
                  ],
                  if (schedule.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '描述',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: af.onBackground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      schedule.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: af.secondaryTextColor,
                      ),
                    ),
                  ],
                  if (schedule.isImportant) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      af, theme, Icons.star, '重要',
                      iconColor: theme.colorScheme.primary,
                    ),
                  ],
                  if (schedule.repeatType != null &&
                      schedule.repeatType != 'none') ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(af, theme, Icons.repeat, '重复: ${schedule.repeatType}'),
                  ],
                ],
              ),
            ),
          ),
          _buildFooter(af, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(AFThemeExtension af, ThemeData theme) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              schedule.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: af.onBackground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: af.lightIconColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    AFThemeExtension af,
    ThemeData theme,
    IconData icon,
    String text, {
    Color? iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? af.lightIconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: af.onBackground),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AFThemeExtension af, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(4),
            hoverColor: af.lightGreyHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 4),
                  Text(
                    '删除',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: onEdit,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('编辑', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(d);
  String _formatTime(DateTime d) => DateFormat('HH:mm').format(d);
}
