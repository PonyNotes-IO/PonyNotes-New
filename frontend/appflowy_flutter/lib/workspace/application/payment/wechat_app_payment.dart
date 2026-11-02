import 'dart:convert';

import 'package:flutter/services.dart';

/// Android使用已有微信SDK；所有签名参数由支付后端生成。
class WeChatAppPayment {
  static const channel = MethodChannel('com.xiaomabiji.app.note/wechat_pay');
  static const appId = 'wx3b1a7737f52a004b';

  static Map<String, String> parseParams(String payInfo) {
    final data = jsonDecode(payInfo);
    const keys = [
      'appid',
      'partnerid',
      'prepayid',
      'package',
      'noncestr',
      'timestamp',
      'sign',
    ];
    if (data is! Map ||
        keys.any(
          (key) => data[key] == null || data[key].toString().trim().isEmpty,
        ) ||
        data['appid'] != appId ||
        data['package'] != 'Sign=WXPay' ||
        int.tryParse(data['timestamp'].toString()) == null) {
      throw const FormatException('微信App支付参数无效');
    }
    return {for (final key in keys) key: data[key].toString()};
  }

  static Future<({bool success, String message})> pay({
    required String payInfo,
    required String orderNo,
    required Future<String?> Function(String) queryStatus,
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    try {
      final params = parseParams(payInfo);
      final response =
          await channel.invokeMapMethod<String, dynamic>('pay', params);
      final code = response?['errCode'];
      // SDK成功或未收到回调时，给后端通知留出处理时间；取消也查一次防止错过付款。
      final attempts = code == 0 || code == -3 ? 10 : 1;
      for (var attempt = 0; attempt < attempts; attempt++) {
        String? status;
        try {
          status =
              await queryStatus(orderNo).timeout(const Duration(seconds: 10));
        } catch (_) {
          // 网络失败不能视为付款成功，继续有限次数的查单。
        }
        if (status == 'success' || status == 'paid') {
          return (success: true, message: '支付成功');
        }
        if (status == 'failed' || status == 'invalid') {
          return (success: false, message: '支付未完成，请查看订单状态');
        }
        if (attempt + 1 < attempts) await Future<void>.delayed(pollInterval);
      }
      return (
        success: false,
        message: code == -2
            ? '已取消支付'
            : code == 0 || code == -3
                ? '支付结果确认中，请稍后查看会员状态，勿重复付款'
                : '微信支付未完成，请稍后查看订单状态',
      );
    } on FormatException {
      return (success: false, message: '微信支付参数无效，请稍后重试');
    } on PlatformException catch (error) {
      return (success: false, message: error.message ?? '无法启动微信支付');
    } on MissingPluginException {
      return (success: false, message: '微信支付组件未加载，请更新App后重试');
    }
  }
}
