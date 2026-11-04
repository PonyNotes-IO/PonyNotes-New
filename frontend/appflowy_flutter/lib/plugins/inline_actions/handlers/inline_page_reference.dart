import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/note_graph/application/note_graph_data.dart';
import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/backlinks/note_reference_picker.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/insert_page_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy/plugins/inline_actions/service_handler.dart';
import 'package:appflowy/shared/flowy_error_page.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/list_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/dialog/styled_dialogs.dart';
import 'package:flutter/material.dart';

// const _channel = "InlinePageReference";

// TODO(Mathias): Clean up and use folder search instead
class InlinePageReferenceService extends InlineActionsDelegate {
  InlinePageReferenceService({
    required this.currentViewId,
    this.workspaceId,
    this.viewLayout,
    this.customTitle,
    this.insertPage = false,
    this.selectBlock = false,
    this.limitResults = 5,
    this.loadViews,
  }) : assert(limitResults > 0, 'limitResults must be greater than 0') {
    init();
  }

  final Completer _initCompleter = Completer<void>();

  final String currentViewId;
  final String? workspaceId;
  final Future<List<ViewPB>> Function()? loadViews;
  final ViewLayoutPB? viewLayout;
  final String? customTitle;

  /// Defaults to false, if set to true the Page
  /// will be inserted as a Reference
  /// When false, a link to the view will be inserted
  ///
  final bool insertPage;
  final bool selectBlock;

  /// Defaults to 5
  /// Will limit the page reference results
  /// to [limitResults].
  ///
  final int limitResults;

  late final CachedRecentService _recentService;

  bool _recentViewsInitialized = false;
  List<InlineActionsMenuItem> _recentViews = [];

  Future<List<InlineActionsMenuItem>> _getRecentViews() async {
    if (_recentViewsInitialized) {
      return _recentViews;
    }

    final sectionViews = await _recentService.recentViews();
    final views =
        sectionViews.unique((e) => e.item.id).map((e) => e.item).toList();

    // Filter by viewLayout
    views.retainWhere(
      (i) =>
          currentViewId != i.id &&
          !NoteGraphData.isWorkspaceRoot(i, workspaceId) &&
          (viewLayout == null || i.layout == viewLayout),
    );

    _recentViews = views.map(_fromView).take(5).toList();
    _recentViewsInitialized = true;
    return _recentViews;
  }

  bool _viewsInitialized = false;
  List<ViewPB> _allViews = [];
  Map<String, ViewPB> _readableViews = {};

  Future<List<ViewPB>> _getViews() async {
    if (_viewsInitialized) {
      return _allViews;
    }

    final List<ViewPB> views;
    if (loadViews != null) {
      views = await loadViews!();
    } else {
      final result = await ViewBackendService.getAllViews();
      views = result.fold(
        (value) => value.items,
        (error) => throw StateError(error.msg),
      );
    }
    _readableViews = {
      for (final view in views)
        if (workspaceId == null ||
            view.workspaceId.isEmpty ||
            view.workspaceId == workspaceId)
          view.id: view,
    };
    final ordered = _readableViews.values.toList();
    if (selectBlock) ordered.sort(_compareReferenceViews);
    _allViews = ordered
        .where((view) => !NoteGraphData.isWorkspaceRoot(view, workspaceId))
        .where((view) => !selectBlock || !view.isSpace)
        .where((v) => viewLayout == null || v.layout == viewLayout)
        .toList();
    _viewsInitialized = true;
    return _allViews;
  }

  int _compareReferenceViews(ViewPB a, ViewPB b) {
    final current = noteSpaceId(currentViewId, _readableViews);
    final aLocal =
        current != null && noteSpaceId(a.id, _readableViews) == current;
    final bLocal =
        current != null && noteSpaceId(b.id, _readableViews) == current;
    if (aLocal != bLocal) return aLocal ? -1 : 1;
    return a.name.compareTo(b.name);
  }

  String _referenceLabel(ViewPB view) {
    if (!selectBlock) return view.nameOrDefault;
    final path = <String>[];
    var parent = view.parentViewId;
    final seen = {view.id};
    while (seen.add(parent)) {
      final ancestor = _readableViews[parent];
      if (ancestor == null ||
          NoteGraphData.isWorkspaceRoot(ancestor, workspaceId)) {
        break;
      }
      if (ancestor.name.isNotEmpty) path.add(ancestor.name);
      parent = ancestor.parentViewId;
    }
    return path.isEmpty
        ? view.nameOrDefault
        : '${view.nameOrDefault} · ${path.reversed.join(' / ')}';
  }

  Future<void> init() async {
    _recentService = getIt<CachedRecentService>();
    // _searchListener.start(onResultsClosed: _onResults);
  }

  @override
  Future<void> dispose() async {
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }

    await super.dispose();
  }

  @override
  Future<InlineActionsResult> search([
    String? search,
  ]) async {
    final isSearching = search != null && search.isNotEmpty;

    late List<InlineActionsMenuItem> items;
    if (selectBlock || isSearching) {
      final allViews = await _getViews();
      final query = search?.trim().toLowerCase() ?? '';
      final matches = allViews
          .where(
            (view) =>
                view.id != currentViewId &&
                (query.isEmpty ||
                    _referenceLabel(view).toLowerCase().contains(query)),
          )
          .toList();
      items = matches.take(limitResults).map(_fromView).toList();
      if (selectBlock && matches.length > limitResults) {
        items.add(
          InlineActionsMenuItem(
            label: 'inlineActions.morePages'.tr(args: ['${matches.length}']),
            iconBuilder: (_) => const Icon(Icons.search, size: 16),
            onSelected: (context, editor, menu, replace) =>
                _selectPassage(editor, replace),
          ),
        );
      }
    } else {
      items = await _getRecentViews();
    }

    return InlineActionsResult(
      title: customTitle?.isNotEmpty == true
          ? customTitle!
          : isSearching || selectBlock
              ? LocaleKeys.inlineActions_pageReference.tr()
              : LocaleKeys.inlineActions_recentPages.tr(),
      results: items,
    );
  }

  Future<void> _onInsertPageRef(
    ViewPB view,
    BuildContext context,
    EditorState editorState,
    (int, int) replace,
  ) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final node = editorState.getNodeAtPath(selection.start.path);

    if (node != null) {
      // Delete search term
      if (replace.$2 > 0) {
        final transaction = editorState.transaction
          ..deleteText(node, replace.$1, replace.$2);
        await editorState.apply(transaction);
      }

      // Insert newline before inserting referenced database
      if (node.delta?.toPlainText().isNotEmpty == true) {
        await editorState.insertNewLine();
      }
    }

    try {
      await editorState.insertReferencePage(view, view.layout);
    } on FlowyError catch (e) {
      if (context.mounted) {
        return Dialogs.show(
          context,
          child: AppFlowyErrorPage(
            error: e,
          ),
        );
      }
    }
  }

  Future<void> _onInsertLinkRef(
    ViewPB view,
    BuildContext context,
    EditorState editorState,
    InlineActionsMenuService menuService,
    (int, int) replace,
  ) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    if (selectBlock && view.layout == ViewLayoutPB.Document) {
      _selectPassage(editorState, replace, view: view);
      return;
    }

    // @page name -> $
    // preload the page infos
    pageMemorizer[view.id] = view;
    final transaction = editorState.transaction
      ..replaceText(
        node,
        replace.$1,
        replace.$2,
        MentionBlockKeys.mentionChar,
        attributes: MentionBlockKeys.buildMentionPageAttributes(
          mentionType: MentionType.page,
          pageId: view.id,
          blockId: null,
        ),
      );

    await editorState.apply(transaction);
  }

  void _selectPassage(EditorState editor, (int, int) replace, {ViewPB? view}) {
    final anchor = NoteReferenceAnchor.capture(
      editor,
      start: replace.$1,
      length: replace.$2,
    );
    final context = editor.document.root.context;
    if (anchor == null || context == null || !context.mounted) return;
    // The inline menu must finish dismissing before the picker takes focus.
    unawaited(
      Future<void>.microtask(() async {
        if (context.mounted) {
          await insertNoteReference(
            context,
            editor,
            initialView: view,
            anchor: anchor,
          );
        }
      }),
    );
  }

  InlineActionsMenuItem _fromView(ViewPB view) => InlineActionsMenuItem(
        keywords: [view.nameOrDefault.toLowerCase()],
        label: _referenceLabel(view),
        iconBuilder: (onSelected) {
          final child = view.icon.value.isNotEmpty
              ? RawEmojiIconWidget(
                  emoji: view.icon.toEmojiIconData(),
                  emojiSize: 16.0,
                  lineHeight: 18.0 / 16.0,
                )
              : view.defaultIcon(size: const Size(16, 16));
          return SizedBox(
            width: 16,
            child: child,
          );
        },
        onSelected: (context, editorState, menu, replace) => insertPage
            ? _onInsertPageRef(view, context, editorState, replace)
            : _onInsertLinkRef(view, context, editorState, menu, replace),
      );

// Future<InlineActionsMenuItem?> _fromSearchResult(
//   SearchResultPB result,
// ) async {
//   final viewRes = await ViewBackendService.getView(result.viewId);
//   final view = viewRes.toNullable();
//   if (view == null) {
//     return null;
//   }

//   return _fromView(view);
// }
}
