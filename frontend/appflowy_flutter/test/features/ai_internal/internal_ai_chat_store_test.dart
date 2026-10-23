import 'package:appflowy/features/ai_internal/application/internal_ai_chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('会话状态在 reset 后清空，并通知监听者', () {
    final store = InternalAiChatStore.instance;
    var notified = 0;
    store.addListener(() => notified++);

    store.addTurn(AiChatTurn.user('你好'));
    store.addHistory('你好', '在');
    store.setError('出错了');
    expect(store.turns, hasLength(1));
    expect(store.history, hasLength(2));
    expect(store.error, '出错了');

    store.reset();
    expect(store.turns, isEmpty);
    expect(store.history, isEmpty);
    expect(store.error, isNull);
    expect(notified, 4);
  });
}
