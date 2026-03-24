import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:intl/intl.dart';
import 'package:appflowy/plugins/homepage/application/todo_models.dart';
import 'package:appflowy/plugins/homepage/application/todo_service.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/flowy_svgs.g.dart';
// kept no external svg here; using Material Icon for quick create header

/// 快速创建事件/待办的组件
/// 直接使用TodoService创建待办事项并保存到数据库
class QuickEventCreator extends StatefulWidget {
  /// 当前展示的日期（左侧日历图标与右侧待办列表同步）
  final DateTime? displayDate;
  /// 用户通过左侧日历选择新日期时回调
  final ValueChanged<DateTime>? onDisplayDateChanged;
  final Function(TodoItem)? onEventCreated;

  const QuickEventCreator({
    super.key,
    this.displayDate,
    this.onDisplayDateChanged,
    this.onEventCreated,
  });

  @override
  State<QuickEventCreator> createState() => _QuickEventCreatorState();
}

class _QuickEventCreatorState extends State<QuickEventCreator> {
  final TextEditingController _titleController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isAllDay = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final displayDate = widget.displayDate ?? DateTime.now();
    final monthText = '${displayDate.month}月';
    final dayText = '${displayDate.day}';
    final canChangeDate = widget.onDisplayDateChanged != null;

    Widget calendarIcon = Container(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          FlowySvg(
            FlowySvgs.image_home_todo_m,
            size: Size(50, 50),
            blendMode: null,
          ),
          Positioned(
            top: 1,
            left: 0,
            right: 0,
            child: FlowyText.regular(
              monthText,
              textAlign: TextAlign.center,
              fontSize: 10,
              color: Colors.white,
            ),
          ),
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: FlowyText.regular(
              dayText,
              textAlign: TextAlign.center,
              fontSize: 22,
              color: theme.textColorScheme.primary,
            ),
          ),
        ],
      ),
    );

    if (canChangeDate) {
      calendarIcon = InkWell(
        onTap: _showDisplayDatePicker,
        borderRadius: BorderRadius.circular(8),
        child: calendarIcon,
      );
    }

    // 简化为：图标 / 标题 / 描述 / 链接按钮（与设计图一致）
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surfaceContainerColorScheme.layer01,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              calendarIcon,
              const SizedBox(height: 12),
              Text(
                "用日历连接你的生活",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "创建待办计划、创建日记，记录你的每个点滴故事……",
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 42),
              // InkWell(
              //   onTap: _openCalendar,
              //   borderRadius: BorderRadius.circular(6),
              //   child: Container(
              //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              //     decoration: BoxDecoration(
              //       color: const Color.fromRGBO(255, 106, 77, 0.12), // 半透明粉色背景
              //       borderRadius: BorderRadius.circular(6),
              //     ),
              //     child: Text(
              //       "链接我的日历",
              //       style: const TextStyle(
              //         fontSize: 13,
              //         color: Color(0xFFFF6A4D),
              //         fontWeight: FontWeight.w600,
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 58,
          height: 51,
          decoration: BoxDecoration(
            color: const Color(0xFFFF8D69),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.calendar_today,
            size: 28,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "快速创建",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTitleInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "标题",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            hintText: "输入待办事项...",
            hintStyle: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                color: Color(0xFFFF8D69),
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "时间",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // 日期选择
            Expanded(
              child: InkWell(
                onTap: _isAllDay ? null : _selectDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    color: _isAllDay 
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.surface,
                  ),
                  child: Text(
                    DateFormat('MM/dd').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 13,
                      color: _isAllDay 
                          ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 时间选择
            Expanded(
              child: InkWell(
                onTap: _isAllDay ? null : _selectTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    color: _isAllDay 
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.surface,
                  ),
                  child: Text(
                    _isAllDay ? "全天" : _selectedTime.format(context),
                    style: TextStyle(
                      fontSize: 13,
                      color: _isAllDay 
                          ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAllDayToggle() {
    return Row(
      children: [
        Switch.adaptive(
          value: _isAllDay,
          onChanged: (value) {
            setState(() {
              _isAllDay = value;
            });
          },
          activeColor: const Color(0xFFFF8D69),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 8),
        Text(
          "全天",
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isCreating ? null : _createEvent,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8D69),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          elevation: 0,
        ),
        child: _isCreating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                "创建待办",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  Widget _buildCalendarLink() {
    return InkWell(
      onTap: _openCalendar,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today,
              size: 12,
              color: Color(0xFFFF8D69),
            ),
            const SizedBox(width: 4),
            const Text(
              "链接我的日历 →",
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFFF8D69),
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFFFF8D69),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点击左侧日历图标时弹出日期选择，选择后通知父组件并更新右侧待办列表
  Future<void> _showDisplayDatePicker() async {
    final initial = widget.displayDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFFFF8D69),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      widget.onDisplayDateChanged?.call(
        DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  void _openCalendar() {
    try {
      // 创建日历插件
      final calendarPlugin = makePlugin(
        pluginType: PluginType.calendar,
        data: null,
      );

      // 在新标签页中打开日历
      context.read<TabsBloc>().add(
        TabsEvent.openPlugin(plugin: calendarPlugin),
      );

      // 显示成功消息
      if (mounted) {
        showToastNotification(
          message: "正在打开日历...",
          type: ToastificationType.success,
        );
      }
    } catch (e) {
      // 显示错误信息
      if (mounted) {
        showToastNotification(
          message: "打开日历失败: $e",
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF8D69),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF8D69),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _createEvent() async {
    if (_titleController.text.trim().isEmpty) {
      showToastNotification(
        message: "请输入待办事项标题",
        type: ToastificationType.warning,
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // 构建 TodoItem 对象
      final dueDate = _isAllDay 
          ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
          : DateTime(
              _selectedDate.year,
              _selectedDate.month, 
              _selectedDate.day,
              _selectedTime.hour,
              _selectedTime.minute,
            );

      final todoItem = TodoItem(
        id: '', // 会在 TodoService.addTodo 中自动生成
        title: _titleController.text.trim(),
        description: '',
        priority: TodoPriority.medium,
        dueDate: dueDate,
        isAllDay: _isAllDay,
        source: TodoSource.manual,
        createdAt: DateTime.now(),
      );

      // 实际保存到数据库
      await TodoService.instance.addTodo(todoItem);
      
      print('待办事项已保存: ${todoItem.title}, 截止时间: ${todoItem.dueDate}');

      // 清空输入
      _titleController.clear();
      setState(() {
        _selectedDate = DateTime.now();
        _selectedTime = TimeOfDay.now();
        _isAllDay = false;
      });

      // 通知父组件
      widget.onEventCreated?.call(todoItem);

      // 显示成功消息
      if (mounted) {
        showToastNotification(
          message: "待办事项创建成功",
          type: ToastificationType.success,
        );
      }
    } catch (e) {
      // 显示错误消息
      if (mounted) {
        showToastNotification(
          message: "创建失败: $e",
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}

