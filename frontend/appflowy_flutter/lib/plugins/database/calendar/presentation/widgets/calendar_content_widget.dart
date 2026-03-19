// 统一的日记和日程展示组件
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/calendar/presentation/widgets/schedule_sidebar_content.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../workspace/application/sidebar/folder/folder_bloc.dart';
import '../../../../../workspace/application/view/view_listener.dart';
import '../../../../../workspace/application/view/view_service.dart';
import '../../../../../workspace/application/view/view_ext.dart';
import '../../../../../workspace/presentation/home/menu/view/view_item.dart';
import '../../../../../workspace/presentation/home/home_sizes.dart';
import '../../application/calendar_content_cubit.dart';
import '../../models/schedule_model.dart';

class CalendarContent extends StatefulWidget {
  final DateTime selectedDate;
  final String? viewId;
  final Function(ScheduleItem)? onScheduleTap; // 点击日程的回调
  final Function(ViewPB)? onNoteTap; // 点击笔记的回调
  final String? selectedNoteId; // 当前选中的笔记ID
  final FolderSpaceType spaceType; // 空间类型

  const CalendarContent({
    Key? key,
    required this.selectedDate,
    this.viewId,
    this.onScheduleTap,
    this.onNoteTap,
    this.selectedNoteId,
    required this.spaceType,
  }) : super(key: key);

  @override
  State<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends State<CalendarContent> {
  List<ViewPB> _realNotes = [];
  /// 全量视图 id→视图，用于拼出笔记的父级路径
  Map<String, ViewPB> _viewById = {};
  bool _isLoading = false;
  ViewListener? _viewListener;

  // 公共方法：手动刷新数据
  void refreshData() {
    _loadNotesForDate();
  }

  @override
  void initState() {
    super.initState();
    _loadNotesForDate();
    _setupViewListener();
  }

  // 设置视图监听器，监听视图变化
  void _setupViewListener() {
    // 不指定 viewId，这样可以监听所有视图的变化，包括文档删除
    _viewListener = ViewListener(viewId: null);
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
          ] else ...[
            // 优先展示笔记
            if (_realNotes.isNotEmpty) ...[
              ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: _buildNoteTree(context),
              ),
              const SizedBox(height: 16),
              // 有笔记时也显示日程（如果有）
              if (widget.viewId != null) ...[
                ScheduleSidebarContent(
                  databaseViewId: widget.viewId,
                  onScheduleTap: widget.onScheduleTap,
                  selectedDate: widget.selectedDate,
                ),
              ],
            ] else ...[
              // 没有笔记，显示"当天暂无笔记"提示
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
              // 显示日程（如果有）
              if (widget.viewId != null) ...[
                ScheduleSidebarContent(
                  databaseViewId: widget.viewId,
                  onScheduleTap: widget.onScheduleTap,
                  selectedDate: widget.selectedDate,
                ),
              ] else ...[
                // 既没有笔记也没有日程（没有viewId），显示空布局
                _buildEmptyState(context),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '当天暂无笔记和日程',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击日历创建新日程',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.4),
              ),
            ),
          ],
        ),
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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取所有视图
      final allViewsResult = await ViewBackendService.getAllViews();

      // await 后检查 mounted，避免 setState() called after dispose()
      if (!mounted) return;

      await allViewsResult.fold(
            (allViews) async {
          // 过滤出文档类型的视图（笔记），包括"我的空间"中的日记
          // 显示所有Document类型的视图，包括孤儿视图和我的空间中的文档
          _viewById = {for (final v in allViews.items) v.id: v};

          final documentViews = allViews.items
              .where((view) =>
              !view.isSpace &&
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

          // 过滤掉空间类型的文档（空间统一页面本身不作为“日记/笔记”显示）
          notesForDate.removeWhere((view) => view.isSpace);
          // 按创建时间排序，从新到旧
          notesForDate.sort((a, b) => b.createTime.compareTo(a.createTime));

          if (!mounted) return;
          setState(() {
            _realNotes = notesForDate;
            _isLoading = false;
          });

          // 如果有笔记且没有当前选中的笔记，自动选择第一条笔记
          if (_realNotes.isNotEmpty && widget.selectedNoteId == null) {
            if (widget.onNoteTap != null) {
              widget.onNoteTap!(_realNotes.first);
            }
          }
        },
            (error) {
          if (!mounted) return;
          setState(() {
            _realNotes = [];
            _viewById = {};
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _realNotes = [];
        _viewById = {};
        _isLoading = false;
      });
    }
  }

  /// 从笔记沿 parentViewId 追溯到根，得到 [顶层, …, 笔记]
  List<ViewPB> _pathFromNoteToRoot(ViewPB note) {
    final path = <ViewPB>[];
    ViewPB? cur = note;
    final seen = <String>{};
    while (cur != null) {
      if (seen.contains(cur.id)) break;
      seen.add(cur.id);
      path.insert(0, cur);
      final pid = cur.parentViewId;
      if (pid.isEmpty) break;
      cur = _viewById[pid];
    }
    return path;
  }

  void _mergePathIntoForest(
      Map<String, _CalendarNoteTreeNode> forest, List<ViewPB> path) {
    if (path.isEmpty) return;
    var level = forest;
    for (var i = 0; i < path.length; i++) {
      final v = path[i];
      level.putIfAbsent(v.id, () => _CalendarNoteTreeNode(v));
      final node = level[v.id]!;
      if (i < path.length - 1) {
        level = node.children;
      }
    }
  }

  List<Widget> _buildNoteTree(BuildContext context) {
    final forest = <String, _CalendarNoteTreeNode>{};
    for (final note in _realNotes) {
      _mergePathIntoForest(forest, _pathFromNoteToRoot(note));
    }
    final roots = forest.values.toList()
      ..sort(_CalendarNoteTreeNode.compare);
    for (final r in roots) {
      r.sortChildrenRecursively();
    }
    final displayRoots = _rootsWithoutLeadingSpace(roots);
    return displayRoots
        .map((n) => _buildNoteTreeNode(context, n, depth: 0))
        .toList();
  }

  /// 仅剥掉名为 Workspace / 工作区的壳（多为文件夹而非 isSpace）；不按 isSpace 泛剥，避免多空间混排。
  bool _isWorkspaceShellView(ViewPB v) {
    final t = v.name.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    return lower == 'workspace' || t == '工作区' || lower == '工作区';
  }

  /// 不展示 Workspace 壳层，将其子节点与同级合并到顶层展示。
  List<_CalendarNoteTreeNode> _rootsWithoutLeadingSpace(
    List<_CalendarNoteTreeNode> roots,
  ) {
    var r = List<_CalendarNoteTreeNode>.from(roots);

    while (r.length == 1 &&
        _isWorkspaceShellView(r.first.view) &&
        r.first.sortedChildren.isNotEmpty) {
      r = r.first.sortedChildren.toList()
        ..sort(_CalendarNoteTreeNode.compare);
      for (final node in r) {
        node.sortChildrenRecursively();
      }
    }

    var changed = true;
    while (changed) {
      changed = false;
      final next = <_CalendarNoteTreeNode>[];
      for (final n in r) {
        if (_isWorkspaceShellView(n.view) && n.sortedChildren.isNotEmpty) {
          next.addAll(n.sortedChildren);
          changed = true;
        } else {
          next.add(n);
        }
      }
      if (changed) {
        r = next..sort(_CalendarNoteTreeNode.compare);
        for (final node in r) {
          node.sortChildrenRecursively();
        }
      }
    }

    return r;
  }

  Widget _buildNoteTreeNode(
    BuildContext context,
    _CalendarNoteTreeNode node, {
    required int depth,
  }) {
    // Folder / Notebook / Space / 有子节点的 Document：统一用可折叠 tile 包装
    final isFolderLike = node.view.layout == ViewLayoutPB.Folder ||
        node.view.layout == ViewLayoutPB.Notebook ||
        node.view.isSpace;
    if (isFolderLike || node.sortedChildren.isNotEmpty) {
      return _CalendarNoteFolderTile(
        key: ValueKey('cal_folder_${node.view.id}'),
        view: node.view,
        depth: depth,
        indent: _perLevelIndent,
        childWidgets: node.sortedChildren
            .map((c) => _buildNoteTreeNode(context, c, depth: depth + 1))
            .toList(),
      );
    }

    // Document（笔记）单独一行
    return _buildNoteItem(node.view, level: depth);
  }

  static const double _perLevelIndent = 16.0;

  Widget _buildNoteItem(ViewPB note, {int level = 0}) {
    final isSelected = widget.selectedNoteId == note.id;

    return ViewItem(
      key: ValueKey(note.id),
      view: note,
      spaceType: widget.spaceType,
      level: level,
      onSelected: (context, view) {
        // 点击笔记时调用回调函数
        if (widget.onNoteTap != null) {
          widget.onNoteTap!(view);
        }
      },
      isFeedback: false,
      height: HomeSpaceViewSizes.viewHeight,
      isDraggable: false,
      isHoverEnabled: true,
      shouldRenderChildren: false,
      disableSelectedStatus: false,
      rightIconsBuilder: (context, view) {
        return [
          Text(
            _formatCreateTime(view.createTime.toInt()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          const HSpace(8),
        ];
      },
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

/// 与 Space Hub 一致：用 [ListView] 承载行 + 本组件内 [State] 保存展开，避免父级重建/滚动抢手势导致点击无效。
class _CalendarNoteFolderTile extends StatefulWidget {
  const _CalendarNoteFolderTile({
    super.key,
    required this.view,
    required this.depth,
    required this.indent,
    required this.childWidgets,
  });

  final ViewPB view;
  final int depth;
  final double indent;
  final List<Widget> childWidgets;

  @override
  State<_CalendarNoteFolderTile> createState() =>
      _CalendarNoteFolderTileState();
}

class _CalendarNoteFolderTileState extends State<_CalendarNoteFolderTile> {
  bool _expanded = true;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final left = widget.depth * widget.indent;

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 200),
      crossFadeState:
          _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeIn,
      sizeCurve: Curves.easeInOut,
      firstChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(left),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: widget.childWidgets,
          ),
        ],
      ),
      secondChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(left),
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildHeader(double left) {
    return Padding(
      padding: EdgeInsets.fromLTRB(left, 0, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: FlowyHover(
              child: GestureDetector(
                onTap: _toggle,
                child: FlowySvg(
                  _expanded
                      ? FlowySvgs.view_item_expand_s
                      : FlowySvgs.view_item_unexpand_s,
                  size: const Size.square(16.0),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: Center(
              child: Opacity(
                opacity: 0.6,
                child: widget.view.defaultIcon(
                  size: const Size(18, 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.view.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 日历当日笔记树节点（合并多条路径）
class _CalendarNoteTreeNode {
  _CalendarNoteTreeNode(this.view);

  final ViewPB view;
  final Map<String, _CalendarNoteTreeNode> children = {};
  List<_CalendarNoteTreeNode> sortedChildren = [];

  static bool _folderLike(ViewPB v) =>
      v.layout == ViewLayoutPB.Folder ||
      v.layout == ViewLayoutPB.Notebook ||
      v.isSpace;

  static int compare(_CalendarNoteTreeNode a, _CalendarNoteTreeNode b) {
    final fa = _folderLike(a.view);
    final fb = _folderLike(b.view);
    if (fa != fb) return fa ? -1 : 1;
    return a.view.name.compareTo(b.view.name);
  }

  void sortChildrenRecursively() {
    sortedChildren = children.values.toList()..sort(compare);
    for (final c in sortedChildren) {
      c.sortChildrenRecursively();
    }
  }
}