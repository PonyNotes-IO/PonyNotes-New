import 'dart:async';

import 'package:appflowy/features/agent/application/agent_controller.dart';
import 'package:appflowy/features/agent/application/agent_service.dart';
import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Service extends AgentService {
  Map<String, dynamic> history = {
    'visibility': 'shared',
    'can_control_run': false,
    'messages': <Map<String, dynamic>>[],
    'sources': <String, dynamic>{},
  };
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final paths = <String>[];
  int reads = 0;
  int sends = 0;
  String user = 'member';
  Completer<void>? reading;

  @override
  Future<String> identity(String workspace) async => 'server|$user|$workspace';

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add('$method/$document$suffix');
    if (suffix.isEmpty && method == 'GET') {
      reads++;
      await reading?.future;
      return history;
    }
    if (suffix == '/references') return {'items': []};
    return {'calls': []};
  }

  @override
  Stream<Map<String, dynamic>> stream(
    String method,
    String workspace,
    String document,
    String suffix, [
    Map<String, dynamic>? body,
  ]) {
    paths.add('$method/$document$suffix');
    if (method == 'POST') sends++;
    return events.stream;
  }
}

AgentController _controller(_Service service) => AgentController(
      chatId: 'shared-chat',
      independent: true,
      collaborative: true,
      service: service,
      workspaceId: () async => 'workspace',
    )..providerConfig = const AiProviderConfig(modelName: 'custom');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('shared sends first refresh history and use chat scoped references',
      () async {
    final service = _Service();
    final controller = _controller(service);
    await controller.connect();
    service.history['messages'] = [
      {'id': 'other', 'role': 'user', 'content': '另一位成员的问题'},
      {'id': 'answer', 'role': 'assistant', 'content': '已有回答'},
    ];
    await controller.loadReferences();
    expect(service.paths, contains('GET/shared-chat/references'));
    final sending = controller.send('接着讨论');
    await Future<void>.delayed(Duration.zero);
    expect(service.reads, 2);
    expect(
      controller.messages.map((m) => m['content']),
      ['另一位成员的问题', '已有回答', '接着讨论'],
    );
    service.events.add({
      'response_type': 'scope',
      'data': {'sources': {}},
    });
    await Future<void>.delayed(Duration.zero);
    expect(await sending, true);
    expect(service.sends, 1);
    expect(controller.canControlRun, true);
    await controller.disconnect();
    controller.dispose();
    await service.events.close();
  });

  test('members observe another run without steering or approving it',
      () async {
    final service = _Service();
    service.history.addAll({
      'active_message_id': 'active',
      'messages': [
        {'id': 'question', 'role': 'user', 'content': '请整理笔记'},
        {
          'id': 'active',
          'role': 'assistant',
          'is_completed': false,
          'pending_prompt': {
            'id': 'approval',
            'kind': 'tool_approval',
            'status': 'pending',
          },
        },
      ],
    });
    final controller = _controller(service);
    await controller.connect();
    expect(controller.running, true);
    expect(controller.canControlRun, false);
    expect(service.paths, contains('GET/shared-chat/stream?message_id=active'));
    await expectLater(
      controller.send('插入指令', behavior: 'follow_up'),
      throwsStateError,
    );
    await controller
        .answerPrompt(controller.prompts.values.single, {'approved': true});
    expect(service.paths.where((p) => p.contains('prompt-response')), isEmpty);
    expect(service.paths.where((p) => p.contains('/steer')), isEmpty);
    await controller.disconnect();
    controller.dispose();
    await service.events.close();
  });

  test('idle shared history polls and account switches discard results',
      () async {
    final service = _Service();
    final controller = _controller(service);
    await controller.connect();
    service.history['messages'] = [
      {'id': 'new', 'role': 'user', 'content': '成员的新消息'},
    ];
    await Future<void>.delayed(const Duration(milliseconds: 5100));
    expect(controller.messages.single['content'], '成员的新消息');
    service.reading = Completer<void>();
    final sending = controller.send('切换后不发送');
    await Future<void>.delayed(Duration.zero);
    service.user = 'different-member';
    service.reading!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(await sending, false);
    expect(service.sends, 0);
    await controller.disconnect();
    controller.dispose();
    await service.events.close();
  });
}
