import 'dart:async';

import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'package:appflowy/plugins/document/application/note_link_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-document/notification.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';

/// One relation snapshot per editor, shared by the footer and every block marker.
class NoteRelationsController extends ChangeNotifier {
  NoteRelationsController({
    required this.pageId,
    required this.workspaceId,
    required this.identity,
    required this.editorState,
    Future<List<ViewPB>> Function()? loadViews,
    Future<DocumentLinksPB> Function()? loadLinks,
    Future<String> Function(String pageId, String blockId, int offset)?
        loadExcerpt,
  })  : _loadViews = loadViews,
        _loadLinks = loadLinks,
        _loadExcerpt = loadExcerpt;

  static final _editors = Expando<NoteRelationsController>();
  static NoteRelationsController? forEditor(EditorState editor) =>
      _editors[editor];

  final String pageId;
  final String workspaceId;
  final String identity;
  final EditorState editorState;
  final Future<List<ViewPB>> Function()? _loadViews;
  final Future<DocumentLinksPB> Function()? _loadLinks;
  final Future<String> Function(String pageId, String blockId, int offset)?
      _loadExcerpt;
  Map<String, ViewPB> views = {};
  DocumentLinksPB? links;
  bool loading = true;
  bool error = false;
  bool incomplete = false;
  String? highlightedBlockId;
  final _contexts = <String, Future<String>>{};
  List<NoteLinkPB>? _cachedOutgoing;
  List<NoteLinkPB>? _cachedIncoming;
  Map<String, List<NoteLinkPB>>? _incomingByBlock;
  StreamSubscription<SubscribeObject>? _updates;
  StreamSubscription<EditorTransactionValue>? _transactions;
  Timer? _debounce;
  Timer? _highlightTimer;
  bool _disposed = false;
  bool _backfilling = false;
  int _generation = 0;

  bool _isHierarchy(NoteLinkPB link) =>
      link.kind == 'embed' &&
      views[link.dstPageId]?.parentViewId == link.srcPageId;

  List<NoteLinkPB> get incoming => _cachedIncoming ??= [
        ...?links?.incoming.where(
          (link) => views.containsKey(link.srcPageId) && !_isHierarchy(link),
        ),
        // Page-level self links are hidden; references to another block in this note are useful.
        ...outgoing.where(
          (link) => link.dstPageId == pageId && link.dstBlockId.isNotEmpty,
        ),
      ];
  List<NoteLinkPB> get outgoing =>
      _cachedOutgoing ??= editorOutgoingLinks(pageId, editorState)
          .where((link) => !_isHierarchy(link))
          .toList();
  List<NoteLinkPB> incomingTo(String blockId) {
    if (_incomingByBlock == null) {
      final byBlock = <String, List<NoteLinkPB>>{};
      for (final link in incoming) {
        if (link.dstBlockId.isNotEmpty) {
          (byBlock[link.dstBlockId] ??= []).add(link);
        }
      }
      _incomingByBlock = byBlock;
    }
    return _incomingByBlock![blockId] ?? const [];
  }

  void _invalidateRelations() {
    _cachedOutgoing = null;
    _cachedIncoming = null;
    _incomingByBlock = null;
  }

  void start() {
    _editors[editorState] = this;
    _transactions = editorState.transactionStream.listen((event) {
      if (!_disposed && event.$1 == TransactionTime.after) {
        _invalidateRelations();
        notifyListeners();
      }
    });
    _updates = RustStreamReceiver.listen((event) {
      final sourceChanged = event.source == 'Document' &&
          event.ty == DocumentNotification.DidReceiveUpdate.value &&
          incoming.any((link) => link.srcPageId == event.id);
      if (event.source == 'Workspace' ||
          sourceChanged ||
          (event.source == 'Document' &&
              event.ty == DocumentNotification.DidUpdateLinks.value &&
              event.id == workspaceId)) {
        if (_backfilling) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 200), refresh);
      }
    });
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final List<ViewPB> accessible;
      if (_loadViews != null) {
        accessible = await _loadViews();
      } else {
        final result = await ViewBackendService.getAllViews();
        accessible = result.fold(
          (value) => value.items,
          (error) => throw StateError(error.msg),
        );
      }
      if (_disposed || generation != _generation) return;
      final snapshot = _loadLinks != null
          ? await _loadLinks()
          : await NoteLinkService.read(
              pageId: pageId,
              workspaceId: workspaceId,
            );
      if (_disposed || generation != _generation) return;
      views = {for (final view in accessible) view.id: view};
      links = snapshot;
      _invalidateRelations();
      _contexts.clear();
      loading = false;
      error = false;
      final count = views.values
          .where((view) => view.layout == ViewLayoutPB.Document)
          .length;
      incomplete = snapshot.indexedPages < count;
      notifyListeners();
      if (incomplete && NoteLinkService.shouldBackfill(identity)) {
        unawaited(_backfill());
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      loading = false;
      error = true;
      // Cached source titles and text must not survive a failed permission refresh.
      views = {};
      _invalidateRelations();
      _contexts.clear();
      notifyListeners();
    }
  }

  /// A user-requested refresh also repairs stale local relationships.
  Future<void> refreshReferences() async {
    await refresh();
    if (!_disposed && !error && !_backfilling) await _backfill();
  }

  /// Only rebuild locally available notes; no explicit reverse insertion is needed.
  Future<void> _backfill() async {
    if (_backfilling || _disposed) return;
    _backfilling = true;
    for (final view in views.values.toList()) {
      if (_disposed) return;
      if (view.layout != ViewLayoutPB.Document) continue;
      try {
        await NoteLinkService.read(
          pageId: view.id,
          workspaceId: workspaceId,
          repair: true,
        );
      } catch (_) {
        // The final snapshot exposes incomplete coverage in user-facing language.
      }
    }
    if (_disposed) return;
    _backfilling = false;
    await refresh();
  }

  Future<String> excerpt(String pageId, String blockId, {int offset = 0}) {
    if (!views.containsKey(pageId) || blockId.isEmpty) return Future.value('');
    return _contexts.putIfAbsent('$pageId/$blockId/$offset', () async {
      if (_loadExcerpt != null) return _loadExcerpt(pageId, blockId, offset);
      final result = await DocumentService()
          .getDocumentNode(documentId: pageId, blockId: blockId);
      if (_disposed || !views.containsKey(pageId)) return '';
      final node = result.fold((value) => value.$3, (_) => null);
      return node == null
          ? ''
          : noteLinkContext(
              noteBlockText(
                node,
                titles: {
                  for (final view in views.values) view.id: view.name,
                },
              ),
              offset,
            );
    });
  }

  void highlight(String blockId) {
    if (_disposed) return;
    highlightedBlockId = blockId;
    _highlightTimer?.cancel();
    notifyListeners();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      highlightedBlockId = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_editors[editorState] == this) _editors[editorState] = null;
    _debounce?.cancel();
    _highlightTimer?.cancel();
    unawaited(_updates?.cancel());
    unawaited(_transactions?.cancel());
    super.dispose();
  }
}
