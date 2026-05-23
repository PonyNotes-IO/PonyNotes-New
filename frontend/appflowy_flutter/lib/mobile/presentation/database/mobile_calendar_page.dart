import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/mobile_new_event_page.dart';
import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_picker.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
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
    // 延迟初始化数据库，避免阻塞 UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCalendarView();
      _loadNotesForDate();
    });
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
            Expanded(
              child: _buildContentCard(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        backgroundColor: const Color(0xFFFF6B35),
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  void _showAddMenu() {
    showMobileBottomSheet(
      context,
      showDragHandle: false,
      showHeader: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionSheetItem(
                label: '新建日记页',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _createNewNote();
                },
              ),
              _buildDivider(),
              _buildActionSheetItem(
                label: '新建日程',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showCreateScheduleDialog();
                },
              ),
              const SizedBox(height: 8),
              _buildDivider(),
              _buildActionSheetItem(
                label: '取消',
                isCancel: true,
                onTap: () => Navigator.of(ctx).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 0.5,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
    );
  }

  Widget _buildActionSheetItem({
    required String label,
    required VoidCallback onTap,
    bool isCancel = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }

  Future<void> _createNewNote() async {
    // TODO: 实现新建日记页的逻辑
  }

  Widget _buildAddMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        '${_selectedDay!.year}年${_selectedDay!.month}月${_selectedDay!.day}日',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  void _showCreateScheduleDialog() {
    final selectedDate = _selectedDay ?? DateTime.now();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MobileNewEventPage(
          selectedDate: selectedDate,
          scheduleModel: _scheduleModel,
          onEventCreated: () {
            // 刷新列表
            _loadNotesForDate();
          },
        ),
      ),
    );
  }

  Widget _buildDialogDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 0.5,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
    );
  }

  Widget _buildDialogItem({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: Theme.of(context).colorScheme.onSurface),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard() {
    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator());
    }

    final schedules = _getSchedulesForDate();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDateTitle(),
              if (_notesForDate.isEmpty && schedules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: _buildEmptyState(),
                )
              else ...[
                if (_notesForDate.isNotEmpty) ...[
                  ..._notesForDate.map((note) => _buildNoteItem(note)),
                  if (schedules.isNotEmpty) const Divider(height: 1),
                ],
                ...schedules.map((schedule) => _buildScheduleItem(schedule)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoteItem(ViewPB note) {
    return InkWell(
      onTap: () => _onNoteTap(note),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
