import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/application/doc_sync_state_listener.dart';
import 'package:appflowy/plugins/document/application/document_awareness_metadata.dart';
import 'package:appflowy/plugins/document/application/document_collab_adapter.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_listener.dart';
import 'package:appflowy/plugins/document/application/document_rules.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/application/editor_transaction_adapter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/resource_node_cleanup.dart';
import 'package:appflowy/plugins/trash/application/trash_service.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/util/color_generator/color_generator.dart';
import 'package:appflowy/util/color_to_hex_string.dart';
import 'package:appflowy/util/debounce.dart';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy/util/throttle.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show AppFlowyEditorLogLevel, EditorState, TransactionTime;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'document_bloc.freezed.dart';

/// Enable this flag to enable the internal log for
/// - document diff
/// - document integrity check
/// - document sync state
/// - document awareness states
bool enableDocumentInternalLog = false;

final Map<String, DocumentBloc> _documentBlocMap = {};

class DocumentBloc extends Bloc<DocumentEvent, DocumentState> {
  DocumentBloc({
    required this.documentId,
    this.databaseViewId,
    this.rowId,
    this.workspaceId,
    bool saveToBlocMap = true,
  })  : _saveToBlocMap = saveToBlocMap,
        _documentListener = DocumentListener(id: documentId),
        _syncStateListener = DocumentSyncStateListener(id: documentId),
        super(DocumentState.initial()) {
    _viewListener = databaseViewId == null && rowId == null
        ? ViewListener(viewId: documentId)
        : null;
    on<DocumentEvent>(_onDocumentEvent);
  }

  static DocumentBloc? findOpen(String documentId) =>
      _documentBlocMap[documentId];

  /// For a normal document, the document id is the same as the view id
  final String documentId;

  final String? databaseViewId;
  final String? rowId;

  /// The workspace id of the document owner (for shared documents)
  final String? workspaceId;

  final bool _saveToBlocMap;

  final DocumentListener _documentListener;
  final DocumentSyncStateListener _syncStateListener;
  late final ViewListener? _viewListener;

  final DocumentService _documentService = DocumentService();
  final TrashService _trashService = TrashService();
  DocumentCollabAdapter? _documentCollabAdapter;
  bool _isInitializing = false;

  bool get isInitializing => _isInitializing;

  late final TransactionAdapter _transactionAdapter = TransactionAdapter(
    documentId: documentId,
    documentService: _documentService,
  );

  late final DocumentRules _documentRules;

  StreamSubscription? _transactionSubscription;

  bool isClosing = false;

  static const _syncDuration = Duration(milliseconds: 250);
  final _updateSelectionDebounce = Debounce(duration: _syncDuration);
  final _syncThrottle = Throttler(duration: _syncDuration);

  // The conflict handle logic is not fully implemented yet
  // use the syncTimer to force to reload the document state when the conflict happens.
  Timer? _syncTimer;

  bool get isLocalMode {
    final userProfilePB = state.userProfilePB;
    final type = userProfilePB?.workspaceType ?? WorkspaceTypePB.LocalW;
    return type == WorkspaceTypePB.LocalW;
  }

  @override
  Future<void> close() async {
    isClosing = true;
    if (_saveToBlocMap) {
      _documentBlocMap.remove(documentId);
    }
    await checkDocumentIntegrity();
    await _cancelSubscriptions();
    _clearEditorState();
    return super.close();
  }

  Future<void> _cancelSubscriptions() async {
    await _documentService.syncAwarenessStates(documentId: documentId);
    await _documentListener.stop();
    await _syncStateListener.stop();
    await _viewListener?.stop();
    await _transactionSubscription?.cancel();
    await _documentService.closeDocument(viewId: documentId);
  }

  void _clearEditorState() {
    _updateSelectionDebounce.dispose();
    _syncThrottle.dispose();

    _syncTimer?.cancel();
    _syncTimer = null;
    state.editorState?.selectionNotifier
        .removeListener(_debounceOnSelectionUpdate);
    state.editorState?.service.keyboardService?.closeKeyboard();
    state.editorState?.dispose();
  }

  Future<void> _onDocumentEvent(
    DocumentEvent event,
    Emitter<DocumentState> emit,
  ) async {
    await event.when(
      initial: () async {
        if (_saveToBlocMap) {
          _documentBlocMap[documentId] = this;
        }
        _onViewChanged();
        _onDocumentChanged();

        // Try to fetch document state once. If fails, start retry loop while keeping loading state.
        final result = await _fetchDocumentState();
        if (result.isSuccess) {
          final s = result.toNullable();
          final userProfilePB =
              await getIt<AuthService>().getUser().toNullable();
          final newState = state.copyWith(
            error: null,
            editorState: s,
            isLoading: false,
            userProfilePB: userProfilePB,
          );
          emit(newState);
          if (newState.userProfilePB != null) {
            await _updateCollaborator();
          }
        } else {
          // keep loading state and start background retry to fetch document for a short period
          emit(state.copyWith(error: null, editorState: null, isLoading: true));
          final FlowyError? initialErr = result.fold((s) => null, (f) => f);
          unawaited(_startRetryFetch(initialErr));
        }
      },
      moveToTrash: () async {
        emit(state.copyWith(isDeleted: true));
      },
      restore: () async {
        emit(state.copyWith(isDeleted: false));
      },
      deletePermanently: () async {
        if (databaseViewId == null && rowId == null) {
          // 在彻底删除前先清理文档节点中的资源附件，释放服务端存储。
          final currentEditorState = state.editorState;
          if (currentEditorState != null) {
            try {
              await cleanupResourceNodesBeforeDelete(
                currentEditorState,
                [currentEditorState.document.root],
              );
            } catch (e) {
              Log.error(
                  'cleanup document resources before permanent delete failed: $e');
            }
          }
          final result = await _trashService.deleteViews([documentId]);
          result.fold(
            (_) {
              if (currentEditorState != null) {
                // 删除成功后再销毁 editor 资源，避免失败时落入错误页。
                _updateSelectionDebounce.dispose();
                _syncThrottle.dispose();
                _syncTimer?.cancel();
                _syncTimer = null;
                currentEditorState.selectionNotifier
                    .removeListener(_debounceOnSelectionUpdate);
                currentEditorState.service.keyboardService?.closeKeyboard();
                currentEditorState.dispose();
              }
              emit(state.copyWith(forceClose: true, editorState: null));
            },
            (error) {
              Log.error('delete document permanently failed: $error');
              showToastNotification(
                message: '彻底删除失败，请重试',
                type: ToastificationType.error,
              );
              // 删除失败时保持当前页面状态，避免出现空 editor 错误页。
              emit(state.copyWith(forceClose: false, error: null));
            },
          );
        }
      },
      restorePage: () async {
        if (databaseViewId == null && rowId == null) {
          final result = await TrashService.putback(documentId);
          final isDeleted = result.fold((l) => false, (r) => true);
          emit(state.copyWith(isDeleted: isDeleted));
        }
      },
      syncStateChanged: (syncState) {
        emit(state.copyWith(syncState: syncState.value));
      },
      clearAwarenessStates: () async {
        // sync a null selection and a null meta to clear the awareness states
        await _documentService.syncAwarenessStates(
          documentId: documentId,
        );
      },
      syncAwarenessStates: () async {
        await _updateCollaborator();
      },
    );
  }

  /// Retry fetching document state in background when initial fetch failed.
  Future<void> _startRetryFetch(FlowyError? initialError) async {
    // 当 collab 不存在时（如协作区共享表格的行文档从未被创建），先创建空文档再重试
    if (initialError?.code == ErrorCode.RecordNotFound) {
      Log.info(
        '[DocumentBloc] Collab not found for documentId: $documentId, attempting to create empty document',
      );
      final payload = CreateDocumentPayloadPB()..documentId = documentId;
      final createResult = await DocumentEventCreateDocument(payload).send();
      createResult.fold(
        (_) => Log.info(
          '[DocumentBloc] Created empty document for documentId: $documentId',
        ),
        (err) => Log.error(
          '[DocumentBloc] Failed to create document for documentId: $documentId, error: $err',
        ),
      );
    }

    const int maxAttempts = 12;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      // exponential-ish backoff: first quick, then longer
      final waitMs = attempt == 1 ? 300 : 300 + (attempt - 1) * 250;
      await Future.delayed(Duration(milliseconds: waitMs));
      final result = await _fetchDocumentState();
      if (result.isSuccess) {
        final s = result.toNullable();
        final userProfilePB = await getIt<AuthService>().getUser().toNullable();
        final newState = state.copyWith(
          error: null,
          editorState: s,
          isLoading: false,
          userProfilePB: userProfilePB,
        );
        // emit only if not closed
        if (!isClosed) {
          // ignore: invalid_use_of_visible_for_testing_member
          emit(newState);
          if (newState.userProfilePB != null) {
            await _updateCollaborator();
          }
        }
        return;
      } else {
        Log.debug(
            '[DocumentBloc] retry attempt $attempt failed for documentId: $documentId, will retry');
      }
    }

    // all attempts failed, emit error state
    if (!isClosed) {
      emit(state.copyWith(
          error: initialError, editorState: null, isLoading: false));
    }
  }

  /// subscribe to the view(document page) change
  void _onViewChanged() {
    _viewListener?.start(
      onViewMoveToTrash: (r) {
        r.map((r) => add(const DocumentEvent.moveToTrash()));
      },
      onViewDeleted: (r) {
        r.map((r) => add(const DocumentEvent.moveToTrash()));
      },
      onViewRestored: (r) => r.map((r) => add(const DocumentEvent.restore())),
    );
  }

  /// subscribe to the document content change
  void _onDocumentChanged() {
    _documentListener.start(
      onDocEventUpdate: _throttleSyncDoc,
      onDocAwarenessUpdate: _onAwarenessStatesUpdate,
    );

    _syncStateListener.start(
      didReceiveSyncState: (syncState) {
        if (!isClosed) {
          add(DocumentEvent.syncStateChanged(syncState));
        }
      },
    );
  }

  /// Fetch document
  Future<FlowyResult<EditorState?, FlowyError>> _fetchDocumentState() async {
    final openStopwatch =
        ponyNotesDiagnosticBuildEnabled ? (Stopwatch()..start()) : null;
    final result = await _documentService.openDocument(
      documentId: documentId,
      workspaceId: workspaceId,
    );
    return result.fold(
      (s) async {
        logDiagnosticMessage(
          'document.open',
          'documentId=$documentId workspaceId=${workspaceId ?? ''} '
              'durationMs=${openStopwatch?.elapsedMilliseconds ?? -1} '
              'success=true',
        );

        final initStopwatch =
            ponyNotesDiagnosticBuildEnabled ? (Stopwatch()..start()) : null;
        final editorState = await _initAppFlowyEditorState(s);
        logDiagnosticMessage(
          'document.init',
          'documentId=$documentId durationMs=${initStopwatch?.elapsedMilliseconds ?? -1} '
              'editorReady=${editorState != null}',
        );
        return FlowyResult.success(editorState);
      },
      (e) {
        logDiagnosticMessage(
          'document.open',
          'documentId=$documentId workspaceId=${workspaceId ?? ''} '
              'durationMs=${openStopwatch?.elapsedMilliseconds ?? -1} '
              'success=false error=$e',
        );
        return FlowyResult.failure(e);
      },
    );
  }

  Future<EditorState?> _initAppFlowyEditorState(DocumentDataPB data) async {
    // 性能优化：减少生产环境中的日志记录
    if (enableDocumentInternalLog) {
      Log.info(
          '[DocumentBloc] _initAppFlowyEditorState START for documentId: $documentId');
      Log.info('document data: ${data.toProto3Json()}');
    }

    var document = data.toDocument();
    if (document == null) {
      Log.error('[DocumentBloc] document is null for documentId: $documentId');

      // mark initializing so UI can show waiting state
      _isInitializing = true;

      // Try to create an empty document on the backend and retry a few times.
      try {
        Log.info(
            '[DocumentBloc] Attempting to create empty document for documentId: $documentId');
        final payload = CreateDocumentPayloadPB()..documentId = documentId;
        FlowyResult<dynamic, Object>? createResult;
        const int maxAttempts = 5;
        bool created = false;
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          Log.info(
              '[DocumentBloc] create empty document attempt $attempt for documentId: $documentId');
          createResult = await DocumentEventCreateDocument(payload).send();
          created = createResult.isSuccess;
          if (created) {
            break;
          }
          // log failure details
          try {
            final failure = createResult.getFailure();
            Log.error(
                '[DocumentBloc] create empty document attempt $attempt failed for documentId: $documentId, error: $failure');
          } catch (err) {
            Log.error(
                '[DocumentBloc] create empty document attempt $attempt failed for documentId: $documentId, unknown error');
          }
          // small backoff
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }

        if (!created) {
          Log.error(
              '[DocumentBloc] Failed to create empty document after $maxAttempts attempts for documentId: $documentId');
          // If failure reason is RecordAlreadyExists, try to open the document repeatedly for a short time
          bool handledByOpening = false;
          try {
            final failure = createResult?.getFailure();
            if (failure != null &&
                failure.toString().contains('RecordAlreadyExists')) {
              Log.info(
                  '[DocumentBloc] Detected RecordAlreadyExists for $documentId, will retry openDocument for a short period');
              const int openAttempts = 12;
              for (var attempt = 1; attempt <= openAttempts; attempt++) {
                final retryResult =
                    await _documentService.openDocument(documentId: documentId);
                if (retryResult.isSuccess) {
                  final retryData = retryResult.toNullable();
                  final retryDocument = retryData?.toDocument();
                  if (retryDocument != null) {
                    Log.info(
                        '[DocumentBloc] openDocument succeeded on attempt $attempt for documentId: $documentId');
                    document = retryDocument;
                    handledByOpening = true;
                    break;
                  }
                } else {
                  Log.debug(
                      '[DocumentBloc] openDocument attempt $attempt returned failure for documentId: $documentId, error: ${retryResult.getFailure()}');
                }
                await Future.delayed(Duration(milliseconds: 500 * attempt));
              }
            }
          } catch (e, st) {
            Log.error(
                '[DocumentBloc] Exception while retrying openDocument for documentId: $documentId, error: $e');
            Log.error('StackTrace: $st');
          }

          if (!handledByOpening) {
            // extended polling: continue to poll openDocument for a longer period before giving up
            Log.info(
                '[DocumentBloc] Entering extended openDocument polling for documentId: $documentId');
            const int longOpenAttempts = 20; // ~10s with 500ms backoff
            for (var attempt = 1; attempt <= longOpenAttempts; attempt++) {
              final retryResult =
                  await _documentService.openDocument(documentId: documentId);
              if (retryResult.isSuccess) {
                final retryData = retryResult.toNullable();
                final retryDocument = retryData?.toDocument();
                if (retryDocument != null) {
                  Log.info(
                      '[DocumentBloc] openDocument succeeded during extended polling on attempt $attempt for documentId: $documentId');
                  document = retryDocument;
                  handledByOpening = true;
                  break;
                }
              } else {
                Log.debug(
                    '[DocumentBloc] extended openDocument attempt $attempt returned failure for documentId: $documentId, error: ${retryResult.getFailure()}');
              }
              await Future.delayed(Duration(milliseconds: 500));
            }
            if (!handledByOpening) {
              Log.error(
                  '[DocumentBloc] extended polling exhausted for documentId: $documentId');
              _isInitializing = false;
              return null;
            }
          }
        } else {
          Log.info(
              '[DocumentBloc] Created empty document, retrying openDocument for documentId: $documentId');
          final retryResult =
              await _documentService.openDocument(documentId: documentId);
          DocumentDataPB? retryData;
          if (retryResult.isSuccess) {
            retryData = retryResult.toNullable();
          } else {
            Log.error(
                '[DocumentBloc] openDocument retry returned failure for documentId: $documentId, error: ${retryResult.getFailure()}');
            retryData = null;
          }
          final retryDocument = retryData?.toDocument();
          if (retryDocument == null) {
            Log.error(
                '[DocumentBloc] Retry failed: document is still null for documentId: $documentId');
            _isInitializing = false;
            return null;
          }

          // replace document with retried one
          Log.info(
              '[DocumentBloc] Retry succeeded: document created for documentId: $documentId');
          document = retryDocument;
        }
      } catch (e, st) {
        Log.error(
            '[DocumentBloc] Exception while creating/retrying document for documentId: $documentId, error: $e');
        Log.error('StackTrace: $st');
        _isInitializing = false;
        return null;
      } finally {
        _isInitializing = false;
      }
    }

    // 性能优化：减少对象创建时的日志记录
    final editorState = EditorState(document: document!);
    _documentCollabAdapter = DocumentCollabAdapter(editorState, documentId);
    _documentRules = DocumentRules(editorState: editorState);

    // subscribe to the document change from the editor
    _transactionSubscription = editorState.transactionStream.listen(
      (value) async {
        final time = value.$1;
        final transaction = value.$2;
        final options = value.$3;
        if (time != TransactionTime.before) {
          return;
        }

        if (options.inMemoryUpdate) {
          if (enableDocumentInternalLog) {
            Log.trace('skip transaction for in-memory update');
          }
          return;
        }

        if (enableDocumentInternalLog) {
          Log.trace(
            '[TransactionAdapter] 1. transaction before apply: ${transaction.hashCode}',
          );
        }

        // apply transaction to backend
        await _transactionAdapter.apply(transaction, editorState);

        // check if the document is empty.
        await _documentRules.applyRules(value: value);

        if (enableDocumentInternalLog) {
          Log.trace(
            '[TransactionAdapter] 4. transaction after apply: ${transaction.hashCode}',
          );
        }

        if (!isClosed) {
          // ignore: invalid_use_of_visible_for_testing_member
          emit(state.copyWith(isDocumentEmpty: editorState.document.isEmpty));
        }
      },
    );

    editorState.selectionNotifier.addListener(_debounceOnSelectionUpdate);

    // output the log from the editor when debug mode
    if (kDebugMode && enableDocumentInternalLog) {
      editorState.logConfiguration
        ..level = AppFlowyEditorLogLevel.all
        ..handler = (log) {
          // Log.info(log);
        };
    }

    return editorState;
  }

  Future<void> _onDocumentStateUpdate(DocEventPB docEvent) async {
    if (!docEvent.isRemote || !FeatureFlag.syncDocument.isOn) {
      return;
    }
    if (_documentCollabAdapter != null) {
      unawaited(_documentCollabAdapter!.syncV3(docEvent: docEvent));
    } else {
      Log.debug(
          '[DocumentBloc] _onDocumentStateUpdate called but _documentCollabAdapter is not initialized yet for documentId: $documentId');
    }
  }

  Future<void> _onAwarenessStatesUpdate(
    DocumentAwarenessStatesPB awarenessStates,
  ) async {
    if (!FeatureFlag.syncDocument.isOn) {
      return;
    }

    final userId = state.userProfilePB?.id;
    if (userId != null) {
      if (_documentCollabAdapter != null) {
        await _documentCollabAdapter!.updateRemoteSelection(
          userId.toString(),
          awarenessStates,
        );
      } else {
        Log.debug(
            '[DocumentBloc] _onAwarenessStatesUpdate called but _documentCollabAdapter is not initialized yet for documentId: $documentId');
      }
    }
  }

  void _debounceOnSelectionUpdate() {
    _updateSelectionDebounce.call(_onSelectionUpdate);
  }

  void _throttleSyncDoc(DocEventPB docEvent) {
    if (enableDocumentInternalLog) {
      Log.info('[DocumentBloc] throttle sync doc: ${docEvent.toProto3Json()}');
    }
    _syncThrottle.call(() {
      _onDocumentStateUpdate(docEvent);
    });
  }

  Future<void> _onSelectionUpdate() async {
    if (isClosing) {
      return;
    }
    final user = state.userProfilePB;
    final deviceId = ApplicationInfo.deviceId;
    if (!FeatureFlag.syncDocument.isOn || user == null) {
      return;
    }

    final editorState = state.editorState;
    if (editorState == null) {
      return;
    }
    final selection = editorState.selection;

    // sync the selection
    final id = user.id.toString() + deviceId;
    final basicColor = ColorGenerator(id.toString()).toColor();
    final metadata = DocumentAwarenessMetadata(
      cursorColor: basicColor.toHexString(),
      selectionColor: basicColor.withValues(alpha: 0.6).toHexString(),
      userName: user.name,
      userAvatar: user.iconUrl,
    );
    await _documentService.syncAwarenessStates(
      documentId: documentId,
      selection: selection,
      metadata: jsonEncode(metadata.toJson()),
    );
  }

  Future<void> _updateCollaborator() async {
    final user = state.userProfilePB;
    final deviceId = ApplicationInfo.deviceId;
    if (!FeatureFlag.syncDocument.isOn || user == null) {
      return;
    }

    // sync the selection
    final id = user.id.toString() + deviceId;
    final basicColor = ColorGenerator(id.toString()).toColor();
    final metadata = DocumentAwarenessMetadata(
      cursorColor: basicColor.toHexString(),
      selectionColor: basicColor.withValues(alpha: 0.6).toHexString(),
      userName: user.name,
      userAvatar: user.iconUrl,
    );
    await _documentService.syncAwarenessStates(
      documentId: documentId,
      metadata: jsonEncode(metadata.toJson()),
    );
  }

  Future<void> forceReloadDocumentState() {
    if (_documentCollabAdapter != null) {
      return _documentCollabAdapter!.syncV3();
    }
    return Future.value();
  }

  // this is only used for debug mode
  Future<void> checkDocumentIntegrity() async {
    if (!enableDocumentInternalLog) {
      return;
    }

    final cloudDocResult =
        await _documentService.getDocument(documentId: documentId);
    final cloudDoc = cloudDocResult.fold((s) => s, (f) => null)?.toDocument();
    final localDoc = state.editorState?.document;
    if (cloudDoc == null || localDoc == null) {
      return;
    }
    final cloudJson = cloudDoc.toJson();
    final localJson = localDoc.toJson();
    final deepEqual = const DeepCollectionEquality().equals(
      cloudJson,
      localJson,
    );
    if (!deepEqual) {
      Log.error('document integrity check failed');
      // Enable it to debug the document integrity check failed
      Log.error('cloud doc: $cloudJson');
      Log.error('local doc: $localJson');

      final context = AppGlobals.rootNavKey.currentContext;
      if (context != null && context.mounted) {
        showToastNotification(
          message: 'document integrity check failed',
          type: ToastificationType.error,
        );
      }
    }
  }
}

@freezed
class DocumentEvent with _$DocumentEvent {
  const factory DocumentEvent.initial() = Initial;
  const factory DocumentEvent.moveToTrash() = MoveToTrash;
  const factory DocumentEvent.restore() = Restore;
  const factory DocumentEvent.restorePage() = RestorePage;
  const factory DocumentEvent.deletePermanently() = DeletePermanently;
  const factory DocumentEvent.syncStateChanged(
    final DocumentSyncStatePB syncState,
  ) = syncStateChanged;
  const factory DocumentEvent.syncAwarenessStates() = SyncAwarenessStates;
  const factory DocumentEvent.clearAwarenessStates() = ClearAwarenessStates;
}

@freezed
class DocumentState with _$DocumentState {
  const factory DocumentState({
    required final bool isDeleted,
    required final bool forceClose,
    required final bool isLoading,
    required final DocumentSyncState syncState,
    bool? isDocumentEmpty,
    UserProfilePB? userProfilePB,
    EditorState? editorState,
    FlowyError? error,
    @Default(null) DocumentAwarenessStatesPB? awarenessStates,
  }) = _DocumentState;

  factory DocumentState.initial() => const DocumentState(
        isDeleted: false,
        forceClose: false,
        isLoading: true,
        syncState: DocumentSyncState.Syncing,
      );
}
