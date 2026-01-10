import 'package:scaled_app/scaled_app.dart';

import 'startup/startup.dart';

Future<void> main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );

  // 注意：已移除RawKeyboard诊断代码
  // RawKeyboard API已被Flutter弃用，与新的HardwareKeyboard系统冲突
  // 会导致键盘事件状态不同步，出现"KeyDownEvent but key already pressed"错误

  await runAppFlowy();
}
