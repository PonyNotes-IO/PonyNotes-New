import 'dart:convert';

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:http/http.dart' as http;

import '../../../env/cloud_env.dart';
import '../../../startup/startup.dart';

/// 支付方式类型（用于后端接口的 paymentType 字段）
class PaymentType {
  static const String applePay = 'APPLE_PAY';
  static const String wechatPay = 'WECHAT_PAY';
  static const String alipay = 'ALIPAY';
}

/// 支付开发测试模式配置
/// 
/// 开启此开关后，将跳过真实支付流程，直接模拟支付成功
/// 并调用后端接口更新用户会员权益
/// 
/// 警告：仅用于开发测试，生产环境必须设为 false！
class PaymentDevConfig {
  /// 是否启用开发测试模式（跳过真实支付）
  /// 设置为 true 后，点击"确认协议开通"将直接模拟支付成功
  static const bool enableTestMode = false;
  
  /// 模拟支付成功的延迟时间（毫秒），用于模拟支付查询轮询效果
  static const int mockPaymentDelayMs = 1500;
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
    if (openid != null && openid!.isNotEmpty) {
      json['openid'] = openid; // 注意：字段名是小写 openid
    }
    if (url != null && url!.isNotEmpty) {
      json['url'] = url;
    }
    
    return json;
  }
}

/// 支付订单数据（data 字段内容）
class PaymentOrderData {
  /// 订单号
  final String orderNo;

  /// 二维码URL（可能为 null）
  final String? qrCodeUrl;

  /// 过期时间
  final String? expireTime;

  /// 支付URL（HTML form 或 URL）
  final String? payUrl;

  /// 支付类型
  final String? payType;

  const PaymentOrderData({
    required this.orderNo,
    this.qrCodeUrl,
    this.expireTime,
    this.payUrl,
    this.payType,
  });

  factory PaymentOrderData.fromJson(Map<String, dynamic> json) {
    return PaymentOrderData(
      orderNo: (json['orderNo'] ?? json['orderId'] ?? json['id'] ?? '').toString(),
      qrCodeUrl: json['qrCodeUrl'] as String?,
      expireTime: json['expireTime'] as String?,
      payUrl: json['payUrl'] as String?,
      payType: json['payType'] as String?,
    );
  }

  /// 兼容旧版本的 orderId（使用 orderNo）
  String get orderId => orderNo;

  /// 检查是否有支付URL（HTML form 或 URL）
  bool get hasPayUrl => payUrl != null && payUrl!.isNotEmpty;

  /// 检查是否是 HTML form 格式
  bool get isHtmlForm => hasPayUrl && payUrl!.contains('<form');
}

/// 创建支付订单返回结果
/// 根据后端返回结构：{msg: "操作成功", code: 200, data: {orderNo, qrCodeUrl, expireTime, payUrl, payType}}
class PaymentCreateResponse {
  /// 响应消息
  final String msg;

  /// 响应码
  final int code;

  /// 订单数据
  final PaymentOrderData? data;

  const PaymentCreateResponse({
    required this.msg,
    required this.code,
    this.data,
  });

  /// 是否成功
  bool get isSuccess => code == 200 && data != null;

  /// 兼容旧版本的 orderId（使用 data.orderNo）
  String get orderId => data?.orderNo ?? '';

  /// 兼容旧版本的 orderNo
  String get orderNo => data?.orderNo ?? '';

  /// 兼容旧版本的 amount（从 data 中提取，如果存在）
  double get amount {
    // 如果 data 中有 amount 字段，使用它
    // 否则返回 0.0
    return 0.0;
  }

  /// 兼容旧版本的 payUrl
  String? get payUrl => data?.payUrl;

  /// 兼容旧版本的 qrCodeUrl
  String? get qrCodeUrl => data?.qrCodeUrl;

  /// 兼容旧版本的 expireTime
  String? get expireTime => data?.expireTime;

  /// 兼容旧版本的 payType
  String? get payType => data?.payType;

  /// 兼容旧版本的 hasPayUrl
  bool get hasPayUrl => data?.hasPayUrl ?? false;

  /// 兼容旧版本的 isHtmlForm
  bool get isHtmlForm => data?.isHtmlForm ?? false;

  factory PaymentCreateResponse.fromJson(Map<String, dynamic> json) {
    final msg = (json['msg'] as String?) ?? '操作成功';
    final code = (json['code'] as int?) ?? 200;

    PaymentOrderData? orderData;
    if (json['data'] is Map<String, dynamic>) {
      orderData = PaymentOrderData.fromJson(json['data'] as Map<String, dynamic>);
    }

    return PaymentCreateResponse(
      msg: msg,
      code: code,
      data: orderData,
    );
  }
}

/// 支付相关云端 API 调用
class PaymentApi {
  /// 存储测试模式下的模拟订单信息（用于关联 planId 和 billingType）
  static final Map<String, Map<String, String>> _mockOrderInfo = {};
  
  /// 从原始 token 中提取 access_token
  /// 
  /// userProfile.token 可能是以下格式之一：
  /// 1. JSON 字符串: {"access_token": "xxx", "refresh_token": "yyy", ...}
  /// 2. 纯 JWT token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  /// 
  /// 此方法会尝试解析 JSON，如果是 JSON 格式则提取 access_token，
  /// 否则直接返回原始 token
  static String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      // 尝试解析为 JSON
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        // 从 JSON 中提取 access_token
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          Log.info('[PaymentApi] 从 JSON 中提取 access_token 成功');
          return accessToken;
        }
      }
    } catch (_) {
      // 不是 JSON，可能是纯 JWT token，直接返回
      Log.info('[PaymentApi] token 不是 JSON 格式，直接使用原始 token');
      return rawToken;
    }
    return null;
  }
  
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
    // ==================== 开发测试模式 ====================
    // 跳过真实支付，生成模拟订单号
    if (PaymentDevConfig.enableTestMode) {
      Log.info('[PaymentApi] ⚠️ 开发测试模式已启用，跳过真实支付！');
      
      // 生成模拟订单号
      final mockOrderNo = 'test_${DateTime.now().millisecondsSinceEpoch}_${request.planId ?? 'plan'}';
      
      // 保存订单信息，用于后续更新会员权益
      _mockOrderInfo[mockOrderNo] = {
        'planId': request.planId ?? '',
        'billingType': request.billingType ?? 'monthly',
        'amount': request.amount,
      };
      
      Log.info('[PaymentApi] 创建模拟订单: $mockOrderNo');
      Log.info('[PaymentApi] 订单信息: planId=${request.planId}, billingType=${request.billingType}');
      
      // 返回模拟的订单创建成功响应（不带 payUrl，这样不会弹出支付页面）
      final mockResponse = PaymentCreateResponse(
        msg: '操作成功（测试模式）',
        code: 200,
        data: PaymentOrderData(
          orderNo: mockOrderNo,
          expireTime: null,
          payUrl: null, // 不设置 payUrl，避免打开浏览器
          payType: 'TEST',
        ),
      );
      
      return FlowyResult.success(mockResponse);
    }
    // ==================== 开发测试模式结束 ====================

    //旧版h5支付逻辑不通，不支持 -- todo 后期接入其他支付再使用
    return createOrder(request);
  }

  static Future<FlowyResult<PaymentCreateResponse, FlowyError>> createOrder
      (PaymentCreateRequest request) async{
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      // 2. 获取当前用户 Profile（包含 token）
      // final userProfileResult = await UserBackendService.getCurrentUserProfile();
      // final UserProfilePB userProfile = userProfileResult.fold(
      //   (profile) => profile,
      //   (error) => throw error,
      // );
      //
      // final token = userProfile.token;

      if (baseUrl.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }

      final uri = Uri.parse('$baseUrl/prod-api/api/payment/create');
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
          // 'Authorization': 'Bearer $token',
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

        // 解析响应
        final result = PaymentCreateResponse.fromJson(json);

        // 检查响应是否成功
        if (!result.isSuccess) {
          Log.error('[PaymentApi] Create payment order failed: code=${result.code}, msg=${result.msg}');
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = result.msg,
          );
        }

        // 检查订单数据是否存在
        if (result.data == null) {
          Log.error('[PaymentApi] Order data is null in response: $json');
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.FailedToParseQuery
              ..msg = '订单数据为空',
          );
        }

        // 检查订单号
        if (result.orderNo.isEmpty) {
          Log.error('[PaymentApi] orderNo is empty in response: $json');
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.FailedToParseQuery
              ..msg = '订单号为空',
          );
        }

        Log.info('[PaymentApi] Payment order created successfully: orderNo=${result.orderNo}, hasPayUrl=${result.hasPayUrl}');
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

  /// 查询支付订单状态
  /// 
  /// [orderNo] 订单号
  /// 返回订单状态：pending（待支付）、paid（已支付）、failed（失败）、expired（已过期）
  static Future<FlowyResult<String, FlowyError>> queryPaymentStatus(
    String orderNo,
  ) async {
    // ==================== 开发测试模式 ====================
    // 直接返回支付成功，并调用后端接口更新会员权益
    if (PaymentDevConfig.enableTestMode && orderNo.startsWith('test_')) {
      Log.info('[PaymentApi] ⚠️ 开发测试模式：模拟支付成功 orderNo=$orderNo');
      
      // 添加一点延迟，模拟真实支付场景
      await Future.delayed(Duration(milliseconds: PaymentDevConfig.mockPaymentDelayMs));
      
      // 获取之前保存的订单信息
      final orderInfo = _mockOrderInfo[orderNo];
      if (orderInfo != null) {
        final planId = orderInfo['planId'] ?? '';
        final billingType = orderInfo['billingType'] ?? 'monthly';
        
        // 会员升级
        Log.info('[PaymentApi] 测试模式：调用后端更新会员订阅 planId=$planId, billingType=$billingType');
        final subscribeResult = await _updateSubscriptionInTestMode(planId, billingType);
        if (subscribeResult.isFailure) {
          final error = subscribeResult.fold((_) => null, (e) => e);
          Log.error('[PaymentApi] 测试模式：更新会员订阅失败 ${error?.msg}');
          // 即使更新失败，也返回支付成功，让用户可以重新刷新
        }
        
        // 清理订单信息
        _mockOrderInfo.remove(orderNo);
      }
      
      return FlowyResult.success('paid');
    }
    // ==================== 开发测试模式结束 ====================
    
    try {
      // 1. 获取当前云端配置（拿到 serverUrl）
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
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

      final uri = Uri.parse('$baseUrl/prod-api/api/payment/status/orderNo=$orderNo');
      Log.info('[PaymentApi] Querying payment status: $uri');

      final response = await http.get(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
        },
      );

      Log.info('[PaymentApi] Query response status: ${response.statusCode}');
      Log.info('[PaymentApi] Query response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = 'Empty response body from /api/payment/query',
          );
        }

        final Map<String, dynamic> json =
            jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = json['code'] as int? ?? 200;
        if (code != 200) {
          final msg = json['msg'] as String? ?? '查询失败';
          Log.error('[PaymentApi] Query payment status failed: code=$code, msg=$msg');
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.Internal
              ..msg = msg,
          );
        }

        // 解析订单状态
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) {
          return FlowyResult.failure(
            FlowyError()
              ..code = ErrorCode.FailedToParseQuery
              ..msg = '订单数据为空',
          );
        }

        // 订单状态字段可能是 status 或 orderStatus
        final status = (data['status'] ?? data['orderStatus'] ?? 'pending').toString().toLowerCase();
        Log.info('[PaymentApi] Payment status: $status');
        return FlowyResult.success(status);
      } else {
        final errorMsg = response.body.isNotEmpty
            ? response.body
            : 'Failed to query payment status (HTTP ${response.statusCode})';
        Log.error('[PaymentApi] Query payment status failed: $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e, s) {
      Log.error('[PaymentApi] Exception when querying payment status: $e\n$s');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to query payment status: $e',
      );
    }
  }

  /// 测试模式：调用后端接口更新会员订阅
  /// 
  /// [planId] 套餐 ID
  /// [billingType] 计费类型：monthly 或 yearly
  static Future<FlowyResult<void, FlowyError>> _updateSubscriptionInTestMode(
    String planId,
    String billingType,
  ) async {
    try {
      // 获取云端配置
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      final baseUrl = cloudConfig.serverUrl;
      if (baseUrl.isEmpty) {
        Log.error('[PaymentApi] 测试模式：serverUrl 为空');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Server URL is empty',
        );
      }

      // 获取当前用户 Profile（包含 token）
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final UserProfilePB userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      // 从 userProfile.token 中提取真正的 access_token
      // userProfile.token 可能是 JSON 格式 {"access_token": "xxx", ...}
      final accessToken = _extractAccessToken(userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('[PaymentApi] 测试模式：无法提取 access_token');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = 'Failed to extract access token',
        );
      }

      // 调用后端的 subscribe 接口
      // POST /api/subscription/subscribe
      // Body: { "plan_id": 2, "billing_type": "monthly" }
      final uri = Uri.parse('$baseUrl/api/subscription/subscribe');
      Log.info('[PaymentApi] 测试模式：调用 $uri');

      final requestBody = jsonEncode({
        'plan_id': int.tryParse(planId) ?? 1,
        'billing_type': billingType,
      });
      Log.info('[PaymentApi] 测试模式：请求体 $requestBody');

      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: requestBody,
      );

      Log.info('[PaymentApi] 测试模式：响应状态 ${response.statusCode}');
      Log.info('[PaymentApi] 测试模式：响应内容 ${response.body}');

      if (response.statusCode == 200) {
        Log.info('[PaymentApi] 测试模式：会员订阅更新成功！');
        return FlowyResult.success(null);
      } else {
        final errorMsg = response.body.isNotEmpty
            ? response.body
            : 'Failed to update subscription (HTTP ${response.statusCode})';
        Log.error('[PaymentApi] 测试模式：更新会员订阅失败 $errorMsg');
        return FlowyResult.failure(
          FlowyError()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e, s) {
      Log.error('[PaymentApi] 测试模式：更新会员订阅异常 $e\n$s');
      return FlowyResult.failure(
        FlowyError()
          ..code = ErrorCode.Internal
          ..msg = 'Failed to update subscription: $e',
      );
    }
  }


}
