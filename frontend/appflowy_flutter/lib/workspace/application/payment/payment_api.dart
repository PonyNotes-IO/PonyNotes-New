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
class PaymentCreateRequest {
  final double amount;
  final String paymentType;
  final String productName;
  final String openId;
  final String url;
  final Map<String, dynamic> userInfo;

  const PaymentCreateRequest({
    required this.amount,
    required this.paymentType,
    required this.productName,
    required this.openId,
    required this.url,
    required this.userInfo,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'amount': amount,
      'paymentType': paymentType,
      'productName': productName,
      'openId': openId,
      'url': url,
      'userInfo': userInfo,
    };
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
  /// 根据你提供的截图，请求参数结构为：
  /// {
  ///   amount: data.amount,
  ///   paymentType: data.paymentType,
  ///   productName: data.productName,
  ///   openId: data.openId,
  ///   url: data.url,
  ///   userInfo: data.userInfo,
  /// }
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

      final baseUrl = cloudConfig.serverUrl;

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

      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
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



