import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/mobile_edit_event_page.dart';
import 'package:appflowy/mobile/presentation/database/mobile_new_event_page.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_note_tree.dart';
import 'package:appflowy/plugins/database/calendar/models/schedule_model.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_picker.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:nanoid/nanoid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  // 用于主动触发 [MobileCalendarDayContent] 重新加载
  final GlobalKey<_MobileCalendarDayContentState> _dayContentKey =
      GlobalKey<_MobileCalendarDayContentState>();

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialDate ?? DateTime.now();
    _selectedDay = _focusedDay;
    // 延迟初始化数据库，避免阻塞 UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCalendarView();
    });
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
    _scheduleModel.dispose();
    super.dispose();
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    // 只更新日期状态，触发子 widget [MobileCalendarDayContent] 重新加载数据，
    // 避免父级整页刷新带来的视觉抖动。
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
  }

  void _onNoteTap(ViewPB note) {
    // 按视图布局选择移动端路由，确保数据库、白板、聊天等页面可正常打开。
    context.pushView(note);
  }

  void _onScheduleTap(ScheduleItem schedule) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => MobileEditEventPage(
          schedule: schedule,
          scheduleModel: _scheduleModel,
          onEventUpdated: () {
            // 数据由 ScheduleModel 的 notifyListeners 通知本卡片刷新
          },
          onEventDeleted: () {
            // 数据由 ScheduleModel 的 notifyListeners 通知本卡片刷新
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MobileAppBar(
        title: '日历',
      ),
      body: SafeArea(
        child: _buildScrollableContent(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        backgroundColor: const Color(0xFFFF6B35),
        elevation: 0,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildScrollableContent() {
    final selectedDate = _selectedDay ?? _focusedDay;

    return SingleChildScrollView(
      child: Column(
        children: [
          // 月份标题
          _buildMonthHeader(),
          // 日期选择器
          _buildCalendar(),
          // 笔记和日程列表（独立 State，切换日期仅本卡片刷新）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: MobileCalendarDayContent(
              key: _dayContentKey,
              selectedDate: selectedDate,
              scheduleModel: _scheduleModel,
              onNoteTap: _onNoteTap,
              onScheduleTap: _onScheduleTap,
              onCreateSchedule: () => _showCreateScheduleDialog(selectedDate),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    // 显示输入标题对话框
    final theme = AppFlowyTheme.of(context);
    String documentTitle = '';
    bool isCreating = false;

    final result = await showDialog<String>(
      context: context,
      barrierColor: theme.surfaceColorScheme.overlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AFModal(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AFModalHeader(
                  leading: const Text('新建日记页'),
                  trailing: [
                    AFGhostButton.normal(
                      onTap: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.all(theme.spacing.xs),
                      builder: (context, isHovering, disabled) {
                        return FlowySvg(
                          FlowySvgs.toast_close_s,
                          size: const Size.square(20),
                        );
                      },
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  child: TextField(
                    autofocus: true,
                    onChanged: (value) {
                      documentTitle = value;
                    },
                    enabled: !isCreating,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(ctx).textTheme.bodyLarge?.color,
                    ),
                    decoration: InputDecoration(
                      hintText: '输入日记标题',
                      filled: true,
                      fillColor: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(ctx).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                AFModalFooter(
                  trailing: [
                    AFOutlinedTextButton.normal(
                      text: '取消',
                      onTap: () {
                        if (!isCreating) {
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    AFFilledTextButton.primary(
                      text: isCreating ? '创建中...' : '创建',
                      onTap: () {
                        if (isCreating || documentTitle.trim().isEmpty) {
                          return;
                        }
                        if (documentTitle.length > 256) {
                          showToastNotification(
                            message: '日记标题过长，请控制在256个字符以内',
                            type: ToastificationType.error,
                          );
                          return;
                        }

                        setDialogState(() {
                          isCreating = true;
                        });

                        Navigator.of(ctx).pop(documentTitle.trim());
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == null || result.isEmpty) return;

    // 创建日记
    try {
      // 获取当前用户和工作空间信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final workspaceResult =
          await FolderEventGetCurrentWorkspaceSetting().send();

      final userProfile = userResult.fold(
        (user) => user,
        (error) => null,
      );
      final workspaceId = workspaceResult.fold(
        (setting) => setting.workspaceId,
        (error) => '',
      );

      if (userProfile == null || workspaceId.isEmpty) {
        showToastNotification(
          message: '无法获取当前用户或工作空间信息',
          type: ToastificationType.error,
        );
        return;
      }

      // 使用 WorkspaceService 创建文档视图
      final workspaceService = WorkspaceService(
        workspaceId: workspaceId,
        userId: userProfile.id,
      );

      // 创建/获取日历空间
      ViewPB externalCalendarView;
      try {
        externalCalendarView = await _buildCalendarSpace(workspaceService);
      } catch (e) {
        showToastNotification(
          message: '创建日记失败：无法访问日历空间',
          type: ToastificationType.error,
        );
        return;
      }

      // 在"日历"空间下创建 Document 类型的视图
      final createResult = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        name: result,
        section: ViewSectionPB.Private,
        parentViewId: externalCalendarView.id,
        openAfterCreate: false,
      );

      createResult.fold(
        (view) {
          showToastNotification(
            message: '日记创建成功',
            type: ToastificationType.success,
          );

          // 延迟刷新日历内容以显示新创建的日记
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _dayContentKey.currentState?.refreshData();
            }
          });
        },
        (error) {
          String errorMsg = '创建日记失败';
          if (error.msg.contains('ViewNameTooLong')) {
            errorMsg = '日记标题过长';
          } else if (error.msg.contains('Folder not initialized')) {
            errorMsg = '系统未完全初始化，请稍后重试';
          } else {
            errorMsg = '创建日记失败: ${error.msg}';
          }
          showToastNotification(
            message: errorMsg,
            type: ToastificationType.error,
          );
        },
      );
    } catch (e) {
      showToastNotification(
        message: '创建日记失败',
        type: ToastificationType.error,
      );
    }
  }

  Future<ViewPB> _buildCalendarSpace(WorkspaceService workspaceService) async {
    // 检查私有空间下是否存在"日历"空间
    final privateViewsResult = await workspaceService.getPrivateViews();
    final privateViews = privateViewsResult.fold(
      (views) => views,
      (error) => throw Exception('读取私有空间失败: ${error.msg}'),
    );

    // 优先复用桌面端或新版移动端创建的真正日历工作区。
    final calendarSpace = privateViews.firstWhere(
      (view) => view.name == LocaleKeys.calendar_menuName.tr() && view.isSpace,
      orElse: () => ViewPB(),
    );

    if (calendarSpace.id.isNotEmpty) {
      return calendarSpace;
    }

    // 旧版移动端创建的同名根节点缺少 Space 元数据，会被侧栏识别为普通文档。
    // 原地补齐元数据可保留其已有日记子文档，同时避免再生成同名工作区。
    final legacyCalendarRoot = privateViews.firstWhere(
      (view) => view.name == LocaleKeys.calendar_menuName.tr(),
      orElse: () => ViewPB(),
    );
    if (legacyCalendarRoot.id.isNotEmpty) {
      final updateResult = await ViewBackendService.updateView(
        viewId: legacyCalendarRoot.id,
        extra: jsonEncode(_calendarSpaceExtra(legacyCalendarRoot.extra)),
      );
      return updateResult.fold(
        // FolderEventUpdateView 当前只返回成功状态，不携带 ViewPB 数据。
        // Dart 侧会把空响应解码为默认 ViewPB，直接返回会丢失原节点 ID。
        (_) => legacyCalendarRoot,
        (error) => throw Exception('升级日历工作区失败: ${error.msg}'),
      );
    }

    // 与桌面端保持一致：创建带完整 Space 元数据的私有日历工作区。
    final createSpaceResult = await workspaceService.createView(
      name: LocaleKeys.calendar_menuName.tr(),
      viewSection: ViewSectionPB.Private,
      layout: ViewLayoutPB.Document,
      extra: jsonEncode(_calendarSpaceExtra()),
      setAsCurrent: false,
    );

    return createSpaceResult.fold(
      (view) {
        if (view.id.trim().isEmpty) {
          throw Exception('创建日历工作区失败: 返回的视图 ID 为空');
        }
        return view;
      },
      (error) => throw Exception('创建日历工作区失败: ${error.msg}'),
    );
  }

  Map<String, dynamic> _calendarSpaceExtra([String existingExtra = '']) {
    var extra = <String, dynamic>{};
    if (existingExtra.isNotEmpty) {
      try {
        final decoded = jsonDecode(existingExtra);
        if (decoded is Map<String, dynamic>) {
          extra = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // 旧数据损坏时使用标准工作区元数据覆盖，确保日历工作区可被识别。
      }
    }

    extra.addAll({
      ViewExtKeys.isSpaceKey: true,
      ViewExtKeys.spaceIconKey: '📥',
      ViewExtKeys.spaceIconColorKey: '#4A90E2',
      ViewExtKeys.spacePermissionKey: SpacePermission.private.index,
    });
    extra.putIfAbsent(
      ViewExtKeys.spaceCreatedAtKey,
      () => DateTime.now().millisecondsSinceEpoch,
    );
    return extra;
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

  void _showCreateScheduleDialog([DateTime? date]) {
    final selectedDate = date ?? _selectedDay ?? DateTime.now();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MobileNewEventPage(
          selectedDate: selectedDate,
          scheduleModel: _scheduleModel,
          onEventCreated: () {
            // 数据由 ScheduleModel 的 notifyListeners 通知本卡片刷新
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
            Icon(icon,
                size: 20, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: 20, color: Theme.of(context).colorScheme.onSurface),
          ],
        ),
      ),
    );
  }
}

/// 当日笔记 + 日程列表（独立 State，自管加载/缓存）
///
/// 设计目标：
/// 1. 选择日期时只有本 widget 内部重建并加载数据；
/// 2. 父级 [MobileCalendarPage] 只需要切换 [selectedDate]，不再触发整页刷新。
/// 3. 通过 [ListenableBuilder] 监听 [ScheduleModel]，日程变更时局部刷新。
class MobileCalendarDayContent extends StatefulWidget {
  const MobileCalendarDayContent({
    super.key,
    required this.selectedDate,
    required this.scheduleModel,
    required this.onNoteTap,
    required this.onScheduleTap,
    required this.onCreateSchedule,
  });

  final DateTime selectedDate;
  final ScheduleModel scheduleModel;
  final ValueChanged<ViewPB> onNoteTap;
  final ValueChanged<ScheduleItem> onScheduleTap;
  final VoidCallback onCreateSchedule;

  @override
  State<MobileCalendarDayContent> createState() =>
      _MobileCalendarDayContentState();
}

class _MobileCalendarDayContentState extends State<MobileCalendarDayContent> {
  bool _isLoading = false;
  List<ViewPB> _notesForDate = [];
  Map<String, ViewPB> _viewById = {};

  /// 公共方法：外部可主动触发重新加载（如新建日记后）
  void refreshData() {
    _loadNotesForDate(widget.selectedDate);
  }

  @override
  void initState() {
    super.initState();
    // 初始加载
    _loadNotesForDate(widget.selectedDate);
    // 监听日程变化（仅本 widget 重建）
    widget.scheduleModel.addListener(_onSchedulesChanged);
  }

  @override
  void didUpdateWidget(MobileCalendarDayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      // 日期切换：重新加载笔记
      _loadNotesForDate(widget.selectedDate);
    }
    if (oldWidget.scheduleModel != widget.scheduleModel) {
      oldWidget.scheduleModel.removeListener(_onSchedulesChanged);
      widget.scheduleModel.addListener(_onSchedulesChanged);
    }
  }

  @override
  void dispose() {
    widget.scheduleModel.removeListener(_onSchedulesChanged);
    super.dispose();
  }

  void _onSchedulesChanged() {
    if (mounted) setState(() {});
  }

  bool _isSystemView(String viewName) {
    const systemViewNames = [
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

  bool _isChildOfDatabaseView(ViewPB view) {
    final pid = view.parentViewId;
    if (pid.isEmpty) return false;
    final parent = _viewById[pid];
    if (parent == null) return false;
    return parent.layout == ViewLayoutPB.Grid ||
        parent.layout == ViewLayoutPB.Board ||
        parent.layout == ViewLayoutPB.Calendar;
  }

  // Rust 层只过滤他人私有空间的根节点，子文档仍可能存在于 allViews 中。
  // 父节点非空但无法从当前可见视图中找到时，整条祖先链不可达，不能在日历展示。
  bool _isAncestorChainAccessible(ViewPB view) {
    final seen = <String>{};
    var currentId = view.parentViewId;
    while (currentId.isNotEmpty) {
      if (!seen.add(currentId)) {
        break;
      }
      final parent = _viewById[currentId];
      if (parent == null) {
        return false;
      }
      currentId = parent.parentViewId;
    }
    return true;
  }

  Future<void> _loadNotesForDate(DateTime selectedDate) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final allViewsResult = await ViewBackendService.getAllViews();
      if (!mounted) return;

      await allViewsResult.fold(
        (allViews) async {
          if (!mounted) return;
          _viewById = {for (final v in allViews.items) v.id: v};

          final calendarViews = allViews.items.where((view) {
            return isCalendarEntryLayout(view.layout) &&
                view.name.isNotEmpty &&
                !_isSystemView(view.name) &&
                !_isChildOfDatabaseView(view) &&
                _isAncestorChainAccessible(view);
          }).toList();

          final selectedDateStart = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
          );
          final selectedDateEnd =
              selectedDateStart.add(const Duration(days: 1));

          final notesForDate = calendarViews.where((view) {
            final createTime = DateTime.fromMillisecondsSinceEpoch(
              view.createTime.toInt() * 1000,
            );
            return createTime.isAfter(selectedDateStart) &&
                createTime.isBefore(selectedDateEnd);
          }).toList();

          notesForDate.sort((a, b) => b.createTime.compareTo(a.createTime));

          if (!mounted) return;
          setState(() {
            _notesForDate = notesForDate;
            _isLoading = false;
          });
        },
        (error) {
          if (!mounted) return;
          setState(() {
            _notesForDate = [];
            _viewById = {};
            _isLoading = false;
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notesForDate = [];
        _viewById = {};
        _isLoading = false;
      });
    }
  }

  String _formatCreateTime(int timestamp) {
    final createTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${createTime.hour.toString().padLeft(2, '0')}:${createTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // 通过 ListenableBuilder 监听 scheduleModel，schedules 变化时只重建本卡片
    return ListenableBuilder(
      listenable: widget.scheduleModel,
      builder: (context, _) {
        final schedules = widget.scheduleModel.getSchedulesForDate(
          widget.selectedDate,
        );
        final notesEmpty = _notesForDate.isEmpty;
        final schedulesEmpty = schedules.isEmpty;

        return Container(
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
              if (_isLoading && notesEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (notesEmpty && schedulesEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: _buildEmptyState(),
                )
              else ...[
                if (_notesForDate.isNotEmpty) ...[
                  ..._buildNoteTree(),
                  if (schedules.isNotEmpty) const Divider(height: 1),
                ],
                ...schedules.map((schedule) => _buildScheduleItem(schedule)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        '${widget.selectedDate.year}年${widget.selectedDate.month}月${widget.selectedDate.day}日',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  List<Widget> _buildNoteTree() {
    final roots = buildCalendarNoteTree(
      notes: _notesForDate,
      viewById: _viewById,
    );
    return roots.map((node) => _buildNoteTreeNode(node, depth: 0)).toList();
  }

  Widget _buildNoteTreeNode(
    CalendarNoteTreeNode node, {
    required int depth,
  }) {
    final isFolderLike = node.view.layout == ViewLayoutPB.Folder ||
        node.view.layout == ViewLayoutPB.Notebook ||
        node.view.isSpace;
    if (isFolderLike || node.sortedChildren.isNotEmpty) {
      return _MobileCalendarNoteFolderTile(
        key: ValueKey('mobile_calendar_folder_${node.view.id}'),
        view: node.view,
        depth: depth,
        onTitleTap: canOpenCalendarNoteTreeNode(node.view)
            ? () => widget.onNoteTap(node.view)
            : null,
        children: node.sortedChildren
            .map((child) => _buildNoteTreeNode(child, depth: depth + 1))
            .toList(),
      );
    }
    return _buildNoteItem(node.view, depth: depth);
  }

  Widget _buildNoteItem(ViewPB note, {required int depth}) {
    return InkWell(
      onTap: () => widget.onNoteTap(note),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16 + depth * _calendarNoteIndent,
          12,
          16,
          12,
        ),
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  static const double _calendarNoteIndent = 16;

  Widget _buildScheduleItem(ScheduleItem schedule) {
    return InkWell(
      onTap: () => widget.onScheduleTap(schedule),
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
                    schedule.title.isNotEmpty
                        ? schedule.title
                        : schedule.description,
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
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlowySvg(
            FlowySvgs.m_empty_page_xl,
            size: const Size(80, 80),
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '当天暂无笔记和日程',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}

/// 移动端沿用电脑端的默认展开层级：工作区整行只展开折叠，普通文档可打开。
class _MobileCalendarNoteFolderTile extends StatefulWidget {
  const _MobileCalendarNoteFolderTile({
    super.key,
    required this.view,
    required this.depth,
    required this.children,
    this.onTitleTap,
  });

  final ViewPB view;
  final int depth;
  final List<Widget> children;
  final VoidCallback? onTitleTap;

  @override
  State<_MobileCalendarNoteFolderTile> createState() =>
      _MobileCalendarNoteFolderTileState();
}

class _MobileCalendarNoteFolderTileState
    extends State<_MobileCalendarNoteFolderTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            8 +
                widget.depth *
                    _MobileCalendarDayContentState._calendarNoteIndent,
            0,
            8,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 48,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 20,
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: widget.onTitleTap ??
                      () => setState(() => _expanded = !_expanded),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        widget.view.defaultIcon(size: const Size(24, 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.view.name,
                            style: Theme.of(context).textTheme.bodyLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.onTitleTap != null)
                          const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}
