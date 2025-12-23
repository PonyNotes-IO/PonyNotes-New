import 'package:scaled_app/scaled_app.dart';
import 'package:flutter/services.dart';

import 'startup/startup.dart';

Future<void> main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );
  // 全局键盘事件诊断：打印 RawKeyEvent 与 HardwareKeyboard 当前按下集合
  // 目的：记录 keydown/keyup 的时序，帮助定位重复 KeyDown 的来源
  try {
    RawKeyboard.instance.addListener((event) {
      try {
        final now = DateTime.now().toIso8601String();
        final phys = event.physicalKey.debugName;
        final logical = event.logicalKey.debugName;
        final pressed = HardwareKeyboard.instance.physicalKeysPressed;
        // 使用 print 让 flutter log 捕获，便于收集
        print('[RAW_KEY_LOG] $now type=${event.runtimeType} physical=$phys logical=$logical pressedSetCount=${pressed.length}');
      } catch (e, st) {
        // 防止诊断代码抛异常影响启动
        print('[RAW_KEY_LOG] diagnostic error: $e\n$st');
      }
    });
  } catch (e) {
    // 在极少数环境 RawKeyboard 未就绪，打印并继续
    print('[RAW_KEY_LOG] attach failed: $e');
  }

  await runAppFlowy();
}
