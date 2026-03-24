import 'dart:convert';
import 'dart:ui';

import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class RepeatSelectionDialog extends StatefulWidget {
  final int currentType; // 0=无 1=每天 2=每周 3=每年 4=法定工作日 99=自定义
  final String? currentCustomSummary;
  final void Function({required int type, String? customSummary}) onSave;

  const RepeatSelectionDialog({
    Key? key,
    required this.currentType,
    this.currentCustomSummary,
    required this.onSave,
  }) : super(key: key);

  @override
  State<RepeatSelectionDialog> createState() => _RepeatSelectionDialogState();
}

class _RepeatSelectionDialogState extends State<RepeatSelectionDialog> {
  late int tempValue;
  String? tempCustomSummary;

  @override
  void initState() {
    super.initState();
    tempValue = widget.currentType;
    tempCustomSummary = widget.currentCustomSummary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 510,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.cancel,
                    size: 24,
                    color: theme.iconTheme.color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '任务重复',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: _onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '保存',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...[
              const MapEntry(0, '无'),
              const MapEntry(1, '每天'),
              const MapEntry(2, '每周'),
              const MapEntry(3, '每年'),
              const MapEntry(4, '法定工作日'),
              const MapEntry(99, '自定义'),
            ].map((entry) {
              final isCustom = entry.key == 99;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          if (isCustom) {
                            final result = await showDialog<String>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => CustomRepeatDialog(initialJson: tempCustomSummary),
                            );
                            if (result != null && result.isNotEmpty) {
                              setState(() {
                                tempValue = 99;
                                tempCustomSummary = result;
                              });
                            } else {
                              setState(() {
                                tempValue = 99;
                              });
                            }
                          } else {
                            setState(() {
                              tempValue = entry.key;
                            });
                          }
                        },
                        child: Container(
                          height: 48,
                          child: Row(
                            children: [
                              Radio<int>(
                                value: entry.key,
                                groupValue: tempValue,
                                onChanged: (v) async {
                                  if (isCustom) {
                                    final result = await showDialog<String>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) => CustomRepeatDialog(initialJson: tempCustomSummary),
                                    );
                                    setState(() {
                                      tempValue = 99;
                                      if (result != null && result.isNotEmpty) {
                                        tempCustomSummary = result;
                                      }
                                    });
                                  } else {
                                    setState(() {
                                      tempValue = v ?? tempValue;
                                    });
                                  }
                                },
                                activeColor: theme.colorScheme.primary,
                              ),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                              if (isCustom)
                                Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: theme.iconTheme.color?.withOpacity(0.7),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isCustom && tempCustomSummary != null && tempCustomSummary!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 48, bottom: 8),
                      child: Text(
                        _extractSummaryFromJson(tempCustomSummary!),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                        ),
                      ),
                    ),
                ],
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _onSave() {
    if (tempValue == 99) {
      if (tempCustomSummary == null || tempCustomSummary!.isEmpty) {
        showToastNotification(message: '请先完善自定义重复设置');
        return;
      }
      widget.onSave(type: 99, customSummary: tempCustomSummary);
      Navigator.pop(context);
      return;
    }
    widget.onSave(type: tempValue, customSummary: null);
    Navigator.pop(context);
  }

  // 从 JSON 中提取显示摘要
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
      // 如果没有 summary 字段，返回默认值
      return '自定义';
    } catch (e) {
      // 如果不是有效的 JSON，返回默认值
      return '自定义';
    }
  }
}

class CustomRepeatDialog extends StatefulWidget {
  /// 已有自定义规则时的 JSON（含 unit、interval、weekdays、summary），用于预填
  final String? initialJson;

  const CustomRepeatDialog({Key? key, this.initialJson}) : super(key: key);

  @override
  State<CustomRepeatDialog> createState() => _CustomRepeatDialogState();
}

class _CustomRepeatDialogState extends State<CustomRepeatDialog> {
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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 510,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.cancel,
                    size: 24,
                    color: theme.iconTheme.color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '自定义编辑',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: _onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    '保存',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              height: 36,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  children: [
                    const TextSpan(text: '周期  '),
                    TextSpan(
                      text: '每${interval}${_unitName(unit)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: Row(
                children: [
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: const _CupertinoPickerScrollBehavior(),
                      child: CupertinoPicker(
                      scrollController: _intervalController,
                      itemExtent: 32,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          interval = index + 1;
                        });
                      },
                      children: List.generate(30, (i) {
                        final value = i + 1;
                        return Center(
                          child: Text(
                            value.toString(),
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                        );
                      }),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: const _CupertinoPickerScrollBehavior(),
                      child: CupertinoPicker(
                      scrollController: _unitController,
                      itemExtent: 32,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          unit = index;
                        });
                      },
                      children: ['天','周','月','年'].map((e) {
                        return Center(
                          child: Text(
                            e,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                        );
                      }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 选择「每周」且尚未选择星期几时，不显示上方的频率预览，避免出现两个「频率」且上方为空
            if (unit != 1 || selectedWeekdays.isNotEmpty) ...[
              Container(
                height: 36,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    children: [
                      const TextSpan(text: '频率  '),
                      TextSpan(
                        text: _previewSummary(),
                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (unit == 1) ...[
              Align(alignment: Alignment.centerLeft, child: const Text('频率')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: List.generate(7, (i) {
                  const labels = ['一','二','三','四','五','六','日'];
                  final selected = selectedWeekdays.contains(i);
                  return ChoiceChip(
                    label: Text(
                      labels[i],
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                    selected: selected,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFF2F3F5),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : (Theme.of(context).dividerColor.withOpacity(0.6)),
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
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              value: skipHolidays,
              onChanged: (v) => setState(() => skipHolidays = v),
              title: const Text('跳过法定节假日'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: skipWeekend,
              onChanged: (v) => setState(() => skipWeekend = v),
              title: const Text('跳过周末'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  void _onSave() {
    if (unit == 1 && selectedWeekdays.isEmpty) {
      showSimpleAlertDialog(
        context: context,
        message: '请在自定义中至少选择一个星期几',
      );
      return;
    }
    final summary = _buildCustomSummary(unit, interval, selectedWeekdays);
    if (summary == null || summary.isEmpty) {
      showSimpleAlertDialog(
        context: context,
        message: '请完善自定义选项',
      );
      return;
    }
    // 返回 JSON 格式的规则数据，同时保留显示文本
    final jsonData = jsonEncode({
      'unit': unit,
      'interval': interval,
      'weekdays': selectedWeekdays.toList()..sort(),
      'summary': summary, // 保留显示文本用于 UI 显示
    });
    Navigator.pop(context, jsonData);
  }

  String? _buildCustomSummary(int unit, int interval, Set<int> weekdays) {
    switch (unit) {
      case 0:
        return '每$interval天';
      case 1:
        if (weekdays.isEmpty) return null;
        const names = ['周一','周二','周三','周四','周五','周六','周日'];
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

class _CupertinoPickerScrollBehavior extends ScrollBehavior {
  const _CupertinoPickerScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
  @override
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) {
    return child;
  }
}



