import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/workspace/presentation/home/view_panes.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/document_sessions.dart';
import 'package:appflowy_backend/protobuf/dart-ffi/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart'
    hide DocumentEvent;
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('split, resize, navigate and close preserve surviving editors',
      (tester) async {
    final key = GlobalKey<ViewPanesState>();
    var view = ViewPB(id: 'a', name: 'A');
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ViewPanes(
              key: key,
              view: view,
              onActiveViewChanged: (active) => rebuild(() => view = active),
              builder: (_, page) => _Editor(key: ValueKey(page.id)),
            );
          },
        ),
      ),
    );
    final original = tester.state(find.byType(_Editor));
    key.currentState!.split(Axis.horizontal);
    await tester.pump();
    expect(find.byType(_Editor), findsNWidgets(2));
    expect(tester.state(find.byType(_Editor).first), same(original));
    final first = tester.getRect(find.byType(_Editor).first);
    final second = tester.getRect(find.byType(_Editor).last);
    expect(first.right, lessThan(second.left));
    final divider = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector && widget.onHorizontalDragUpdate != null,
    );
    await tester.drag(divider, const Offset(80, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(_Editor).first).width,
      greaterThan(first.width),
    );

    key.currentState!.split(Axis.vertical);
    await tester.pump();
    expect(find.byType(_Editor), findsNWidgets(3));
    final upper = tester.getRect(find.byType(_Editor).at(1));
    final lower = tester.getRect(find.byType(_Editor).at(2));
    expect(upper.bottom, lessThan(lower.top));
    rebuild(() => view = ViewPB(id: 'b', name: 'B'));
    await tester.pump();
    expect(find.byKey(const ValueKey('a')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
    expect(tester.state(find.byType(_Editor).first), same(original));

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    expect(find.byType(_Editor), findsOneWidget);
    expect(tester.state(find.byType(_Editor)), same(original));
    expect(tester.takeException(), isNull);
  });

  test('backend document stays open until its final pane or window closes',
      () async {
    await DocumentSessions.retain('note');
    await DocumentSessions.retain('note');
    await DocumentSessions.retain('note', owner: 'window');
    expect(await DocumentSessions.release('note'), isFalse);
    expect(await DocumentSessions.release('note', owner: 'window'), isFalse);
    expect(await DocumentSessions.release('note'), isTrue);

    await DocumentSessions.retain('shared');
    await DocumentSessions.retain('shared', owner: 'window');
    await DocumentSessions.retain('only-in-window', owner: 'window');
    expect(DocumentSessions.releaseOwner('window'), ['only-in-window']);
    expect(await DocumentSessions.release('shared'), isTrue);
  });

  test('local edits reach both editors and survive closing one', () async {
    final backend =
        Document(root: pageNode(children: [paragraphNode(text: 'old')]));
    var closes = 0;
    Completer<void>? saveGate;
    final saveStarted = Completer<void>();
    getIt.registerSingleton<AuthService>(_Auth());
    Dispatch.requestProxy = (bytes) async {
      final request = FFIRequest.fromBuffer(bytes);
      if (request.event == 'ApplyAction' && saveGate != null) {
        saveStarted.complete();
        await saveGate.future;
      }
      final payload = switch (request.event) {
        'OpenDocument' ||
        'GetDocumentData' =>
          DocumentDataPBFromTo.fromDocument(backend)!.writeToBuffer(),
        _ => <int>[],
      };
      if (request.event == 'CloseView') closes++;
      return FFIResponse(code: FFIStatusCode.Ok, payload: payload)
          .writeToBuffer();
    };
    final first = DocumentBloc(documentId: 'shared-note')
      ..add(const DocumentEvent.initial());
    final second = DocumentBloc(documentId: 'shared-note')
      ..add(const DocumentEvent.initial());
    addTearDown(() async {
      if (!first.isClosed) await first.close();
      if (!second.isClosed) await second.close();
      Dispatch.requestProxy = null;
      await getIt.reset();
    });
    await Future.wait([
      first.stream.firstWhere((state) => state.editorState != null),
      second.stream.firstWhere((state) => state.editorState != null),
    ]);
    expect(first.state.editorState, isNotNull);
    expect(second.state.editorState, isNotNull);

    void update(String text) {
      backend.root.children.first.updateAttributes({
        'delta': (Delta()..insert(text)).toJson(),
      });
      RustStreamReceiver.receiveFromMainWindow(
        SubscribeObject(
          source: 'Document',
          id: 'shared-note',
          ty: DocumentNotification.DidReceiveUpdate.value,
          payload: DocEventPB(isRemote: false).writeToBuffer(),
        ).writeToBuffer(),
      );
    }

    update('first change');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    update('final change');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(
      first.state.editorState!.document.root.children.first.delta!
          .toPlainText(),
      'final change',
    );
    expect(
      second.state.editorState!.document.root.children.first.delta!
          .toPlainText(),
      'final change',
    );
    await first.close();
    expect(closes, 0);
    expect(DocumentBloc.findOpen('shared-note'), same(second));
    update('still editable');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(
      second.state.editorState!.document.root.children.first.delta!
          .toPlainText(),
      'still editable',
    );
    saveGate = Completer<void>();
    final editor = second.state.editorState!;
    final transaction = editor.transaction
      ..insertNode([1], Node(type: 'divider'));
    await editor.apply(transaction);
    await saveStarted.future;
    final flush = DocumentBloc.flushPendingChanges();
    var closed = false;
    final closing = second.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(closes, 0);
    saveGate.complete();
    await flush;
    await closing;
    expect(closes, 1);
  });

  test('secondary windows receive attachment upload progress', () async {
    Dispatch.requestProxy =
        (bytes) async => FFIResponse(code: FFIStatusCode.Ok).writeToBuffer();
    final service = FileStorageService();
    addTearDown(() async {
      await service.dispose();
      Dispatch.requestProxy = null;
    });
    final progress = service.onFileProgress(fileUrl: 'attachment');
    await Future<void>.delayed(Duration.zero);
    RustStreamReceiver.receiveFromMainWindow(
      SubscribeObject(
        source: 'FileProgress',
        payload: utf8.encode(
          jsonEncode({'file_url': 'attachment', 'progress': 0.75}),
        ),
      ).writeToBuffer(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(progress.value.progress, 0.75);
  });
}

class _Auth implements AuthService {
  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> getUser() async =>
      FlowyResult.success(UserProfilePB(name: 'test'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Editor extends StatefulWidget {
  const _Editor({super.key});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  @override
  Widget build(BuildContext context) => const Material(child: TextField());
}
