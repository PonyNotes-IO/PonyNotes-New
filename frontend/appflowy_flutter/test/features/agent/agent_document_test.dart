import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy/features/agent/presentation/ai_conversation.dart';
import 'package:appflowy/features/agent/presentation/agent_model_settings.dart';
import 'package:appflowy/plugins/ai_chat/chat_page.dart';
import 'package:appflowy/plugins/standalone_ai_chat/presentation/widgets/ai_input_area.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widget_test/widget_test_wrapper.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('AgentTestFont')
            ..addFont(font.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  testWidgets(
      'Agent welcome submits without cloud models or subscription lookup',
      (tester) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? submitted;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: Colors.white,
            child: Theme(
              data: ThemeData(fontFamily: 'AgentTestFont'),
              child: Center(
                child: AIInputArea(
                  agentMode: true,
                  onMessageSent:
                      (text, model, images, thinking, search, knowledgeSearch) {
                    submitted = text;
                    expect(model, isNull);
                    expect(thinking, false);
                    expect(search, false);
                    expect(knowledgeSearch, false);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AgentModelSettingsButton), findsOneWidget);
    expect(find.text('深度思考'), findsNothing);
    expect(find.text('联网搜索'), findsNothing);
    expect(find.text('知识库检索'), findsNothing);
    await tester.enterText(find.byType(TextField), '帮我整理会议记录');
    await tester.pump();
    final output = Platform.environment['PONYNOTES_AGENT_SCREENSHOTS'];
    if (output != null) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/welcome-agent.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.widget<TextField>(find.byType(TextField)).onSubmitted!('');
    await tester.pump();
    expect(submitted, '帮我整理会议记录');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Agent documents dispatch directly using their document ID and keep initial attachments',
      (tester) async {
    Widget? page;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          page = AIChatPage(
            view: ViewPB(
              id: 'agent-document',
              extra:
                  '{"ai_mode":"agent","initial_message":"整理会议记录","initial_images":["selected.png"]}',
            ),
            userProfile: UserProfilePB(),
            onDeleted: () {},
          ).build(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(page, isA<AiConversation>());
    final conversation = page! as AiConversation;
    expect(conversation.documentId, 'agent-document');
    expect(conversation.initialMessage, '整理会议记录');
    expect(conversation.initialImagePaths, ['selected.png']);
  });

  testWidgets('old Chat documents retain the original Chat engine',
      (tester) async {
    Widget? page;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          page = AIChatPage(
            view: ViewPB(id: 'old-document'),
            userProfile: UserProfilePB(),
            onDeleted: () {},
          ).build(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(page, isNot(isA<AiConversation>()));
  });
}
