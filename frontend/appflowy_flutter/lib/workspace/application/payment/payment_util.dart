import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';

/// 支付方式枚举
enum PaymentMethod {
  applePay,
  wechatPay,
  alipay,
}

/// 支付结果
class PaymentResult {
  final bool success;
  final String message;
  final String? orderId;

  const PaymentResult({
    required this.success,
    required this.message,
    this.orderId,
  });

  factory PaymentResult.success({String message = '支付成功', String? orderId}) {
    return PaymentResult(success: true, message: message, orderId: orderId);
  }

  factory PaymentResult.failure({String message = '支付失败'}) {
    return PaymentResult(success: false, message: message);
  }
}

/// 支持的平台与支付方式管理
class PaymentPlatformSupport {
  /// 根据当前平台返回可用支付方式
  ///
  /// 约定：
  /// - macOS：只使用 Apple Pay
  /// - Windows：使用 微信支付 + 支付宝支付
  /// - 其他平台：暂不开放（返回空列表）
  static List<PaymentMethod> getAvailableMethods() {
    if (Platform.isMacOS) {
      return [PaymentMethod.applePay];
    }

    if (Platform.isWindows) {
      return [
        PaymentMethod.wechatPay,
        PaymentMethod.alipay,
      ];
    }

    return [];
  }

  static bool get isApplePayAvailable =>
      Platform.isMacOS && getAvailableMethods().contains(PaymentMethod.applePay);

  static bool get isWeChatPayAvailable =>
      Platform.isWindows &&
      getAvailableMethods().contains(PaymentMethod.wechatPay);

  static bool get isAlipayAvailable =>
      Platform.isWindows &&
      getAvailableMethods().contains(PaymentMethod.alipay);
}

/// 支付工具类
///
/// 当前先打通整体调用流程，具体平台 SDK 接入通过 MethodChannel
/// 在各平台原生侧实现：
/// - Apple Pay（macOS）：startApplePay
/// - 微信支付：startWeChatPay
/// - 支付宝支付：startAlipayPay
class PaymentUtil {
  static const MethodChannel _channel =
      MethodChannel('com.ponynotes.payment/channel');

  /// 根据指定支付方式发起支付
  ///
  /// [amount] 支付金额（单位：分或你自定义的单位，由后端约定）
  /// [currency] 货币，例如 CNY
  /// [orderId] 订单号，由你服务端生成
  /// [extra] 预留扩展字段，例如预下单返回的参数
  static Future<PaymentResult> pay({
    required PaymentMethod method,
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    switch (method) {
      case PaymentMethod.applePay:
        return _payWithApplePay(
          amount: amount,
          currency: currency,
          orderId: orderId,
          extra: extra,
        );
      case PaymentMethod.wechatPay:
        return _payWithWeChat(
          amount: amount,
          currency: currency,
          orderId: orderId,
          extra: extra,
        );
      case PaymentMethod.alipay:
        return _payWithAlipay(
          amount: amount,
          currency: currency,
          orderId: orderId,
          extra: extra,
        );
    }
  }

  /// Apple Pay 支付（macOS）
  static Future<PaymentResult> _payWithApplePay({
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    if (!Platform.isMacOS) {
      return PaymentResult.failure(message: '当前平台不支持 Apple Pay');
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startApplePay',
        <String, dynamic>{
          'amount': amount,
          'currency': currency,
          'orderId': orderId,
          'extra': extra ?? <String, dynamic>{},
        },
      );

      final success = result?['success'] == true;
      final message = (result?['message'] as String?) ?? '';
      final paidOrderId = result?['orderId'] as String?;

      return success
          ? PaymentResult.success(
              message: message.isEmpty ? '支付成功' : message,
              orderId: paidOrderId ?? orderId,
            )
          : PaymentResult.failure(
              message: message.isEmpty ? '支付失败' : message,
            );
    } catch (e, s) {
      Log.error('Apple Pay 支付异常: $e\n$s');
      return PaymentResult.failure(message: 'Apple Pay 支付异常');
    }
  }

  /// 微信支付（Windows）
  static Future<PaymentResult> _payWithWeChat({
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    if (!Platform.isWindows) {
      return PaymentResult.failure(message: '当前平台不支持微信支付');
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startWeChatPay',
        <String, dynamic>{
          'amount': amount,
          'currency': currency,
          'orderId': orderId,
          'extra': extra ?? <String, dynamic>{},
        },
      );

      final success = result?['success'] == true;
      final message = (result?['message'] as String?) ?? '';
      final paidOrderId = result?['orderId'] as String?;

      return success
          ? PaymentResult.success(
              message: message.isEmpty ? '支付成功' : message,
              orderId: paidOrderId ?? orderId,
            )
          : PaymentResult.failure(
              message: message.isEmpty ? '支付失败' : message,
            );
    } catch (e, s) {
      Log.error('微信支付异常: $e\n$s');
      return PaymentResult.failure(message: '微信支付异常');
    }
  }

  /// 支付宝支付（Windows）
  static Future<PaymentResult> _payWithAlipay({
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    if (!Platform.isWindows) {
      return PaymentResult.failure(message: '当前平台不支持支付宝支付');
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startAlipayPay',
        <String, dynamic>{
          'amount': amount,
          'currency': currency,
          'orderId': orderId,
          'extra': extra ?? <String, dynamic>{},
        },
      );

      final success = result?['success'] == true;
      final message = (result?['message'] as String?) ?? '';
      final paidOrderId = result?['orderId'] as String?;

      return success
          ? PaymentResult.success(
              message: message.isEmpty ? '支付成功' : message,
              orderId: paidOrderId ?? orderId,
            )
          : PaymentResult.failure(
              message: message.isEmpty ? '支付失败' : message,
            );
    } catch (e, s) {
      Log.error('支付宝支付异常: $e\n$s');
      return PaymentResult.failure(message: '支付宝支付异常');
    }
  }
}



