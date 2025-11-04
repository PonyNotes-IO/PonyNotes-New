import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';

/// 统一的提醒选择对话框
/// 用于新建和编辑日程页面
class ReminderSelectionDialog extends StatefulWidget {
  final ReminderOption currentOption;
  final bool hasTime;
  final TimeFormatPB timeFormat;
  final Function(ReminderOption) onSave;

  const ReminderSelectionDialog({
    Key? key,
    required this.currentOption,
    required this.hasTime,
    required this.timeFormat,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ReminderSelectionDialog> createState() => _ReminderSelectionDialogState();
}

class _ReminderSelectionDialogState extends State<ReminderSelectionDialog> {
  late ReminderOption _tempSelectedOption;

  @override
  void initState() {
    super.initState();
    _tempSelectedOption = widget.currentOption;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 获取可用选项（与 reminder_selector.dart 逻辑一致）
    final options = ReminderOption.values.toList();
    
    // 如果当前选项不是 custom，则移除 custom 选项
    if (widget.currentOption != ReminderOption.custom) {
      options.remove(ReminderOption.custom);
    }
    
    // 根据 hasTime 过滤选项（与 reminder_selector.dart 逻辑一致）
    options.removeWhere(
      (o) => !o.timeExempt && (!widget.hasTime ? !o.withoutTime : o.requiresNoTime),
    );
    
    // 构建选项列表
    final optionWidgets = options.map((o) {
      String label = o.label;
      // 对于 withoutTime 的选项，显示时间信息（与 reminder_selector.dart 逻辑一致）
      if (o.withoutTime && !o.timeExempt) {
        const time = "09:00";
        final t = widget.timeFormat == TimeFormatPB.TwelveHour ? "$time AM" : time;
        label = "$label ($t)";
      }
      
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _tempSelectedOption = o;
              });
            },
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Radio<ReminderOption>(
                    value: o,
                    groupValue: _tempSelectedOption,
                    onChanged: (value) {
                      setState(() {
                        _tempSelectedOption = value!;
                      });
                    },
                    activeColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  if (o == _tempSelectedOption)
                    Icon(
                      Icons.check,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 510,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            // 限制对话框最大高度，超过则滚动
            maxHeight: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      size: 24,
                      color: theme.iconTheme.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '提醒时间',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.titleLarge?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // 保存按钮
                  ElevatedButton(
                    onPressed: () {
                      widget.onSave(_tempSelectedOption);
                      Navigator.pop(context);
                    },
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
                    child: const Text(
                      '保存',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 选项列表（可滚动，避免超出边界）
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: optionWidgets,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
