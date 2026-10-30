import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/ai_internal/application/internal_ai_service.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_data.dart';
import 'package:appflowy/plugins/knowledge_graph/application/knowledge_graph_extraction.dart';
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
    this.extracting = false,
    this.completedChunks = 0,
    this.totalChunks = 0,
    this.failedExtractions = 0,
    this.extractionError = '',
    this.cacheError = false,
  });

  final KnowledgeGraphData data;
  final bool loading;
  final bool indexing;
  final int failedDocuments;
  final bool error;
  final bool extracting;
  final int completedChunks;
  final int totalChunks;
  final int failedExtractions;
  final String extractionError;
  final bool cacheError;

  KnowledgeGraphState copyWith({
    KnowledgeGraphData? data,
    bool? extracting,
    int? completedChunks,
    int? totalChunks,
    int? failedExtractions,
    String? extractionError,
    bool? cacheError,
  }) =>
      KnowledgeGraphState(
        data: data ?? this.data,
        loading: loading,
        indexing: indexing,
        failedDocuments: failedDocuments,
        error: error,
        extracting: extracting ?? this.extracting,
        completedChunks: completedChunks ?? this.completedChunks,
        totalChunks: totalChunks ?? this.totalChunks,
        failedExtractions: failedExtractions ?? this.failedExtractions,
        extractionError: extractionError ?? this.extractionError,
        cacheError: cacheError ?? this.cacheError,
      );
}

class KnowledgeGraphCubit extends Cubit<KnowledgeGraphState> {
  KnowledgeGraphCubit({
    required this.workspaceId,
    this.focusViewId,
    GraphViewLoader? loadViews,
    GraphDocumentLoader? loadDocument,
    GraphChunkExtractor? extractChunk,
    GraphExtractionCache? cache,
    KnowledgeGraphExtractor? extractor,
  })  : _loadViews = loadViews ?? _readViews,
        _loadDocument = loadDocument ?? _readDocument,
        _extractChunk = extractChunk,
        _cache = cache,
        _extractor = extractor ?? KnowledgeGraphExtractor(),
        super(const KnowledgeGraphState());

  final String workspaceId;
  final String? focusViewId;
  final GraphViewLoader _loadViews;
  final GraphDocumentLoader _loadDocument;
  final GraphChunkExtractor? _extractChunk;
  final GraphExtractionCache? _cache;
  final KnowledgeGraphExtractor _extractor;
  KnowledgeGraphBuilder? _builder;
  Map<String, dynamic> _cachedPages = {};
  Map<String, List<GraphSource>> _chunks = {};
  final _fingerprints = <String, String>{};
  List<ViewPB> _documents = [];
  bool _cacheLoaded = false;
  bool _extractionCanceled = false;
  Completer<void>? _cancellation;
  Future<void>? _saving;
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
    if (state.extracting) {
      _refreshAgain = true;
      cancelExtraction();
      return;
    }
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final generation = ++_generation;
    bool active() => !isClosed && generation == _generation;
    try {
      var cacheError = false;
      if (!_cacheLoaded) {
        try {
          _cachedPages = await _cache?.load() ?? {};
        } catch (_) {
          cacheError = true;
        }
        _cacheLoaded = true;
      }
      final views = await _loadViews().timeout(const Duration(seconds: 15));
      if (!active()) return;
      final builder = KnowledgeGraphBuilder(
        views,
        workspaceId: workspaceId,
        focusViewId: focusViewId,
      );
      final documents = builder
          .build()
          .nodes
          .map((node) => node.view)
          .where(KnowledgeGraphBuilder.isDocument)
          .toList();
      _documents = documents;
      _chunks = {};
      _fingerprints.clear();
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
                final chunks = graphDocumentChunks(view.id, document);
                _chunks[view.id] = chunks;
                _fingerprints[view.id] = graphDocumentFingerprint(chunks);
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
        final validPages = <String, dynamic>{};
        for (final view in documents) {
          final cached = _cachedPages[view.id];
          final chunks = _chunks[view.id];
          if (chunks == null ||
              cached is! Map ||
              cached['fingerprint'] != _fingerprints[view.id] ||
              cached['chunks'] is! List ||
              (cached['chunks'] as List).length != chunks.length) {
            continue;
          }
          try {
            final graphs = [
              for (var i = 0; i < chunks.length; i++)
                parseGraphExtraction(
                  jsonEncode(cached['chunks'][i]),
                  chunks[i].text,
                ),
            ];
            for (var i = 0; i < chunks.length; i++) {
              builder.addExtraction(view, chunks[i], graphs[i]);
            }
            validPages[view.id] = {
              'fingerprint': cached['fingerprint'],
              'chunks': graphs,
            };
          } on FormatException {
            // Derived data can be rebuilt; never show malformed or stale facts.
            cacheError = true;
          }
        }
        _cachedPages = validPages;
        _builder = builder;
        emit(
          KnowledgeGraphState(
            data: builder.build(),
            loading: false,
            failedDocuments: failed,
            cacheError: cacheError,
          ),
        );
        await _saveCache();
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

  /// Explicit action: opening/refreshing the graph never sends notes to an LLM.
  /// Unchanged successful documents are reused, failed documents remain retryable.
  Future<void> extract() async {
    if (isClosed ||
        state.extracting ||
        _refreshing ||
        state.loading ||
        state.error ||
        _builder == null) {
      return;
    }
    final pending = _documents
        .where(
          (view) =>
              (focusViewId == null || view.id == focusViewId) &&
              _chunks.containsKey(view.id) &&
              !_cachedPages.containsKey(view.id),
        )
        .toList();
    _extractionCanceled = false;
    _cancellation = Completer<void>();
    emit(
      state.copyWith(
        extracting: true,
        completedChunks: 0,
        totalChunks:
            pending.fold<int>(0, (n, view) => n + _chunks[view.id]!.length),
        failedExtractions: 0,
        extractionError: '',
      ),
    );
    bool active() => !isClosed && !_extractionCanceled;
    try {
      for (final view in pending) {
        if (!active()) break;
        final chunks = _chunks[view.id]!;
        final graphs = <Map<String, dynamic>>[];
        try {
          // Sequential requests respect provider rate limits and cancellation.
          for (final chunk in chunks) {
            if (!active()) break;
            final graph = await Future.any([
              (_extractChunk?.call(chunk) ?? _extractor.extract(chunk))
                  .timeout(const Duration(seconds: 65)),
              _cancellation!.future.then<Map<String, dynamic>>(
                (_) => throw InternalAiException(
                  InternalAiErrorKind.canceled,
                  'Canceled',
                ),
              ),
            ]);
            if (!active()) break;
            graphs.add(parseGraphExtraction(jsonEncode(graph), chunk.text));
            emit(state.copyWith(completedChunks: state.completedChunks + 1));
          }
          if (!active()) break;
          _cachedPages[view.id] = {
            'fingerprint': _fingerprints[view.id],
            'chunks': graphs,
          };
          for (var i = 0; i < chunks.length; i++) {
            _builder!.addExtraction(view, chunks[i], graphs[i]);
          }
          emit(state.copyWith(data: _builder!.build()));
          await _saveCache();
        } catch (error) {
          if (!active()) break;
          final key = error is InternalAiException
              ? error.kind.name
              : error is TimeoutException
                  ? 'network'
                  : 'invalidResponse';
          emit(
            state.copyWith(
              failedExtractions: state.failedExtractions + 1,
              extractionError: key,
            ),
          );
          // Configuration, quota and network errors affect every following page.
          if (error is InternalAiException || error is TimeoutException) break;
        }
      }
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            extracting: false,
            extractionError:
                _extractionCanceled ? 'canceled' : state.extractionError,
          ),
        );
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  void cancelExtraction() {
    _extractionCanceled = true;
    if (_cancellation?.isCompleted == false) _cancellation!.complete();
    _extractor.cancel();
  }

  Future<void> _saveCache() async {
    if (_cache == null || isClosed) return;
    try {
      _saving = _cache.save(_cachedPages);
      await _saving;
      if (!isClosed && state.cacheError) {
        emit(state.copyWith(cacheError: false));
      }
    } catch (_) {
      if (!isClosed) emit(state.copyWith(cacheError: true));
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    cancelExtraction();
    _extractor.dispose();
    _debounce?.cancel();
    await _subscription?.cancel();
    try {
      await _saving;
    } catch (_) {/* Already reported by _saveCache. */}
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
