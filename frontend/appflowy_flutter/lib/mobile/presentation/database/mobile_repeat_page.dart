import 'dart:convert';

import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MobileRepeatPage extends StatefulWidget {
  final int initialType;
  final String? initialCustomSummary;

  const MobileRepeatPage({
    super.key,
    required this.initialType,
    this.initialCustomSummary,
  });

  @override
  State<MobileRepeatPage> createState() => _MobileRepeatPageState();
}

class _MobileRepeatPageState extends State<MobileRepeatPage> {
  late int _selectedType;
  String? _customSummary;

  static const _repeatOptions = [
    MapEntry(0, '无'),
    MapEntry(1, '每天'),
    MapEntry(2, '每周'),
    MapEntry(3, '每年'),
    MapEntry(4, '法定工作日'),
    MapEntry(99, '自定义'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _customSummary = widget.initialCustomSummary;
  }

  String _getOptionLabel(MapEntry<int, String> option) {
    if (option.key == 99) {
      if (_customSummary != null && _customSummary!.isNotEmpty) {
        return _extractSummaryFromJson(_customSummary);
      }
      return '自定义';
    }
    return option.value;
  }

  String _extractSummaryFromJson(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return '自定义';
    }
    try {
      final data = jsonDecode(jsonStr);
      if (data is Map && data.containsKey('summary')) {
        final summary = data['summary'];
        if (summary is String && summary.isNotEmpty) {
          return summary;
        }
      }
      return '自定义';
    } catch (e) {
      return jsonStr;
    }
  }

  void _showCustomRepeatEditor() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => _CustomRepeatEditor(
        initialJson: _customSummary,
        onSave: (result) {
          setState(() {
            _selectedType = 99;
            _customSummary = result;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: MobileAppBar(
        title: '任务重复',
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
                    if (_selectedType == 99) {
                      if (_customSummary == null || _customSummary!.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('请先完善自定义重复设置'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                    }
                    Navigator.pop(context, {
                      'type': _selectedType,
                      'customSummary': _customSummary,
                    });
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
        children: _repeatOptions.map((option) {
          return _buildOptionItem(option, theme);
        }).toList(),
      ),
    );
  }

  Widget _buildOptionItem(MapEntry<int, String> option, ThemeData theme) {
    final isSelected = _selectedType == option.key;
    final isCustom = option.key == 99;
    final showCustomSummary = isCustom && _customSummary != null && _customSummary!.isNotEmpty;

    return GestureDetector(
      onTap: () {
        if (isCustom) {
          setState(() {
            _selectedType = option.key;
          });
          _showCustomRepeatEditor();
        } else {
          setState(() {
            _selectedType = option.key;
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
              margin: EdgeInsets.only(top: showCustomSummary ? 0 : 2),
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
                          isCustom ? '自定义' : option.value,
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isCustom)
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                    ],
                  ),
                  if (showCustomSummary)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _extractSummaryFromJson(_customSummary),
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
}

// 自定义重复编辑器
class _CustomRepeatEditor extends StatefulWidget {
  final String? initialJson;
  final void Function(String result) onSave;

  const _CustomRepeatEditor({
    this.initialJson,
    required this.onSave,
  });

  @override
  State<_CustomRepeatEditor> createState() => _CustomRepeatEditorState();
}

class _CustomRepeatEditorState extends State<_CustomRepeatEditor> {
  int unit = 1; // 0=天 1=周 2=月 3=年
  int interval = 1;
  final Set<int> selectedWeekdays = <int>{};
  bool skipHolidays = true;
  bool skipWeekend = false;
  final FixedExtentScrollController _intervalController = FixedExtentScrollController();
  final FixedExtentScrollController _unitController = FixedExtentScrollController();

  @override
  void initState() {
    super.initState();
    _applyInitialJson();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _intervalController.jumpToItem(interval - 1);
      _unitController.jumpToItem(unit);
    });
  }

  void _applyInitialJson() {
    final jsonStr = widget.initialJson;
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final data = jsonDecode(jsonStr);
      if (data is! Map) return;
      if (data['unit'] is int) unit = (data['unit'] as int).clamp(0, 3);
      if (data['interval'] is int) interval = (data['interval'] as int).clamp(1, 30);
      if (data['weekdays'] is List) {
        selectedWeekdays.clear();
        for (final e in data['weekdays']) {
          if (e is int && e >= 0 && e <= 6) selectedWeekdays.add(e);
        }
      }
      if (data['skipHolidays'] is bool) skipHolidays = data['skipHolidays'] as bool;
      if (data['skipWeekend'] is bool) skipWeekend = data['skipWeekend'] as bool;
    } catch (_) {}
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
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
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    '自定义重复',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  TextButton(
                    onPressed: _onSave,
                    child: Text(
                      '确定',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容区域
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // 周期预览
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        children: [
                          const TextSpan(text: '周期  '),
                          TextSpan(
                            text: '每$interval${_unitName(unit)}',
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 选择器
                  SizedBox(
                    height: 160,
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: _intervalController,
                            itemExtent: 32,
                            onSelectedItemChanged: (index) {
                              setState(() {
                                interval = index + 1;
                              });
                            },
                            children: List.generate(30, (i) {
                              return Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: _unitController,
                            itemExtent: 32,
                            onSelectedItemChanged: (index) {
                              setState(() {
                                unit = index;
                              });
                            },
                            children: ['天', '周', '月', '年'].map((e) {
                              return Center(
                                child: Text(
                                  e,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 频率预览
                  if (unit != 1 || selectedWeekdays.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      height: 36,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          children: [
                            const TextSpan(text: '频率  '),
                            TextSpan(
                              text: _previewSummary(),
                              style: TextStyle(color: theme.colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // 星期选择
                  if (unit == 1) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        '频率',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: List.generate(7, (i) {
                          const labels = ['一', '二', '三', '四', '五', '六', '日'];
                          final selected = selectedWeekdays.contains(i);
                          return ChoiceChip(
                            label: Text(labels[i]),
                            selected: selected,
                            selectedColor: theme.colorScheme.primary,
                            labelStyle: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : theme.textTheme.bodyMedium?.color,
                            ),
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.dividerColor.withValues(alpha: 0.6),
                              ),
                            ),
                            onSelected: (_) {
                              setState(() {
                                if (selected) {
                                  selectedWeekdays.remove(i);
                                } else {
                                  selectedWeekdays.add(i);
                                }
                              });
                            },
                          );
                        }),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 开关选项
                  _buildSwitch(
                    theme: theme,
                    title: '跳过法定节假日',
                    value: skipHolidays,
                    onChanged: (v) => setState(() => skipHolidays = v),
                  ),
                  _buildSwitch(
                    theme: theme,
                    title: '跳过周末',
                    value: skipWeekend,
                    onChanged: (v) => setState(() => skipWeekend = v),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch({
    required ThemeData theme,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  void _onSave() {
    if (unit == 1 && selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请至少选择一个星期几'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final summary = _buildCustomSummary(unit, interval, selectedWeekdays);
    if (summary == null || summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请完善自定义选项'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final jsonData = jsonEncode({
      'unit': unit,
      'interval': interval,
      'weekdays': selectedWeekdays.toList()..sort(),
      'skipHolidays': skipHolidays,
      'skipWeekend': skipWeekend,
      'summary': summary,
    });

    widget.onSave(jsonData);
    Navigator.pop(context);
  }

  String? _buildCustomSummary(int unit, int interval, Set<int> weekdays) {
    switch (unit) {
      case 0:
        return '每$interval天';
      case 1:
        if (weekdays.isEmpty) return null;
        const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        final days = weekdays.toList()..sort();
        final joined = days.map((i) => names[i]).join('、');
        return '每$interval周的$joined';
      case 2:
        return '每$interval月';
      case 3:
        return '每$interval年';
    }
    return null;
  }

  String _unitName(int unit) {
    switch (unit) {
      case 0:
        return '天';
      case 1:
        return '周';
      case 2:
        return '月';
      case 3:
        return '年';
      default:
        return '周';
    }
  }

  String _previewSummary() {
    final s = _buildCustomSummary(unit, interval, selectedWeekdays);
    return s ?? '';
  }
}
