import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

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
/// Apple Pay 使用 in_app_purchase 包处理（App Store 内购）
/// 其他支付方式通过 MethodChannel 在各平台原生侧实现：
/// - 微信支付：startWeChatPay
/// - 支付宝支付：startAlipayPay
class PaymentUtil {
  static const MethodChannel _channel =
      MethodChannel('com.ponynotes.payment/channel');
  
  // In-App Purchase 实例
  static final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  
  // 购买结果监听器（用于处理异步购买结果）
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

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

  /// Apple Pay 支付（macOS/iOS）- 使用 in_app_purchase 处理 App Store 内购
  static Future<PaymentResult> _payWithApplePay({
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return PaymentResult.failure(message: '当前平台不支持 App Store 内购');
    }

    try {
      // 检查是否可用
      final bool available = await _inAppPurchase.isAvailable();
      if (!available) {
        return PaymentResult.failure(message: 'App Store 内购不可用');
      }

      // 从 extra 中获取产品 ID（productId）
      // 如果没有提供，尝试从 orderId 或其他字段中获取
      final String? productId = extra?['productId'] as String?;
      if (productId == null || productId.isEmpty) {
        Log.error('Apple Pay: 缺少 productId，无法发起内购');
        return PaymentResult.failure(message: '缺少产品 ID');
      }

      Log.info('Apple Pay: 开始购买产品，productId: $productId, orderId: $orderId');

      // 设置购买结果监听器（如果还没有设置）
      if (_purchaseSubscription == null) {
        _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
          (List<PurchaseDetails> purchaseDetailsList) {
            _handlePurchaseUpdates(purchaseDetailsList);
          },
          onDone: () {
            Log.info('Apple Pay: 购买流已关闭');
            _purchaseSubscription?.cancel();
            _purchaseSubscription = null;
          },
          onError: (error) {
            Log.error('Apple Pay: 购买流错误: $error');
          },
        );
      }

      // 获取产品详情
      final ProductDetailsResponse productDetailResponse =
          await _inAppPurchase.queryProductDetails({productId});

      if (productDetailResponse.error != null) {
        Log.error('Apple Pay: 查询产品失败: ${productDetailResponse.error}');
        return PaymentResult.failure(
          message: '查询产品失败: ${productDetailResponse.error?.message ?? '未知错误'}',
        );
      }

      if (productDetailResponse.productDetails.isEmpty) {
        Log.error('Apple Pay: 未找到产品: $productId');
        return PaymentResult.failure(message: '未找到产品: $productId');
      }

      final ProductDetails productDetails = productDetailResponse.productDetails.first;

      // 创建购买参数
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      // 发起购买（根据产品类型选择合适的方法）
      // 如果是订阅类产品，使用 buyNonConsumable 或 buyConsumable
      // 如果是订阅，应该使用 buyNonConsumable（非消耗性产品）
      final bool purchaseInitiated = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!purchaseInitiated) {
        Log.error('Apple Pay: 购买请求失败');
        return PaymentResult.failure(message: '购买请求失败');
      }

      Log.info('Apple Pay: 购买请求已发起，等待用户确认');
      
      // 由于 in_app_purchase 的购买结果是异步的，需要通过 Stream 监听
      // 这里先返回成功，表示购买流程已启动
      // 实际的购买结果会在 _handlePurchaseUpdates 中处理
      return PaymentResult.success(
        message: '购买请求已发起，请完成支付',
        orderId: orderId,
      );
    } catch (e, s) {
      Log.error('Apple Pay 支付异常: $e\n$s');
      return PaymentResult.failure(message: 'Apple Pay 支付异常: $e');
    }
  }

  /// 处理购买更新（购买结果回调）
  static void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      Log.info('Apple Pay: 收到购买更新，productId: ${purchaseDetails.productID}, status: ${purchaseDetails.status}');

      if (purchaseDetails.status == PurchaseStatus.pending) {
        Log.info('Apple Pay: 购买进行中...');
        // 可以在这里显示加载状态
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        Log.info('Apple Pay: 购买成功');
        // 验证收据（应该在后端验证）
        // 这里只是标记为已完成，实际验证应该在后端进行
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        Log.error('Apple Pay: 购买失败: ${purchaseDetails.error}');
        // 处理错误
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        Log.info('Apple Pay: 用户取消了购买');
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
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

  /// 使用浏览器打开支付链接（支持 HTML form 和 URL）
  /// 
  /// [payUrl] 可以是 HTML form 格式或直接的 URL
  /// 如果是 HTML form，会写入临时文件并通过浏览器打开
  static Future<void> webPay(String payUrl) async {
    try {
//       final isHtmlForm = payUrl.contains('<form') || payUrl.contains('<FORM');
//
//       if (isHtmlForm) {
//         // 解码 HTML 实体
//         String html = payUrl
//             .replaceAll('&amp;', '&')
//             .replaceAll('&quot;', '"')
//             .replaceAll('&lt;', '<')
//             .replaceAll('&gt;', '>')
//             .replaceAll('&#39;', "'")
//             .replaceAll('&#x27;', "'")
//             .replaceAll('&#x2F;', '/');
//
//         // 兼容 action=" `URL` "
//         html = html.replaceAll('action=" `', 'action="').replaceAll('`"', '"');
//
//         // 包装成完整 HTML（保证 <script> 能执行）
//         if (!html.contains('<!DOCTYPE') && !html.toLowerCase().contains('<html')) {
//           html = '''<!DOCTYPE html>
// <html>
// <head>
//   <meta charset="UTF-8">
//   <meta name="viewport" content="width=device-width, initial-scale=1.0">
//   <title>支付页面</title>
// </head>
// <body>
// $html
// </body>
// </html>''';
//         }
//
//         // 写入临时文件
//         final tmpDir = await getTemporaryDirectory();
//         final fileName = 'alipay_pay_${DateTime.now().millisecondsSinceEpoch}.html';
//         final filePath = '${tmpDir.path}/$fileName';
//         await File(filePath).writeAsString(html, flush: true);

        // 通过浏览器打开本地文件
      //   final uri = Uri.file(filePath);
      //   if (await canLaunchUrl(uri)) {
      //     await launchUrl(uri, mode: LaunchMode.externalApplication);
      //     Log.info('[PaymentUtil] Opened payment form in browser: $filePath');
      //   } else {
      //     Log.error('[PaymentUtil] Cannot launch file URL: $filePath');
      //   }
      // } else {
      //   // 直接打开 URL
      //   final uri = Uri.parse(payUrl);
      //   if (await canLaunchUrl(uri)) {
      //     await launchUrl(uri, mode: LaunchMode.externalApplication);
      //     Log.info('[PaymentUtil] Opened payment URL in browser: $payUrl');
      //   } else {
      //     Log.error('[PaymentUtil] Cannot launch URL: $payUrl');
      //   }
      // }
      final uri = Uri.parse(payUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          Log.info('[PaymentUtil] Opened payment URL in browser: $payUrl');
        } else {
          Log.error('[PaymentUtil] Cannot launch URL: $payUrl');
        }
    } catch (e, s) {
      Log.error('[PaymentUtil] Failed to open payment in browser: $e\n$s');
    }
  }
}



