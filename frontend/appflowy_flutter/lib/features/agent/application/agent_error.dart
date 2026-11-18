import 'dart:convert';

void checkAgentResponse(int status, String body) {
  if (status >= 200 && status < 300) return;
  if (status == 401) throw StateError('登录已过期，请重新登录后重试');
  var message = body.trim();
  try {
    final data = jsonDecode(message);
    if (data is Map) {
      final error = data['error'];
      final value = error is Map
          ? error['message']
          : data['message'] ?? data['msg'] ?? error;
      message = value is String ? value.trim() : '';
    } else {
      message = '';
    }
  } on FormatException {
    // Cloud also returns plain text errors.
  }
  if (message.startsWith('<')) message = '';
  throw StateError(
    message.isNotEmpty
        ? message
        : switch (status) {
            402 => 'AI 调用次数已用完，请升级套餐或购买补充包',
            403 => '无权访问当前工作区或对话，请联系工作区管理员',
            404 => 'AI 服务或对话暂不可用，请稍后重试',
            429 => '请求过于频繁，请稍后重试',
            _ => 'AI 请求失败（$status），请稍后重试',
          },
  );
}
