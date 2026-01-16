import 'dart:convert';

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:http/http.dart' as http;

/// 支付方式类型（用于后端接口的 paymentType 字段）
class PaymentType {
  static const String applePay = 'APPLE_PAY';
  static const String wechatPay = 'WECHAT_PAY';
  static const String alipay = 'ALIPAY';
}

/// 创建支付订单入参
/// 根据接口文档：/api/payment/create
class PaymentCreateRequest {
  /// 支付金额（精确到分/元，按业务金额单位定义）- 必传
  final String amount;
  
  /// 支付类型（如微信/支付宝/银行卡等，传参值按业务枚举定义）- 必传
  final String paymentType;
  
  /// 用户信息（JSON/自定义格式，存储用户标识/账号等核心信息）- 必传
  /// 注意：接口要求为 String 类型（JSON 字符串格式）
  final String userInfo;
  
  /// 产品名称（支付对应的商品/服务名称）- 可选
  final String? productName;
  
  /// 方案ID（套餐/定价方案唯一标识）- 可选
  final String? planId;
  
  /// 计费类型（如按次/包月/包年等，传参值按业务枚举定义）- 可选
  final String? billingType;
  
  /// 附加项ID（增值服务/附加功能唯一标识）- 可选
  final String? addonId;
  
  /// 微信开放ID（微信支付场景必传，非微信支付可空）- 可选
  /// 注意：接口字段名为 openid（小写d）
  final String? openid;
  
  /// 回调/跳转URL（支付成功/失败后的页面/接口地址）- 可选
  final String? url;

  const PaymentCreateRequest({
    required this.amount,
    required this.paymentType,
    required this.userInfo,
    this.productName,
    this.planId,
    this.billingType,
    this.addonId,
    this.openid,
    this.url,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      // 必传参数：确保 amount 始终存在
      // 注意：保持为数字类型，后端 BigDecimal 可以接收数字
      'amount': amount,
      'paymentType': paymentType,
      'userInfo': userInfo, // 已经是 JSON 字符串格式
    };
    
    // 只添加非空的可选参数
    if (productName != null && productName!.isNotEmpty) {
      json['productName'] = productName;
    }
    if (planId != null && planId!.isNotEmpty) {
      json['planId'] = planId;
    }
    if (billingType != null && billingType!.isNotEmpty) {
      json['billingType'] = billingType;
    }
    if (addonId != null && addonId!.isNotEmpty) {
      json['addonId'] = addonId;
    }
    if (openid != null && openid!.isNotEmpty) {
      json['openid'] = openid; // 注意：字段名是小写 openid
    }
    if (url != null && url!.isNotEmpty) {
      json['url'] = url;
    }
    
    return json;
  }
}

/// 创建支付订单返回结果（根据后端返回结构可以再扩展）
class PaymentCreateResponse {
  final String orderId;
  final double amount;
  final Map<String, dynamic> raw;

  const PaymentCreateResponse({
    required this.orderId,
    required this.amount,
    required this.raw,
  });

  factory PaymentCreateResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final orderId = (data['orderId'] ?? data['id'] ?? '').toString();
    final amountValue = (data['amount'] is num)
        ? (data['amount'] as num).toDouble()
        : 0.0;

    return PaymentCreateResponse(
      orderId: orderId,
      amount: amountValue,
      raw: data,
    );
  }
}

/// 支付相关云端 API 调用
class PaymentApi {
  /// 调用后端 `/api/payment/create` 创建支付订单
  ///
  /// 接口文档：
  /// - 请求方式：POST
  /// - 接口地址：/api/payment/create
  /// - 返回格式：JSON (AjaxResult 统一响应格式)
  ///
  /// 必传参数：
  /// - amount: 支付金额（BigDecimal，精确到分/元）
  /// - paymentType: 支付类型（String，如微信/支付宝/银行卡等）
  /// - userInfo: 用户信息（String，JSON/自定义格式）
  ///
  /// 可选参数：
  /// - productName: 产品名称（String）
  /// - planId: 方案ID（String）
  /// - billingType: 计费类型（String，如按次/包月/包年等）
  /// - addonId: 附加项ID（String）
  /// - openid: 微信开放ID（String，微信支付场景必传）
  /// - url: 回调/跳转URL（String）
  static Future<FlowyResult<PaymentCreateResponse, FlowyError>>
      createPaymentOrder(
    PaymentCreateRequest request,
  ) async {
    try {
      // 1. 获取当前云端配置（拿到 serverUrl）
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      // final baseUrl = cloudConfig.serverUrl;
      final baseUrl = "https://www.xiaomabiji.com/prod-api";

      // 2. 获取当前用户 Profile（包含 token）
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final UserProfilePB userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      final token = userProfile.token;

      if (baseUrl.isEmpty || token.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }

      final uri = Uri.parse('$baseUrl/api/payment/create');
      Log.info('[PaymentApi] Calling $uri');

      final payload = request.toJson();
      Log.info('[PaymentApi] Request payload: ${jsonEncode(payload)}');
      Log.info('[PaymentApi] Amount value: ${payload['amount']}, type: ${payload['amount'].runtimeType}');

      // 确保 payload 中包含所有必传字段
      if (!payload.containsKey('amount') || payload['amount'] == null) {
        Log.error('[PaymentApi] Amount is missing in payload!');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Amount is required but missing in request payload',
        );
      }

      // 根据错误信息，后端期望的是 request parameter（@RequestParam）
      // 这意味着参数应该在查询参数或表单数据中，而不是 JSON body
      // 对于 BigDecimal，Spring Boot 通常接收字符串格式的数字
      
      // 将 amount 转换为字符串格式（BigDecimal 在后端通常接收字符串）
      final formData = <String, String>{};
      
      // 处理 amount：转换为字符串，保留两位小数
      final amountValue = payload['amount'];
      if (amountValue is num) {
        formData['amount'] = amountValue.toStringAsFixed(2);
      } else {
        formData['amount'] = amountValue.toString();
      }
      
      // 处理 paymentType
      formData['paymentType'] = payload['paymentType'] as String;
      
      // 处理 userInfo（已经是 JSON 字符串）
      formData['userInfo'] = payload['userInfo'] as String;
      
      // 处理可选参数
      if (payload['productName'] != null && (payload['productName'] as String).isNotEmpty) {
        formData['productName'] = payload['productName'] as String;
      }
      if (payload['planId'] != null && (payload['planId'] as String).isNotEmpty) {
        formData['planId'] = payload['planId'] as String;
      }
      if (payload['billingType'] != null && (payload['billingType'] as String).isNotEmpty) {
        formData['billingType'] = payload['billingType'] as String;
      }
      if (payload['addonId'] != null && (payload['addonId'] as String).isNotEmpty) {
        formData['addonId'] = payload['addonId'] as String;
      }
      if (payload['openid'] != null && (payload['openid'] as String).isNotEmpty) {
        formData['openid'] = payload['openid'] as String;
      }
      if (payload['url'] != null && (payload['url'] as String).isNotEmpty) {
        formData['url'] = payload['url'] as String;
      }

      Log.info('[PaymentApi] Form data: $formData');
      Log.info('[PaymentApi] Amount (form): ${formData['amount']}');

      // 使用表单格式发送（application/x-www-form-urlencoded）
      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: formData.entries
            .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
            .join('&'),
      );

      Log.info('[PaymentApi] Response status: ${response.statusCode}');
      Log.info('[PaymentApi] Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Empty response body from /api/payment/create',
          );
        }

        final Map<String, dynamic> json =
            jsonDecode(response.body) as Map<String, dynamic>;
        final result = PaymentCreateResponse.fromJson(json);
        if (result.orderId.isEmpty) {
          Log.error('[PaymentApi] orderId is empty in response: $json');
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.FailedToParseQuery
              ..msg = result.raw.toString(),
          );
        }

        return FlowyResult.success(result);
      } else {
        final errorMsg = response.body.isNotEmpty
            ? response.body
            : 'Failed to create payment order (HTTP ${response.statusCode})';
        Log.error('[PaymentApi] Create payment order failed: $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e, s) {
      Log.error('[PaymentApi] Exception when creating payment order: $e\n$s');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to create payment order: $e',
      );
    }
  }
}



