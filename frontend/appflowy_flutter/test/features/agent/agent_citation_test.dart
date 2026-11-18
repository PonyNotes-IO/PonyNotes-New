import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/presentation/agent_citation_syntax.dart';
import 'package:appflowy/features/agent/presentation/agent_workspace.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/dart-ffi/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

class _CitationTabs extends MockBloc<TabsEvent, TabsState> implements TabsBloc {
  final opened = <ViewPB>[];
  @override
  void openTab(ViewPB view) => opened.add(view);
}

void main() {
  const url = 'ponynotes://open?viewId=page&workspaceId=workspace';
  const citation = '<kb doc="胡迪的小知识" chunk_id="chunk" kb_id="base" />';
  const sources = {
    'knowledge': {'title': '胡迪的小知识', 'url': url},
    'same-title': {'title': '胡迪的小知识', 'url': 'ponynotes://open?viewId=wrong'},
  };
  const result = {
    'chunk_id': 'chunk',
    'knowledge_id': 'knowledge',
    'knowledge_base_id': 'base',
  };
  String render(
    String text,
    Iterable<Map> evidence, {
    Map<String, Map<String, dynamic>> authorized = sources,
  }) =>
      md.renderToHtml(
        md.Document(
          inlineSyntaxes: [AgentCitationSyntax(authorized, evidence)],
          blockSyntaxes: [AgentCitationBlockSyntax()],
        ).parseLines(text.split('\n')),
      );

  test('native search, read and quick-answer evidence resolves exact note IDs',
      () {
    for (final evidence in [
      [result],
      [
        {
          'results': [result],
        },
      ],
      [
        {
          'chunk_ids': ['chunk'],
          'knowledge_id': 'knowledge',
          'knowledge_base_id': 'base',
        },
      ],
      [
        {
          'id': 'chunk',
          'knowledge_id': 'knowledge',
          'knowledge_base_id': 'base',
        },
      ],
    ]) {
      final html = render('番茄。$citation', evidence);
      expect(html, contains('href="$url"'));
      expect(html, contains('〔来源：胡迪的小知识〕'));
      expect(html, isNot(contains('viewId=wrong')));
      expect(html, isNot(contains('chunk_id')));
    }
    expect(render('番茄。\n\n$citation', [result]), contains('href="$url"'));
  });

  test('unavailable, forged and revoked citations never guess by title', () {
    for (final html in [
      render('番茄。$citation', []),
      render('番茄。${citation.replaceFirst('base', 'foreign')}', [result]),
      render('番茄。$citation', [result], authorized: {}),
    ]) {
      expect(html, contains('暂不可用'));
      expect(html, isNot(contains('href=')));
      expect(html, isNot(contains('chunk_id')));
    }
    expect(render('番茄。<kb doc="胡迪', [result]), '<p>番茄。</p>');
  });

  test('citation labels stay literal and code examples remain unchanged', () {
    final html = render(
      '正文$citation\n\n`$citation`\n\n```xml\n$citation\n```',
      [result],
      authorized: {
        'knowledge': {
          'title': '[链接](https://forged.test) <script>',
          'url': url,
        },
      },
    );
    expect(RegExp('<a ').allMatches(html).length, 1);
    expect(html, contains('[链接](https://forged.test) <script>'));
    expect(html, contains('<code>'));
    expect(html, contains('chunk_id='));
  });

  testWidgets(
      'live and restored native citations use the existing link handler',
      (tester) async {
    final tabs = _CitationTabs();
    getIt.registerSingleton<TabsBloc>(tabs);
    Dispatch.requestProxy = (bytes) async {
      final request = FFIRequest.fromBuffer(bytes);
      expect(request.event, 'GetView');
      expect(ViewIdPB.fromBuffer(request.payload).value, 'page');
      return FFIResponse(
        code: FFIStatusCode.Ok,
        payload: ViewPB(id: 'page', name: '胡迪的小知识').writeToBuffer(),
      ).writeToBuffer();
    };
    addTearDown(() async {
      Dispatch.requestProxy = null;
      await getIt.unregister<TabsBloc>();
      await tabs.close();
    });
    final controller = AgentController(chatId: 'citation-test')
      ..connected = true;
    controller.messages.add({'role': 'user', 'content': '胡迪喜欢吃什么？'});
    controller.sources.addAll(sources);
    controller.receive({
      'response_type': 'tool_result',
      'data': {
        'tool_call_id': 'search',
        'tool_name': 'search_knowledge',
        'success': true,
        'results': [result],
      },
    });
    controller.streamingText = '番茄。$citation';
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: AgentWorkspace(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void expectCitation() {
      final markdown =
          tester.widgetList<MarkdownWidget>(find.byType(MarkdownWidget)).last;
      final syntax = markdown.markdownGenerator!.inlineSyntaxList.single;
      final html = md.renderToHtml(
        md.Document(inlineSyntaxes: [syntax]).parseInline(markdown.data),
      );
      expect(html, contains('href="$url"'));
      expect(markdown.config!.a.onTap, isNotNull);
      expect(
        find.textContaining('〔来源：胡迪的小知识〕', findRichText: true),
        findsWidgets,
      );
    }

    Future<void> clickCitation() async {
      const label = '〔来源：胡迪的小知识〕';
      final richText = find
          .byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText().contains(label),
          )
          .last;
      final paragraph = tester.renderObject<RenderParagraph>(richText);
      final offset = paragraph.text.toPlainText().indexOf(label);
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: offset,
              extentOffset: offset + label.length,
            ),
          )
          .first;
      await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();
    }

    expectCitation();
    await clickCitation();
    expect(tabs.opened.map((view) => view.id), ['page']);
    controller.streamingText = '';
    controller.activities.clear();
    controller.messages.add({
      'role': 'assistant',
      'content': '番茄。$citation',
      'knowledge_references': [],
      'agent_steps': [
        {
          'tool_calls': [
            {
              'result': {
                'success': true,
                'data': {
                  'results': [result],
                },
              },
            },
          ],
        },
      ],
    });
    controller.changed();
    await tester.pumpAndSettle();
    expectCitation();
    await clickCitation();
    expect(tabs.opened.map((view) => view.id), ['page', 'page']);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
