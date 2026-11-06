import 'package:appflowy/ai/widgets/knowledge_search_button.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('knowledge retrieval toggles on and off', (tester) async {
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => KnowledgeSearchButton(
              enabled: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('知识库检索'));
    await tester.pump();
    expect(enabled, isTrue);
    await tester.tap(find.text('知识库检索'));
    await tester.pump();
    expect(enabled, isFalse);
  });

  test('wire format preserves the switch and original question', () {
    final request = StreamChatPayloadPB(
      message: '查找我的发布计划',
      enableKnowledgeSearch: true,
      enableThinking: true,
      enableWebSearch: true,
    );
    final decoded = StreamChatPayloadPB.fromBuffer(request.writeToBuffer());
    expect(decoded.enableKnowledgeSearch, isTrue);
    expect(decoded.message, '查找我的发布计划');
    expect(decoded.enableThinking && decoded.enableWebSearch, isTrue);
    expect(StreamChatPayloadPB().enableKnowledgeSearch, isFalse);
  });
}
