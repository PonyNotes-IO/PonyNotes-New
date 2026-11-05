import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';

class VersionHistoryService {
  Future<DocumentHistoryListPB> list(
    String documentId, {
    int offset = 0,
  }) async {
    final result = await DocumentEventListDocumentVersions(
      DocumentHistoryQueryPB(documentId: documentId, offset: offset),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentSnapshotMetaPB> save(String documentId) async {
    await DocumentBloc.flushPendingChanges();
    final result = await DocumentEventSaveDocumentVersion(
      DocumentHistoryQueryPB(documentId: documentId),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentDataPB> get(String documentId, String snapshotId) async {
    final result = await DocumentEventGetDocumentVersion(
      DocumentHistoryQueryPB(documentId: documentId, snapshotId: snapshotId),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentDataPB> readCurrent(String documentId) async {
    await DocumentBloc.flushPendingChanges();
    final result = await DocumentService().getDocument(documentId: documentId);
    return result.fold((value) => value, (error) => throw error);
  }

  Future<DocumentSnapshotMetaPB> restore(
    String documentId,
    String snapshotId,
  ) async {
    await DocumentBloc.flushPendingChanges();
    final result = await DocumentEventRestoreDocumentVersion(
      DocumentHistoryQueryPB(documentId: documentId, snapshotId: snapshotId),
    ).send();
    return result.fold((value) => value, (error) => throw error);
  }
}
