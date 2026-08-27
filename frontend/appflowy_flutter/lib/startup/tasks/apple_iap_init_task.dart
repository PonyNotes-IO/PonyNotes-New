import 'package:appflowy/workspace/application/payment/apple_iap_service.dart';
import 'package:appflowy_backend/log.dart';

import '../startup.dart';

/// 在 App 启动后尽早初始化 [AppleIAPService]，启动 purchaseStream
/// 永久监听，对未 finish 的交易（扣款成功但 verify 网络异常、
/// 掉单、自动续费等）下次启动自动补单。
///
/// 放置在启动任务尾部（非关键路径），避免阻塞首帧。
class AppleIAPInitTask extends LaunchTask {
  const AppleIAPInitTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    try {
      await AppleIAPService.instance.initialize();
    } catch (e, s) {
      Log.warn('[AppleIAPInitTask] initialize failed: $e\n$s');
      // 非致命失败：用户点支付按钮时 purchase() 仍会再尝试
    }
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}
