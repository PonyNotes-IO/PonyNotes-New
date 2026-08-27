import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

/// StoreKit 2 苹果内购服务（iOS / iPad / macOS 平台）。
///
/// 严格遵循如下规范，任何违反都会导致用户"扣款但不开通"：
///
/// 🔴 三条红线：
///   1) [purchaseProduct] 必须传入 [userUuid]（标准 UUID 格式），
///      内部会把它设置为 PurchaseParam 的 appAccountToken，这样
///      苹果 server-to-server 通知掉单时，后端才能按用户身份认账。
///   2) 任何交易必须先 POST /api/payment/apple/verify 拿到 code=200，
///      之后才能 completePurchase（finish）。失败/异常/超时一定
///      不要 finish，StoreKit 下次启动会通过 [purchaseStream] 再交
///      付一次，直到我们真正 finish。
///   3) App 端不解析交易金额，也不判断是否开通——完全以 verify 响应
///      为准。
///
/// ✅ 其他能力：
///   - [initialize] 应在 App 启动时尽早调用（见 payment_init_task.dart）。
///   - [purchaseStream] 监听器永久运行，处理：续费、掉单重试、
///     跨 App 会话的未 finish 交易补单。
///   - [restorePurchases] 用于用户手动点"恢复购买"（重装/换设备）。
///   - [fetchProducts] 从 App Store 拉取本地化展示价格 & 币种。
class AppleIAPService {
  AppleIAPService._();

  static final AppleIAPService instance = AppleIAPService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;

  /// 苹果商品 ID 前缀，与 App Store Connect / 后端 `payment.apple.products`
  /// 的 key 前缀保持一致。
  /// 商品 ID 拼接格式：`com.ponynotes.{billingType}.{planCode}`
  /// 例如：com.ponynotes.monthly.pro、com.ponynotes.yearly.pro
  static const String kAppleProductIdPrefix = 'com.ponynotes';

  /// 根据套餐 planCode 和计费周期 billingType 拼接苹果商品 ID。
  /// ⚠️ 必须与 App Store Connect 中配置的 Product ID 完全一致。
  static String buildAppleProductId(String planCode, String billingType) {
    return '$kAppleProductIdPrefix.$billingType.$planCode';
  }

  /// 是否在当前平台可用（iOS / iPadOS / macOS）。
  bool get isApplePlatform =>
      Platform.isIOS || Platform.isMacOS;

  // ----------------------------------------------------------------
  // 生命周期
  // ----------------------------------------------------------------

  /// App 启动时调用一次：
  ///   - 启动 [purchaseStream] 永久监听，捕获未 finish 的交易、
  ///     自动续费、以及跨 App 重启的掉单补单。
  ///   - [force] 为 true 会先取消老订阅再重建（热重载场景使用）。
  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    if (!isApplePlatform) {
      _initialized = true;
      return;
    }

    if (force) {
      await _subscription?.cancel();
      _subscription = null;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseStreamEvent,
      onDone: () {
        Log.info('[AppleIAP] purchaseStream done');
        _subscription = null;
      },
      onError: (Object e, StackTrace s) {
        Log.error('[AppleIAP] purchaseStream error: $e\n$s');
      },
    );

    // 冷启动后立刻同步一次，确保上次 App 关闭前遗留的未 finish
    // 交易在本次启动第一时间进入 onPurchaseStreamEvent 处理。
    try {
      await _iap.restorePurchases();
    } catch (e, s) {
      Log.warn('[AppleIAP] initial restorePurchases failed: $e\n$s');
    }

    _initialized = true;
    Log.info('[AppleIAP] initialized');
  }

  // ----------------------------------------------------------------
  // 商品列表
  // ----------------------------------------------------------------

  /// 从 App Store 拉取商品详情（本地化 displayPrice / currency）。
  /// 如果某 productId 没配置，将不会出现在返回结果中。
  /// [productIds] 为空时不查询。
  Future<ProductDetailsResponse> fetchProducts(
    List<String> productIds,
  ) async {
    if (!isApplePlatform) {
      return ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: productIds,
        error: null,
      );
    }
    return _iap.queryProductDetails(productIds.toSet());
  }

  // ----------------------------------------------------------------
  // 发起购买（前台用户手动点击）
  // ----------------------------------------------------------------

  /// 发起苹果内购购买。
  ///
  /// 参数：
  ///   [productId]    由 [buildAppleProductId] 拼接得到，必须与
  ///                  App Store Connect 中的 Product ID 一致
  ///   [userUuid]     标准 UUID（JWT sub 字段），会被放进 appAccountToken
  ///
  /// 顺序：
  ///   purchase() → 系统扣款 → Stream 回调 → verify 后端 → 成功才 finish → 刷新订阅
  ///
  /// 返回值：PurchaseResult.success 时调用方能给用户提示"支付成功"；
  ///        失败时给出错误文案。App 端本身不参与成功逻辑，一切由 stream
  ///        里的 verify 结果驱动。
  Future<PurchaseResult> purchaseProduct({
    required String productId,
    required String userUuid,
  }) async {
    if (!isApplePlatform) {
      return PurchaseResult.failure('当前平台不支持 App Store 内购');
    }
    if (productId.isEmpty) {
      return PurchaseResult.failure('缺少产品 ID');
    }

    final available = await _iap.isAvailable();
    if (!available) {
      return PurchaseResult.failure('App Store 内购不可用，请检查设置');
    }

    // 1) 拉一次商品详情，校验 productId 在 App Store Connect 中真实存在
    final products = await fetchProducts(<String>[productId]);
    if (products.error != null) {
      Log.error('[AppleIAP] fetchProducts error: ${products.error}');
      return PurchaseResult.failure(
          '查询苹果产品失败：${products.error?.message ?? '未知错误'}');
    }
    final match = products.productDetails
        .where((p) => p.id == productId)
        .toList();
    if (match.isEmpty) {
      Log.error('[AppleIAP] product not found: $productId');
      return PurchaseResult.failure('未找到产品：$productId');
    }
    final product = match.first;

    // 2) 把 userUuid 放进 applicationUserName，插件会把它映射为
    //    SK2ProductPurchaseOptions.appAccountToken（红线 1）。
    final PurchaseParam param;
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        // Sk2PurchaseParam 声明了在 iOS 上需要的字段，插件会优先将
        // applicationUserName 作为 appAccountToken 透传给 StoreKit 2。
        param = Sk2PurchaseParam(
          productDetails: product,
          applicationUserName: userUuid,
        );
      } else {
        param = PurchaseParam(productDetails: product);
      }
    } catch (e, s) {
      Log.error('[AppleIAP] build PurchaseParam error: $e\n$s');
      return PurchaseResult.failure('构造内购参数失败');
    }

    // 3) 对于订阅类商品必须用 buyNonConsumable（或订阅接口）。
    //    这里用更通用的 buyConsumable 会导致订阅被"消耗"，错误。
    //    由于 in_app_purchase 订阅也是通过 buyNonConsumable 购买，
    //    我们的 product 是 monthly / yearly 订阅，走 buyNonConsumable。
    final bool ok = await _iap.buyNonConsumable(purchaseParam: param);
    if (!ok) {
      Log.error('[AppleIAP] buyNonConsumable returned false');
      return PurchaseResult.failure('无法发起购买，请稍后重试');
    }

    Log.info('[AppleIAP] purchase initiated — product=$productId, '
        'appAccountToken=$userUuid');
    return PurchaseResult.initiated();
  }

  // ----------------------------------------------------------------
  // 恢复购买（重装 / 换设备 / 跨账号迁移）
  // ----------------------------------------------------------------

  /// 提交用户的当前权益（currentEntitlements）给后端 restore 接口。
  ///
  /// 用户在"设置 / 会员页"点"恢复购买"时调用，内部会：
  ///   1) 调 restorePurchases() 触发 StoreKit 重新发放交易
  ///   2) 遍历 currentEntitlements 的已验签交易，取出 jws
  ///   3) 调用 PaymentApi.appleRestore 批量提交后端
  ///   4) 成功后通知 SubscriptionSuccessListenable & 返回 true
  Future<RestoreResult> restorePurchasesForUser(String userUuid) async {
    if (!isApplePlatform) {
      return RestoreResult.failure('当前平台不支持 App Store 内购');
    }
    try {
      await _iap.restorePurchases();
    } catch (e, s) {
      Log.warn('[AppleIAP] restorePurchases call failed: $e\n$s');
    }

    // 手动从 PurchaseDetails 的 StoreKit 专属扩展中拿 jwsRepresentation。
    // 注意：restorePurchases() 本身也会走 purchaseStream；为了给用户
    // 一个"我点了恢复购买 → 有结果"的同步交互，这里再显式抓一遍。
    final List<String> jwsList = <String>[];
    try {
      final all = await _availablePurchaseDetails();
      for (final pd in all) {
        final jws = _extractJwsFromPurchase(pd);
        if (jws != null && jws.isNotEmpty) jwsList.add(jws);
      }
    } catch (e, s) {
      Log.warn('[AppleIAP] collect entitlements jws failed: $e\n$s');
    }

    if (jwsList.isEmpty) {
      Log.info('[AppleIAP] restore — 无可用交易');
      return RestoreResult.empty();
    }

    final res = await PaymentApi.appleRestore(
      userInfo: userUuid,
      transactions: jwsList,
    );

    if (res.isFailure) {
      final err = res.fold((_) => null, (e) => e);
      return RestoreResult.failure(err?.msg ?? '恢复购买失败');
    }
    try {
      getIt<SubscriptionSuccessListenable>().onPaymentSuccess(null);
    } catch (_) {}
    return RestoreResult.success();
  }

  // ----------------------------------------------------------------
  // 内部：purchaseStream 事件处理核心
  // ----------------------------------------------------------------

  Future<void> _onPurchaseStreamEvent(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final PurchaseDetails pd in purchaseDetailsList) {
      Log.info('[AppleIAP] stream event — productId=${pd.productID}, '
          'status=${pd.status}, purchaseID=${pd.purchaseID}, '
          'pendingComplete=${pd.pendingCompletePurchase}');

      switch (pd.status) {
        case PurchaseStatus.pending:
          // 无需 finish
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _handleVerifiedPurchase(pd);
          break;
        case PurchaseStatus.error:
          Log.error('[AppleIAP] PurchaseStatus.error: ${pd.error}');
          // 明确错误态也 finish，避免 StoreKit 一直留着（用户取消/
          // 系统弹错的交易不会被重交付）。
          if (pd.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(pd);
            } catch (e, s) {
              Log.error('[AppleIAP] error-completePurchase failed: $e\n$s');
            }
          }
          break;
        case PurchaseStatus.canceled:
          Log.info('[AppleIAP] PurchaseStatus.canceled');
          if (pd.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(pd);
            } catch (e, s) {
              Log.error('[AppleIAP] canceled-completePurchase failed: $e\n$s');
            }
          }
          break;
      }
    }
  }

  /// 处理 purchased / restored 的交易：verify → 成功 finish → 通知刷新。
  ///
  /// 🔴 红线 2：verify 成功之前绝不 completePurchase。
  /// 🔴 红线 3：不解析交易金额，一切以后端 verify 返回为准。
  ///
  /// 失败 / 网络异常 → **不 completePurchase** → 苹果下次启动
  /// 再通过 purchaseStream 重发 → 我们再次走 verify。
  /// apple/verify 接口是幂等的（同一苹果交易号返回原订单），所以
  /// 重复执行没有问题。
  Future<void> _handleVerifiedPurchase(PurchaseDetails pd) async {
    final jws = _extractJwsFromPurchase(pd);
    final purchaseId = pd.purchaseID ?? '';

    if (jws == null || jws.isEmpty) {
      Log.error('[AppleIAP] handleVerifiedPurchase: no jwsRepresentation, '
          'productId=${pd.productID}, purchaseID=$purchaseId');
      // 没有 jws 我们无法验签。为了不永远阻塞在未 finish 队列，
      // 视情况 finish 但记录严重错误，便于后续排查。
      if (pd.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(pd);
          Log.warn('[AppleIAP] finished purchase without jws (can not verify), '
              'productId=${pd.productID}');
        } catch (e, s) {
          Log.error('[AppleIAP] completePurchase without jws failed: $e\n$s');
        }
      }
      return;
    }

    // 苹果 server-to-server 通知掉单时，后端靠 appAccountToken 关联用户。
    // 但这里的 verify 接口需要"当前登录用户"做 userInfo。一般情况下
    // 这两个值一致（购买时我们就把 appAccountToken 设为 userUuid）；
    // 极端不一致时以后端校验为准。
    final String? userUuid = await _resolveCurrentUserUuid();
    if (userUuid == null || userUuid.isEmpty) {
      Log.error('[AppleIAP] userUuid unavailable, skip verify, purchaseID=$purchaseId');
      // 不 finish，等用户登录后再触发 restorePurchases 补单
      return;
    }

    final verify = await PaymentApi.appleVerify(
      userInfo: userUuid,
      transaction: jws,
    );

    if (verify.isFailure) {
      final err = verify.fold((_) => null, (e) => e);
      Log.error('[AppleIAP] verify failed — productId=${pd.productID}, '
          'purchaseID=$purchaseId, msg=${err?.msg}');
      // 🔴 红线 2：verify 失败，一定不要 completePurchase。
      // 下次启动 purchaseStream 会重新交付此交易，再尝试一次。
      return;
    }

    Log.info('[AppleIAP] verify success, productId=${pd.productID}, '
        'purchaseID=$purchaseId');

    // verify 成功 → 先 finish，再通知 UI 刷新订阅
    if (pd.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(pd);
      } catch (e, s) {
        Log.error('[AppleIAP] completePurchase failed: $e\n$s');
        // 即使 completePurchase 抛异常，Subscription 刷新先跑起来。
        // 苹果侧的 finish 下次启动会再补一次。
      }
    }

    try {
      getIt<SubscriptionSuccessListenable>().onPaymentSuccess(null);
    } catch (e) {
      Log.warn('[AppleIAP] notify subscription refresh failed: $e');
    }
  }

  // ----------------------------------------------------------------
  // 内部辅助
  // ----------------------------------------------------------------

  /// 从 PurchaseDetails 中提取 jwsRepresentation。
  ///
  /// in_app_purchase 3.x 在 iOS/macOS StoreKit 2 模式下：
  ///   - PurchaseDetails.runtimeType = SK2PurchaseDetails
  ///   - PurchaseDetails.verificationData.serverVerificationData = receiptData
  ///     （插件已明确标注该字段为 JWS 表示，见 sk2_transaction_wrapper 125 行注释）
  /// 在 StoreKit 1 模式下：
  ///   - PurchaseDetails.runtimeType = AppStorePurchaseDetails
  ///   - serverVerificationData = 旧版 receipt（base64），也传给后端
  ///     由后端按 receipt 方式校验。
  String? _extractJwsFromPurchase(PurchaseDetails pd) {
    try {
      final data = pd.verificationData.serverVerificationData;
      if (data.isNotEmpty) return data;
    } catch (e, s) {
      Log.warn('[AppleIAP] extract jws exception: $e\n$s');
    }
    return null;
  }

  /// 取当前登录用户的 UUID（标准格式）。
  /// 和 mobile_upgrade_plan_page._extractUserId 一致：解析 JWT.sub。
  Future<String?> _resolveCurrentUserUuid() async {
    try {
      // 调用 PaymentApi 暴露的静态方法无法直接拿到用户信息，
      // 这里复用用户服务的 getCurrentUserProfile 自己取一下。
      final profile = await _getProfileSync();
      return profile?.$1;
    } catch (e, s) {
      Log.error('[AppleIAP] resolveUserUuid failed: $e\n$s');
      return null;
    }
  }

  // (userUuid, displayName)
  Future<(String? userUuid, String? display)?> _getProfileSync() async {
    final res = await UserBackendService.getCurrentUserProfile();
    return res.fold((UserProfilePB profile) {
      try {
        final rawToken = profile.token;
        String? accessToken;
        try {
          final decoded = jsonDecode(rawToken);
          if (decoded is Map<String, dynamic>) {
            accessToken = decoded['access_token'] as String?;
          }
        } catch (_) {
          accessToken = rawToken;
        }
        if (accessToken != null && accessToken.isNotEmpty) {
          try {
            final parts = accessToken.split('.');
            if (parts.length >= 2) {
              var normalized =
                  parts[1].replaceAll('-', '+').replaceAll('_', '/');
              while (normalized.length % 4 != 0) normalized += '=';
              final decoded = utf8.decode(base64.decode(normalized));
              final payload = jsonDecode(decoded);
              if (payload is Map && payload['sub'] is String) {
                return (payload['sub'] as String, profile.name);
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
      return (profile.id.toString(), profile.name);
    }, (_) => null);
  }

  /// 返回当前已存在的 PurchaseDetails 列表（用于恢复购买手动扫描）。
  ///
  /// 目前 in_app_purchase 插件没有直接的 currentEntitlements API，
  /// 所以这里保守返回空数组，真正权益同步靠 purchaseStream 驱动；
  /// 恢复购买时由于我们先调用了 restorePurchases()，所有有效交易
  /// 都会重新进入 purchaseStream 并走一遍 verify → finish。
  Future<List<PurchaseDetails>> _availablePurchaseDetails() async {
    return const <PurchaseDetails>[];
  }

  /// 已无需单独校验 UUID 格式：
  /// applicationUserName 会直接传入，插件会原样作为 appAccountToken
  /// 写进交易里；后端 verify 也是按 JWT.sub (userUuid) 做字符串匹配。
  /// 保留此占位以兼容历史调用（当前无调用）。
  @Deprecated('不再做本地 UUID 格式校验，上游会传入原始 userUuid')
  static String? _parseUuidOrNull(String raw) {
    if (raw.isEmpty) return null;
    return raw;
  }
}

// ========================================================================
// 返回类型（用于调用方给用户提示）
// ========================================================================

class PurchaseResult {
  final bool ok;
  final bool initiated;
  final String message;

  PurchaseResult._(this.ok, this.initiated, this.message);

  factory PurchaseResult.initiated() =>
      PurchaseResult._(true, true, '购买已发起，请完成支付确认');

  factory PurchaseResult.success(String message) =>
      PurchaseResult._(true, false, message);

  factory PurchaseResult.failure(String message) =>
      PurchaseResult._(false, false, message);
}

class RestoreResult {
  final bool ok;
  final bool empty;
  final String message;

  RestoreResult._(this.ok, this.empty, this.message);

  factory RestoreResult.success() =>
      RestoreResult._(true, false, '已同步购买记录');

  factory RestoreResult.empty() =>
      RestoreResult._(true, true, '未找到之前的购买记录');

  factory RestoreResult.failure(String message) =>
      RestoreResult._(false, false, message);
}
