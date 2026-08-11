import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/startup/tasks/webview2_task.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

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

    if (Platform.isIOS) {
      return [PaymentMethod.applePay];
    }

    if (Platform.isAndroid) {
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
      (Platform.isMacOS || Platform.isIOS) && getAvailableMethods().contains(PaymentMethod.applePay);

  static bool get isWeChatPayAvailable =>
      (Platform.isWindows || Platform.isAndroid) &&
      getAvailableMethods().contains(PaymentMethod.wechatPay);

  static bool get isAlipayAvailable =>
      (Platform.isWindows || Platform.isAndroid) &&
      getAvailableMethods().contains(PaymentMethod.alipay);
}

class PaymentUtil {
  static const MethodChannel _channel =
      MethodChannel('com.ponynotes.payment/channel');

  static InAppPurchase get _inAppPurchaseInstance => InAppPurchase.instance;

  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  /// 根据 planCode 和 billingType 获取 App Store Connect 内购产品 ID
  /// App Store Connect 实际配置的产品 ID（消耗型项目）：
  ///   标准版：com.ponynotes.standard.{monthly,yearly}
  ///   专业版：com.ponynotes.professional.{monthly,yearly}
  ///   高级版：com.ponynotes.premium.{monthly,yearly}
  ///
  /// 后端 plan_code 与 App Store Connect 产品名称的对应关系：
  ///   standard/stand → standard
  ///   pro/professor/profersor → professional
  ///   hiclass/premium/team → premium
  static String? getAppleProductId(String planCode, String billingType) {
    final applePlanName = _toApplePlanName(planCode);
    if (applePlanName == null) {
      Log.error('Apple Pay: 未知的套餐代码: $planCode');
      return null;
    }
    return 'com.ponynotes.$applePlanName.$billingType';
  }

  /// 将后端 plan_code 转换为 App Store Connect 产品 ID 中的套餐名称
  /// 返回值：standard / professional / premium
  static String? _toApplePlanName(String planCode) {
    final lower = planCode.toLowerCase();
    switch (lower) {
      case 'standard':
      case 'stand':
        return 'standard';
      case 'pro':
      case 'professor':
      case 'profersor':
      case 'professional':
        return 'professional';
      case 'hiclass':
      case 'premium':
      case 'team':
        return 'premium';
      default:
        return null;
    }
  }

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

      // App Store Connect 配置的是"消耗型项目"，必须使用 buyConsumable
      final bool purchaseInitiated = await _inAppPurchaseInstance.buyConsumable(
        purchaseParam: purchaseParam,
        autoConsume: true,
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
        _onPurchaseSuccess(purchaseDetails);
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

  static Future<void> _onPurchaseSuccess(PurchaseDetails purchaseDetails) async {
    try {
      final productId = purchaseDetails.productID;
      final transactionId = purchaseDetails.purchaseID;
      Log.info('Apple Pay: 处理购买成功，productId: $productId, transactionId: $transactionId');

      await _verifyAndUpdateSubscription(productId, transactionId);
    } catch (e, s) {
      Log.error('Apple Pay: 处理购买成功异常: $e\n$s');
    }
  }

  static Future<void> _verifyAndUpdateSubscription(String productId, String? transactionId) async {
    try {
      final planInfo = _parseProductId(productId);
      if (planInfo == null) {
        Log.error('Apple Pay: 无法解析 productId: $productId');
        return;
      }

      final planId = planInfo['planId'] ?? '';
      final billingType = planInfo['billingType'] ?? 'monthly';
      final planName = planInfo['planName'] ?? '';

      Log.info('Apple Pay: 调用后端更新会员订阅，planId: $planId, billingType: $billingType, planName: $planName');

      await _updateSubscription(planId, billingType, planName, transactionId);
    } catch (e, s) {
      Log.error('Apple Pay: 验证并更新订阅异常: $e\n$s');
    }
  }

  static Map<String, String>? _parseProductId(String productId) {
    // 解析 App Store Connect 产品 ID 格式：com.ponynotes.{planName}.{billingType}
    // 实际产品 ID 中的 planName：standard / professional / premium
    // 需要反向映射回后端可识别的 planName：standard / pro / hiclass
    if (productId.startsWith('com.ponynotes.')) {
      final parts = productId.split('.');
      // com.ponynotes.xxx.yyy → 至少 4 段
      if (parts.length >= 4) {
        final billingType = parts.last; // monthly / yearly
        final applePlanName = parts[parts.length - 2]; // standard / professional / premium

        // Apple 产品 ID 名称 → 后端 planId + planName
        // 后端 planName 需要被 SubscriptionSuccessListenable 识别
        const applePlanToBackend = <String, Map<String, String>>{
          'standard': {'planId': '2', 'planName': 'standard'},
          'professional': {'planId': '3', 'planName': 'pro'},
          'premium': {'planId': '4', 'planName': 'hiclass'},
        };

        final backendInfo = applePlanToBackend[applePlanName];
        if (backendInfo != null) {
          return {
            'planId': backendInfo['planId']!,
            'billingType': billingType,
            'planName': backendInfo['planName']!,
          };
        }

        Log.error('Apple Pay: 无法从 productId 中识别套餐: $productId, planName=$applePlanName');
        return null;
      }
    }

    // 兼容旧格式：数字产品 ID（000001-000006）
    const numericIdMap = <String, Map<String, String>>{
      '000001': {'planId': '2', 'billingType': 'monthly', 'planName': 'standard'},
      '000002': {'planId': '3', 'billingType': 'monthly', 'planName': 'pro'},
      '000003': {'planId': '4', 'billingType': 'monthly', 'planName': 'hiclass'},
      '000004': {'planId': '2', 'billingType': 'yearly', 'planName': 'standard'},
      '000005': {'planId': '3', 'billingType': 'yearly', 'planName': 'pro'},
      '000006': {'planId': '4', 'billingType': 'yearly', 'planName': 'hiclass'},
    };

    if (numericIdMap.containsKey(productId)) {
      return numericIdMap[productId];
    }

    Log.error('Apple Pay: 无法解析 productId 格式: $productId');
    return null;
  }

  static Future<void> _updateSubscription(String planId, String billingType, String planName, String? transactionId) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      final baseUrl = cloudConfig.serverUrl;
      if (baseUrl.isEmpty) {
        Log.error('Apple Pay: serverUrl 为空');
        return;
      }

      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final UserProfilePB userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      String? accessToken;
      try {
        final decoded = jsonDecode(userProfile.token);
        if (decoded is Map<String, dynamic>) {
          accessToken = decoded['access_token'] as String?;
        }
      } catch (_) {
        accessToken = userProfile.token;
      }

      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Apple Pay: 无法提取 access_token');
        return;
      }

      final uri = Uri.parse('$baseUrl/api/subscription/subscribe');

      final requestBody = jsonEncode({
        'plan_id': int.tryParse(planId) ?? 1,
        'billing_type': billingType,
        'transaction_id': transactionId,
      });

      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        Log.info('Apple Pay: 会员订阅更新成功！planName: $planName');
        // 通知 UI 订阅成功，触发 AccountManagementBloc 刷新订阅信息
        try {
          getIt<SubscriptionSuccessListenable>().onPaymentSuccess(planName);
        } catch (e) {
          Log.error('Apple Pay: 通知 SubscriptionSuccessListenable 失败: $e');
        }
      } else {
        final errorMsg = response.body.isNotEmpty
            ? response.body
            : '更新会员订阅失败 (HTTP ${response.statusCode})';
        Log.error('Apple Pay: $errorMsg');
      }
    } catch (e, s) {
      Log.error('Apple Pay: 更新订阅异常: $e\n$s');
    }
  }

  static Future<PaymentResult> _payWithWeChat({
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    if (Platform.isWindows) {
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

    if (Platform.isAndroid) {
      try {
        final payUrl = extra?['payUrl'] as String?;
        if (payUrl != null && payUrl.isNotEmpty) {
          return _launchWeChatApp(payUrl, orderId);
        }
        return PaymentResult.failure(message: '缺少支付链接');
      } catch (e, s) {
        Log.error('微信支付异常: $e\n$s');
        return PaymentResult.failure(message: '微信支付异常');
      }
    }

    return PaymentResult.failure(message: '当前平台不支持微信支付');
  }

  static Future<PaymentResult> _payWithAlipay({
    required int amount,
    required String currency,
    required String orderId,
    Map<String, dynamic>? extra,
  }) async {
    if (Platform.isWindows) {
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

    if (Platform.isAndroid) {
      try {
        final payUrl = extra?['payUrl'] as String?;
        if (payUrl != null && payUrl.isNotEmpty) {
          return _launchAlipayApp(payUrl, orderId);
        }
        return PaymentResult.failure(message: '缺少支付链接');
      } catch (e, s) {
        Log.error('支付宝支付异常: $e\n$s');
        return PaymentResult.failure(message: '支付宝支付异常');
      }
    }

    return PaymentResult.failure(message: '当前平台不支持支付宝支付');
  }

  static Future<PaymentResult> _launchWeChatApp(String payUrl, String orderId) async {
    try {
      final wechatUrl = Uri.parse(payUrl);
      
      if (await canLaunchUrl(wechatUrl)) {
        await launchUrl(wechatUrl, mode: LaunchMode.externalApplication);
        Log.info('[PaymentUtil] 已启动微信 App: $payUrl');
        return PaymentResult.success(
          message: '请在微信中完成支付',
          orderId: orderId,
        );
      } else {
        Log.info('[PaymentUtil] 未安装微信 App，尝试通过网页支付');
        await _showTabletPaymentWebView(payUrl);
        return PaymentResult.success(
          message: '请完成网页支付',
          orderId: orderId,
        );
      }
    } catch (e, s) {
      Log.error('[PaymentUtil] 启动微信失败: $e\n$s');
      try {
        await _showTabletPaymentWebView(payUrl);
        return PaymentResult.success(
          message: '请完成网页支付',
          orderId: orderId,
        );
      } catch (webError) {
        Log.error('[PaymentUtil] 网页支付也失败: $webError');
        return PaymentResult.failure(message: '无法启动微信，请检查是否安装微信 App');
      }
    }
  }

  static Future<PaymentResult> _launchAlipayApp(String payUrl, String orderId) async {
    try {
      final alipayUrl = Uri.parse(payUrl);
      
      if (await canLaunchUrl(alipayUrl)) {
        await launchUrl(alipayUrl, mode: LaunchMode.externalApplication);
        Log.info('[PaymentUtil] 已启动支付宝 App: $payUrl');
        return PaymentResult.success(
          message: '请在支付宝中完成支付',
          orderId: orderId,
        );
      } else {
        Log.info('[PaymentUtil] 未安装支付宝 App，尝试通过网页支付');
        await _showTabletPaymentWebView(payUrl);
        return PaymentResult.success(
          message: '请完成网页支付',
          orderId: orderId,
        );
      }
    } catch (e, s) {
      Log.error('[PaymentUtil] 启动支付宝失败: $e\n$s');
      try {
        await _showTabletPaymentWebView(payUrl);
        return PaymentResult.success(
          message: '请完成网页支付',
          orderId: orderId,
        );
      } catch (webError) {
        Log.error('[PaymentUtil] 网页支付也失败: $webError');
        return PaymentResult.failure(message: '无法启动支付宝，请检查是否安装支付宝 App');
      }
    }
  }

  static Future<void> webPay(String payUrl, {String? plan}) async {
    try {
      final uri = Uri.parse(payUrl);

      await _showTabletPaymentWebView(uri.toString(), plan: plan);
      Log.info('[PaymentUtil] Opened payment URL in in-app webview: $payUrl, plan: $plan');
    } catch (e, s) {
      Log.error('[PaymentUtil] Failed to open payment in browser: $e\n$s');
    }
  }

  static Future<void> _showTabletPaymentWebView(String payUrl, {String? plan}) async {
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
                  var uri = Uri.parse(url);
                  Log.info('[PaymentUtil] Handling payment deep link: $uri');

                  if (uri.queryParameters['plan'] == null && plan != null) {
                    Log.info('[PaymentUtil] Adding plan parameter: $plan');
                    uri = uri.replace(queryParameters: {
                      ...uri.queryParameters,
                      'plan': plan,
                    });
                  }

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
