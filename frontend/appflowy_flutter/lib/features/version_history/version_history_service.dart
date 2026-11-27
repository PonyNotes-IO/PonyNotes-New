import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy_backend/document_sessions.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:fixnum/fixnum.dart';

class VersionHistoryService {
  VersionHistoryService({this.workspaceId});

  final String? workspaceId;

  Future<DocumentHistoryIndexPB> listDocuments({
    required String search,
    required String workspace,
    DocumentHistorySummaryPB? after,
  }) async {
    final result = await DocumentEventListDocumentsWithHistory(
      DocumentHistoryIndexQueryPB(
        search: search,
        workspaceId: workspace,
        before: after?.latestVersionAt ?? Int64.ZERO,
        beforeDocument: after?.documentId ?? '',
      ),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentHistoryListPB> list(
    String documentId, {
    int offset = 0,
  }) async {
    final result = await DocumentEventListDocumentVersions(
      DocumentHistoryQueryPB(
        documentId: documentId,
        workspaceId: workspaceId,
        offset: offset,
      ),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentSnapshotMetaPB> save(String documentId) =>
      _withEditableDocument(documentId, () async {
        final result = await DocumentEventSaveDocumentVersion(
          DocumentHistoryQueryPB(
            documentId: documentId,
            workspaceId: workspaceId,
          ),
        ).send();
        return result.fold((value) => value, (error) => throw error);
      });

  Future<DocumentDataPB> get(String documentId, String snapshotId) async {
    final result = await DocumentEventGetDocumentVersion(
      DocumentHistoryQueryPB(
        documentId: documentId,
        workspaceId: workspaceId,
        snapshotId: snapshotId,
      ),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentDataPB> readCurrent(String documentId) async {
    await DocumentBloc.flushPendingChanges();
    final result = await DocumentService().getDocument(
      documentId: documentId,
      workspaceId: workspaceId,
    );
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentSnapshotMetaPB> restore(
    String documentId,
    String snapshotId,
  ) =>
      _withEditableDocument(documentId, () async {
        final result = await DocumentEventRestoreDocumentVersion(
          DocumentHistoryQueryPB(
            documentId: documentId,
            workspaceId: workspaceId,
            snapshotId: snapshotId,
          ),
        ).send();
        return result.fold((value) => value, (error) => throw error);
      });

  Future<DocumentSnapshotMetaPB> _withEditableDocument(
    String documentId,
    Future<DocumentSnapshotMetaPB> Function() perform,
  ) async {
    await DocumentBloc.flushPendingChanges();
    if (workspaceId == null) return perform();

    final service = DocumentService();
    await DocumentSessions.retain(documentId);
    try {
      final opened = await service.openDocument(
        documentId: documentId,
        workspaceId: workspaceId,
      );
      opened.fold((_) {}, (error) => throw error);
      return await perform();
    } finally {
      if (await DocumentSessions.release(documentId)) {
        await service.closeDocument(viewId: documentId);
      }
    }
  }
}
