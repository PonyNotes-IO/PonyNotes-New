import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class MobileReminderPage extends StatefulWidget {
  final ReminderOption initialOption;

  const MobileReminderPage({
    super.key,
    required this.initialOption,
  });

  @override
  State<MobileReminderPage> createState() => _MobileReminderPageState();
}

class _MobileReminderPageState extends State<MobileReminderPage> {
  late ReminderOption _selectedOption;

  static const _options = [
    ReminderOption.none,
    ReminderOption.atTimeOfEvent,
    ReminderOption.fiveMinsBefore,
    ReminderOption.thirtyMinsBefore,
    ReminderOption.oneHourBefore,
    ReminderOption.oneDayBefore,
    ReminderOption.custom,
  ];

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.initialOption;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: _options.map((option) {
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
                    Expanded(
                      child: Text(
                        option.label,
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
          }).toList(),
        ),
      ),
    );
  }
}
