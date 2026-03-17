import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:appflowy/plugins/homepage/application/todo_bloc.dart';
import 'package:appflowy/plugins/homepage/application/todo_models.dart';
import 'package:appflowy/plugins/homepage/widgets/quick_event_creator.dart';
import 'package:appflowy/plugins/homepage/application/calendar_event.dart';
import 'package:appflowy/plugins/homepage/application/todo_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';

import '../../../startup/plugin/plugin.dart';
import '../../../workspace/application/tabs/tabs_bloc.dart';
import '../../database/calendar/calendar.dart' hide CalendarEvent;

/// 主页待办计划区域的主组件
/// 包含左侧的快速创建区域和右侧的待办列表展示
class TodoPlanSection extends StatelessWidget {
  const TodoPlanSection({super.key, this.workspaceId});

  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TodoBloc()..add(const TodoEvent.initial()),
      child: BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        listener: (context, state) {
          // 当工作区切换时，重新初始化待办计划
          context.read<TodoBloc>().add(const TodoEvent.initial());
        },
      child: TodoPlanSectionContent(workspaceId: workspaceId),
      ),
    );
  }
}

class TodoPlanSectionContent extends StatefulWidget {
  const TodoPlanSectionContent({super.key, this.workspaceId});

  final String? workspaceId;

  @override
  State<TodoPlanSectionContent> createState() => _TodoPlanSectionContentState();
}

class _TodoPlanSectionContentState extends State<TodoPlanSectionContent> {
  late Future<List<TodoItem>> _eventsFuture;
  /// 当前选中的展示日期，左侧日历图标与右侧待办列表均以此为准
  DateTime _displayDate = DateTime.now();

  Future<List<TodoItem>> _loadEvents() async {
    try {
      await TodoService.instance.initialize();
    } catch (_) {}
    return TodoService.instance.getTodosForDate(_displayDate);
  }

  void _refreshEvents() {
    setState(() {
      _eventsFuture = _loadEvents();
    });
  }

  void _onDisplayDateChanged(DateTime date) {
    setState(() {
      _displayDate = DateTime(date.year, date.month, date.day);
      _eventsFuture = _loadEvents();
    });
  }

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadEvents();
  }

  @override
  void didUpdateWidget(covariant TodoPlanSectionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _refreshEvents();
    }
  }

  List<CalendarEvent> _withDemoEventIfEmpty(List<CalendarEvent> events) {
    if (events.isNotEmpty) {
      return events;
    }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8, 0);
    return [
      CalendarEvent(
        id: 'homepage_demo_event_1',
        title: '起床与张总开会',
        start: start,
        end: start.add(const Duration(hours: 1)),
        isAllDay: false,
      ),
      CalendarEvent(
        id: 'homepage_demo_event_2',
        title: '读研分享会',
        start: start.add(const Duration(hours: 3)),
        end: start.add(const Duration(hours: 4)),
        isAllDay: false,
      ),
    ];
  }

  String _formatMonthDay(DateTime date) => '${date.month}月${date.day}日';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatHourMinute(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeRange(CalendarEvent event) {
    if (event.isAllDay) {
      return '全天';
    }
    final start = event.start;
    final end = (event.end == null || !event.end!.isAfter(start))
        ? start.add(const Duration(hours: 1))
        : event.end!;
    return '${_formatHourMinute(start)} - ${_formatHourMinute(end)}';
  }

  Widget _buildScheduleCard(BuildContext context, CalendarEvent event) {
    final now = DateTime.now();
    final isToday = _isSameDay(now, event.start);
    final textColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.72);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isToday) ...[
                  Text(
                    '今天',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  _formatMonthDay(event.start),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimeRange(event),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor.withOpacity(0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList(BuildContext context, List<CalendarEvent> events) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: events.map((e) => _buildScheduleCard(context, e)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: BlocBuilder<TodoBloc, TodoState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state.errorMessage.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage,
                    style: TextStyle(
                      color: Colors.red[600],
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Use Expanded to split the row into two equal parts.
          // Avoid LayoutBuilder so height remains intrinsic inside the scrolling parent.
          const double dividerWidth = 1;
          const double dividerHorizontalMargin = 15;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: QuickEventCreator(
                      displayDate: _displayDate,
                      onDisplayDateChanged: _onDisplayDateChanged,
                      onEventCreated: (todoItem) {
                        // 创建成功后仅刷新右侧日程，避免整块区域重复 loading 闪动。
                        _refreshEvents();
                      },
                    ),
                  ),
                ),
              ),
              // Divider
              Container(
                width: dividerWidth,
                margin: const EdgeInsets.symmetric(horizontal: dividerHorizontalMargin),
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  padding: EdgeInsets.all(16),
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: FutureBuilder<List<TodoItem>>(
                    future: _eventsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        Log.error('[Homepage Calendar] load error: ${snapshot.error}');
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '无法加载日程',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () {
                                  _refreshEvents();
                                },
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }

                      final todos = snapshot.data ?? [];
                      final calendarEvents = todos
                          .where((t) => t.source == TodoSource.calendar && t.dueDate != null)
                          .map((t) => CalendarEvent(
                                id: t.id,
                                title: t.title,
                                start: t.dueDate!,
                                end: t.dueDate!.add(const Duration(hours: 1)),
                                isAllDay: t.isAllDay,
                              ))
                          .toList();
                      final displayEvents = _withDemoEventIfEmpty(calendarEvents);
                      final isToday = _isSameDay(DateTime.now(), _displayDate);
                      final dateLabel = isToday
                          ? '今天 ${_formatMonthDay(_displayDate)}'
                          : _formatMonthDay(_displayDate);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              dateLabel,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.72),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _buildScheduleList(context, displayEvents),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: () => _openCalendar(_displayDate),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(255, 106, 77, 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  "创建待办计划",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFFF6A4D),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 打开日历插件，并跳转到指定日期，自动打开新建日程页面
  void _openCalendar(DateTime date) {
    try {
      // 创建日历插件，带上日期参数
      final pluginData = CalendarPluginData(
        initialDate: date,
        openNewEvent: true,
      );
      final calendarPlugin = makePlugin(
        pluginType: PluginType.calendar,
        data: pluginData,
      );

      // 在新标签页中打开日历
      context.read<TabsBloc>().add(
        TabsEvent.openPlugin(plugin: calendarPlugin),
      );

      // 显示成功消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("正在打开日历..."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 显示错误信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("打开日历失败: $e"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

/// 创建待办计划底部面板，日期默认使用左侧所选日期
class _CreateTodoSheet extends StatefulWidget {
  const _CreateTodoSheet({
    required this.displayDate,
    required this.onCreated,
  });

  final DateTime displayDate;
  final VoidCallback onCreated;

  @override
  State<_CreateTodoSheet> createState() => _CreateTodoSheetState();
}

class _CreateTodoSheetState extends State<_CreateTodoSheet> {
  late TextEditingController _titleController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isAllDay = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _selectedDate = DateTime(
      widget.displayDate.year,
      widget.displayDate.month,
      widget.displayDate.day,
    );
    _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(_selectedDate.year - 1),
      lastDate: DateTime(_selectedDate.year + 2),
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
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
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
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入待办标题')),
        );
      }
      return;
    }

    setState(() => _isCreating = true);

    try {
      final dueDate = _isAllDay
          ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
          : DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _selectedTime.hour,
              _selectedTime.minute,
            );

      final item = TodoItem(
        id: '',
        title: title,
        description: '',
        priority: TodoPriority.medium,
        dueDate: dueDate,
        isAllDay: _isAllDay,
        source: TodoSource.manual,
        createdAt: DateTime.now(),
      );

      await TodoService.instance.addTodo(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('待办计划已创建')),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewPadding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '创建待办计划',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: '输入待办事项…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _isAllDay ? null : _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      DateFormat('yyyy/MM/dd').format(_selectedDate),
                      style: TextStyle(
                        color: _isAllDay
                            ? theme.colorScheme.onSurface.withOpacity(0.5)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _isAllDay ? null : _pickTime,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isAllDay ? '全天' : _selectedTime.format(context),
                      style: TextStyle(
                        color: _isAllDay
                            ? theme.colorScheme.onSurface.withOpacity(0.5)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch.adaptive(
                value: _isAllDay,
                onChanged: (v) => setState(() => _isAllDay = v),
                activeColor: const Color(0xFFFF8D69),
              ),
              const SizedBox(width: 8),
              Text(
                '全天',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isCreating ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF8D69),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isCreating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('创建'),
            ),
          ),
        ],
      ),
    );
  }
}


