import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/plugins/homepage/application/todo_bloc.dart';
import 'package:appflowy/plugins/homepage/application/todo_models.dart';
import 'package:appflowy/plugins/homepage/widgets/quick_event_creator.dart';
import 'package:appflowy/plugins/homepage/widgets/todo_list_display.dart';
import 'package:appflowy/plugins/homepage/application/calendar_event.dart';
import 'package:appflowy/plugins/homepage/application/todo_service.dart';
import 'package:appflowy/plugins/homepage/widgets/calendar_event_list.dart';
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
    final start = DateTime(now.year, now.month, now.day + 1, 9, 0);
    return [
      CalendarEvent(
        id: 'homepage_demo_event',
        title: 'Demo 日程：创建你的第一个待办计划',
        start: start,
        end: start.add(const Duration(minutes: 30)),
        isAllDay: false,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
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
              // Divider
              Container(
                width: dividerWidth,
                margin: const EdgeInsets.symmetric(horizontal: dividerHorizontalMargin),
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
              Expanded(
                flex: 1,
                child: ConstrainedBox(
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
                                end: t.dueDate,
                                isAllDay: t.isAllDay,
                              ))
                          .toList();
                      final displayEvents = _withDemoEventIfEmpty(calendarEvents);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              child: CalendarEventList(
                                events: displayEvents,
                                // display-only on the homepage; no click handler
                                showHeader: false,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Spacer(),
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


