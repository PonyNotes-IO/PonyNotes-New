import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_picker.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Mobile Calendar Page - Simplified full screen calendar for mobile
class MobileCalendarPage extends StatefulWidget {
  const MobileCalendarPage({
    super.key,
    this.initialDate,
  });

  final DateTime? initialDate;

  static const routeName = '/mobile_calendar';

  @override
  State<MobileCalendarPage> createState() => _MobileCalendarPageState();
}

class _MobileCalendarPageState extends State<MobileCalendarPage> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  final ScheduleModel _scheduleModel = ScheduleModel();
  String? _currentViewId;
  bool _isLoadingNotes = false;
  List<ViewPB> _notesForDate = [];
  Map<String, ViewPB> _viewById = {};

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialDate ?? DateTime.now();
    _selectedDay = _focusedDay;
    _initializeCalendarView();
    _loadNotesForDate();
    _scheduleModel.addListener(_onSchedulesChanged);
  }

  void _onSchedulesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeCalendarView() async {
    try {
      final fixedViewId = fixedUuid(12345, UuidType.privateSpace);
      final result = await ViewBackendService.getView(fixedViewId);

      await result.fold(
        (view) async {
          if (mounted) {
            _currentViewId = view.id;
            _scheduleModel.setViewId(view.id);
          }
        },
        (error) async {
          final createResult = await ViewBackendService.createOrphanView(
            viewId: fixedViewId,
            name: '日历视图',
            layoutType: ViewLayoutPB.Calendar,
          );
          createResult.fold(
            (view) {
              if (mounted) {
                _currentViewId = view.id;
                _scheduleModel.setViewId(view.id);
              }
            },
            (_) {},
          );
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _scheduleModel.removeListener(_onSchedulesChanged);
    _scheduleModel.dispose();
    super.dispose();
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
    _loadNotesForDate();
  }

  Future<void> _loadNotesForDate() async {
    if (_selectedDay == null) return;

    setState(() => _isLoadingNotes = true);

    try {
      final allViewsResult = await ViewBackendService.getAllViews();

      await allViewsResult.fold(
        (allViews) async {
          _viewById = {for (final v in allViews.items) v.id: v};

          final documentViews = allViews.items.where((view) {
            return view.layout == ViewLayoutPB.Document &&
                view.name.isNotEmpty &&
                !_isSystemView(view.name) &&
                !_isChildOfDatabaseView(view);
          }).toList();

          final selectedDateStart = DateTime(
            _selectedDay!.year,
            _selectedDay!.month,
            _selectedDay!.day,
          );
          final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));

          final notesForDate = documentViews.where((view) {
            final createTime = DateTime.fromMillisecondsSinceEpoch(
              view.createTime.toInt() * 1000,
            );
            return createTime.isAfter(selectedDateStart) &&
                createTime.isBefore(selectedDateEnd);
          }).toList();

          notesForDate.sort((a, b) => b.createTime.compareTo(a.createTime));

          if (mounted) {
            _notesForDate = notesForDate;
            _isLoadingNotes = false;
          }
        },
        (error) {
          if (mounted) {
            _notesForDate = [];
            _isLoadingNotes = false;
          }
        },
      );
    } catch (_) {
      if (mounted) {
        _notesForDate = [];
        _isLoadingNotes = false;
      }
    }
  }

  bool _isSystemView(String viewName) {
    const systemViewNames = [
      'Workspace', 'workspace', 'Workspace Settings',
      'Getting Started', 'Welcome', 'Home', 'Inbox',
      'Favorites', 'Trash', 'Settings', 'Preferences',
      'Help', 'About',
    ];
    return systemViewNames.contains(viewName) ||
        viewName.toLowerCase().contains('workspace') ||
        viewName.toLowerCase().contains('system') ||
        viewName.toLowerCase().contains('setting');
  }

  bool _isChildOfDatabaseView(ViewPB view) {
    final pid = view.parentViewId;
    if (pid.isEmpty) return false;
    final parent = _viewById[pid];
    if (parent == null) return false;
    return parent.layout == ViewLayoutPB.Grid ||
        parent.layout == ViewLayoutPB.Board ||
        parent.layout == ViewLayoutPB.Calendar;
  }

  void _onNoteTap(ViewPB note) {
    context.push('/editor/${note.id}');
  }

  void _onScheduleTap(ScheduleItem schedule) {
    _showScheduleDetail(schedule);
  }

  void _showScheduleDetail(ScheduleItem schedule) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: schedule.title.isNotEmpty ? schedule.title : '日程详情',
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (schedule.description.isNotEmpty) ...[
              Text(schedule.description),
              const SizedBox(height: 16),
            ],
            Text(
              '开始: ${_formatTime(schedule.startTime)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '结束: ${_formatTime(schedule.endTime)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  List<ScheduleItem> _getSchedulesForDate() {
    if (_currentViewId == null || _selectedDay == null) return [];
    return _scheduleModel.getSchedulesForDate(_selectedDay!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MobileAppBar(
        title: '日历',
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildMonthHeader(),
            _buildCalendar(),
            const Divider(height: 1),
            _buildDateTitle(),
            Expanded(
              child: _buildContentList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_focusedDay.year}年${_focusedDay.month}月',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: () => _changeMonth(-1),
            tooltip: '上一月',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: () => _changeMonth(1),
            tooltip: '下一月',
          ),
        ],
      ),
    );
  }

  void _changeMonth(int delta) {
    final candidate = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
    final first = DateTime(DateTime.now().year - 1, 1, 1);
    final last = DateTime(DateTime.now().year + 1, 12, 31);
    if (candidate.isBefore(first)) return;
    if (candidate.isAfter(last)) return;

    setState(() {
      _focusedDay = candidate;
    });
  }

  Widget _buildCalendar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DatePicker(
        isRange: false,
        focusedDay: _focusedDay,
        selectedDay: _selectedDay,
        onDaySelected: _onDaySelected,
        onPageChanged: (focusedDay) {
          setState(() {
            _focusedDay = focusedDay;
          });
        },
        rowHeight: 36,
        dowHeight: 28,
        dowBottomPadding: 2,
        topPadding: 0,
      ),
    );
  }

  Widget _buildDateTitle() {
    if (_selectedDay == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            '${_selectedDay!.year}年${_selectedDay!.month}月${_selectedDay!.day}日',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _showCreateScheduleDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建日程'),
          ),
        ],
      ),
    );
  }

  void _showCreateScheduleDialog() {
    // TODO: 显示新建日程对话框
  }

  Widget _buildContentList() {
    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator());
    }

    final schedules = _getSchedulesForDate();

    if (_notesForDate.isEmpty && schedules.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 笔记列表
        ..._notesForDate.map((note) => _buildNoteItem(note)),
        if (_notesForDate.isNotEmpty && schedules.isNotEmpty)
          const SizedBox(height: 16),
        // 日程列表
        ...schedules.map((schedule) => _buildScheduleItem(schedule)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildNoteItem(ViewPB note) {
    return InkWell(
      onTap: () => _onNoteTap(note),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            note.defaultIcon(size: const Size(24, 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                note.name,
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatCreateTime(note.createTime.toInt()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleItem(ScheduleItem schedule) {
    return InkWell(
      onTap: () => _onScheduleTap(schedule),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: schedule.isCompleted ? Colors.grey : Colors.green,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.title.isNotEmpty ? schedule.title : schedule.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          decoration: schedule.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  String _formatCreateTime(int timestamp) {
    final createTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${createTime.hour.toString().padLeft(2, '0')}:${createTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlowySvg(
            FlowySvgs.m_empty_page_xl,
            size: const Size(80, 80),
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '当天暂无笔记和日程',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}
