import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/workspace/application/payment/payment_util.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/identity_verification_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/email_binding_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/phone_change_dialog.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../generated/locale_keys.g.dart';
import '../../../../user/presentation/screens/legal_document_screen.dart';
import 'package:http/http.dart' as http;

enum PurchaseDurationOption {
  monthly,
  yearly,
}

class AccountManagementView extends StatefulWidget {
  const AccountManagementView({
    super.key,
    required this.userProfile,
    required this.workspaceId,
    required this.changeSelectedPage,
    this.currentSubscription,
    this.isLoadingCurrentSubscription = false,
  });

  final UserProfilePB userProfile;
  final String workspaceId;
  final void Function(SettingsPage page) changeSelectedPage;
  final CurrentSubscription? currentSubscription;
  final bool isLoadingCurrentSubscription;

  @override
  State<AccountManagementView> createState() => _AccountManagementViewState();
}

class _AccountManagementViewState extends State<AccountManagementView> {
  WorkspaceSubscriptionInfoPB? _subscriptionInfo;
  bool _isLoadingSubscription = true;
  bool _isLoadingPlans = true;
  WorkspacePlanPB? _selectedPlan;
  PurchaseDurationOption _selectedDuration = PurchaseDurationOption.monthly;
  bool _agreedProtocols = false;
  Map<WorkspacePlanPB, _RemotePlan> _planConfigs = {};

  @override
  void initState() {
    super.initState();
    _loadSubscriptionInfo();
    _loadSubscriptionPlans();
  }

  bool get _isLoading => _isLoadingSubscription || _isLoadingPlans;

  Future<void> _loadSubscriptionInfo() async {
    setState(() {
      _isLoadingSubscription = true;
    });

    final result = await UserBackendService.getWorkspaceSubscriptionInfo(widget.workspaceId);

    result.fold(
      (info) {
        if (mounted) {
          setState(() {
            _subscriptionInfo = info;
            // 如果当前是免费版或者无版本信息，默认选中学生版
            // 如果不是免费版，就选中当前已经购买的版本
            if (info.plan == WorkspacePlanPB.FreePlan) {
              _selectedPlan = WorkspacePlanPB.StudentPlan;
            } else {
              _selectedPlan = info.plan;
            }
            _isLoadingSubscription = false;
          });
        }
      },
      (error) {
        Log.error('Failed to load subscription info: ${error.msg}');
        if (mounted) {
          setState(() {
            // 加载失败时，如果没有选中计划，默认选中学生版
            _selectedPlan ??= WorkspacePlanPB.StudentPlan;
            _isLoadingSubscription = false;
          });
        }
      },
    );
  }

  Future<void> _loadSubscriptionPlans() async {
    setState(() {
      _isLoadingPlans = true;
    });

    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('订阅计划接口 baseUrl 为空，跳过远程加载');
        setState(() {
          _isLoadingPlans = false;
        });
        return;
      }

      final rawToken = widget.userProfile.token;
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('订阅计划接口无法获取 access_token，使用本地默认配置');
        setState(() {
          _isLoadingPlans = false;
        });
        return;
      }

      final uri = Uri.parse(baseUrl).replace(path: '/api/subscription/plans');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        Log.warn('订阅计划接口返回非 200: ${response.statusCode}, body: ${response.body}');
        setState(() {
          _isLoadingPlans = false;
        });
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        final message = decoded['message'] as String? ?? 'unknown error';
        Log.warn('订阅计划接口返回错误 code=$code, message=$message');
        setState(() {
          _isLoadingPlans = false;
        });
        return;
      }

      final data = decoded['data'];
      if (data is! List) {
        Log.warn('订阅计划接口 data 非数组，使用本地默认配置');
        setState(() {
          _isLoadingPlans = false;
        });
        return;
      }

      final Map<WorkspacePlanPB, _RemotePlan> configs = {};
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final codeStr = item['plan_code'] as String? ?? '';
        final mappedPlan = _mapPlanCodeToPb(codeStr);
        if (mappedPlan == null) continue;
        configs[mappedPlan] = _RemotePlan.fromJson(item);
      }

      if (mounted) {
        setState(() {
          _planConfigs = configs;
          _isLoadingPlans = false;
        });
      }
    } catch (e, stackTrace) {
      Log.error('订阅计划接口请求异常: $e', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLoadingPlans = false;
        });
      }
    }
  }

  // 根据订阅计划返回对应的配置
  Map<String, dynamic> _getPlanConfig(WorkspacePlanPB? plan) {
    if (plan == null) return {};
    final remote = _planConfigs[plan];
    if (remote != null) {
      final monthly = remote.monthlyPriceYuan ?? 0.0;
      final yearly = remote.yearlyPriceYuan ?? monthly * 12;
      return {
        'title': remote.planNameCn.isNotEmpty ? remote.planNameCn : remote.planName,
        'price': '¥${_formatCurrency(monthly)}/月',
        'tag': remote.planNameCn,
        'monthlyPrice': monthly,
        'yearlyPrice': yearly,
      };
    }
    switch (plan) {
      case WorkspacePlanPB.FreePlan:
        return {};
      case WorkspacePlanPB.StudentPlan:
        return {};
      case WorkspacePlanPB.StandardPlan:
        return {};
      case WorkspacePlanPB.TeamPlan:
        return {};
      default:
        return {};
    }
  }

  WorkspacePlanPB? get _effectivePlan {
    final availablePlans = _planConfigs.keys.toList();
    if (availablePlans.isEmpty) return null;

    if (_selectedPlan != null && _planConfigs.containsKey(_selectedPlan)) {
      return _selectedPlan;
    }
    if (_subscriptionInfo != null &&
        _planConfigs.containsKey(_subscriptionInfo!.plan)) {
      return _subscriptionInfo!.plan;
    }
    return availablePlans.first;
  }

  double _getDurationPrice(PurchaseDurationOption option) {
    final config = _getPlanConfig(_effectivePlan);
    final key = option == PurchaseDurationOption.monthly
        ? 'monthlyPrice'
        : 'yearlyPrice';
    final value = config[key] as double?;
    if (value != null) {
      return value;
    }
    final monthly = (config['monthlyPrice'] as double?) ?? 0.0;
    return option == PurchaseDurationOption.monthly ? monthly : monthly * 12;
  }

  String _formatCurrency(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final hasPlans = _planConfigs.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: SettingsBody(
            title: "我的账户",
            headerTrailingBuilder: (_) => OutlinedRoundedButton(
              text: '充值记录',
              onTap: () => widget.changeSelectedPage(SettingsPage.rechargeRecords),
            ),
            children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (!hasPlans) ...[
                    const SizedBox(height: 20),
                    const Center(child: Text('暂无可用的会员计划')),
                    const SizedBox(height: 24),
                  ] else ...[
                      _buildPlanCards(context),
                      const VSpace(24),
                      _buildBenefitSection(context),
                      const VSpace(24),
                      _buildPurchaseDurationSection(context),
                      const VSpace(32),
                    ],
              _buildFeatureItem(context, '文档光标颜色', '购买', showArrow: true),
              _buildFeatureItem(
                context,
                'AI使用次数',
                _buildAiUsageSubtitle(),
                showArrow: true,
              ),
              GestureDetector(
                onTap: () => widget.changeSelectedPage(SettingsPage.userProfile),
                child: _buildFeatureItem(context, '个人资料', '', showArrow: true),
              ),
              GestureDetector(
                onTap: () => _showPhoneVerificationDialog(context),
                child: _buildFeatureItem(context, '绑定手机', '修改', showButton: true, buttonText: '修改'),
              ),
              GestureDetector(
                onTap: () => _showEmailVerificationDialog(context),
                child: _buildFeatureItem(context, '邮箱', '修改', showButton: true, buttonText: '修改'),
              ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: GestureDetector(
                onTap: () async {
                  await getIt<AuthService>().signOut();
                  await runAppFlowy();
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFFF6B47),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(theme.spacing.s),
                  ),
                  child: const Center(
                    child: FlowyText(
                      '退出登录',
                      fontSize: 16,
                      color: Color(0xFFFF6B47),
                    ),
                  ),
                ),
              ),
          ),
      ],
    );
  }

  Widget _buildPlanCards(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    // final currentPlan = _subscriptionInfo?.plan ?? WorkspacePlanPB.FreePlan;
    final selectedPlan = _effectivePlan;
    final plans = _planConfigs.entries
        .where((e) => e.value.isActive)
        .map((e) => e.key)
        .toList();

    if (selectedPlan == null || plans.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = theme.spacing.m;
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;

        // 根据可用宽度动态计算每行展示多少个卡片，避免尺寸溢出或过小
        const double minCardWidth = 80;
        int crossAxisCount = (maxWidth / (minCardWidth + spacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, plans.length + 1);

        final cardWidth = (maxWidth - spacing * (crossAxisCount - 1)) /
            crossAxisCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: plans.map((plan) {
        final config = _getPlanConfig(plan);
            // 当前版本暂未显示“当前套餐”标识，后续如需可使用 isCurrent 高亮
            // final isCurrent = plan == currentPlan;
            final isSelected = plan == selectedPlan;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPlan = plan;
                });
              },
              child: Container(
                width: cardWidth,
                decoration: BoxDecoration(
                  color: theme.surfaceColorScheme.layer01,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6B47)
                        : const Color(0xFFE9E9E9),
                    width: isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Stack(
                  children: [
                    // 左下角应用 Logo 水印
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Opacity(
                          opacity: 0.12,
                          child: FlowySvg(
                              FlowySvgs.pony_notes_logo_xl,
                              size: const Size(56, 56),
                              blendMode: isSelected ? null : BlendMode.srcATop,
                          ),
                        ),
                      ),
                    ),
                    // 右下角选中角标
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomRight: Radius.circular(6),
                        ),
                        child: Container(
                          width: 32,
                          height: 20,
                          color: isSelected
                              ? const Color(0xFFFF6B47)
                              : Colors.transparent,
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                    // 中间标题 + 价格
                    Center(
                      child: Column(
                        children: [
                          VSpace(16),
                          FlowyText(
                            config['title'] as String,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.textColorScheme.primary,
                          ),
                          const VSpace(4),
                          FlowyText(
                            config['price'] as String,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: theme.textColorScheme.primary,
                          ),
                          VSpace(16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBenefitSection(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final benefits = _buildBenefitsForSelectedPlan();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          '获赠权益',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.textColorScheme.primary,
        ),
        const VSpace(16),
        Row(
          children: [
            for (int i = 0; i < benefits.length; i++) ...[
              Expanded(
          child: Container(
            margin: EdgeInsets.only(
                    right: i == benefits.length - 1 ? 0 : theme.spacing.s,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FlowySvg(
                        benefits[i]['icon'] as FlowySvgData,
                        size: const Size(48, 48),
                        blendMode: null,
                ),
                const VSpace(8),
                FlowyText(
                        benefits[i]['label'] as String,
                  fontSize: 14,
                        color: theme.textColorScheme.primary,
                ),
              ],
            ),
          ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _buildBenefitsForSelectedPlan() {
    final plan = _effectivePlan;
    final config = plan != null ? _planConfigs[plan] : null;

    // 根据 cloudStorageGb 动态生成空间大小标签
    String _getStorageLabel() {
      final storageGb = config?.cloudStorageGb;
      if (storageGb == null || storageGb == -1) {
        return '无空间';
      } else if (storageGb == 0) {
        return '无限制空间';
      } else if (storageGb >= 1000) {
        // 大于等于1000GB，显示为TB
        final tb = (storageGb / 1000).toStringAsFixed(1);
        return '${tb}T空间';
      } else {
        return '${storageGb}GB空间';
      }
    }

    // 基础权益
    final base = <Map<String, dynamic>>[
      {'label': '小马AI', 'icon': FlowySvgs.icon_rights_ai_xl},
      {'label': '小马日历', 'icon': FlowySvgs.icon_rights_calendar_xl},
      {'label': '小马收藏夹', 'icon': FlowySvgs.icon_rights_collection_xl},
      {'label': '云端同步', 'icon': FlowySvgs.icon_rights_cloud_xl},
      {'label': _getStorageLabel(), 'icon': FlowySvgs.icon_rights_space_xl},
    ];

    return base;
  }

  Widget _buildInfoChip({
    required String label,
    required String value,
    required AppFlowyThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer02,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          FlowyText(
            label,
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
          const SizedBox(width: 6),
          FlowyText(
            value,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.textColorScheme.primary,
          ),
        ],
      ),
    );
  }

  String _buildAiUsageSubtitle() {
    final usage = widget.currentSubscription?.usage;
    final remaining = usage?.aiChatRemaining;
    if (remaining == null) {
      return '';
    }
    return '本月剩余$remaining次';
  }

  Widget _buildPurchaseDurationSection(BuildContext context) {
    if (_effectivePlan == null) {
      return const SizedBox.shrink();
    }
    final theme = AppFlowyTheme.of(context);
    final monthlyPrice = _getDurationPrice(PurchaseDurationOption.monthly);
    final yearlyPrice = _getDurationPrice(PurchaseDurationOption.yearly);
    final selectedPrice = _selectedDuration == PurchaseDurationOption.monthly
        ? monthlyPrice
        : yearlyPrice;

    final options = [
      {
        'type': PurchaseDurationOption.monthly,
        'title': '包月30天',
        'price': monthlyPrice,
      },
      {
        'type': PurchaseDurationOption.yearly,
        'title': '包年365天',
        'price': yearlyPrice,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          '选择购买时长',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.textColorScheme.primary,
        ),
        const VSpace(12),
        Row(
          children: options.map((option) {
            final type = option['type'] as PurchaseDurationOption;
            final isSelected = type == _selectedDuration;
            final price = option['price'] as double;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDuration = type;
                });
              },
              child: Container(
                margin: EdgeInsets.only(
                  right: option == options.last ? 0 : theme.spacing.s,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 30,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFFF3EC)
                      : theme.surfaceColorScheme.layer01,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6B47)
                        : const Color(0xFFE9E9E9),
                    width: 1.4,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      option['title'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected
                            ? const Color(0xFFFF6B47)
                            : theme.textColorScheme.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatCurrency(price)}元',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const VSpace(16),
        Row(
          children: [
            Checkbox(
              value: _agreedProtocols,
              onChanged: (value) {
                setState(() {
                  _agreedProtocols = value ?? false;
                });
              },
              activeColor: const Color(0xFFFF6B47),
            ),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                  ),
                  children: [
                    const TextSpan(text: "确认 "),
                    TextSpan(
                      text: "《会员协议》",
                      style: const TextStyle(
                        color: Color(0xFFF89575),
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LegalDocumentScreen(
                                title: LocaleKeys.sidebar_appName.tr() + LocaleKeys.legal_userAgreement.tr(),
                                content: LocaleKeys.legal_userAgreementContent.tr(),
                              ),
                            ),
                          );
                        },
                    ),
                    TextSpan(
                      text: "《${LocaleKeys.legal_privacyPolicy.tr()}》",
                      style: const TextStyle(
                        color: Color(0xFFF89575),
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LegalDocumentScreen(
                                title: LocaleKeys.legal_privacyPolicy.tr(),
                                content: LocaleKeys.legal_privacyPolicyContent.tr(),
                              ),
                            ),
                          );
                        },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const VSpace(8),
        Align(
          alignment: Alignment.centerRight,
          child: Opacity(
            opacity: _agreedProtocols ? 1 : 0.5,
            child: GestureDetector(
              onTap: _agreedProtocols
                  ? () => _handleUpgradePay(context, selectedPrice)
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B47),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '¥${_formatCurrency(selectedPrice)} 确认协议开通',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 升级按钮点击后的支付逻辑
  ///
  /// 当前阶段按照需求，传递「空订单号和金额」给支付工具类：
  /// - amount: 0
  /// - orderId: ''
  /// 后续会在这里对接后端下单接口，使用真实的订单号与金额。
  Future<void> _handleUpgradePay(BuildContext context, double selectedPrice) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final planConfig = _getPlanConfig(_effectivePlan);
    final remotePlan = _effectivePlan != null ? _planConfigs[_effectivePlan!] : null;
    final planId = remotePlan?.id;
    if (planId == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('无法获取计划ID，暂无法订阅'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 0. 先创建/更新订阅
    final subscribed = await _createOrUpdateSubscription(
      planId: planId,
      billingType: _selectedDuration == PurchaseDurationOption.monthly
          ? 'monthly'
          : 'yearly',
      scaffoldMessenger: scaffoldMessenger,
    );
    if (!subscribed) {
      return;
    }

    // 订阅成功后刷新设置页的订阅信息（存储用量等）
    if (context.mounted) {
      context.read<SettingsDialogBloc>().add(const SettingsDialogEvent.initial());
    }

    // 1. 根据当前平台获取可用支付方式（macOS: Apple Pay; Windows: 微信/支付宝）
    final methods = PaymentPlatformSupport.getAvailableMethods();
    if (methods.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('当前平台暂不支持支付功能'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 暂时默认选择第一个可用支付方式，后续可增加 UI 让用户选择
    final method = methods.first;

    // 2. 先调用后端创建支付订单接口
    final paymentType = switch (method) {
      PaymentMethod.applePay => PaymentType.applePay,
      PaymentMethod.wechatPay => PaymentType.wechatPay,
      PaymentMethod.alipay => PaymentType.alipay,
    };

    // 示例：amount 使用「元」金额，后端如需「分」可在服务器换算
    final createRequest = PaymentCreateRequest(
      amount: selectedPrice,
      paymentType: paymentType,
      productName: planConfig['title'] as String? ?? '会员订阅',
      // 这里暂时使用 workspaceId 作为 openId，后续如果有专门的 openId 可替换
      openId: widget.workspaceId,
      // 回调地址先占位，后端可按需要使用
      url: '',
      userInfo: <String, dynamic>{
        'userId': widget.userProfile.id.toString(),
        'name': widget.userProfile.name,
        'email': widget.userProfile.email,
      },
    );

    final orderResult = await PaymentApi.createPaymentOrder(createRequest);

    if (orderResult.isFailure) {
      final error = orderResult.fold((_) => null, (e) => e);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(error?.msg ?? '创建支付订单失败'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final order = orderResult.fold(
      (order) => order,
      (_) => null,
    );
    if (order == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('创建支付订单失败'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 3. 调用统一支付工具类（传递真实订单号和金额）
    final result = await PaymentUtil.pay(
      method: method,
      amount: (order.amount * 100).round(), // 转为整型，示例：单位分
      currency: 'CNY',
      orderId: order.orderId,
      extra: <String, dynamic>{
        'plan': planConfig['title'],
        'duration': _selectedDuration == PurchaseDurationOption.monthly ? 'monthly' : 'yearly',
        'displayPrice': selectedPrice,
        'order': order.raw,
      },
    );

    // 4. 根据支付结果提示用户
    if (result.success) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isNotEmpty ? result.message : '支付成功'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isNotEmpty ? result.message : '支付失败'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildFeatureItem(
    BuildContext context,
    String title,
    String subtitle, {
    bool showArrow = false,
    bool showButton = false,
    String buttonText = '',
  }) {
    final theme = AppFlowyTheme.of(context);
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
      child: Row(
        children: [
          Expanded(
            child: FlowyText(
              title,
              fontSize: 16,
              color: theme.textColorScheme.primary,
            ),
          ),
          if (subtitle.isNotEmpty && !showButton)
            FlowyText(
              subtitle,
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
          if (showButton)
            FlowyText(
              buttonText,
              fontSize: 14,
              color: theme.textColorScheme.secondary,
            ),
          if (showArrow)
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
        ],
      ),
    );
  }

  void _showPhoneVerificationDialog(BuildContext context) {
    // 调试：打印用户资料信息
    Log.info('用户资料 - email: ${widget.userProfile.email}, name: ${widget.userProfile.name}');
    
    // 从用户资料中获取手机号
    // 优先使用 phone 字段，如果没有则检查 email 字段
    String phoneNumber = '';
    
    if (widget.userProfile.hasPhone() && widget.userProfile.phone.isNotEmpty) {
      // 优先使用 phone 字段
      phoneNumber = widget.userProfile.phone;
      Log.info('从用户资料的 phone 字段获取到手机号: $phoneNumber');
    } else if (widget.userProfile.email.isNotEmpty && 
        !widget.userProfile.email.contains('@') &&
        Validator.isValidPhone(widget.userProfile.email)) {
      // 兼容旧数据：检查 email 字段是否包含手机号
      phoneNumber = widget.userProfile.email;
      Log.info('从用户资料的 email 字段获取到手机号: $phoneNumber');
    } else {
      Log.info('用户资料中没有有效的手机号，显示输入对话框');
      // 如果没有绑定手机号，显示提示让用户输入
      _showPhoneInputDialog(context);
      return;
    }
    
    // 保存外层的 context，避免在对话框关闭后访问失效的 context
    final outerContext = context;
        
    showDialog(
      context: context,
      builder: (dialogContext) => IdentityVerificationDialog(
        phoneNumber: phoneNumber,
        onVerificationComplete: () {
          // 身份验证成功后，打开更改手机号码对话框
          // 使用保存的外层 context
          _showPhoneChangeDialog(outerContext);
        },
      ),
    );
  }

  void _showPhoneInputDialog(BuildContext context) {
    final phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入手机号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入您要绑定的手机号码'),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                hintText: '请输入手机号',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入手机号'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              // 验证手机号格式
              if (!Validator.isValidPhone(phone)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入正确的手机号格式'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (context) => IdentityVerificationDialog(
                  phoneNumber: phone,
                  onVerificationComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('手机验证完成'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showPhoneChangeDialog(BuildContext context) {
    // 保存 ScaffoldMessenger 和 SettingsDialogBloc 的引用，避免在对话框关闭后访问 context
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final settingsBloc = context.read<SettingsDialogBloc>();
    
    showDialog(
      context: context,
      builder: (dialogContext) => PhoneChangeDialog(
        onChangeComplete: () async {
          // 更改完成后的回调
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('手机号更改成功'),
              duration: Duration(seconds: 2),
            ),
          );
          
          // 刷新用户资料（Rust 后端会同步从云端刷新）
          Log.info('📱 开始刷新用户资料...');
          final result = await UserBackendService.getCurrentUserProfile();
          result.fold(
            (newProfile) {
              Log.info('✅ 刷新后的用户资料:');
              Log.info('   - name: ${newProfile.name}');
              Log.info('   - email: ${newProfile.email}');
              final hasPhone = newProfile.hasPhone() && newProfile.phone.isNotEmpty;
              final phoneValue = hasPhone ? newProfile.phone : '(null)';
              Log.info('   - phone: $phoneValue');
              Log.info('   - phone.isEmpty: ${!hasPhone}');
              
              if (!hasPhone) {
                Log.error('⚠️ 警告：刷新后的用户资料中 phone 字段为空！');
                Log.error('   这可能是因为：');
                Log.error('   1. 云端数据库没有更新成功');
                Log.error('   2. 云端 API 返回的数据中没有 phone 字段');
                Log.error('   3. 前端 Rust 代码没有正确映射 phone 字段');
                Log.error('   4. 本地数据库没有保存 phone 字段');
              } else {
                Log.info('✅ phone 字段正常: ${newProfile.phone}');
              }
              
              // 通知 SettingsDialogBloc 更新用户资料
              settingsBloc.add(
                SettingsDialogEvent.didReceiveUserProfile(newProfile),
              );
            },
            (error) {
              Log.error('❌ 刷新用户资料失败: ${error.msg}');
            },
          );
        },
      ),
    );
  }

  void _showEmailVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EmailBindingDialog(
        onBindingComplete: () {
          // 绑定完成后的回调
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('邮箱绑定完成'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _createOrUpdateSubscription({
    required int planId,
    required String billingType,
    required ScaffoldMessengerState scaffoldMessenger,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('订阅接口 baseUrl 为空');
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('无法创建订阅：服务地址为空'),
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }

      final accessToken = _extractAccessToken(widget.userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('订阅接口缺少 access_token');
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('无法创建订阅：未登录或 token 失效'),
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }

      final uri = Uri.parse(baseUrl).replace(path: '/api/subscription/subscribe');
      final body = jsonEncode({
        'plan_id': planId,
        'billing_type': billingType,
      });

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        Log.warn('创建订阅失败: ${response.statusCode}, body: ${response.body}');
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('创建订阅失败：HTTP ${response.statusCode}'),
            duration: const Duration(seconds: 2),
          ),
        );
        return false;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        final msg = decoded['message'] as String? ?? '创建订阅失败';
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 2),
          ),
        );
        return false;
      }

      Log.info('订阅创建/更新成功: ${decoded['data']}');
      return true;
    } catch (e, stackTrace) {
      Log.error('创建订阅异常: $e', e, stackTrace);
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('创建订阅异常'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
  }

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      // 不是 JSON，直接返回
      return rawToken;
    }
    return null;
  }

  WorkspacePlanPB? _mapPlanCodeToPb(String code) {
    switch (code) {
      case 'free_local':
        return WorkspacePlanPB.FreePlan;
      case 'student':
        return WorkspacePlanPB.StudentPlan;
      case 'standard':
        return WorkspacePlanPB.StandardPlan;
      case 'team':
        return WorkspacePlanPB.TeamPlan;
      default:
        return null;
    }
  }
}

class _RemotePlan {
  const _RemotePlan({
    required this.id,
    required this.planCode,
    required this.planName,
    required this.planNameCn,
    required this.monthlyPriceYuan,
    required this.yearlyPriceYuan,
    required this.cloudStorageGb,
    required this.hasInbox,
    required this.hasMultiDeviceSync,
    required this.hasApiSupport,
    required this.versionHistoryDays,
    required this.aiChatCountPerMonth,
    required this.aiImageGenerationPerMonth,
    required this.hasShareLink,
    required this.hasPublish,
    required this.workspaceMemberLimit,
    required this.collaborativeWorkspaceLimit,
    required this.pagePermissionGuestEditors,
    required this.hasSpaceMemberManagement,
    required this.hasSpaceMemberGrouping,
    required this.isActive,
  });

  final int? id;
  final String planCode;
  final String planName;
  final String planNameCn;
  final double? monthlyPriceYuan;
  final double? yearlyPriceYuan;
  final int? cloudStorageGb;
  final bool hasInbox;
  final bool hasMultiDeviceSync;
  final bool hasApiSupport;
  final int? versionHistoryDays;
  final int? aiChatCountPerMonth;
  final int? aiImageGenerationPerMonth;
  final bool hasShareLink;
  final bool hasPublish;
  final int? workspaceMemberLimit;
  final int? collaborativeWorkspaceLimit;
  final int? pagePermissionGuestEditors;
  final bool hasSpaceMemberManagement;
  final bool hasSpaceMemberGrouping;
  final bool isActive;

  factory _RemotePlan.fromJson(Map<String, dynamic> json) {
    double? _parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final str = value.toString();
      return double.tryParse(str);
    }
    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return _RemotePlan(
      id: _parseInt(json['id']),
      planCode: json['plan_code'] as String? ?? '',
      planName: json['plan_name'] as String? ?? '',
      planNameCn: json['plan_name_cn'] as String? ?? '',
      monthlyPriceYuan: _parseDouble(json['monthly_price_yuan']),
      yearlyPriceYuan: _parseDouble(json['yearly_price_yuan']),
      cloudStorageGb: _parseInt(json['cloud_storage_gb']),
      hasInbox: json['has_inbox'] as bool? ?? false,
      hasMultiDeviceSync: json['has_multi_device_sync'] as bool? ?? false,
      hasApiSupport: json['has_api_support'] as bool? ?? false,
      versionHistoryDays: _parseInt(json['version_history_days']),
      aiChatCountPerMonth: _parseInt(json['ai_chat_count_per_month']),
      aiImageGenerationPerMonth: _parseInt(json['ai_image_generation_per_month']),
      hasShareLink: json['has_share_link'] as bool? ?? false,
      hasPublish: json['has_publish'] as bool? ?? false,
      workspaceMemberLimit: _parseInt(json['workspace_member_limit']),
      collaborativeWorkspaceLimit: _parseInt(json['collaborative_workspace_limit']),
      pagePermissionGuestEditors: _parseInt(json['page_permission_guest_editors']),
      hasSpaceMemberManagement:
          json['has_space_member_management'] as bool? ?? false,
      hasSpaceMemberGrouping:
          json['has_space_member_grouping'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  // 、、**字段说明：**
  // - `cloud_storage_gb`: -1表示无，0表示无限制，正数表示具体GB数
  // - `version_history_days`: -1表示无版本历史
  // - `ai_chat_count_per_month`: -1表示无限制
  // - `ai_image_generation_per_month`: -1表示无限制
  // - `workspace_member_limit`: -1表示无限制
  // - `collaborative_workspace_limit`: -1表示无限制，0表示仅限1个
  // - `page_permission_guest_editors`: -1表示无，0表示仅查看，正数表示可编辑的访客数量
}
