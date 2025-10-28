
// 统一的日记和日程展示组件
import 'package:appflowy/plugins/database/calendar/widgets/schedule_sidebar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../workspace/application/view/view_listener.dart';
import '../../../../workspace/application/view/view_service.dart';
import '../application/calendar_content_cubit.dart';
import '../models/schedule_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CalendarContent extends StatefulWidget {
  final DateTime selectedDate;
  final String? viewId;
  final Function(ScheduleItem)? onScheduleTap; // 点击日程的回调
  final Function(ViewPB)? onNoteTap; // 点击笔记的回调
  final String? selectedNoteId; // 当前选中的笔记ID
  // 使用Bloc触发刷新，移除refreshTick

  const CalendarContent({
    Key? key,
    required this.selectedDate,
    this.viewId,
    this.onScheduleTap,
    this.onNoteTap,
    this.selectedNoteId,
  }) : super(key: key);

  @override
  State<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends State<CalendarContent> {
  List<ViewPB> _realNotes = [];
  bool _isLoading = false;
  ViewListener? _viewListener;
  // 新增：用于刷新日程侧栏内容（不能引用私有State类型，使用非泛型GlobalKey）
  final GlobalKey _scheduleContentKey = GlobalKey();

  // 公共方法：手动刷新数据
  void refreshData() {
    _loadNotesForDate();
    // 同步刷新日程侧栏（通过dynamic调用，避免跨库私有类型）
    final state = _scheduleContentKey.currentState;
    if (state != null) {
      try {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refreshData();
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNotesForDate();
    _setupViewListener();
  }

  // 设置视图监听器，监听视图变化
  void _setupViewListener() {
    // 监听工作空间级别的视图变化
    _viewListener = ViewListener(viewId: 'workspace');
    _viewListener?.start(
      onViewUpdated: (view) {
        // 当视图更新时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
      onViewChildViewsUpdated: (childViews) {
        // 当子视图更新时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
      onViewDeleted: (view) {
        // 当视图删除时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
      onViewRestored: (view) {
        // 当视图恢复时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
    );
  }

  @override
  void didUpdateWidget(CalendarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _loadNotesForDate();
    }
    // 如果视图ID发生变化，也重新加载数据
    if (oldWidget.viewId != widget.viewId) {
      _loadNotesForDate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CalendarContentCubit, int>(
      listenWhen: (prev, curr) => prev != curr,
      listener: (_, __) => refreshData(),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 动态日期标题 - 根据选中的日期显示
          Text(
            '${widget.selectedDate.year}年${widget.selectedDate.month}月${widget.selectedDate.day}日',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else if (_realNotes.isNotEmpty) ...[
            ...(_realNotes.map((note) => _buildNoteItem(note))),
            const SizedBox(height: 16),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '当天暂无笔记',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
              ),
            ),
          ],
          if (widget.viewId != null) ...[
            ScheduleSidebarContent(
              key: _scheduleContentKey,
              databaseViewId: widget.viewId,
              onScheduleTap: widget.onScheduleTap,
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _viewListener?.stop();
    super.dispose();
  }

  // 判断是否为系统视图
  bool _isSystemView(String viewName) {
    // 系统视图名称列表
    final systemViewNames = [
      'Workspace',
      'workspace',
      'Workspace Settings',
      'Getting Started',
      'Welcome',
      'Home',
      'Inbox',
      'Favorites',
      'Trash',
      'Settings',
      'Preferences',
      'Help',
      'About',
    ];

    return systemViewNames.contains(viewName) ||
        viewName.toLowerCase().contains('workspace') ||
        viewName.toLowerCase().contains('system') ||
        viewName.toLowerCase().contains('setting');
  }

  Future<void> _loadNotesForDate() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取所有视图
      final allViewsResult = await ViewBackendService.getAllViews();

      await allViewsResult.fold(
            (allViews) async {
          // 过滤出文档类型的视图（笔记），包括"我的空间"中的日记
          // 显示所有Document类型的视图，包括孤儿视图和我的空间中的文档
          final documentViews = allViews.items
              .where((view) =>
          view.layout == ViewLayoutPB.Document &&
              // 显示所有文档，包括有父视图的（我的空间）和孤儿视图（日历创建）
              view.name.isNotEmpty && // 只过滤掉名称为空的文档
              // 排除系统视图，如"Workspace"等
              !_isSystemView(view.name)) // 排除系统视图
              .toList();

          // 根据选中日期过滤笔记
          final selectedDateStart = DateTime(
            widget.selectedDate.year,
            widget.selectedDate.month,
            widget.selectedDate.day,
          );
          final selectedDateEnd = selectedDateStart.add(Duration(days: 1));

          // 过滤当天创建的笔记
          final notesForDate = documentViews.where((view) {
            final createTime = DateTime.fromMillisecondsSinceEpoch(
              view.createTime.toInt() * 1000,
            );
            return createTime.isAfter(selectedDateStart) &&
                createTime.isBefore(selectedDateEnd);
          }).toList();

          setState(() {
            _realNotes = notesForDate;
            _isLoading = false;
          });
        },
            (error) {
          setState(() {
            _realNotes = [];
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _realNotes = [];
        _isLoading = false;
      });
    }
  }

  Widget _buildNoteItem(ViewPB note) {
    final isSelected = widget.selectedNoteId == note.id;

    return FlowyHover(
      style: HoverStyle(hoverColor: Theme.of(context).colorScheme.secondary),
      builder: (_, onHover) => GestureDetector(
        onTap: () {
          // 点击笔记时调用回调函数
          if (widget.onNoteTap != null) {
            widget.onNoteTap!(note);
          }
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isSelected
                ? Border.all(
              color:
              Theme.of(context).colorScheme.primary.withOpacity(0.3),
              width: 1,
            )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.description : Icons.description_outlined,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatCreateTime(note.createTime.toInt()),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isSelected
                      ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.7)
                      : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCreateTime(int timestamp) {
    final createTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createDate =
    DateTime(createTime.year, createTime.month, createTime.day);

    if (createDate == today) {
      return '${createTime.hour.toString().padLeft(2, '0')}:${createTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${createTime.month}/${createTime.day}';
    }
  }
}