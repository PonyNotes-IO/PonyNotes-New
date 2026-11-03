import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/query.pb.dart';
import 'package:fixnum/fixnum.dart';

/// Local derived index. A blank document id requests the workspace graph.
class NoteLinkService {
  static final _backfillAttempts = <String>{};
  static bool shouldBackfill(String identity) =>
      _backfillAttempts.add(identity);
  static Future<List<String>> findLocalCandidates(String title) async {
    final response = await SearchEventLocalSearch(
      SearchQueryPB(search: title, limit: Int64(50)),
    ).send();
    return response.fold(
      (result) => result.items.map((item) => item.id).toList(),
      (error) => throw StateError(error.msg),
    );
  }

  static Future<DocumentLinksPB> read({
    String pageId = '',
    String? workspaceId,
    bool repair = false,
  }) async {
    final request =
        OpenDocumentPayloadPB(documentId: pageId, workspaceId: workspaceId);
    final result = repair
        ? await DocumentEventReindexDocumentLinks(request).send()
        : await DocumentEventGetDocumentLinks(request).send();
    return result.fold((data) => data, (error) => throw StateError(error.msg));
  }
}
