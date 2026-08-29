import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
// ignore: implementation_imports
import 'package:in_app_purchase_storekit/src/store_kit_2_wrappers/sk2_product_wrapper.dart';
import 'package:toastification/toastification.dart';

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

  // -----------------------------------------------------------------
  // 用户交互 vs 启动补单的区分标记
  // -----------------------------------------------------------------
  //
  // 启动后 purchaseStream 会投递 StoreKit 遗留的"未 finish 交易"，
  // 此时可能：
  //   a) 用户 token 还没恢复 → userUuid 为空 → 误弹"缺少用户信息"
  //   b) 交易已是历史数据，verify 可能异常 → 误弹"验证失败"
  //   c) 用户早就开通了订阅 → 重复触发 onPaymentSuccess → 重复弹
  //      "成功升级到高级版"
  // 这些都是"后台自动补单"场景，不应该打扰用户。
  //
  // 只有当用户显式：
  //   1) 点击购买（purchaseProduct），或
  //   2) 手动恢复（restorePurchasesForUser）
  // 之后的 Stream 事件才是"用户主动触发"，此时才弹 toast / overlay。
  //
  // 我们用一个 token 记录"最近一次用户主动触发的时间戳"，
  // 事件若在该时间戳之前（或太久远）就按"静默补单"处理：
  //   - 错误不弹 toast
  //   - verify 成功不弹 UpgradeSuccessOverlay（但仍 finish、仍刷新）
  // -----------------------------------------------------------------
  int _lastUserActionTimestamp = 0;

  /// 一笔交易事件距离用户主动点击购买超过这个阈值，视为启动/历史
  /// 交易自动补单，按静默模式处理。默认 10 分钟。
  static const int _silentGraceMs = 10 * 60 * 1000;

  bool _isSilentMode() {
    if (_lastUserActionTimestamp == 0) return true; // 从未点过购买 → 启动补单
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - _lastUserActionTimestamp > _silentGraceMs;
  }

  /// 标记一次"用户主动操作"，后续 Stream 事件按有 UI 反馈处理。
  void _markUserAction() {
    _lastUserActionTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

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

    // ⚠️  不要在此处调用 _iap.restorePurchases()。
    //
    // 它会强制把用户历史上所有购买过的商品（包括已 finish、已续费多
    // 次的）全部以 PurchaseStatus.restored 重新投递到 Stream，导致：
    //   1) 对已完成交易重复调 /api/payment/apple/verify → 重复弹
    //      UpgradeSuccessOverlay（"成功升级到高级版"）
    //   2) 沙箱环境遗留脏数据 → 误弹"验证失败"
    //
    // 真正需要补的"未 finish 交易"，StoreKit 会通过
    // purchaseStream 自动投递，不需要 restorePurchases() 触发。
    // 用户手动"恢复购买"时走 restorePurchasesForUser()，那里会
    // 主动调一次 _iap.restorePurchases()。

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

  /// 发起苹果内购购买（用户主动点击购买按钮）。
  ///
  /// 参数：
  ///   [productId]    由 [buildAppleProductId] 拼接得到，必须与
  ///                  App Store Connect 中的 Product ID 一致
  ///   [userUuid]     标准 UUID（JWT sub 字段），会被放进
  ///                  SK2ProductPurchaseOptions.appAccountToken（红线 1）
  ///
  /// 顺序：
  ///   SK2Product.purchase() → **同步等待用户在系统弹窗确认/取消**
  ///   → 返回 success / userCancelled / pending
  ///   → Stream 异步处理 verify → 成功才 finish → 刷新订阅
  ///
  /// 返回值：
  ///   * PurchaseResult.success  → 用户扣款确认（后续异步 verify + overlay）
  ///   * PurchaseResult.failure  → 用户取消 / 参数错误 / 插件异常
  ///                               （message 以"购买已取消"开头表示取消）
  ///   * PurchaseResult.initiated → pending（Ask to Buy 等场景，少用）
  ///
  /// **保证**：此方法返回时，苹果系统支付窗已经关闭，调用方 finally
  /// 里的 setState(isProcessingPayment=false) 会可靠解除「确认协议
  /// 开通」按钮的 loading。
  Future<PurchaseResult> purchaseProduct({
    required String productId,
    required String userUuid,
  }) async {
    // 🎯 用户主动操作，后续 Stream 事件启用 toast / overlay 反馈
    _markUserAction();

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

    // 2) 直接调用 StoreKit 2 原生 SK2Product.purchase()。
    //    🔑  关键：它返回 SK2ProductPurchaseResult（success / userCancelled
    //       / pending），是**同步等待苹果系统支付窗关闭**的——这正是
    //       我们用来解除 UI loading 的可靠信号。
    //
    //    Flutter 的 InAppPurchase.buyNonConsumable 故意丢弃了这个
    //    同步结果（只 return true/false），导致之前只能靠
    //    purchaseStream 做跨线程分发，存在竞态 & 监听器未 attach 时
    //    丢 canceled 事件的风险。这里直接用底层 SK2 API 解决。
    try {
      final options = SK2ProductPurchaseOptions(appAccountToken: userUuid);
      final SK2ProductPurchaseResult result = await SK2Product.purchase(
        productId,
        options: options,
      );
      Log.info('[AppleIAP] SK2Product.purchase result=$result, '
          'product=$productId, appAccountToken=$userUuid');

      switch (result) {
        case SK2ProductPurchaseResult.success:
          // ✅ 用户已在系统弹窗里确认扣款（实际是"成功触发交易创建"）。
          //    真正的 verify → finish → UpgradeSuccessOverlay 会在
          //    purchaseStream 监听器里异步执行（三条红线严格遵守）。
          return PurchaseResult.success('购买发起成功');

        case SK2ProductPurchaseResult.userCancelled:
          // ❌ 用户在系统弹窗点了「取消」。
          //    此处直接给调用方返回 failure 带特殊前缀"购买已取消"，
          //    调用方 finally 会立即 setState(false) 解除 loading。
          //    PurchaseStream 的 canceled 分支仍然会独立弹一个 info
          //    toast，调用方对这个前缀做了过滤避免重复 toast。
          return PurchaseResult.failure('购买已取消');

        case SK2ProductPurchaseResult.pending:
          // ⏳ 需家长批准（Ask to Buy）等场景。认为流程结束，解除
          //    loading，提示用户等批准结果（会通过 purchaseStream
          //    异步推到 purchased / restored 再处理）。
          return PurchaseResult.initiated();
      }
    } catch (e, s) {
      Log.error('[AppleIAP] SK2Product.purchase exception: $e\n$s');
      return PurchaseResult.failure('支付失败：${e.toString()}');
    }
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
    // 🎯 用户主动点"恢复购买"，后续 Stream 事件启用 toast / overlay 反馈
    _markUserAction();

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
    // 🤫 启动补单 vs 用户主动点击购买：
    //    _isSilentMode() 为 true 时只记日志、不打扰用户。
    final silent = _isSilentMode();
    if (silent) {
      Log.info('[AppleIAP] stream event — silent-mode (startup/background '
          'retry, no UI feedback)');
    }

    for (final PurchaseDetails pd in purchaseDetailsList) {
      Log.info('[AppleIAP] stream event — productId=${pd.productID}, '
          'status=${pd.status}, purchaseID=${pd.purchaseID}, '
          'pendingComplete=${pd.pendingCompletePurchase}, silent=$silent');

      switch (pd.status) {
        case PurchaseStatus.pending:
          // 无需 finish
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // 真正的 verify / finish / overlay。
          // ⚠️  UI loading 的解除已经在 purchaseProduct() 同步返回时
          //     通过 finally setState 做过了，这里不再重复控制按钮
          //     状态（严格"单一责任"：purchaseProduct 同步返回→关闭
          //     loading；Stream 异步→ verify & 权益开通）。
          await _handleVerifiedPurchase(pd, silent: silent);
          break;
        case PurchaseStatus.error:
          Log.error('[AppleIAP] PurchaseStatus.error: ${pd.error}');
          final errMsg = pd.error?.message ?? '未知错误';
          // silent=false 且 purchaseProduct 同步返回未覆盖到的分支
          // （如自动续费失败）才弹 error toast。
          if (!silent) {
            showToastNotification(
              message: '购买失败：$errMsg',
              type: ToastificationType.error,
            );
          }
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
          // 取消事件：不做 UI 反馈 — purchaseProduct 同步返回时已经把
          // UI loading 解除了。启动补单的 canceled 也静默。
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
  /// [silent] = true 时表示此交易来自"启动自动补单 / 历史重放"，不
  /// 打扰用户（不弹 toast，不触发 UpgradeSuccessOverlay）；但
  /// **红线仍严格执行**：verify 成功才 finish，失败不 finish（下次
  /// 启动自动重试）。
  ///
  /// 失败 / 网络异常 → **不 completePurchase** → 苹果下次启动
  /// 再通过 purchaseStream 重发 → 我们再次走 verify。
  /// apple/verify 接口是幂等的（同一苹果交易号返回原订单），所以
  /// 重复执行没有问题。
  Future<void> _handleVerifiedPurchase(
    PurchaseDetails pd, {
    required bool silent,
  }) async {
    final jws = _extractJwsFromPurchase(pd);
    final purchaseId = pd.purchaseID ?? '';

    if (jws == null || jws.isEmpty) {
      Log.error('[AppleIAP] handleVerifiedPurchase: no jwsRepresentation, '
          'productId=${pd.productID}, purchaseID=$purchaseId, silent=$silent');
      if (!silent) {
        showToastNotification(
          message: '支付验证异常：无法获取交易凭证，请稍后重试或联系客服',
          type: ToastificationType.error,
        );
      }
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
      Log.error('[AppleIAP] userUuid unavailable, skip verify, '
          'purchaseID=$purchaseId, silent=$silent');
      // 🤫 静默模式（典型：启动时 token 还没恢复）不弹 toast，StoreKit
      //    下次启动会再投递，届时用户可能已经登录了。
      if (!silent) {
        showToastNotification(
          message: '无法获取用户信息，请重新登录后重试',
          type: ToastificationType.error,
        );
      }
      // 不 finish，等用户登录后再触发 restorePurchases 补单
      return;
    }

    final verify = await PaymentApi.appleVerify(
      userInfo: userUuid,
      transaction: jws,
    );

    // 从后端返回的 data 中提取 planCode，作为 onPaymentSuccess 的 fallback。
    // SubscriptionSuccessListenable 会先尝试从服务端重新拉订阅（更准确，
    // 考虑跨设备续费/合并订单等情况）；拉取失败时会退回到 fallbackPlan。
    // 即便在最坏情况下（两次都取不到），_notifyWithPlan 也会跳过通知，
    // 所以传 data 里的 planCode 只做额外保证。
    final data = verify.fold((m) => m, (_) => null);
    final fallbackPlan = (data?['planCode'] as String?) ??
        (data?['plan_code'] as String?);

    if (verify.isFailure) {
      final err = verify.fold((_) => null, (e) => e);
      final errMsg = err?.msg ?? '验证失败';
      Log.error('[AppleIAP] verify failed — productId=${pd.productID}, '
          'purchaseID=$purchaseId, msg=$errMsg, silent=$silent');
      // 🔴 红线 2：verify 失败，一定不要 completePurchase。
      // 下次启动 purchaseStream 会重新交付此交易，再尝试一次。
      if (!silent) {
        showToastNotification(
          message: '支付验证失败：$errMsg',
          type: ToastificationType.error,
        );
      }
      return;
    }

    Log.info('[AppleIAP] verify success, productId=${pd.productID}, '
        'purchaseID=$purchaseId, fallbackPlan=$fallbackPlan, silent=$silent');

    // verify 成功 → 先 finish（红线 2），无论是否静默都必须 finish。
    if (pd.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(pd);
      } catch (e, s) {
        Log.error('[AppleIAP] completePurchase failed: $e\n$s');
      }
    }

    // 🤫 静默模式（启动补单 / 历史交易重放）：
    //    用户早就看到过"开通成功"的提示了，这里只刷新订阅状态，
    //    不再触发 onPaymentSuccess → UpgradeSuccessOverlay。
    if (silent) {
      Log.info('[AppleIAP] silent-mode: skipping onPaymentSuccess (no '
          'UpgradeSuccessOverlay)');
      return;
    }

    // 用户主动购买 / 恢复购买场景：调 onPaymentSuccess(planCode) →
    // SubscriptionSuccessListenable._fetchAndNotify() 从服务端拉取
    // 最新 planCode → notifyListeners() → desktop_home_screen 展示
    // UpgradeSuccessOverlay（图片+文案弹窗），同时 SettingsDialog
    // 自动关闭。
    try {
      getIt<SubscriptionSuccessListenable>().onPaymentSuccess(fallbackPlan);
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

/// 用户关闭苹果支付弹窗后的**最终事件**（与 verify 成功与否无关）。
///
/// 用于调用方 await 到一个"可以停止 loading"的时刻。
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
