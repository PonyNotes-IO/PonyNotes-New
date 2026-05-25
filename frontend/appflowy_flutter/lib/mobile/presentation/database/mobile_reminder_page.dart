import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/cupertino.dart';
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
  bool _hasCustomTimeSet = false;

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
    _hasCustomTimeSet = widget.initialOption == ReminderOption.custom;
  }

  String _getOptionLabel(ReminderOption option) {
    return option.label;
  }

  void _showCustomTimePicker() {
    int tempDays = ReminderOption.customMinutes ~/ (24 * 60);
    int tempHours = (ReminderOption.customMinutes % (24 * 60)) ~/ 60;
    int tempMins = ReminderOption.customMinutes % 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖动条
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            '取消',
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '自定义提醒时间',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.titleLarge?.color,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // 更新枚举中的自定义时间
                            ReminderOption.setCustomMinutes(
                              tempDays * 24 * 60 + tempHours * 60 + tempMins,
                            );
                            setState(() {
                              _hasCustomTimeSet = true;
                            });
                            Navigator.pop(context);
                          },
                          child: Text(
                            '确定',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 时间选择器
                  SizedBox(
                    height: 200,
                    child: Row(
                      children: [
                        // 天数
                        Expanded(
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('天', style: TextStyle(fontSize: 14)),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  itemExtent: 40,
                                  scrollController: FixedExtentScrollController(
                                    initialItem: tempDays,
                                  ),
                                  onSelectedItemChanged: (index) {
                                    setSheetState(() {
                                      tempDays = index;
                                    });
                                  },
                                  children: List.generate(8, (index) {
                                    return Center(
                                      child: Text(
                                        '$index',
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 小时
                        Expanded(
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('小时', style: TextStyle(fontSize: 14)),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  itemExtent: 40,
                                  scrollController: FixedExtentScrollController(
                                    initialItem: tempHours,
                                  ),
                                  onSelectedItemChanged: (index) {
                                    setSheetState(() {
                                      tempHours = index;
                                    });
                                  },
                                  children: List.generate(24, (index) {
                                    return Center(
                                      child: Text(
                                        '$index',
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 分钟
                        Expanded(
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('分钟', style: TextStyle(fontSize: 14)),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  itemExtent: 40,
                                  scrollController: FixedExtentScrollController(
                                    initialItem: tempMins ~/ 5,
                                  ),
                                  onSelectedItemChanged: (index) {
                                    setSheetState(() {
                                      tempMins = index * 5;
                                    });
                                  },
                                  children: List.generate(12, (index) {
                                    return Center(
                                      child: Text(
                                        '${index * 5}',
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOptionList(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _options.map((option) {
          return _buildOptionItem(option, theme);
        }).toList(),
      ),
    );
  }

  Widget _buildOptionItem(ReminderOption option, ThemeData theme) {
    final isSelected = _selectedOption == option;
    final isCustomOption = option == ReminderOption.custom;

    return GestureDetector(
      onTap: () {
        if (isCustomOption) {
          setState(() {
            _selectedOption = option;
          });
          _showCustomTimePicker();
        } else {
          setState(() {
            _selectedOption = option;
          });
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 圆形单选指示器
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: isSelected ? 2 : 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            // 选项文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isCustomOption ? '自定义' : _getOptionLabel(option),
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isCustomOption)
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                    ],
                  ),
                  if (isCustomOption && _hasCustomTimeSet)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 15,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: MobileAppBar(
        title: '设置提醒',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 选项列表
              _buildOptionList(theme),
              const Spacer(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    // 如果选择了自定义但没有设置具体时间，则切换到"无"
                    if (_selectedOption == ReminderOption.custom && !_hasCustomTimeSet) {
                      Navigator.pop(context, ReminderOption.none);
                    } else {
                      Navigator.pop(context, _selectedOption);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
