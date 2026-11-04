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
import 'package:flutter_bloc/flutter_bloc.dart';

import 'note_graph_data.dart';

class NoteGraphState {
  NoteGraphState({
    NoteGraphData? data,
    this.loading = false,
    this.error = false,
    this.incomplete = false,
    this.truncated = false,
  }) : data = data ?? NoteGraphData.empty();
  final NoteGraphData data;
  final bool loading;
  final bool error;
  final bool incomplete;
  final bool truncated;
}

/// Independent of the semantic knowledge graph, its AI pipeline and layout cache.
class NoteGraphCubit extends Cubit<NoteGraphState> {
  NoteGraphCubit({
    required this.workspaceId,
    Future<List<ViewPB>> Function()? loadViews,
    Future<DocumentLinksPB> Function()? loadLinks,
    Future<String> Function(String page, String block)? loadExcerpt,
  })  : _loadViews = loadViews ??
            (() async {
              final result = await ViewBackendService.getAllViews();
              return result.fold(
                (value) => value.items,
                (error) => throw StateError(error.msg),
              );
            }),
        _loadLinks =
            loadLinks ?? (() => NoteLinkService.read(workspaceId: workspaceId)),
        _loadExcerpt = loadExcerpt,
        super(NoteGraphState(loading: true));

  final String workspaceId;
  final Future<List<ViewPB>> Function() _loadViews;
  final Future<DocumentLinksPB> Function() _loadLinks;
  final Future<String> Function(String page, String block)? _loadExcerpt;
  StreamSubscription<SubscribeObject>? _updates;
  Timer? _debounce;
  int _generation = 0;
  final _excerpts = <(String, String), Future<String>>{};

  void start() {
    _updates ??= RustStreamReceiver.listen((event) {
      if (event.source == 'Workspace' ||
          (event.source == 'Document' &&
              event.ty == DocumentNotification.DidUpdateLinks.value &&
              event.id == workspaceId) ||
          (event.source == 'Document' &&
              event.ty == DocumentNotification.DidReceiveUpdate.value &&
              state.data.notes.containsKey(event.id))) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), refresh);
      }
    });
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    emit(NoteGraphState(loading: true));
    _excerpts.clear();
    try {
      final views = await _loadViews().timeout(const Duration(seconds: 15));
      if (isClosed || generation != _generation) return;
      final snapshot = await _loadLinks().timeout(const Duration(seconds: 15));
      if (isClosed || generation != _generation) return;
      final data = NoteGraphData.fromIndex(views, snapshot, workspaceId: workspaceId);
      emit(
        NoteGraphState(
          data: data,
          incomplete: snapshot.indexedPages < data.notes.length,
          truncated: snapshot.truncated,
        ),
      );
    } catch (_) {
      if (!isClosed && generation == _generation) {
        emit(NoteGraphState(error: true));
      }
    }
  }

  /// Body text is read only for the selected relationship, never to build the graph.
  Future<String> excerpt(String page, String block) {
    if (block.isEmpty || !state.data.notes.containsKey(page)) {
      return Future.value('');
    }
    return _excerpts.putIfAbsent((page, block), () async {
      final generation = _generation;
      final String text;
      if (_loadExcerpt != null) {
        text = await _loadExcerpt(page, block);
      } else {
        final result = await DocumentService()
            .getDocumentNode(documentId: page, blockId: block);
        final node = result.fold((value) => value.$3, (_) => null);
        text = node == null
            ? ''
            : noteBlockText(
                node,
                titles: {
                  for (final view in state.data.notes.values)
                    view.id: view.name,
                },
              );
      }
      if (isClosed ||
          generation != _generation ||
          !state.data.notes.containsKey(page)) {
        return '';
      }
      return String.fromCharCodes(text.runes.take(260));
    });
  }

  @override
  Future<void> close() async {
    _generation++;
    _debounce?.cancel();
    await _updates?.cancel();
    return super.close();
  }
}
