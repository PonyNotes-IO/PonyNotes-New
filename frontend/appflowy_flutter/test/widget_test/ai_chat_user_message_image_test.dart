import 'dart:convert';

import 'package:appflowy/plugins/ai_chat/application/chat_member_bloc.dart';
import 'package:appflowy/plugins/ai_chat/presentation/message/user_message_bubble.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockChatMemberBloc extends MockBloc<ChatMemberEvent, ChatMemberState>
    implements ChatMemberBloc {}

void main() {
  testWidgets('keeps an uploaded image while the keyboard inset changes',
      (tester) async {
    final chatMemberBloc = _MockChatMemberBloc();
    whenListen(
      chatMemberBloc,
      const Stream<ChatMemberState>.empty(),
      initialState: const ChatMemberState(),
    );

    final message = TextMessage(
      id: 'message-id',
      author: const User(id: 'user-id'),
      createdAt: DateTime(2026),
      text: '图片问题',
    );
    const imageData =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL6rwAAAABJRU5ErkJggg==';

    Widget buildSubject(double keyboardInset) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: Scaffold(
            body: BlocProvider<ChatMemberBloc>.value(
              value: chatMemberBloc,
              child: ChatUserMessageBubble(
                message: message,
                images: const [imageData],
                child: const Text('图片问题'),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildSubject(0));
    final initialImage = tester.widget<Image>(find.byType(Image));
    final initialProvider = initialImage.image;

    expect(initialProvider, isA<MemoryImage>());
    expect(initialImage.gaplessPlayback, isTrue);
    expect(
      base64Decode(imageData),
      isNotEmpty,
      reason: 'The test fixture must remain valid base64 image data.',
    );

    await tester.pumpWidget(buildSubject(320));
    final keyboardImage = tester.widget<Image>(find.byType(Image));

    expect(identical(keyboardImage.image, initialProvider), isTrue);
    expect(keyboardImage.gaplessPlayback, isTrue);

    await tester.pumpWidget(buildSubject(0));
    final restoredImage = tester.widget<Image>(find.byType(Image));

    expect(identical(restoredImage.image, initialProvider), isTrue);
    expect(restoredImage.gaplessPlayback, isTrue);
  });
}
