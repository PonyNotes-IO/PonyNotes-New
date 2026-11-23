import 'dart:convert';

import 'package:appflowy/plugins/document/application/document_collab_adapter.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _DocumentService extends Mock implements DocumentService {}

const _syncWindow = Duration(milliseconds: 250);
const _text = '双端格式同步';

DocumentDataPB _snapshot(Delta delta) => DocumentDataPB(
      pageId: 'page',
      blocks: {
        'page': BlockPB(
          id: 'page',
          ty: 'page',
          data: '{}',
          childrenId: 'children',
        ),
        'paragraph': BlockPB(
          id: 'paragraph',
          ty: 'paragraph',
          data: '{}',
          parentId: 'page',
          externalId: 'external-text',
          externalType: 'text',
        ),
      },
      meta: MetaPB(
        childrenMap: {
          'children': ChildrenPB(children: ['paragraph']),
        },
        textMap: {'external-text': jsonEncode(delta.toJson())},
      ),
    );

void main() {
  final underline = AppFlowyRichTextKeys.underline;
  final plain = Delta()..insert(_text);
  final underlined = Delta()..insert(_text, attributes: {underline: true});
  final remote = DocEventPB(isRemote: true);

  late EditorState editor;
  late DocumentCollabAdapter adapter;
  late _DocumentService service;
  late DocumentDataPB snapshot;

  setUp(() {
    snapshot = _snapshot(plain);
    editor = EditorState(document: snapshot.toDocument()!);
    service = _DocumentService();
    when(() => service.getDocument(documentId: 'page'))
        .thenAnswer((_) async => FlowyResult.success(snapshot));
    adapter = DocumentCollabAdapter(editor, 'page', documentService: service);
  });

  tearDown(() {
    adapter.dispose();
    editor.dispose();
  });

  List<Object?>? currentDelta() => editor.getNodeAtPath([0])?.delta?.toJson();

  testWidgets('applies the latest format-only update in a sync burst', (
    tester,
  ) async {
    adapter.scheduleSync(remote);
    await tester.pump();
    expect(currentDelta(), plain.toJson());
    verify(() => service.getDocument(documentId: 'page')).called(1);

    snapshot = _snapshot(underlined);
    adapter.scheduleSync(remote);
    adapter.scheduleSync(remote);
    await tester.pump(_syncWindow);

    expect(currentDelta(), underlined.toJson());
    verify(() => service.getDocument(documentId: 'page')).called(1);

    // Removing underline is also a format-only update.
    snapshot = _snapshot(plain);
    adapter.scheduleSync(remote);
    await tester.pump(_syncWindow);
    expect(currentDelta(), plain.toJson());
    await tester.pump(_syncWindow);
  });

  testWidgets('local notifications do not delay incoming formatting', (
    tester,
  ) async {
    adapter.scheduleSync(DocEventPB(isRemote: false));
    snapshot = _snapshot(underlined);
    adapter.scheduleSync(remote);
    await tester.pump();

    expect(currentDelta(), underlined.toJson());
    verify(() => service.getDocument(documentId: 'page')).called(1);
    await tester.pump(_syncWindow);
  });

  testWidgets('disposing the adapter cancels the pending refresh', (
    tester,
  ) async {
    adapter.scheduleSync(remote);
    await tester.pump();
    verify(() => service.getDocument(documentId: 'page')).called(1);

    snapshot = _snapshot(underlined);
    adapter.scheduleSync(remote);
    adapter.dispose();
    await tester.pump(_syncWindow);

    expect(currentDelta(), plain.toJson());
    verifyNever(() => service.getDocument(documentId: 'page'));
  });
}
