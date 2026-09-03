import 'dart:convert';

import 'package:appflowy/plugins/database/calendar/application/calendar_note_tree.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('日历候选支持所有可创建的页面布局', () {
    expect(ViewLayoutPB.values.every(isCalendarEntryLayout), isTrue);
  });

  test('工作区不可跳转但其他页面类型可以打开', () {
    final space = _view(id: 'space', name: '工作区', isSpace: true);
    final parentDocument = _view(id: 'parent-document', name: '父文档');

    expect(canOpenCalendarNoteTreeNode(space), isFalse);
    expect(canOpenCalendarNoteTreeNode(parentDocument), isTrue);
    for (final layout in ViewLayoutPB.values) {
      final view = _view(
        id: 'view-${layout.value}',
        name: layout.name,
        layout: layout,
      );
      expect(
        canOpenCalendarNoteTreeNode(view),
        isTrue,
        reason: '${layout.name} 页面应允许从日历打开',
      );
    }
  });

  test('当天文档按工作区父子关系展示并隐藏 Workspace 壳', () {
    final workspaceShell = _view(
      id: 'workspace',
      name: 'Workspace',
      layout: ViewLayoutPB.Folder,
    );
    final externalImport = _view(
      id: 'external-import',
      name: '外部导入',
      parentViewId: workspaceShell.id,
      isSpace: true,
    );
    final importedDocument = _view(
      id: 'dff',
      name: 'dff',
      parentViewId: externalImport.id,
    );
    final projectSpace = _view(
      id: 'project',
      name: '项目资料',
      parentViewId: workspaceShell.id,
      isSpace: true,
    );
    final projectDocument = _view(
      id: 'plan',
      name: '开发计划',
      parentViewId: projectSpace.id,
    );
    final allViews = [
      workspaceShell,
      externalImport,
      importedDocument,
      projectSpace,
      projectDocument,
    ];

    final roots = buildCalendarNoteTree(
      notes: [importedDocument, projectDocument],
      viewById: {for (final view in allViews) view.id: view},
    );

    expect(roots.map((node) => node.view.name), ['外部导入', '项目资料']);
    expect(
      roots.first.sortedChildren.map((node) => node.view.name),
      ['dff'],
    );
    expect(
      roots.last.sortedChildren.map((node) => node.view.name),
      ['开发计划'],
    );
  });

  test('同一父工作区的多篇当天文档合并到一个节点并稳定排序', () {
    final space = _view(id: 'space', name: '工作项目', isSpace: true);
    final documentB = _view(
      id: 'document-b',
      name: '文档 B',
      parentViewId: space.id,
    );
    final documentA = _view(
      id: 'document-a',
      name: '文档 A',
      parentViewId: space.id,
    );

    final roots = buildCalendarNoteTree(
      notes: [documentB, documentA],
      viewById: {
        space.id: space,
        documentB.id: documentB,
        documentA.id: documentA,
      },
    );

    expect(roots, hasLength(1));
    expect(roots.single.view.id, space.id);
    expect(
      roots.single.sortedChildren.map((node) => node.view.name),
      ['文档 A', '文档 B'],
    );
  });
}

ViewPB _view({
  required String id,
  required String name,
  String parentViewId = '',
  ViewLayoutPB layout = ViewLayoutPB.Document,
  bool isSpace = false,
}) {
  return ViewPB()
    ..id = id
    ..name = name
    ..parentViewId = parentViewId
    ..layout = layout
    ..extra = isSpace ? jsonEncode({ViewExtKeys.isSpaceKey: true}) : '';
}
