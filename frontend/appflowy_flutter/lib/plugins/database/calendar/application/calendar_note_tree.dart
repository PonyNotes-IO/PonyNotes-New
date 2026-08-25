import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// 日历当天文档的层级节点。
///
/// [view] 既可能是当天创建的文档，也可能只是为了还原路径而补入的父工作区、
/// 文件夹或父文档。
class CalendarNoteTreeNode {
  CalendarNoteTreeNode(this.view);

  final ViewPB view;
  final Map<String, CalendarNoteTreeNode> _children = {};
  List<CalendarNoteTreeNode> sortedChildren = const [];

  static bool _folderLike(ViewPB view) =>
      view.layout == ViewLayoutPB.Folder ||
      view.layout == ViewLayoutPB.Notebook ||
      view.isSpace;

  static int compare(CalendarNoteTreeNode a, CalendarNoteTreeNode b) {
    final aFolderLike = _folderLike(a.view);
    final bFolderLike = _folderLike(b.view);
    if (aFolderLike != bFolderLike) {
      return aFolderLike ? -1 : 1;
    }
    return a.view.name.compareTo(b.view.name);
  }

  void _sortChildrenRecursively() {
    sortedChildren = _children.values.toList()..sort(compare);
    for (final child in sortedChildren) {
      child._sortChildrenRecursively();
    }
  }
}

/// 只有普通文档允许从日历文档树跳转打开。
///
/// 工作区在数据层同样使用 Document 布局，但它只是日历树中的归属容器，点击时
/// 应展开或折叠子文档，不能按普通文档跳转。
bool canOpenCalendarNoteTreeNode(ViewPB view) =>
    view.layout == ViewLayoutPB.Document && !view.isSpace;

/// 按电脑端日历的规则，把当天文档沿 parentViewId 还原成工作区文档树。
///
/// 顶层仅剥离历史数据中名为 Workspace / 工作区的壳节点，真实工作区会被保留，
/// 因此“外部导入 > dff”和其他工作区二级文档都能显示正确归属。
List<CalendarNoteTreeNode> buildCalendarNoteTree({
  required Iterable<ViewPB> notes,
  required Map<String, ViewPB> viewById,
}) {
  final forest = <String, CalendarNoteTreeNode>{};

  for (final note in notes) {
    final path = _pathFromNoteToRoot(note, viewById);
    var level = forest;
    for (var index = 0; index < path.length; index++) {
      final view = path[index];
      level.putIfAbsent(view.id, () => CalendarNoteTreeNode(view));
      if (index < path.length - 1) {
        level = level[view.id]!._children;
      }
    }
  }

  var roots = forest.values.toList()..sort(CalendarNoteTreeNode.compare);
  for (final root in roots) {
    root._sortChildrenRecursively();
  }

  var changed = true;
  while (changed) {
    changed = false;
    final visibleRoots = <CalendarNoteTreeNode>[];
    for (final root in roots) {
      if (_isWorkspaceShell(root.view) && root.sortedChildren.isNotEmpty) {
        visibleRoots.addAll(root.sortedChildren);
        changed = true;
      } else {
        visibleRoots.add(root);
      }
    }
    roots = visibleRoots..sort(CalendarNoteTreeNode.compare);
  }

  return roots;
}

List<ViewPB> _pathFromNoteToRoot(
  ViewPB note,
  Map<String, ViewPB> viewById,
) {
  final path = <ViewPB>[];
  final seen = <String>{};
  ViewPB? current = note;

  while (current != null && seen.add(current.id)) {
    path.insert(0, current);
    final parentViewId = current.parentViewId;
    current = parentViewId.isEmpty ? null : viewById[parentViewId];
  }

  return path;
}

bool _isWorkspaceShell(ViewPB view) {
  final name = view.name.trim();
  if (name.isEmpty) {
    return false;
  }
  return name.toLowerCase() == 'workspace' || name == '工作区';
}
