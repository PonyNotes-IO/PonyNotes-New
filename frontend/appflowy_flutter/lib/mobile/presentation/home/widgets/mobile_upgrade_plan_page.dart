import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/payment/payment_util.dart';
import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'mobile_recharge_records_page.dart';
import 'mobile_upgrade_plan_card.dart';

class _PlanConfig {
  const _PlanConfig(
    this.id,
    this.name,
    this.priceMonthly,
    this.priceAnnual,
    this.storage,
    this.workspaces,
    this.aiQuota,
    this.priceColor,
    this.priceBgColor,
  );

  final String id;
  final String name;
  final double priceMonthly;
  final double priceAnnual;
  final String storage;
  final String workspaces;
  final String aiQuota;
  final Color priceColor;
  final Color priceBgColor;
}

enum _BillingPeriod { monthly, yearly }

String _formatStorage(int? cloudStorageGb) {
  if (cloudStorageGb == null) return '';
  if (cloudStorageGb >= 1024) {
    return '${(cloudStorageGb / 1024).toStringAsFixed(1)}TB';
  } else {
    return '${cloudStorageGb}GB';
  }
}

class MobileUpgradePlanPage extends StatefulWidget {
  const MobileUpgradePlanPage({
    super.key,
    required this.subscriptionInfo,
    required this.workspaceId,
  });

  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final String workspaceId;

  @override
  State<MobileUpgradePlanPage> createState() => _MobileUpgradePlanPageState();
}

class _MobileUpgradePlanPageState extends State<MobileUpgradePlanPage> {
  _BillingPeriod _billingPeriod = _BillingPeriod.monthly;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildAppBar(theme),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _UpgradePlanBody(
                subscriptionInfo: widget.subscriptionInfo,
                billingPeriod: _billingPeriod,
                onBillingPeriodChanged: (period) {
                  setState(() => _billingPeriod = period);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(AppFlowyThemeData theme) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: FlowySvg(
                FlowySvgs.mobile_return_s,
                size: const Size(7, 12),
                color: theme.iconColorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '会员升级',
                style: theme.textStyle.heading4.standard(
                  color: theme.textColorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _UpgradePlanBody extends StatefulWidget {
  const _UpgradePlanBody({
    required this.subscriptionInfo,
    required this.billingPeriod,
    required this.onBillingPeriodChanged,
  });

  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final _BillingPeriod billingPeriod;
  final void Function(_BillingPeriod) onBillingPeriodChanged;

  @override
  State<_UpgradePlanBody> createState() => _UpgradePlanBodyState();
}

class _RemotePlanInfo {
  final int? cloudStorageGb;
  final int? collaborativeWorkspaceLimit;
  final int? aiChatCountPerMonth;

  const _RemotePlanInfo({
    this.cloudStorageGb,
    this.collaborativeWorkspaceLimit,
    this.aiChatCountPerMonth,
  });

  factory _RemotePlanInfo.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return _RemotePlanInfo(
      cloudStorageGb: parseInt(json['cloud_storage_gb']),
      collaborativeWorkspaceLimit:
          parseInt(json['collaborative_workspace_limit']),
      aiChatCountPerMonth: parseInt(json['ai_chat_count_per_month']),
    );
  }
}

class _UpgradePlanBodyState extends State<_UpgradePlanBody> {
  int _selectedPlanIndex = 2;
  bool _isProcessingPayment = false;
  PaymentMethod? _selectedPaymentMethod;
  Map<String, _RemotePlanInfo> _remotePlanInfos = {};

  static const _plans = [
    _PlanConfig('student', '学生版', 5.0, 50.0, '1GB', '3个', '50次/月',
        Color(0xFFFFFFFF), Color(0xFF2EACB2),),
    _PlanConfig('standard', '标准版', 9.0, 99.0, '10GB', '5个工作区', '300次/月',
        Color(0xFFF9D8A7), Color(0xFF343543),),
    _PlanConfig('pro', '专业版', 15.0, 158.0, '50GB', '10个工作区', '1200次/月',
        Color(0xFFFFE4C4), Color(0xFF371A0D),),
    _PlanConfig('premium', '高级版', 29.0, 298.0, '150GB', '18个工作区', '3000次/月',
        Color(0xFFADD8E6), Color(0xFF1E3A5F),),
  ];

  @override
  void initState() {
    super.initState();
    _loadRemotePlanInfo();
  }

  Future<void> _loadRemotePlanInfo() async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('订阅计划接口 baseUrl 为空，使用本地默认配置');
        return;
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold((user) => user, (_) => null);
      if (userProfile == null) {
        Log.warn('无法获取用户信息，使用本地默认配置');
        return;
      }

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
        Log.warn('订阅计划接口无法获取 access_token，使用本地默认配置');
        return;
      }

      final uri = Uri.parse(baseUrl).replace(path: 'api/subscription/plans');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        Log.warn(
            '订阅计划接口返回非 200: ${response.statusCode}, body: ${response.body}');
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        Log.warn('订阅计划接口返回错误 code=$code');
        return;
      }

      final data = decoded['data'];
      if (data is! List) {
        Log.warn('订阅计划接口 data 非数组');
        return;
      }

      final Map<String, _RemotePlanInfo> remoteInfos = {};
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final planCode = item['plan_code'] as String?;
        if (planCode == null || planCode.isEmpty) continue;
        remoteInfos[planCode.toLowerCase()] = _RemotePlanInfo.fromJson(item);
      }

      if (mounted) {
        setState(() => _remotePlanInfos = remoteInfos);
      }
    } catch (e) {
      Log.error('加载远程计划信息失败: $e');
    }
  }

  _PlanConfig _getPlanWithRemoteInfo(_PlanConfig plan) {
    final remoteInfo = _remotePlanInfos[plan.id.toLowerCase()] ??
        _remotePlanInfos[plan.name.toLowerCase()];

    if (remoteInfo == null) return plan;

    final storage = remoteInfo.cloudStorageGb != null
        ? _formatStorage(remoteInfo.cloudStorageGb)
        : plan.storage;
    final workspaces = remoteInfo.collaborativeWorkspaceLimit != null
        ? '${remoteInfo.collaborativeWorkspaceLimit}个工作区'
        : plan.workspaces;
    final aiQuota = remoteInfo.aiChatCountPerMonth != null
        ? '${remoteInfo.aiChatCountPerMonth}次/月'
        : plan.aiQuota;

    return _PlanConfig(
      plan.id,
      plan.name,
      plan.priceMonthly,
      plan.priceAnnual,
      storage,
      workspaces,
      aiQuota,
      plan.priceColor,
      plan.priceBgColor,
    );
  }

  Future<void> _confirmAndPay() async {
    final plan = _plans[_selectedPlanIndex];
    final isYearly = widget.billingPeriod == _BillingPeriod.yearly;
    final billingType = isYearly ? 'yearly' : 'monthly';
    final price = isYearly ? plan.priceAnnual : plan.priceMonthly;

    setState(() => _isProcessingPayment = true);

    try {
      final userProfile = await UserBackendService.getCurrentUserProfile();
      final userUuid = userProfile.fold((p) => p.id.toString(), (_) => '');

      final paymentMethods = PaymentPlatformSupport.getAvailableMethods();
      if (paymentMethods.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前平台暂不支持支付')),
          );
        }
        return;
      }

      PaymentMethod paymentMethod;
      if (_selectedPaymentMethod != null &&
          paymentMethods.contains(_selectedPaymentMethod)) {
        paymentMethod = _selectedPaymentMethod!;
      } else {
        if (Platform.isIOS) {
          paymentMethod = PaymentMethod.applePay;
        } else {
          final alipayIndex = paymentMethods.indexOf(PaymentMethod.alipay);
          if (alipayIndex >= 0) {
            paymentMethod = PaymentMethod.alipay;
          } else {
            paymentMethod = paymentMethods.first;
          }
        }
        setState(() => _selectedPaymentMethod = paymentMethod);
      }

      Log.info('[MobileUpgradePlan] 支付方式: $paymentMethod, 平台: ${Platform.operatingSystem}');

      if (Platform.isIOS) {
        await _handleIOSPayment(paymentMethod, plan, price, billingType, userUuid);
      } else {
        await _handleAndroidPayment(paymentMethod, plan, price, billingType, userUuid);
      }
    } catch (e) {
      Log.error('[MobileUpgradePlan] 支付异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('支付异常: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  Future<void> _handleIOSPayment(
    PaymentMethod paymentMethod,
    _PlanConfig plan,
    double price,
    String billingType,
    String userUuid,
  ) async {
    Log.info('[MobileUpgradePlan] iOS 使用 Apple Pay 内购');

    final productId = _getProductId(plan.id, billingType);
    if (productId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂不支持该套餐的 Apple Pay 支付')),
        );
      }
      return;
    }

    final extra = <String, dynamic>{
      'productId': productId,
      'planId': plan.id,
      'billingType': billingType,
      'userInfo': userUuid,
    };

    final paymentResult = await PaymentUtil.pay(
      method: paymentMethod,
      amount: (price * 100).toInt(),
      currency: 'CNY',
      orderId: 'ios_${DateTime.now().millisecondsSinceEpoch}',
      extra: extra,
    );

    if (mounted) {
      if (paymentResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(paymentResult.message)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('支付失败: ${paymentResult.message}')),
        );
      }
    }
  }

  Future<void> _handleAndroidPayment(
    PaymentMethod paymentMethod,
    _PlanConfig plan,
    double price,
    String billingType,
    String userUuid,
  ) async {
    Log.info('[MobileUpgradePlan] Android 使用 $paymentMethod 支付');

    final paymentType = switch (paymentMethod) {
      PaymentMethod.wechatPay => PaymentType.wechatPay,
      PaymentMethod.alipay => PaymentType.alipay,
      _ => PaymentType.alipay,
    };

    final createRequest = PaymentCreateRequest(
      amount: price.toString(),
      paymentType: paymentType,
      userInfo: userUuid,
      productName: plan.name,
      planId: plan.id,
      billingType: billingType,
    );

    Log.info('[MobileUpgradePlan] 创建支付订单: plan=${plan.name}, price=$price, billingType=$billingType, paymentType=$paymentType');

    final orderResult = await PaymentApi.createPaymentOrder(createRequest);

    if (orderResult.isFailure) {
      final error = orderResult.fold((_) => null, (e) => e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建订单失败: ${error?.msg ?? '未知错误'}')),
        );
      }
      return;
    }

    final orderData = orderResult.fold((r) => r, (_) => null);
    if (orderData?.data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('订单数据为空')),
        );
      }
      return;
    }

    final orderNo = orderData!.data!.orderNo;
    Log.info('[MobileUpgradePlan] 订单创建成功: orderNo=$orderNo');

    final extra = <String, dynamic>{
      'payUrl': orderData.data?.payUrl,
    };

    final paymentResult = await PaymentUtil.pay(
      method: paymentMethod,
      amount: (price * 100).toInt(),
      currency: 'CNY',
      orderId: orderNo,
      extra: extra,
    );

    if (mounted) {
      if (paymentResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(paymentResult.message)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('支付失败: ${paymentResult.message}')),
        );
      }
    }
  }

  String? _getProductId(String planId, String billingType) {
    final productIds = <String, String>{
      'student_monthly': 'com.ponynotes.student.monthly',
      'student_yearly': 'com.ponynotes.student.yearly',
      'standard_monthly': 'com.ponynotes.standard.monthly',
      'standard_yearly': 'com.ponynotes.standard.yearly',
      'pro_monthly': 'com.ponynotes.pro.monthly',
      'pro_yearly': 'com.ponynotes.pro.yearly',
      'premium_monthly': 'com.ponynotes.premium.monthly',
      'premium_yearly': 'com.ponynotes.premium.yearly',
    };
    return productIds['${planId}_$billingType'];
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBillingToggle(theme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '手机 / 电脑 / 平板 均可使用',
                  style: theme.textStyle.body.standard(
                    color: theme.textColorScheme.secondary,
                  ).copyWith(fontSize: 12),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const MobileRechargeRecordsPage(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '充值记录',
                          style: theme.textStyle.body.standard(
                            color: theme.textColorScheme.secondary,
                          ).copyWith(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        FlowySvg(
                          FlowySvgs.top_up_records_s,
                          size: const Size(4, 8),
                          color: theme.iconColorScheme.secondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildUpgradePlanCards(),
          const SizedBox(height: 24),
          _buildPaymentMethodSelector(theme),
          const SizedBox(height: 16),
          _buildConfirmPayButton(theme),
          const SizedBox(height: 24),
          _buildBenefitIcons(),
        ],
      ),
    );
  }

  Widget _buildUpgradePlanCards() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (int i = 0; i < _plans.length; i++) ...[
            _buildPlanCard(_getPlanWithRemoteInfo(_plans[i]), i),
            if (i < _plans.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(_PlanConfig plan, int index) {
    return UpgradePlanCard(
      planName: plan.name,
      priceMonthly: '¥${plan.priceMonthly.toInt()}',
      priceAnnual: '¥${plan.priceAnnual.toInt()}',
      storage: plan.storage,
      workspaces: plan.workspaces,
      aiQuota: plan.aiQuota,
      priceColor: plan.priceColor,
      priceBgColor: plan.priceBgColor,
      priceColor2: index == 1 ? Colors.white : (index >= 2 ? const Color(0xFFF9D8A7) : null),
      isHighlighted: index == 2,
      isYearly: widget.billingPeriod == _BillingPeriod.yearly,
      isSelected: _selectedPlanIndex == index,
      onTap: () => setState(() => _selectedPlanIndex = index),
    );
  }

  Widget _buildBillingToggle(AppFlowyThemeData theme) {
    final isYearly = widget.billingPeriod == _BillingPeriod.yearly;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onBillingPeriodChanged(_BillingPeriod.monthly),
              child: Container(
                decoration: BoxDecoration(
                  color: !isYearly
                      ? (isDarkMode
                          ? const Color(0xFF3A3A3A)
                          : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !isYearly
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '月付',
                  style: theme.textStyle.body.standard(
                    color: !isYearly
                        ? theme.textColorScheme.primary
                        : theme.textColorScheme.secondary,
                  ).copyWith(fontWeight: !isYearly ? FontWeight.w600 : FontWeight.normal),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onBillingPeriodChanged(_BillingPeriod.yearly),
              child: Container(
                decoration: BoxDecoration(
                  color: isYearly
                      ? (isDarkMode
                          ? const Color(0xFF3A3A3A)
                          : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isYearly
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '年付',
                      style: theme.textStyle.body.standard(
                        color: isYearly
                            ? theme.textColorScheme.primary
                            : theme.textColorScheme.secondary,
                      ).copyWith(fontWeight: isYearly ? FontWeight.w600 : FontWeight.normal),
                    ),
                    if (isYearly) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '省15%',
                          style: theme.textStyle.body.standard(color: Colors.white).copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector(AppFlowyThemeData theme) {
    final paymentMethods = PaymentPlatformSupport.getAvailableMethods();
    if (paymentMethods.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_selectedPaymentMethod == null) {
      if (Platform.isIOS) {
        _selectedPaymentMethod = PaymentMethod.applePay;
      } else {
        final alipayIndex = paymentMethods.indexOf(PaymentMethod.alipay);
        if (alipayIndex >= 0) {
          _selectedPaymentMethod = PaymentMethod.alipay;
        } else {
          _selectedPaymentMethod = paymentMethods.first;
        }
      }
    }

    final methodNames = <PaymentMethod, String>{
      PaymentMethod.applePay: 'Apple Pay',
      PaymentMethod.wechatPay: '微信支付',
      PaymentMethod.alipay: '支付宝',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '支付方式',
          style: theme.textStyle.body
              .standard(color: theme.textColorScheme.primary)
              .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: paymentMethods.map((method) {
            final isSelected = _selectedPaymentMethod == method;
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedPaymentMethod = method),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDarkMode ? const Color(0xFF3A3A3A) : Colors.white)
                        : (isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF3800)
                          : (isDarkMode ? const Color(0xFF3A3A3A) : Colors.transparent),
                      width: isSelected ? 2 : 0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    methodNames[method] ?? method.name,
                    style: theme.textStyle.body.standard(
                      color: isSelected
                          ? theme.textColorScheme.primary
                          : theme.textColorScheme.secondary,
                    ).copyWith(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildConfirmPayButton(AppFlowyThemeData theme) {
    final plan = _plans[_selectedPlanIndex];
    final isYearly = widget.billingPeriod == _BillingPeriod.yearly;
    final price = isYearly ? plan.priceAnnual : plan.priceMonthly;
    final periodText = isYearly ? '/年' : '/月';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isProcessingPayment ? null : _confirmAndPay,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3800),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFF3800).withValues(alpha: 0.6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
            ),
            child: _isProcessingPayment
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    '确认协议并支付',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '开通前请确认《会员服务协议》',
          style: theme.textStyle.body.standard(
            color: theme.textColorScheme.secondary,
          ).copyWith(fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBenefitIcons() {
    final theme = AppFlowyTheme.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final benefits = [
      {'label': '小马AI', 'iconLight': FlowySvgs.m_rights_ai_xl, 'iconDark': FlowySvgs.md_rights_ai_xl},
      {'label': '小马日历', 'iconLight': FlowySvgs.m_rights_calender_xl, 'iconDark': FlowySvgs.md_rights_calender_xl},
      {'label': '云端同步', 'iconLight': FlowySvgs.m_rights_cloud_xl, 'iconDark': FlowySvgs.md_rights_cloud_xl},
      {'label': '小马收藏夹', 'iconLight': FlowySvgs.m_rights_collect_xl, 'iconDark': FlowySvgs.md_rights_collect_xl},
      {'label': '云端空间', 'iconLight': FlowySvgs.m_rights_storage_xl, 'iconDark': FlowySvgs.md_rights_storage_xl},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '获赠权益',
          style: theme.textStyle.body
              .standard(color: theme.textColorScheme.primary)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _BenefitCard(label: benefits[0]['label'] as String, icon: isDarkMode ? benefits[0]['iconDark'] as FlowySvgData : benefits[0]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
            const SizedBox(width: 8),
            Expanded(child: _BenefitCard(label: benefits[1]['label'] as String, icon: isDarkMode ? benefits[1]['iconDark'] as FlowySvgData : benefits[1]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
            const SizedBox(width: 8),
            Expanded(child: _BenefitCard(label: benefits[2]['label'] as String, icon: isDarkMode ? benefits[2]['iconDark'] as FlowySvgData : benefits[2]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _BenefitCard(label: benefits[3]['label'] as String, icon: isDarkMode ? benefits[3]['iconDark'] as FlowySvgData : benefits[3]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
            const SizedBox(width: 8),
            Expanded(child: _BenefitCard(label: benefits[4]['label'] as String, icon: isDarkMode ? benefits[4]['iconDark'] as FlowySvgData : benefits[4]['iconLight'] as FlowySvgData, isDarkMode: isDarkMode, theme: theme)),
          ],
        ),
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.label,
    required this.icon,
    required this.isDarkMode,
    required this.theme,
  });

  final String label;
  final FlowySvgData icon;
  final bool isDarkMode;
  final AppFlowyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderColorScheme.primary, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlowySvg(icon, size: const Size(32, 32), blendMode: null),
          Expanded(
            child: Text(
              label,
              style: theme.textStyle.body.standard(color: theme.textColorScheme.secondary).copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
