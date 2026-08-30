import 'dart:convert';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/presentation/screens/legal_document_screen.dart';
import 'package:appflowy/workspace/application/payment/apple_iap_service.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/payment/payment_util.dart';
import 'package:appflowy/workspace/application/settings/account/account_management_bloc.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';
import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'mobile_recharge_records_page.dart';

class MobileUpgradePlanPage extends StatefulWidget {
  const MobileUpgradePlanPage({
    super.key,
    required this.subscriptionInfo,
    required this.workspaceId,
    this.userProfile,
    this.currentSubscription,
  });

  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final String workspaceId;
  final UserProfilePB? userProfile;
  final CurrentSubscription? currentSubscription;

  @override
  State<MobileUpgradePlanPage> createState() => _MobileUpgradePlanPageState();
}

class _MobileUpgradePlanPageState extends State<MobileUpgradePlanPage> {
  String? _lastHandledPaymentResult;
  final List<TapGestureRecognizer> _gestureRecognizers = [];
  late final SubscriptionSuccessListenable _subscriptionSuccessListenable;
  late final VoidCallback _subscriptionSuccessListener;

  void _resetPaymentPromptDedup() {
    _lastHandledPaymentResult = null;
  }

  @override
  void initState() {
    super.initState();
    // 与桌面端 SettingsDialog / desktop_home_screen 保持一致：
    // 支付成功触发 SubscriptionSuccessListenable → 自动关闭移动
    // 会员页（如果是 push 进入的话），同时 desktop_home_screen 会
    // 在上层展示 UpgradeSuccessOverlay（浮层在所有路由之上，pop
    // 不影响 overlay 出现）。
    _subscriptionSuccessListenable = getIt<SubscriptionSuccessListenable>();
    _subscriptionSuccessListener = () {
      if (!mounted) return;
      Log.info('[MobileUpgradePlan] subscription success — closing page, '
          'message=${_subscriptionSuccessListenable.upgradeSuccessMessage}');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    };
    _subscriptionSuccessListenable.addListener(_subscriptionSuccessListener);
  }

  @override
  void dispose() {
    _subscriptionSuccessListenable
        .removeListener(_subscriptionSuccessListener);
    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    _gestureRecognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return BlocProvider<AccountManagementBloc>(
      create: (context) => AccountManagementBloc(
        workspaceId: widget.workspaceId,
        userProfile: widget.userProfile ?? UserProfilePB(),
        currentSubscription: widget.currentSubscription,
      )..add(const AccountManagementEvent.initial()),
      child: BlocConsumer<AccountManagementBloc, AccountManagementState>(
        listener: (context, state) {
          state.maybeWhen(
            orElse: () {},
            ready: (
              subscriptionInfo,
              planConfigs,
              selectedPlan,
              selectedDuration,
              selectedTab,
              agreedProtocols,
              isLoadingSubscription,
              isLoadingPlans,
              isProcessingPayment,
              error,
              paymentResult,
            ) {
              if (error != null && error.isNotEmpty) {
                showToastNotification(message: error);
              }
              if (paymentResult != null && paymentResult.isNotEmpty) {
                if (_lastHandledPaymentResult == paymentResult) {
                  return;
                }
                _lastHandledPaymentResult = paymentResult;
                showToastNotification(message: paymentResult);
                if (paymentResult.contains('成功')) {
                  _refreshSubscriptionInfo(context);
                }
              }
            },
          );
        },
        builder: (context, state) {
          return Scaffold(
            body: Stack(
              children: [
                _UpgradePlanBody(
                  workspaceId: widget.workspaceId,
                  userProfile: widget.userProfile,
                ),
                _buildAppBar(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  void _refreshSubscriptionInfo(BuildContext context) {
    try {
      final accountBloc = context.read<AccountManagementBloc>();
      if (!accountBloc.isClosed) {
        accountBloc.add(const AccountManagementEvent.loadSubscriptionInfo());
        accountBloc.add(const AccountManagementEvent.loadSubscriptionPlans());
      }
    } catch (e) {
      Log.warn('无法刷新 AccountManagementBloc: $e');
    }
  }

  Widget _buildAppBar(AppFlowyThemeData theme) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSpace(30),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: FlowySvg(
              FlowySvgs.mobile_return_s,
              size: const Size(7, 12),
              color: theme.iconColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradePlanBody extends StatefulWidget {
  const _UpgradePlanBody({
    required this.workspaceId,
    required this.userProfile,
  });

  final String workspaceId;
  final UserProfilePB? userProfile;

  @override
  State<_UpgradePlanBody> createState() => _UpgradePlanBodyState();
}

class _UpgradePlanBodyState extends State<_UpgradePlanBody> {
  bool _isProcessingPayment = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return BlocBuilder<AccountManagementBloc, AccountManagementState>(
      builder: (context, state) {
        return state.maybeWhen(
          initial: () => const Center(child: CircularProgressIndicator()),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error) => Center(
            child: Text('加载失败: ${error?.msg ?? '未知错误'}'),
          ),
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            final hasPlans = planConfigs.isNotEmpty;
            final isLoading = isLoadingSubscription || isLoadingPlans;

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      _buildUserProfile(theme, selectedDuration),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildBillingToggle(theme, selectedDuration),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '手机 / 电脑 / 平板 均可使用',
                            style: theme.textStyle.body
                                .standard(
                                  color: theme.textColorScheme.secondary,
                                )
                                .copyWith(fontSize: 12),
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
                                    style: theme.textStyle.body
                                        .standard(
                                          color:
                                              theme.textColorScheme.secondary,
                                        )
                                        .copyWith(fontSize: 12),
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
                            // iOS/macOS 专属：StoreKit 恢复购买
                            if (Platform.isIOS || Platform.isMacOS) ...[
                              const SizedBox(width: 20),
                              GestureDetector(
                                onTap: () async => _restoreApplePurchases(),
                                child: Text(
                                  '恢复购买',
                                  style: theme.textStyle.body
                                      .standard(
                                        color:
                                            theme.textColorScheme.secondary,
                                      )
                                      .copyWith(fontSize: 12),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (!hasPlans) ...[
                    const SizedBox(height: 20),
                    const Center(child: Text('暂无可用的会员计划')),
                    const SizedBox(height: 24),
                  ] else ...[
                   _buildUpgradePlanCards(
                          theme,
                          planConfigs,
                          selectedPlan,
                          selectedDuration,
                          subscriptionInfo,
                        ),
                    const SizedBox(height: 24),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: _buildAgreementActionRow(
                          context,
                          theme,
                          agreedProtocols,
                          isProcessingPayment || _isProcessingPayment,
                          subscriptionInfo,
                          planConfigs,
                          selectedPlan,
                          selectedDuration,
                        )),
                    const SizedBox(height: 24),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: _buildBenefitIcons(theme)),
                  ],
                ],
              ),
            );
          },
          orElse: () => const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildUserProfile(
      AppFlowyThemeData theme, PurchaseDurationOption selectedDuration) {
    const double avatarSize = 48;
    const double bgHeight = 180;
    final isYearly = selectedDuration == PurchaseDurationOption.yearly;
    final bgAsset = isYearly
        ? 'assets/images/setting/bg_setting_year.svg'
        : 'assets/images/setting/bg_setting_mouth.svg';

    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: bgHeight,
          child: SvgPicture.asset(
            bgAsset,
            fit: BoxFit.fill,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 80, left: 20),
          child: Row(
            children: [
              _buildAvatar(avatarSize),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _displayName,
                  style: theme.textStyle.heading2.standard(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : theme.textColorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _displayName {
    final userProfile = widget.userProfile;
    if (userProfile == null) return '小马AI笔记的用户';
    if (userProfile.name.isNotEmpty) return userProfile.name;
    if (userProfile.hasPhone() && userProfile.phone.isNotEmpty) {
      return userProfile.phone;
    }
    if (userProfile.email.isNotEmpty) return userProfile.email;
    return '小马AI笔记的用户';
  }

  Widget _buildAvatar(double size) {
    final userProfile = widget.userProfile;
    if (userProfile == null) return _buildDefaultAvatar(size);

    final iconUrl = userProfile.iconUrl;
    if (iconUrl.isEmpty) return _buildDefaultAvatar(size);

    final borderWidth = 1.0;
    final contentSize = size - borderWidth * 2;

    Widget avatarWidget;
    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(contentSize / 2),
        child: Image.network(
          iconUrl,
          width: contentSize,
          height: contentSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
        ),
      );
    } else {
      avatarWidget = ClipRRect(
        borderRadius: BorderRadius.circular(contentSize / 2),
        child: Image.file(
          File(iconUrl),
          width: contentSize,
          height: contentSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: borderWidth,
        ),
      ),
      child: Center(child: avatarWidget),
    );
  }

  Widget _buildDefaultAvatar(double size) {
    final borderWidth = 1.0;
    final contentSize = size - borderWidth * 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: borderWidth,
        ),
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(contentSize / 2),
          child: AFAvatar(
            name: _displayName,
            size: AFAvatarSize.s,
          ),
        ),
      ),
    );
  }

  Widget _buildBillingToggle(
    AppFlowyThemeData theme,
    PurchaseDurationOption selectedDuration,
  ) {
    final isYearly = selectedDuration == PurchaseDurationOption.yearly;
    return Row(
      children: [
        Expanded(
          child: _buildLeftTabItem(
            context: context,
            theme: theme,
            label: LocaleKeys.settings_billingPage_paidMonthlyMobile.tr(),
            selected: !isYearly,
            onTap: () => context.read<AccountManagementBloc>().add(
                const AccountManagementEvent.selectDuration(
                    PurchaseDurationOption.monthly)),
          ),
        ),
        Expanded(
          child: _buildRightTabItem(
            context: context,
            theme: theme,
            label: LocaleKeys.settings_billingPage_paidYearlyMobile.tr(),
            selected: isYearly,
            onTap: () => context.read<AccountManagementBloc>().add(
                const AccountManagementEvent.selectDuration(
                    PurchaseDurationOption.yearly)),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftTabItem({
    required BuildContext context,
    required AppFlowyThemeData theme,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const double tabHeight = 44;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: tabHeight,
        width: double.infinity,
        child: Stack(
          children: [
            if (selected)
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/images/setting/bg_setting_left_tab.svg',
                  fit: BoxFit.fill,
                ),
              ),
            SizedBox(
              height: tabHeight,
              width: double.infinity,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? const Color(0xFF8B4513)
                        : const Color(0xFF333333),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightTabItem({
    required BuildContext context,
    required AppFlowyThemeData theme,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const double tabHeight = 44;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: tabHeight,
        width: double.infinity,
        child: Stack(
          children: [
            if (selected)
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/images/setting/bg_setting_right_tab.svg',
                  fit: BoxFit.fill,
                ),
              ),
            SizedBox(
              height: tabHeight,
              width: double.infinity,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? const Color(0xFF8B4513)
                        : const Color(0xFF333333),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradePlanCards(
    AppFlowyThemeData theme,
    Map<WorkspacePlanPB, RemotePlan> planConfigs,
    WorkspacePlanPB? selectedPlan,
    PurchaseDurationOption selectedDuration,
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
  ) {
    final plans = planConfigs.entries
        .where((e) => e.value.isActive)
        .map((e) => e.key)
        .toList();

    plans.sort((a, b) {
      final order = {
        WorkspacePlanPB.FreePlan: 1,
        WorkspacePlanPB.StandPlan: 2,
        WorkspacePlanPB.ProPlan: 3,
        WorkspacePlanPB.HiclassPlan: 4,
      };
      return (order[a] ?? 999).compareTo(order[b] ?? 999);
    });

    final filteredPlans =
        plans.where((e) => e != WorkspacePlanPB.FreePlan).toList();
    if (filteredPlans.isNotEmpty) {
      plans.clear();
      plans.addAll(filteredPlans);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          const SizedBox(width: 12),
          for (int i = 0; i < plans.length; i++) ...[
            _buildPlanCard(
              theme,
              plans[i],
              planConfigs[plans[i]]!,
              plans[i] == selectedPlan,
              selectedDuration,
              subscriptionInfo,
            ),
            if (i < plans.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    AppFlowyThemeData theme,
    WorkspacePlanPB plan,
    RemotePlan config,
    bool isSelected,
    PurchaseDurationOption selectedDuration,
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final currentPlan = subscriptionInfo?.plan;
    final isBelowCurrent = plan.value < (currentPlan?.value ?? 0);

    final monthly = config.monthlyPriceYuan ?? 0.0;
    final yearly = config.yearlyPriceYuan ?? 0.0;
    final price =
        selectedDuration == PurchaseDurationOption.monthly ? monthly : yearly;
    final suffix =
        selectedDuration == PurchaseDurationOption.monthly ? '/月' : '/年';
    final priceText = '¥${formatCurrency(price)}$suffix';

    return GestureDetector(
      onTap: () {
        context.read<AccountManagementBloc>().add(
              AccountManagementEvent.selectPlan(plan),
            );
      },
      child: Opacity(
        opacity: isBelowCurrent ? 0.45 : 1.0,
        child: SizedBox(
          width: 160,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDarkMode
                      ? theme.surfaceColorScheme.layer02
                      : const Color(0xFFFFF7F2))
                  : theme.surfaceColorScheme.layer01,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : theme.borderColorScheme.primary,
                width: isSelected ? 1.6 : 1.0,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowyText(
                  (config.planNameCn?.isNotEmpty ?? false)
                      ? config.planNameCn!
                      : config.planName ?? '',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textColorScheme.primary,
                ),
                const SizedBox(height: 8),
                _buildPriceBox(theme, config, priceText, suffix),
                const SizedBox(height: 8),
                _buildFeatureRow(theme, isSelected, selectedDuration, config),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBox(
    AppFlowyThemeData theme,
    RemotePlan config,
    String priceText,
    String suffix,
  ) {
    final bgColor = colorPriceInit(config.planCode);
    final isStandard = config.planCode?.contains('stand') == true ||
        config.planCode?.contains('standard') == true;
    final textColor = isStandard ? Colors.white : const Color(0xFFF9D8A7);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: priceText.replaceAll(suffix, ''),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            suffix == '/月' ? '按月支付' : '按年支付',
            style: TextStyle(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    AppFlowyThemeData theme,
    bool isSelected,
    PurchaseDurationOption selectedDuration,
    RemotePlan config,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: FlowySvg(
                FlowySvgs.icon_plan_info_indicator_s,
                blendMode: null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText(
                  _initStorage(config.cloudStorageGb),
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                FlowyText(
                  "工作区限制${config.collaborativeWorkspaceLimit}个",
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                FlowyText(
                  "每月AI对话额度${config.aiChatCountPerMonth}次",
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgreementActionRow(
    BuildContext context,
    AppFlowyThemeData theme,
    bool agreedProtocols,
    bool isProcessing,
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
    Map<WorkspacePlanPB, RemotePlan> planConfigs,
    WorkspacePlanPB? selectedPlan,
    PurchaseDurationOption selectedDuration,
  ) {
    final enabled = agreedProtocols && !isProcessing;
    final effectivePlan = selectedPlan ?? subscriptionInfo?.plan;
    final config = effectivePlan != null ? planConfigs[effectivePlan] : null;

    if (config == null) {
      return const SizedBox.shrink();
    }

    final monthly = config.monthlyPriceYuan ?? 0.0;
    final yearly = config.yearlyPriceYuan ?? 0.0;
    final price =
        selectedDuration == PurchaseDurationOption.monthly ? monthly : yearly;
    final suffix =
        selectedDuration == PurchaseDurationOption.monthly ? '/月' : '/年';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: GestureDetector(
            onTap: enabled
                ? () => _confirmAndPay(
                      subscriptionInfo,
                      planConfigs,
                      effectivePlan!,
                      selectedDuration,
                    )
                : null,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: isProcessing
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        '确认协议开通',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: agreedProtocols,
              onChanged: (value) => context.read<AccountManagementBloc>().add(
                    AccountManagementEvent.setAgreedProtocols(value ?? false),
                  ),
              activeColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                  ),
                  children: [
                    const TextSpan(text: '升级前请确认 '),
                    TextSpan(
                      text: '《会员协议》',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: () {
                        final recognizer = TapGestureRecognizer()
                          ..onTap = () {
                            final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
                            final base_web_domain =
                                cloudEnv.appflowyCloudConfig.base_web_domain;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => LegalDocumentScreen(
                                  title: LocaleKeys.sidebar_appName.tr() +
                                      LocaleKeys.legal_userAgreement.tr(),
                                  url:
                                      '$base_web_domain/agreements/paidSubscription',
                                ),
                              ),
                            );
                          };
                        return recognizer;
                      }(),
                    ),
                    TextSpan(
                      text: '《${LocaleKeys.legal_privacyPolicy.tr()}》',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: () {
                        final recognizer = TapGestureRecognizer()
                          ..onTap = () {
                            final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
                            final base_web_domain =
                                cloudEnv.appflowyCloudConfig.base_web_domain;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => LegalDocumentScreen(
                                  title: LocaleKeys.legal_privacyPolicy.tr(),
                                  url: '$base_web_domain/privacy',
                                ),
                              ),
                            );
                          };
                        return recognizer;
                      }(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 从用户 token 中解析出 GoTrue 的用户 UUID（JWT 的 sub 字段），
  /// 如果解析失败，则回退为内部自增 ID（userProfile.id）。
  /// 与 AccountManagementBloc._getUserUuid() 逻辑保持一致。
  String _extractUserId(UserProfilePB profile) {
    final rawToken = profile.token;
    if (rawToken.isNotEmpty) {
      String? accessToken;
      try {
        final decoded = jsonDecode(rawToken);
        if (decoded is Map<String, dynamic>) {
          accessToken = decoded['access_token'] as String?;
        }
      } catch (_) {
        // 不是 JSON，直接当作 access_token
        accessToken = rawToken;
      }
      if (accessToken != null && accessToken.isNotEmpty) {
        try {
          final parts = accessToken.split('.');
          if (parts.length >= 2) {
            var normalized =
                parts[1].replaceAll('-', '+').replaceAll('_', '/');
            while (normalized.length % 4 != 0) {
              normalized += '=';
            }
            final decoded = utf8.decode(base64.decode(normalized));
            final payload = jsonDecode(decoded);
            if (payload is Map && payload['sub'] is String) {
              return payload['sub'] as String;
            }
          }
        } catch (_) {
          // JWT 解析失败，回退到内部 ID
        }
      }
    }
    return profile.id.toString();
  }

  /// StoreKit 恢复购买（重装 / 换设备 / 掉单 时手动同步）。
  ///
  /// 内部会：
  /// 1. 调 InAppPurchase.restorePurchases() 触发 StoreKit 重放历史交易
  ///    → purchaseStream 监听器会逐条执行 verify → finish。
  /// 2. 再兜底扫一次 Transaction.unfinished（in_app_purchase 3.x 走
  ///    queryPastPurchases）把没 finish 的再补一次。
  Future<void> _restoreApplePurchases() async {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      showToastNotification(message: '当前平台不支持恢复购买');
      return;
    }
    showToastNotification(message: '正在恢复购买，请稍候...');
    await AppleIAPService.instance.initialize();
    final userRes = await UserBackendService.getCurrentUserProfile();
    final userUuid = userRes.fold((p) => _extractUserId(p), (_) => '');
    if (userUuid.isEmpty) {
      showToastNotification(message: '未登录，无法恢复购买');
      return;
    }
    final res = await AppleIAPService.instance
        .restorePurchasesForUser(userUuid);
    if (!mounted) return;
    if (res.ok) {
      showToastNotification(message: res.message);
    } else {
      showToastNotification(message: '恢复失败: ${res.message}');
    }
  }

  Future<void> _confirmAndPay(
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
    Map<WorkspacePlanPB, RemotePlan> planConfigs,
    WorkspacePlanPB selectedPlan,
    PurchaseDurationOption selectedDuration,
  ) async {
    final config = planConfigs[selectedPlan];
    if (config == null) {
      showToastNotification(message: '无法获取计划配置');
      return;
    }

    final billingType = selectedDuration == PurchaseDurationOption.monthly
        ? 'monthly'
        : 'yearly';
    final price = selectedDuration == PurchaseDurationOption.monthly
        ? (config.monthlyPriceYuan ?? 0.0)
        : (config.yearlyPriceYuan ?? 0.0);

    setState(() => _isProcessingPayment = true);

    try {
      final userProfile = await UserBackendService.getCurrentUserProfile();
      final userUuid = userProfile.fold((p) => _extractUserId(p), (_) => '');
      Log.info('[MobileUpgradePlan] iOS 直接调用 Apple Pay');
      if (Platform.isIOS) {
        // iPhone/iPad 直接调用 Apple Pay 内购
        Log.info('[MobileUpgradePlan] iOS 直接调用 Apple Pay');
        await _handleIOSPayment(
            PaymentMethod.applePay, config, price, billingType, userUuid);
      } else {
        // Android 手机直接走支付宝应用支付，无需选择支付方式
        Log.info('[MobileUpgradePlan] Android 直接调用支付宝支付');
        await _handleAndroidPayment(
            PaymentMethod.alipay, config, price, billingType, userUuid);
      }
    } catch (e) {
      Log.error('[MobileUpgradePlan] 支付异常: $e');
      showToastNotification(message: '支付异常: $e');
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  /// Android 端弹出支付方式选择弹框，返回用户选择的支付方式
  Future<PaymentMethod?> _showAndroidPaymentSelector() {
    final theme = AppFlowyTheme.of(context);
    return showModalBottomSheet<PaymentMethod>(
      context: context,
      backgroundColor: theme.surfaceColorScheme.layer01,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.textColorScheme.tertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  '选择支付方式',
                  style: theme.textStyle.body
                      .standard(color: theme.textColorScheme.primary)
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildPaymentOptionTile(
                  theme,
                  icon: FlowySvgs.m_rights_ai_xl,
                  label: '支付宝',
                  onTap: () => Navigator.of(sheetContext).pop(PaymentMethod.alipay),
                ),
                _buildPaymentOptionTile(
                  theme,
                  icon: FlowySvgs.m_rights_ai_xl,
                  label: '微信支付',
                  onTap: () => Navigator.of(sheetContext).pop(PaymentMethod.wechatPay),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentOptionTile(
    AppFlowyThemeData theme, {
    required FlowySvgData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            FlowySvg(icon, size: const Size(24, 24), blendMode: null),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textStyle.body
                    .standard(color: theme.textColorScheme.primary)
                    .copyWith(fontSize: 15),
              ),
            ),
            FlowySvg(
              FlowySvgs.arrow_right_s,
              size: const Size(6, 12),
              color: theme.iconColorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 创建支付订单（Android / iOS 共用）。
  ///
  /// 支付方式与平台对应关系：
  ///   - iOS     → apple_pay（App Store 内购）
  ///   - Android → alipay_app（支付宝 App 支付）/ wechat_pay
  ///
  /// 返回完整订单数据（含 orderNo、payUrl），创建失败时返回 null 并已弹出 toast。
  Future<PaymentCreateResponse?> _createPaymentOrder({
    required PaymentMethod paymentMethod,
    required RemotePlan config,
    required double price,
    required String billingType,
    required String userUuid,
  }) async {
    final paymentType = switch (paymentMethod) {
      PaymentMethod.applePay => PaymentType.applePay,
      PaymentMethod.wechatPay => PaymentType.wechatPay,
      PaymentMethod.alipay => PaymentType.alipayApp,
    };

    final createRequest = PaymentCreateRequest(
      amount: price.toString(),
      paymentType: paymentType,
      userInfo: userUuid,
      productName: config.planNameCn?.isNotEmpty == true
          ? config.planNameCn!
          : config.planName ?? '会员升级',
      planId: config.id?.toString(),
      billingType: billingType,
    );

    Log.info(
        '[MobileUpgradePlan] 创建支付订单: plan=${config.planName}, '
        'price=$price, billingType=$billingType, paymentType=$paymentType');

    final orderResult = await PaymentApi.createPaymentOrder(createRequest);

    if (orderResult.isFailure) {
      final error = orderResult.fold((_) => null, (e) => e);
      showToastNotification(message: '创建订单失败: ${error?.msg ?? '未知错误'}');
      return null;
    }

    final orderData = orderResult.fold((r) => r, (_) => null);
    if (orderData?.data == null) {
      showToastNotification(message: '订单数据为空');
      return null;
    }

    final orderNo = orderData!.data!.orderNo;
    Log.info('[MobileUpgradePlan] 订单创建成功: orderNo=$orderNo');
    return orderData;
  }

  Future<void> _handleIOSPayment(
    PaymentMethod paymentMethod,
    RemotePlan config,
    double price,
    String billingType,
    String userUuid,
  ) async {
    Log.info('[MobileUpgradePlan] iOS 使用 Apple Pay（StoreKit 2）内购，'
        'userUuid=$userUuid, billing=$billingType');

    // 空值检查：getCurrentUserProfile() 失败或 JWT 解析失败时
    // userUuid 为空，避免后续接口报"缺少用户信息"。
    if (userUuid.isEmpty) {
      showToastNotification(message: '无法获取用户信息，请重新登录后重试');
      return;
    }

    final planCode = config.planCode;
    if (planCode == null || planCode.isEmpty) {
      showToastNotification(message: '暂不支持该套餐的 Apple Pay 支付');
      return;
    }

    // 商品 ID 拼接格式：com.ponynotes.{billingType}.{planCode}
    final productId =
        AppleIAPService.buildAppleProductId(planCode, billingType);

    // 苹果内购不走后端创建订单流程（订单落库由 /api/payment/apple/verify
    // 接口在后端幂等完成），这里直接拉起 StoreKit 2 购买。
    final paymentResult = await PaymentUtil.pay(
      method: paymentMethod,
      amount: (price * 100).toInt(),
      currency: 'CNY',
      orderId: 'ios_${DateTime.now().millisecondsSinceEpoch}',
      extra: {
        'productId': productId,
        'userUuid': userUuid,
      },
    );

    if (!mounted) return;
    if (!paymentResult.success) {
      // "购买已取消"、"购买失败：xxx"在 AppleIAPService.purchaseStream
      // 监听器里已经通过 showToastNotification 弹过 info/error，不再
      // 重复弹"支付失败: 购买已取消"。其它异常（参数缺失/插件不可用）
      // 仍然提示。
      final msg = paymentResult.message;
      if (!msg.startsWith('购买已取消') &&
          !msg.startsWith('支付失败：') &&
          !msg.startsWith('支付失败:')) {
        showToastNotification(message: '支付失败: $msg');
      }
    }
    // 购买发起成功后不再弹 toast — purchaseStream 监听器会在
    // verify 成功时通过 UpgradeSuccessOverlay 展示版本图片+文案，
    // verify 失败时弹出错误 toast。
  }

  Future<void> _handleAndroidPayment(
    PaymentMethod paymentMethod,
    RemotePlan config,
    double price,
    String billingType,
    String userUuid,
  ) async {
    Log.info('[MobileUpgradePlan] Android 使用 $paymentMethod 支付');

    // ① 创建订单（与 iOS 共用）
    final orderData = await _createPaymentOrder(
      paymentMethod: paymentMethod,
      config: config,
      price: price,
      billingType: billingType,
      userUuid: userUuid,
    );
    if (orderData == null) return;

    // ② 用订单中的 payUrl 唤起支付宝 App 支付
    final extra = <String, dynamic>{
      'payUrl': orderData.data?.payUrl,
      'plan': config.planName,
      'userUuid': userUuid,
    };

    final paymentResult = await PaymentUtil.pay(
      method: paymentMethod,
      amount: (price * 100).toInt(),
      currency: 'CNY',
      orderId: orderData.data!.orderNo,
      extra: extra,
    );

    if (mounted) {
      if (paymentResult.success) {
        showToastNotification(message: paymentResult.message);
      } else {
        showToastNotification(message: '支付失败: ${paymentResult.message}');
      }
    }
  }

  Widget _buildBenefitIcons(AppFlowyThemeData theme) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final benefits = [
      {
        'label': '小马AI',
        'iconLight': FlowySvgs.m_rights_ai_xl,
        'iconDark': FlowySvgs.md_rights_ai_xl
      },
      {
        'label': '小马日历',
        'iconLight': FlowySvgs.m_rights_calender_xl,
        'iconDark': FlowySvgs.md_rights_calender_xl
      },
      {
        'label': '云端同步',
        'iconLight': FlowySvgs.m_rights_cloud_xl,
        'iconDark': FlowySvgs.md_rights_cloud_xl
      },
      {
        'label': '小马收藏夹',
        'iconLight': FlowySvgs.m_rights_collect_xl,
        'iconDark': FlowySvgs.md_rights_collect_xl
      },
      {
        'label': '云端空间',
        'iconLight': FlowySvgs.m_rights_storage_xl,
        'iconDark': FlowySvgs.md_rights_storage_xl
      },
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
            Expanded(
                child: _BenefitCard(
                    label: benefits[0]['label'] as String,
                    icon: isDarkMode
                        ? benefits[0]['iconDark'] as FlowySvgData
                        : benefits[0]['iconLight'] as FlowySvgData,
                    isDarkMode: isDarkMode,
                    theme: theme)),
            const SizedBox(width: 8),
            Expanded(
                child: _BenefitCard(
                    label: benefits[1]['label'] as String,
                    icon: isDarkMode
                        ? benefits[1]['iconDark'] as FlowySvgData
                        : benefits[1]['iconLight'] as FlowySvgData,
                    isDarkMode: isDarkMode,
                    theme: theme)),
            const SizedBox(width: 8),
            Expanded(
                child: _BenefitCard(
                    label: benefits[2]['label'] as String,
                    icon: isDarkMode
                        ? benefits[2]['iconDark'] as FlowySvgData
                        : benefits[2]['iconLight'] as FlowySvgData,
                    isDarkMode: isDarkMode,
                    theme: theme)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _BenefitCard(
                    label: benefits[3]['label'] as String,
                    icon: isDarkMode
                        ? benefits[3]['iconDark'] as FlowySvgData
                        : benefits[3]['iconLight'] as FlowySvgData,
                    isDarkMode: isDarkMode,
                    theme: theme)),
            const SizedBox(width: 8),
            Expanded(
                child: _BenefitCard(
                    label: benefits[4]['label'] as String,
                    icon: isDarkMode
                        ? benefits[4]['iconDark'] as FlowySvgData
                        : benefits[4]['iconLight'] as FlowySvgData,
                    isDarkMode: isDarkMode,
                    theme: theme)),
          ],
        ),
      ],
    );
  }

  String formatCurrency(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Color colorPriceInit(String? id) {
    if (id == null) return const Color(0xFF371A0D);
    if (id == 'stand' || id == 'standard') {
      return const Color(0xFF2EACB2);
    } else if (id == 'profersor' || id == 'professor' || id == 'pro') {
      return const Color(0xFF343543);
    } else if (id == 'hiclass' || id == 'premium') {
      return const Color(0xFF371A0D);
    } else {
      return const Color(0xFF371A0D);
    }
  }

  String _initStorage(int? cloudStorageGb) {
    if (cloudStorageGb != null) {
      final storageGb = NumberFormat('#.##').format(cloudStorageGb / 1024);
      return "每月${storageGb}GB空间";
    }
    return "";
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
              style: theme.textStyle.body
                  .standard(color: theme.textColorScheme.secondary)
                  .copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
