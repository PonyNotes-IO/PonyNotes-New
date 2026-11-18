import 'dart:convert';

import 'package:appflowy/features/agent/application/agent_error.dart';
import 'package:appflowy/features/agent/application/agent_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI failures preserve their cause without a Dart exception prefix', () {
    final cases = [
      (403, 'AI 调用次数已用完，请升级套餐或购买补充包', 'AI 调用次数已用完，请升级套餐或购买补充包'),
      (
        402,
        jsonEncode({
          'error': {'code': 'AI_LIMIT_EXCEEDED', 'message': '本月 AI 次数已用完'},
        }),
        '本月 AI 次数已用完',
      ),
      (403, '{"message":"无权访问此 AI 对话"}', '无权访问此 AI 对话'),
      (403, '', '无权访问当前工作区或对话，请联系工作区管理员'),
      (401, 'Unauthorized', '登录已过期，请重新登录后重试'),
      (502, '<html>Bad Gateway</html>', 'AI 请求失败（502），请稍后重试'),
      (429, '', '请求过于频繁，请稍后重试'),
    ];
    for (final (status, body, expected) in cases) {
      expect(
        () => checkAgentResponse(status, body),
        throwsA(
          isA<StateError>().having(
            (error) => agentDisplayText('$error'),
            'display text',
            expected,
          ),
        ),
      );
    }
    expect(() => checkAgentResponse(200, '{}'), returnsNormally);
  });
}
