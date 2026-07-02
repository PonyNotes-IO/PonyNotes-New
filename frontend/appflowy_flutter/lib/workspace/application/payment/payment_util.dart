import 'dart:async';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/startup/tasks/webview2_task.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

enum PaymentMethod {
  applePay,
  wechatPay,
  alipay,
}

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

class PaymentPlatformSupport {
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

    if (PlatformInfo.isDesktopOrTablet) {
      return [PaymentMethod.wechatPay];
    }

    return [
      PaymentMethod.wechatPay,
      PaymentMethod.alipay,
    ];
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

class PaymentUtil {
  static const MethodChannel _channel =
      MethodChannel('com.ponynotes.payment/channel');

  static InAppPurchase? _inAppPurchase;

  static InAppPurchase get _inAppPurchaseInstance {
    _inAppPurchase ??= InAppPurchase.instance;
    return _inAppPurchase!;
  }

  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

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
      final bool available = await _inAppPurchaseInstance.isAvailable();
      if (!available) {
        return PaymentResult.failure(message: 'App Store 内购不可用');
      }

      final String? productId = extra?['productId'] as String?;
      if (productId == null || productId.isEmpty) {
        Log.error('Apple Pay: 缺少 productId，无法发起内购');
        return PaymentResult.failure(message: '缺少产品 ID');
      }

      Log.info('Apple Pay: 开始购买产品，productId: $productId, orderId: $orderId');

      if (_purchaseSubscription == null) {
        _purchaseSubscription = _inAppPurchaseInstance.purchaseStream.listen(
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

      final ProductDetailsResponse productDetailResponse =
          await _inAppPurchaseInstance.queryProductDetails({productId});

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

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final bool purchaseInitiated = await _inAppPurchaseInstance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!purchaseInitiated) {
        Log.error('Apple Pay: 购买请求失败');
        return PaymentResult.failure(message: '购买请求失败');
      }

      Log.info('Apple Pay: 购买请求已发起，等待用户确认');

      return PaymentResult.success(
        message: '购买请求已发起，请完成支付',
        orderId: orderId,
      );
    } catch (e, s) {
      Log.error('Apple Pay 支付异常: $e\n$s');
      return PaymentResult.failure(message: 'Apple Pay 支付异常: $e');
    }
  }

  static void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      Log.info('Apple Pay: 收到购买更新，productId: ${purchaseDetails.productID}, status: ${purchaseDetails.status}');

      if (purchaseDetails.status == PurchaseStatus.pending) {
        Log.info('Apple Pay: 购买进行中...');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        Log.info('Apple Pay: 购买成功');
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchaseInstance.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        Log.error('Apple Pay: 购买失败: ${purchaseDetails.error}');
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchaseInstance.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        Log.info('Apple Pay: 用户取消了购买');
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchaseInstance.completePurchase(purchaseDetails);
        }
      }
    }
  }

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

  static Future<void> webPay(String payUrl) async {
    try {
      final uri = Uri.parse(payUrl);

      await _showTabletPaymentWebView(uri.toString());
      Log.info('[PaymentUtil] Opened payment URL in in-app webview: $payUrl');
    } catch (e, s) {
      Log.error('[PaymentUtil] Failed to open payment in browser: $e\n$s');
    }
  }

  static Future<void> _showTabletPaymentWebView(String payUrl) async {
    final context = AppGlobals.rootNavKey.currentContext;
    if (context == null) {
      Log.error('[PaymentUtil] No context available to show payment webview');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('支付'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            body: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(payUrl)),
              webViewEnvironment: sharedWebViewEnvironment,
              onLoadStart: (controller, url) {
                Log.info('[PaymentUtil] Payment webview loading: $url');
              },
              onLoadStop: (controller, url) {
                Log.info('[PaymentUtil] Payment webview loaded: $url');
              },
              onReceivedError: (controller, request, error) {
                Log.error('[PaymentUtil] Payment webview error: $error');
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url?.toString();
                if (url != null && url.startsWith('ponynotes://')) {
                  Navigator.of(context).pop();
                  final uri = Uri.parse(url);
                  Log.info('[PaymentUtil] Handling payment deep link: $uri');
                  await DeepLinkHandlerRegistry.instance.processDeepLink(
                    uri: uri,
                    onStateChange: (_, __) {},
                    onResult: (_, __) {},
                    onError: (error) {
                      Log.error('[PaymentUtil] Failed to process payment deep link: $error');
                    },
                  );
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
            ),
          );
        },
      ),
    );
  }
}
