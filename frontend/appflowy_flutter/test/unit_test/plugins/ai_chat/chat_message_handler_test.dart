import 'package:appflowy/plugins/ai_chat/application/chat_message_handler.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inserts a pending image question before returning', () async {
    final controller = InMemoryChatController();
    final handler = ChatMessageHandler(
      chatId: 'chat-id',
      userId: 'user-id',
      chatController: controller,
    );
    final questionStream = QuestionStream();

    addTearDown(() async {
      await questionStream.dispose();
      controller.dispose();
    });

    final pendingMessage = await handler.createAndInsertQuestionStreamMessage(
      questionStream,
      const {
        'has_images': true,
      },
      text: '这是什么',
    );

    expect(controller.messages, hasLength(1));
    expect(controller.messages.single, pendingMessage);
    expect(controller.messages.single.metadata?['has_images'], isTrue);
  });
}
