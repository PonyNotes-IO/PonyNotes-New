// 统一的日记展示组件
import 'package:appflowy/generated/flowy_svgs.g.dart';
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
import '../../application/calendar_note_tree.dart';

class CalendarContent extends StatefulWidget {
  final DateTime selectedDate;
  final String? viewId;
  final Function(ViewPB)? onNoteTap; // 点击笔记的回调
  final String? selectedNoteId; // 当前选中的笔记ID
  final FolderSpaceType spaceType; // 空间类型

  const CalendarContent({
    Key? key,
    required this.selectedDate,
    this.viewId,
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
            if (_realNotes.isNotEmpty) ...[
              ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: _buildNoteTree(context),
              ),
            ] else ...[
              _buildEmptyState(context),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              '当天暂无笔记',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
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

  // 判断视图是否是数据库类型（Grid/Board/Calendar）的子页面（如表格行展开的页面）
  bool _isChildOfDatabaseView(ViewPB view, Map<String, ViewPB> viewById) {
    final pid = view.parentViewId;
    if (pid.isEmpty) return false;
    final parent = viewById[pid];
    if (parent == null) return false;
    return parent.layout == ViewLayoutPB.Grid ||
        parent.layout == ViewLayoutPB.Board ||
        parent.layout == ViewLayoutPB.Calendar;
  }

  // 判断视图的祖先链是否完整可达。
  // Rust 层仅过滤掉他人私有空间的根节点 ID，但其子文档仍存在于 allViews 中。
  // 若沿 parentViewId 向上追溯时遇到"非空但不存在于 viewById 的父节点"，
  // 则说明该视图的祖先被过滤掉了（属于他人的私有空间），应将其排除。
  bool _isAncestorChainAccessible(ViewPB view, Map<String, ViewPB> viewById) {
    final seen = <String>{};
    String? currentId = view.parentViewId.isEmpty ? null : view.parentViewId;
    while (currentId != null) {
      if (seen.contains(currentId)) break; // 防止循环
      seen.add(currentId);
      final parent = viewById[currentId];
      if (parent == null) {
        // parentViewId 非空但在 viewById 中找不到，说明祖先被过滤
        return false;
      }
      currentId = parent.parentViewId.isEmpty ? null : parent.parentViewId;
    }
    return true;
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
              .where(
                (view) =>
                    !view.isSpace &&
                    view.name.isNotEmpty &&
                    !_isSystemView(view.name) &&
                    // 排除数据库类型（Grid/Board/Calendar）子页面（表格行展开的页面、图片等）
                    !_isChildOfDatabaseView(view, _viewById) &&
                    // 排除祖先链不完整的视图（即其父节点已被 Rust 过滤，
                    // 属于他人私有空间内的子文档，不应对当前用户可见）
                    _isAncestorChainAccessible(view, _viewById),
              )
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

  List<Widget> _buildNoteTree(BuildContext context) {
    final roots = buildCalendarNoteTree(
      notes: _realNotes,
      viewById: _viewById,
    );
    return roots.map((n) => _buildNoteTreeNode(context, n, depth: 0)).toList();
  }

  Widget _buildNoteTreeNode(
    BuildContext context,
    CalendarNoteTreeNode node, {
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
        onTitleTap: node.view.isDocument && widget.onNoteTap != null
            ? () => widget.onNoteTap!(node.view)
            : null,
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
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7)
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
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
    this.onTitleTap,
    required this.childWidgets,
  });

  final ViewPB view;
  final int depth;
  final double indent;

  /// 点击标题行（图标+名称）时打开该笔记；仅对含子页面的 Document 等需要。
  final VoidCallback? onTitleTap;
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
      child: FlowyHover(
        style: HoverStyle(hoverColor: Theme.of(context).colorScheme.secondary),
        builder: (_, onHover) {
          // 标题区域（图标 + 名称），点击打开笔记；整行悬停时与 ViewItem 行为一致
          final titleWidget = widget.onTitleTap == null
              ? Row(
                  children: [
                    _buildIcon(),
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
                )
              : InkWell(
                  onTap: widget.onTitleTap,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        _buildIcon(),
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
                  ),
                );

          return Row(
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
              Expanded(child: titleWidget),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIcon() {
    return SizedBox(
      width: 22,
      child: Center(
        child: Opacity(
          opacity: 0.6,
          child: widget.view.defaultIcon(size: const Size(18, 18)),
        ),
      ),
    );
  }
}
