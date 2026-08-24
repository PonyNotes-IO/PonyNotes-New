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
import 'package:tobias/tobias.dart';
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
      return [PaymentMethod.wechatPay, PaymentMethod.alipay];
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
      return [PaymentMethod.alipay];
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
      Platform.isIOS && getAvailableMethods().contains(PaymentMethod.applePay);

  static bool get isWeChatPayAvailable =>
      Platform.isWindows &&
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
      //支付宝支付需要上线后增加支付功能
      return PaymentResult.failure(message: '功能开发中');
      // ═══════════════════════════════════════════════════════════════════
      // 严格模式：Android 手机端只允许走 Tobias，不允许任何降级。
      //
      // 旧代码存在的多级降级路径（已全部删除）：
      //   1) Tobias 抛异常 → fall-through alipays:// scheme (_launchAlipayApp)
      //   2) scheme 失败 → 降级 WebView
      //   3) HTML/HTTP URL → WebView 打开 H5 支付
      //
      // 用户明确要求：「Android 手机必须走 Tobias，不要降级」。
      //   - H5 支付和 App 支付是两套不同的支付宝产品（需分别开通权限）；
      //   - H5 支付体验差，且前端无法同步拿到 resultStatus；
      //   - 降级路径会把"插件没注册"（MissingPluginException）错误给掩盖掉。
      //
      // 新策略：
      //   a) 缺少 payUrl / payUrl 不是 orderInfo 格式 → 直接 failure
      //   b) 前置 isAliPayInstalled，MissingPlugin 直接 return（不要"继续支付"）
      //   c) Tobias 异常按 MissingPlugin/PlatformException/其他 分三类日志
      //   d) Tobias 返回 9000 成功时通知 SubscriptionSuccessListenable
      // ═══════════════════════════════════════════════════════════════════
      final payPayload = extra?['payUrl'] as String?;
      if (payPayload == null || payPayload.isEmpty) {
        Log.error('[PaymentUtil][Alipay] Android 缺少 payUrl（orderId=$orderId）');
        return PaymentResult.failure(message: '缺少支付链接');
      }

      final trimmed = payPayload.trim();

      // ═══════════════════════════════════════════════════════════════════════
      // 先做排除性检测（HTML / HTTP URL / scheme）——这些格式即使内部碰巧
      // 包含 app_id= / sign= / biz_content 子串（例如 HTML 表单的
      // <form action="https://...?app_id=xxx&sign=xxx"> 和
      // <input name="biz_content" value="..."> 就会 3 个 contains 全 true），
      // 也必须优先识别为降级格式并拒绝。
      // ═══════════════════════════════════════════════════════════════════════
      final looksLikeHtml = trimmed.toLowerCase().startsWith('<') ||
          trimmed.toLowerCase().contains('<form') ||
          trimmed.toLowerCase().startsWith('<!doctype');
      final looksLikeHttpUrl = trimmed.startsWith('http://') || trimmed.startsWith('https://');
      final looksLikeAlipayScheme =
          trimmed.startsWith('alipays://') || trimmed.startsWith('alipay://');

      // App 支付 orderInfo 是纯 key=value&key=value 拼接串，第一个字符一定是
      // 字母或数字（'a' in app_id=... 或 '_'/'_' 下划线前缀等），绝不是 '<'。
      final startsWithAlphaNum = trimmed.isNotEmpty &&
          (trimmed.codeUnitAt(0) >= 0x30 /*0*/ && trimmed.codeUnitAt(0) <= 0x39 /*9*/ ||
              trimmed.codeUnitAt(0) >= 0x41 /*A*/ && trimmed.codeUnitAt(0) <= 0x5A /*Z*/ ||
              trimmed.codeUnitAt(0) >= 0x61 /*a*/ && trimmed.codeUnitAt(0) <= 0x7A /*z*/ ||
              trimmed.codeUnitAt(0) == 0x5F /*_*/);
      final hasAppId = trimmed.contains('app_id=');
      final hasSign = trimmed.contains('sign=');
      final hasBiz = trimmed.contains('biz_content');
      final looksLikeOrderInfo =
          !looksLikeHtml && !looksLikeHttpUrl && !looksLikeAlipayScheme &&
          startsWithAlphaNum && hasAppId && hasSign && hasBiz;

      final String detectedType = looksLikeHtml
          ? 'HTML_FORM'
          : looksLikeHttpUrl
              ? 'HTTP_URL'
              : looksLikeAlipayScheme
                  ? 'ALIPAY_SCHEME'
                  : looksLikeOrderInfo
                      ? 'ORDER_INFO'
                      : 'UNKNOWN';

      Log.info('[PaymentUtil][Alipay] Android 端收到支付凭证 (orderId=$orderId): '
          'type=$detectedType '
          'startsWithAlphaNum=$startsWithAlphaNum '
          'hasAppId=$hasAppId hasSign=$hasSign hasBiz=$hasBiz '
          'preview=${_ellipsis(trimmed, 60)}');

      // 先拦截所有降级格式，给出明确错误
      if (looksLikeHtml) {
        Log.error('[PaymentUtil][Alipay] 后端返回了 HTML 表单（网页支付产品），'
            'Android 端只支持 App 支付 orderInfo，拒绝降级 (orderId=$orderId)');
        return PaymentResult.failure(
          message: '后端返回的是网页支付表单，请联系后端使用 alipay.trade.app.pay 接口'
              '生成 App 支付 orderInfo（请求 product_code=QUICK_MSECURITY_PAY）',
        );
      }
      if (looksLikeHttpUrl) {
        Log.error('[PaymentUtil][Alipay] 后端返回了 HTTP H5 URL，'
            'Android 端只支持 Tobias App 支付，拒绝降级 WebView (orderId=$orderId)');
        return PaymentResult.failure(
          message: '后端返回的是 H5 网页支付链接，请联系后端改为 App 支付 orderInfo'
              '（product_code=QUICK_MSECURITY_PAY）',
        );
      }
      if (looksLikeAlipayScheme) {
        Log.error('[PaymentUtil][Alipay] 后端返回了 alipays:// scheme，'
            '请改为返回 orderInfo 字符串，通过 Tobias 统一唤起支付宝 App 并同步拿到结果'
            ' (orderId=$orderId)');
        return PaymentResult.failure(
          message: '请后端返回 App 支付 orderInfo（product_code=QUICK_MSECURITY_PAY），'
              '不要直接返回 alipays:// 跳转链接',
        );
      }
      if (!looksLikeOrderInfo) {
        Log.error('[PaymentUtil][Alipay] 无法识别的支付凭证格式，拒绝降级：'
            '${_ellipsis(trimmed, 80)} (orderId=$orderId)');
        return PaymentResult.failure(message: '支付凭证格式错误，请联系客服');
      }

      // ===== 前置检查：Tobias 插件注册 + 是否安装支付宝 App =====
      // 真机出现 MissingPluginException(isAliPayInstalled) 的常见根因：
      //   1) 用户设备上仍是旧版签名 APK（tobias 依赖加入之前的旧构建，
      //      GeneratedPluginRegistrant 中根本没有 TobiasPlugin）—— 必须卸载重装
      //   2) flutter run 增量构建 dex 没合并进 TobiasPlugin
      //   3) 冷启动时 ActivityAware.onAttachedToActivity 尚未回调：此时
      //      isAliPayInstalled 内部 activity==null 静默返回 false（误报未安装）
      //
      // MissingPlugin 与 activity==null 能清晰区分：
      //   - invokeMethod 尚未进入原生端前就抛 MissingPluginException → 插件未注册
      //   - 成功执行原生逻辑但返回 false → 可能是真未安装或 activity==null
      final tobias = Tobias();
      bool installed = false;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          installed = await tobias.isAliPayInstalled;
          if (installed) break;
          // 第一次返回 false：再等 500ms 后重试一次（冷启动 Activity attach 间隙）
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        } on MissingPluginException catch (e, s) {
          // ══════════════════════════════════════════════════════════════
          // MethodChannel "com.jarvanmo/tobias" 在 FlutterEngine 侧不存在
          // → 这是** APK 构建问题**，不是运行时/网络问题。"退出 App 重新打开"
          // 永远修不好 MissingPluginException，必须提示卸载重装。
          // ══════════════════════════════════════════════════════════════
          Log.error('[PaymentUtil][Alipay] ❌ MissingPluginException(isAliPayInstalled): '
              'Tobias 插件未注册到 FlutterEngine，本机安装的 APK 极可能是 tobias 依赖'
              '加入之前的旧构建。Troubleshoot 清单（开发者）：\n'
              '  1) flutter clean 彻底清理 build / .dart_tool 增量产物\n'
              '  2) flutter pub get 重新生成 GeneratedPluginRegistrant.java\n'
              '  3) 确认 GeneratedPluginRegistrant.java 中包含：\n'
              '     flutterEngine.getPlugins().add(new com.jarvan.tobias.TobiasPlugin())\n'
              '  4) 确认 MainActivity.configureFlutterEngine 第一行就是 super.configureFlutterEngine\n'
              '  5) 卸载真机旧 App → 重新安装新构建的 APK（禁止覆盖安装！）\n'
              '  channel=com.jarvanmo/tobias, error=$e\n$s');
          return PaymentResult.failure(
            message: '支付宝支付启动失败：检测到您当前使用的是旧版 App，请先卸载本机 App，'
                '重新安装最新版本后再使用支付宝支付；如仍有问题请联系客服',
          );
        } catch (e, s) {
          // 其他异常（ROM 包可见性查询失败等）：不阻塞支付，仅打 WARN。
          // PayTask(activity) 本身在未安装时会给出支付宝官方的未安装提示。
          Log.warn('[PaymentUtil][Alipay] 查询支付宝是否安装时发生非 MissingPlugin 异常，'
              '允许继续唤起支付（PayTask 会自行处理未安装场景）: $e\n$s');
          installed = true; // 放行
          break;
        }
      }
      Log.info('[PaymentUtil][Alipay] 支付宝是否安装: $installed (orderId=$orderId)');
      if (!installed) {
        // 两次检测均为 false → 可信地提示未安装
        return PaymentResult.failure(message: '请先安装支付宝 App 后再完成支付');
      }

      // ===== 唯一允许路径：Tobias().pay(orderInfo) =====
      final plan = extra?['plan'] as String?;
      try {
        Log.info('[PaymentUtil][Alipay] 调用 Tobias().pay(orderInfo) 唤起支付宝 App'
            ' (orderId=$orderId)');
        final payResult = await tobias.pay(trimmed);
        Log.info('[PaymentUtil][Alipay] Tobias 返回支付结果 (orderId=$orderId): $payResult');

        final result = _parseTobiasResult(payResult, orderId);
        if (result.success) {
          // 支付成功 → 通知 UI 刷新订阅状态，对齐 Apple Pay
          try {
            if (plan != null && plan.isNotEmpty) {
              Log.info('[PaymentUtil][Alipay] 支付成功，通知订阅刷新，plan=$plan');
              getIt<SubscriptionSuccessListenable>().onPaymentSuccess(plan);
            } else {
              Log.warn('[PaymentUtil][Alipay] 支付成功，但 extra.plan 为空，'
                  '无法通知 SubscriptionSuccessListenable，请调用方确认 planCode 是否传入');
            }
          } catch (e) {
            Log.error('[PaymentUtil][Alipay] 通知 SubscriptionSuccessListenable 失败: $e');
          }
        }
        return result;
      } on MissingPluginException catch (e, s) {
        Log.error('[PaymentUtil][Alipay] ❌ MissingPluginException(pay): Tobias 插件未注册。'
            'Troubleshoot 清单：\n'
            '  1) 执行 flutter clean 删除所有 build 产物（当前极大概率是旧增量 dex 仍在用！）\n'
            '  2) 再 flutter pub get → flutter run/android 重新构建\n'
            '  3) 确认 MainActivity.configureFlutterEngine 先 super.configureFlutterEngine\n'
            '     再 GeneratedPluginRegistrant.registerWith(flutterEngine) 兜底\n'
            '  4) 确认 GeneratedPluginRegistrant.java 中有 TobiasPlugin 注册\n'
            '  channel=com.jarvanmo/tobias, error=$e\n$s');
        return PaymentResult.failure(
          message: '支付宝支付启动失败：支付插件未加载，请退出 App 重新打开后重试；'
              '如仍有问题请联系客服',
        );
      } on PlatformException catch (e, s) {
        Log.error('[PaymentUtil][Alipay] ❌ PlatformException(Tobias 原生错误): '
            'code=${e.code}, message=${e.message}, details=${e.details}\n$s');
        return PaymentResult.failure(
          message: '支付宝支付失败：${e.message ?? '原生侧调用异常'}',
        );
      } catch (e, s) {
        Log.error('[PaymentUtil][Alipay] ❌ 未知异常(Tobias 调用失败): $e\n$s');
        return PaymentResult.failure(message: '支付宝支付失败: ${e.toString()}');
      }
    }

    return PaymentResult.failure(message: '当前平台不支持支付宝支付');
  }

  /// 截断字符串并添加省略号，用于日志中预览支付凭证
  static String _ellipsis(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// 解析 Tobias.pay() 返回的支付结果 Map 为 PaymentResult
  /// 支付宝官方 resultStatus 码：
  ///   9000 订单支付成功
  ///   8000 正在处理中（需查询订单状态）
  ///   4000 订单支付失败
  ///   5000 重复请求
  ///   6001 用户中途取消
  ///   6002 网络连接出错
  static PaymentResult _parseTobiasResult(Map payResult, String orderId) {
    // Tobias 3.x Android 上一般返回 Map；
    // 少数场景下是 "resultStatus=xx&result=xx&memo=xx" 字符串形式，这里做兼容。
    String? resultStatus;
    String? memo;

    resultStatus = payResult['resultStatus']?.toString() ??
        payResult['result_status']?.toString();
    memo = payResult['memo']?.toString() ?? payResult['result']?.toString();

    if (resultStatus == null || resultStatus.isEmpty) {
      final raw = payResult.values.firstWhere(
        (v) => v != null && v.toString().contains('resultStatus'),
        orElse: () => null,
      );
      if (raw != null) {
        final str = raw.toString();
        resultStatus = RegExp(r'resultStatus=([^&]+)').firstMatch(str)?.group(1);
        memo = RegExp(r'memo=([^&]+)').firstMatch(str)?.group(1);
      }
    }

    Log.info('[PaymentUtil][Alipay] Tobias 解析结果: resultStatus=$resultStatus, memo=$memo');

    switch (resultStatus) {
      case '9000':
        return PaymentResult.success(
          message: (memo != null && memo.isNotEmpty) ? memo : '支付成功',
          orderId: orderId,
        );
      case '8000':
        return PaymentResult.success(
          message: (memo != null && memo.isNotEmpty)
              ? memo
              : '支付处理中，请稍后查看订单状态确认是否成功',
          orderId: orderId,
        );
      case '6001':
        return PaymentResult.failure(message: '已取消支付');
      case '4000':
        return PaymentResult.failure(
          message: (memo != null && memo.isNotEmpty) ? memo : '订单支付失败',
        );
      case '6002':
        return PaymentResult.failure(
          message: (memo != null && memo.isNotEmpty) ? memo : '网络连接出错，请重试',
        );
      case '5000':
        return PaymentResult.failure(message: '重复请求，请稍后重试');
      default:
        return PaymentResult.failure(
          message: (memo != null && memo.isNotEmpty)
              ? memo
              : '支付失败 (code: ${resultStatus ?? 'unknown'})',
        );
    }
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
