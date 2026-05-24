import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileReminderPage extends StatefulWidget {
  final ReminderOption initialOption;
  final bool isAllDay;
  final TimeFormatPB timeFormat;

  const MobileReminderPage({
    super.key,
    required this.initialOption,
    required this.isAllDay,
    this.timeFormat = TimeFormatPB.TwentyFourHour,
  });

  @override
  State<MobileReminderPage> createState() => _MobileReminderPageState();
}

class _MobileReminderPageState extends State<MobileReminderPage> {
  late ReminderOption _selectedOption;

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.initialOption;
  }

  List<ReminderOption> _getAvailableOptions() {
    final options = ReminderOption.values.toList();
    // 与桌面端 ReminderSelector 逻辑一致：移除 custom
    if (_selectedOption != ReminderOption.custom) {
      options.remove(ReminderOption.custom);
    }
    // 与桌面端 ReminderSelector 逻辑一致：过滤选项
    options.removeWhere(
      (o) => !o.timeExempt && (!widget.isAllDay ? !o.withoutTime : o.requiresNoTime),
    );
    return options;
  }

  String _getOptionLabel(ReminderOption option) {
    String label = option.label;
    if (option.withoutTime && !option.timeExempt) {
      const time24 = "09:00";
      final time12 = "$time24 AM";
      final t = widget.timeFormat == TimeFormatPB.TwelveHour ? time12 : time24;
      label = "$label ($t)";
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _getAvailableOptions();

    return Scaffold(
      appBar: MobileAppBar(
        title: '设置提醒',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context, _selectedOption);
              },
              child: Text(
                '保存',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: options.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 56,
            color: theme.dividerColor,
          ),
          itemBuilder: (context, index) {
            final option = options[index];
            final isSelected = _selectedOption == option;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedOption = option;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    FlowySvg(
                      FlowySvgs.icon_alarm_clock_m,
                      color: theme.iconTheme.color,
                      size: const Size.square(24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getOptionLabel(option),
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
