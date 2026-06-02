import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';

import '../models/schedule_model.dart';
import 'widgets/reminder_selection_dialog.dart';

/// 点击日历格子呼出的上下文菜单，用于快速新建日程
///
/// 类似飞书的日历点击效果：在点击位置弹出浮动表单。
/// 颜色全部使用 AFThemeExtension / ColorScheme，适配亮/暗主题。
class CalendarContextMenu {
  CalendarContextMenu._();

  /// 在指定位置显示上下文菜单
  static void show({
    required BuildContext context,
    required Offset position,
    required DateTime date,
    required ScheduleModel scheduleModel,
    VoidCallback? onEventCreated,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) => _CalendarContextMenuOverlay(
        position: position,
        date: date,
        scheduleModel: scheduleModel,
        onDismiss: () => entry.remove(),
        onEventCreated: onEventCreated,
      ),
    );

    overlay.insert(entry);
  }
}

class _CalendarContextMenuOverlay extends StatefulWidget {
  const _CalendarContextMenuOverlay({
    required this.position,
    required this.date,
    required this.scheduleModel,
    required this.onDismiss,
    this.onEventCreated,
  });

  final Offset position;
  final DateTime date;
  final ScheduleModel scheduleModel;
  final VoidCallback onDismiss;
  final VoidCallback? onEventCreated;

  @override
  State<_CalendarContextMenuOverlay> createState() =>
      _CalendarContextMenuOverlayState();
}

class _CalendarContextMenuOverlayState
    extends State<_CalendarContextMenuOverlay> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _focusNode = FocusNode();

  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isAllDay = false;
  bool _isImportant = false;
  ReminderOption _reminderOption = ReminderOption.none;
  bool _isSaving = false;
  bool _showStartTimePicker = false;
  bool _showEndTimePicker = false;

  static const double _menuWidth = 320;
  static const double _menuMaxHeight = 480;

  @override
  void initState() {
    super.initState();
    _startDate = widget.date;
    _endDate = widget.date;
    final now = TimeOfDay.now();
    _startTime = TimeOfDay(hour: now.hour, minute: 0);
    _endTime = TimeOfDay(hour: now.hour + 1, minute: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Offset _calculatePosition(BuildContext context) {
    final size = MediaQuery.of(context).size;
    double x = widget.position.dx;
    double y = widget.position.dy;

    if (x + _menuWidth > size.width) x = size.width - _menuWidth - 16;
    if (y + _menuMaxHeight > size.height) y = size.height - _menuMaxHeight - 16;
    if (x < 16) x = 16;
    if (y < 16) y = 16;

    return Offset(x, y);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showToastNotification(
        message: '请输入日程标题',
        type: ToastificationType.warning,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final startDateTime = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _isAllDay ? 0 : _startTime.hour,
        _isAllDay ? 0 : _startTime.minute,
      );
      final endDateTime = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _isAllDay ? 0 : _endTime.hour,
        _isAllDay ? 0 : _endTime.minute,
      );

      await widget.scheduleModel.createSchedule(
        title: title,
        description: _descriptionController.text.trim(),
        startTime: startDateTime,
        endTime: endDateTime,
        isAllDay: _isAllDay,
        isImportant: _isImportant,
        reminderOption: _reminderOption,
      );

      if (mounted) {
        showToastNotification(
          message: '日程创建成功: $title',
          type: ToastificationType.success,
        );
        widget.onEventCreated?.call();
        widget.onDismiss();
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: '创建失败: $e',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    final af = AFThemeExtension.of(context);
    final theme = Theme.of(context);
    final pos = _calculatePosition(context);

    return Stack(
      children: [
        // 点击外部关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // 菜单主体
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: af.background,
            shadowColor: af.scrollbarColor,
            child: Container(
              width: _menuWidth,
              constraints: const BoxConstraints(maxHeight: _menuMaxHeight),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: af.borderColor, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(af, theme),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitleField(af, theme),
                          const SizedBox(height: 12),
                          _buildTimeSection(af, theme),
                          const SizedBox(height: 12),
                          _buildDescriptionField(af, theme),
                          const SizedBox(height: 12),
                          _buildOptionsRow(af, theme),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  _buildFooter(af, theme),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 顶部标题栏 ----------

  Widget _buildHeader(AFThemeExtension af, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.event, size: 18, color: af.lightIconColor),
          const SizedBox(width: 8),
          Text(
            '新建日程',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: af.onBackground,
            ),
          ),
          const Spacer(),
          Text(
            DateFormat('M月d日 EEEE', 'zh_CN').format(widget.date),
            style: TextStyle(fontSize: 12, color: af.secondaryTextColor),
          ),
        ],
      ),
    );
  }

  // ---------- 标题输入 ----------

  Widget _buildTitleField(AFThemeExtension af, ThemeData theme) {
    return TextField(
      controller: _titleController,
      focusNode: _focusNode,
      style: TextStyle(fontSize: 14, color: af.onBackground),
      decoration: InputDecoration(
        hintText: '日程标题',
        hintStyle: TextStyle(fontSize: 14, color: af.secondaryTextColor),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        // 使用项目统一的边框色
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: af.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: af.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1),
        ),
      ),
      textInputAction: TextInputAction.next,
    );
  }

  // ---------- 时间区域 ----------

  Widget _buildTimeSection(AFThemeExtension af, ThemeData theme) {
    return Column(
      children: [
        // 全天开关
        Row(
          children: [
            Icon(Icons.access_time, size: 16, color: af.lightIconColor),
            const SizedBox(width: 8),
            Text(
              '全天',
              style: TextStyle(fontSize: 13, color: af.secondaryTextColor),
            ),
            const Spacer(),
            SizedBox(
              height: 24,
              child: Switch(
                value: _isAllDay,
                onChanged: (v) => setState(() {
                  _isAllDay = v;
                  if (v) {
                    _showStartTimePicker = false;
                    _showEndTimePicker = false;
                  }
                }),
                activeColor: theme.colorScheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (!_isAllDay) ...[
          const SizedBox(height: 8),
          _buildTimeRow(af, '开始', _startTime, true),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showStartTimePicker
                ? _buildInlineTimePicker(af, _startTime, (t) {
                    setState(() => _startTime = t);
                  })
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
          _buildTimeRow(af, '结束', _endTime, false),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showEndTimePicker
                ? _buildInlineTimePicker(af, _endTime, (t) {
                    setState(() => _endTime = t);
                  })
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  Widget _buildTimeRow(
    AFThemeExtension af,
    String label,
    TimeOfDay time,
    bool isStart,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: af.secondaryTextColor),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                if (isStart) {
                  _showStartTimePicker = !_showStartTimePicker;
                  _showEndTimePicker = false;
                } else {
                  _showEndTimePicker = !_showEndTimePicker;
                  _showStartTimePicker = false;
                }
              });
            },
            borderRadius: BorderRadius.circular(6),
            hoverColor: af.lightGreyHover,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: af.borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 13, color: af.onBackground),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    (isStart ? _showStartTimePicker : _showEndTimePicker)
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: af.lightIconColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineTimePicker(
    AFThemeExtension af,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      margin: const EdgeInsets.only(left: 50, top: 4, bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: af.borderColor),
        borderRadius: BorderRadius.circular(8),
        color: af.background,
      ),
      child: Row(
        children: [
          // 小时滚轮
          Expanded(
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                initialItem: time.hour,
              ),
              itemExtent: 32,
              onSelectedItemChanged: (index) {
                onChanged(TimeOfDay(hour: index, minute: time.minute));
              },
              children: List.generate(24, (index) {
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 16,
                      color: af.onBackground,
                    ),
                  ),
                );
              }),
            ),
          ),
          Text(
            ':',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: af.onBackground,
            ),
          ),
          // 分钟滚轮
          Expanded(
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                initialItem: time.minute ~/ 5,
              ),
              itemExtent: 32,
              onSelectedItemChanged: (index) {
                onChanged(TimeOfDay(hour: time.hour, minute: index * 5));
              },
              children: List.generate(12, (index) {
                final minute = index * 5;
                return Center(
                  child: Text(
                    minute.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 16,
                      color: af.onBackground,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 描述 ----------

  Widget _buildDescriptionField(AFThemeExtension af, ThemeData theme) {
    return TextField(
      controller: _descriptionController,
      style: TextStyle(fontSize: 13, color: af.onBackground),
      maxLines: 2,
      decoration: InputDecoration(
        hintText: '添加描述...',
        hintStyle: TextStyle(fontSize: 13, color: af.secondaryTextColor),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: af.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: af.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1),
        ),
      ),
    );
  }

  // ---------- 选项行（重要性 / 提醒） ----------

  Widget _buildOptionsRow(AFThemeExtension af, ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _buildChip(
          af,
          theme,
          icon: _isImportant ? Icons.star : Icons.star_border,
          label: _isImportant ? '重要' : '标记重要',
          isActive: _isImportant,
          onTap: () => setState(() => _isImportant = !_isImportant),
        ),
        _buildChip(
          af,
          theme,
          icon: Icons.notifications_none,
          label: _reminderOption == ReminderOption.none
              ? '提醒'
              : _reminderOption.label,
          isActive: _reminderOption != ReminderOption.none,
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => ReminderSelectionDialog(
                currentOption: _reminderOption,
                hasTime: !_isAllDay,
                timeFormat: TimeFormatPB.TwentyFourHour,
                onSave: (option) => setState(() => _reminderOption = option),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChip(
    AFThemeExtension af,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      hoverColor: af.lightGreyHover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : af.borderColor,
          ),
          color: isActive
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? theme.colorScheme.primary : af.lightIconColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? theme.colorScheme.primary
                    : af.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 底部按钮 ----------

  Widget _buildFooter(AFThemeExtension af, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: af.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 取消按钮 — 与项目中 TextButton 风格一致
          InkWell(
            onTap: widget.onDismiss,
            borderRadius: BorderRadius.circular(4),
            hoverColor: af.lightGreyHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                '取消',
                style: TextStyle(fontSize: 13, color: af.secondaryTextColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 创建按钮 — 使用项目主色
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : Text(
                    '创建',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
