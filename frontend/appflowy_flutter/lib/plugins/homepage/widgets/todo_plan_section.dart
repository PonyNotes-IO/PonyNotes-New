import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/plugins/homepage/application/todo_bloc.dart';
import 'package:appflowy/plugins/homepage/application/todo_models.dart';
import 'package:appflowy/plugins/homepage/widgets/quick_event_creator.dart';
import 'package:appflowy/plugins/homepage/application/calendar_event.dart';
import 'package:appflowy/plugins/homepage/application/todo_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';

import '../../../startup/plugin/plugin.dart';
import '../../../workspace/application/tabs/tabs_bloc.dart';

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
  Future<List<TodoItem>>? _eventsFuture;

  Future<List<TodoItem>> _loadEvents() async {
    try {
      await TodoService.instance.initialize();
    } catch (_) {}
    return TodoService.instance.getUpcomingTodos();
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
      _eventsFuture = _loadEvents();
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
                      onEventCreated: (todoItem) {
                        // 创建成功后刷新待办列表
                        context.read<TodoBloc>().add(const TodoEvent.loadTodos());
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
                                  setState(() {
                                    _eventsFuture = _loadEvents();
                                  });
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

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: _buildScheduleList(context, displayEvents),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: _openCalendar,
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


