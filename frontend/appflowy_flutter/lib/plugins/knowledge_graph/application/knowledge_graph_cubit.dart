import 'dart:async';

import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-document/notification.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef GraphViewLoader = Future<List<ViewPB>> Function();
typedef GraphDocumentLoader = Future<DocumentDataPB?> Function(String id);

class KnowledgeGraphState {
  const KnowledgeGraphState({
    this.data = const KnowledgeGraphData(),
    this.loading = true,
    this.indexing = false,
    this.failedDocuments = 0,
    this.error = false,
  });

  final KnowledgeGraphData data;
  final bool loading;
  final bool indexing;
  final int failedDocuments;
  final bool error;
}

class KnowledgeGraphCubit extends Cubit<KnowledgeGraphState> {
  KnowledgeGraphCubit({
    required this.workspaceId,
    GraphViewLoader? loadViews,
    GraphDocumentLoader? loadDocument,
  })  : _loadViews = loadViews ?? _readViews,
        _loadDocument = loadDocument ?? _readDocument,
        super(const KnowledgeGraphState());

  final String workspaceId;
  final GraphViewLoader _loadViews;
  final GraphDocumentLoader _loadDocument;
  StreamSubscription<SubscribeObject>? _subscription;
  Timer? _debounce;
  int _generation = 0;
  bool _refreshing = false;
  bool _refreshAgain = false;

  void start() {
    _subscription ??= RustStreamReceiver.listen((event) {
      final folderChanged = event.source == 'Workspace' &&
          const {
            FolderNotification.DidUpdateWorkspaceViews,
            FolderNotification.DidUpdateView,
            FolderNotification.DidUpdateChildViews,
            FolderNotification.DidDeleteView,
            FolderNotification.DidRestoreView,
            FolderNotification.DidMoveViewToTrash,
            FolderNotification.DidUpdateTrash,
            FolderNotification.DidUpdateSectionViews,
            FolderNotification.DidUpdateSharedViews,
            FolderNotification.DidRemoveMySharedView,
          }.contains(FolderNotification.valueOf(event.ty));
      final documentChanged = event.source == 'Document' &&
          event.ty == DocumentNotification.DidReceiveUpdate.value;
      if (folderChanged || documentChanged) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 800), refresh);
      }
    });
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (isClosed) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final generation = ++_generation;
    bool active() => !isClosed && generation == _generation;
    try {
      final views = await _loadViews().timeout(const Duration(seconds: 15));
      if (!active()) return;
      final builder = KnowledgeGraphBuilder(views, workspaceId: workspaceId);
      final documents = builder.build().nodes.map((node) => node.view).toList();
      emit(
        KnowledgeGraphState(
          data: builder.build(),
          loading: false,
          indexing: documents.isNotEmpty,
        ),
      );
      var failed = 0;
      // Bound FFI reads and keep indexing cancellable when the workspace closes.
      for (var offset = 0; offset < documents.length; offset += 4) {
        if (!active()) return;
        final batch = documents.skip(offset).take(4);
        await Future.wait(
          batch.map((view) async {
            try {
              final document = await _loadDocument(view.id)
                  .timeout(const Duration(seconds: 8));
              if (!active()) return;
              if (document == null) {
                failed++;
              } else {
                builder.addDocument(view, document);
              }
            } catch (error) {
              failed++;
              Log.warn('Knowledge graph could not read ${view.id}: $error');
            }
          }),
        );
        if (!active()) return;
      }
      if (active()) {
        emit(
          KnowledgeGraphState(
            data: builder.build(),
            loading: false,
            failedDocuments: failed,
          ),
        );
      }
    } catch (error) {
      Log.error('Failed to load workspace graph', error);
      if (active()) {
        emit(
          KnowledgeGraphState(data: state.data, loading: false, error: true),
        );
      }
    } finally {
      _refreshing = false;
      if (active() && _refreshAgain) {
        _refreshAgain = false;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 800), refresh);
      }
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    _debounce?.cancel();
    await _subscription?.cancel();
    return super.close();
  }

  static Future<List<ViewPB>> _readViews() async =>
      (await ViewBackendService.getAllViews()).fold(
        (views) => views.items,
        (error) => throw StateError(error.msg),
      );

  static Future<DocumentDataPB?> _readDocument(String id) async =>
      (await DocumentService().getDocument(documentId: id)).fold(
        (document) => document,
        (error) => null,
      );
}
