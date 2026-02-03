import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/util/validator.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart'
    show UserWorkspaceBloc, UserWorkspaceEvent;
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/account/account_management_bloc.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/payment/payment_util.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/identity_verification_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/email_binding_dialog.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/phone_change_dialog.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../generated/locale_keys.g.dart';
import '../../../../user/presentation/screens/legal_document_screen.dart';

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

class _AccountManagementViewState extends State<AccountManagementView>
    with WidgetsBindingObserver {
  String? _lastHandledPaymentResult;
  bool _expectSubscribePaymentDialog = false;

  // TapGestureRecognizer 实例，用于在 dispose 时释放
  final List<TapGestureRecognizer> _gestureRecognizers = [];

  void _resetPaymentPromptDedup() {
    _lastHandledPaymentResult = null;
  }

  void _markExpectSubscribeDialog() {
    _expectSubscribePaymentDialog = true;
  }

  void _clearExpectSubscribeDialog() {
    _expectSubscribePaymentDialog = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 停止支付轮询（通过 Bloc 的 close 方法会自动停止）
    WidgetsBinding.instance.removeObserver(this);

    // 释放所有 TapGestureRecognizer
    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    _gestureRecognizers.clear();

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// 刷新订阅信息（全局刷新）
  void _refreshSubscriptionInfo(BuildContext context) {
    // 刷新 SettingsDialogBloc
    context.read<SettingsDialogBloc>().add(
          const SettingsDialogEvent.initial(),
        );

    // 刷新 UserWorkspaceBloc
    try {
      final workspaceBloc = context.read<UserWorkspaceBloc?>();
      if (workspaceBloc != null) {
        workspaceBloc.add(
          UserWorkspaceEvent.updateCloudSyncEnabled(enabled: true),
        );
        workspaceBloc.add(
          UserWorkspaceEvent.fetchCurrentSubscription(),
        );
      }
    } catch (e) {
      Log.warn('无法刷新 UserWorkspaceBloc: $e');
    }

    // 刷新 AccountManagementBloc 的订阅信息
    try {
      final accountBloc = context.read<AccountManagementBloc>();
      if (!accountBloc.isClosed) {
        accountBloc.add(const AccountManagementEvent.loadSubscriptionInfo());
      }
    } catch (e) {
      Log.warn('无法刷新 AccountManagementBloc: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 检查 widget 是否已挂载，避免在 build 之前访问 context
    if (!mounted) {
      return;
    }

    // 延迟执行，确保 build 方法已经执行，BlocProvider 已经创建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      // 检查 BlocProvider 是否已经创建
      // 使用 try-catch 安全地检查，如果不存在就不处理
      AccountManagementBloc bloc;
      try {
        bloc = context.read<AccountManagementBloc>();
      } catch (e) {
        // BlocProvider 还未创建（build 方法还没执行），忽略此次生命周期事件
        return;
      }

      if (bloc.isClosed) {
        return;
      }

      // 当应用进入后台时停止轮询，回到前台时恢复轮询
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        bloc.add(const AccountManagementEvent.stopPaymentPolling());
      } else if (state == AppLifecycleState.resumed) {
        // 检查当前状态，如果有订单号则恢复轮询
        final currentState = bloc.state;
        currentState.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            addons,
            selectedPlan,
            selectedDuration,
            selectedTab,
            selectedAddonIndex,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isLoadingAddons,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            // 如果 paymentResult 中有订单号，恢复轮询
            if (paymentResult != null && paymentResult.contains('orderNo:')) {
              final parts = paymentResult.split('|');
              for (final part in parts) {
                if (part.startsWith('orderNo:')) {
                  final orderNo = part.substring('orderNo:'.length);
                  if (orderNo.isNotEmpty) {
                    bloc.add(
                        AccountManagementEvent.startPaymentPolling(orderNo));
                    break;
                  }
                }
              }
            }
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AccountManagementBloc>(
      create: (context) => AccountManagementBloc(
        workspaceId: widget.workspaceId,
        userProfile: widget.userProfile,
        currentSubscription: widget.currentSubscription,
      )..add(const AccountManagementEvent.initial()),
      child: BlocConsumer<AccountManagementBloc, AccountManagementState>(
        listener: (context, state) {
          // 处理错误提示
          state.maybeWhen(
            orElse: () {},
            ready: (
              subscriptionInfo,
              planConfigs,
              addons,
              selectedPlan,
              selectedDuration,
              selectedTab,
              selectedAddonIndex,
              agreedProtocols,
              isLoadingSubscription,
              isLoadingPlans,
              isLoadingAddons,
              isProcessingPayment,
              error,
              paymentResult,
            ) {
              if (error != null && error.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              if (paymentResult != null && paymentResult.isNotEmpty) {
                // 避免同一条 paymentResult 多次触发提示
                if (_lastHandledPaymentResult == paymentResult) {
                  return;
                }

                // 处理支付初始化标记
                if (paymentResult == 'PAYMENT_INITIATED') {
                  // 支付已初始化，通过浏览器打开支付链接
                  // 支付成功后会通过 appScheme 回调自动处理
                  _lastHandledPaymentResult = paymentResult;
                  return;
                }

                // 普通消息提示
                _lastHandledPaymentResult = paymentResult;
                // 普通消息提示
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(paymentResult),
                    duration: const Duration(seconds: 2),
                  ),
                );
                // 支付成功后刷新订阅信息
                if (paymentResult.contains('成功')) {
                  _refreshSubscriptionInfo(context);
                }
              }
            },
          );
        },
        builder: (context, state) {
          return _buildContent(context, state);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, AccountManagementState state) {
    final theme = AppFlowyTheme.of(context);

    return state.maybeWhen(
      initial: () => const Center(child: CircularProgressIndicator()),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error) => Center(
        child: Text('加载失败: ${error?.msg ?? '未知错误'}'),
      ),
      ready: (
        subscriptionInfo,
        planConfigs,
        addons,
        selectedPlan,
        selectedDuration,
        selectedTab,
        selectedAddonIndex,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isLoadingAddons,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        final hasPlans = planConfigs.isNotEmpty;
        final isLoading = isLoadingSubscription || isLoadingPlans;

        return Column(
          children: [
            Expanded(
              child: SettingsBody(
                autoSeparate: false,
                title: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
                headerTrailingBuilder: (_) =>
                    // selectedTab == MembershipTab.upgrade ?
                    OutlinedRoundedButton(
                  text: '充值记录',
                  onTap: () =>
                      widget.changeSelectedPage(SettingsPage.rechargeRecords),
                  // ) : OutlinedRoundedButton(
                  //   text: '购买记录',
                  //   onTap: () => context.read<SettingsDialogBloc>().add(
                  //     const SettingsDialogEvent.setSelectedPage(
                  //       SettingsPage.addonPurchaseRecords,
                  //     ),
                  //   ),
                ),
                children: [
                  // 顶部切换月付/年付（改版：不再在底部切换）
                  _buildDurationSwitcher(
                    context,
                    selectedDuration,
                    (duration) => context.read<AccountManagementBloc>().add(
                          AccountManagementEvent.selectDuration(duration),
                        ),
                  ),
                  VSpace(10),
                  _buildUpgradeContent(
                    context,
                    state,
                    hasPlans,
                    isLoading,
                    selectedPlan,
                    selectedDuration,
                    agreedProtocols,
                    isProcessingPayment,
                  ),
                ],
              ),
            ),
          ],
        );
      },
      orElse: () => const Center(child: CircularProgressIndicator()),
    );
  }

  // 顶部月付/年付切换（改版）
  Widget _buildDurationSwitcher(
    BuildContext context,
    PurchaseDurationOption selectedDuration,
    void Function(PurchaseDurationOption) onDurationChanged,
  ) {
    final theme = AppFlowyTheme.of(context);
    final bool isMonthly = selectedDuration == PurchaseDurationOption.monthly;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode
            ? theme.surfaceColorScheme.layer02
            : theme.borderColorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabItem(
            context: context,
            label: LocaleKeys.settings_billingPage_paidMonthly.tr(),
            selected: isMonthly,
            onTap: () => onDurationChanged(PurchaseDurationOption.monthly),
          ),
          _buildTabItem(
            context: context,
            label: LocaleKeys.settings_billingPage_paidYearly.tr(),
            selected: !isMonthly,
            onTap: () => onDurationChanged(PurchaseDurationOption.yearly),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = AppFlowyTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : theme.textColorScheme.secondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpgradeContent(
    BuildContext context,
    AccountManagementState state,
    bool hasPlans,
    bool isLoading,
    WorkspacePlanPB? selectedPlan,
    PurchaseDurationOption selectedDuration,
    bool agreedProtocols,
    bool isProcessingPayment,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (!hasPlans) ...[
          const SizedBox(height: 20),
          const Center(child: Text('暂无可用的会员计划')),
          const SizedBox(height: 24),
        ] else ...[
          _buildUpgradePlanCards(context, state, selectedPlan),
          const VSpace(24),
          _buildBenefitIcons(context),
          const VSpace(24),
          _buildAgreementActionRow(
            context: context,
            agreedProtocols: agreedProtocols,
            isProcessing: isProcessingPayment,
            buttonText: '确认协议开通',
            onToggleAgreed: (value) =>
                context.read<AccountManagementBloc>().add(
                      AccountManagementEvent.setAgreedProtocols(value),
                    ),
            onPressed: () {
              // 仅在用户点击“确认协议开通”时，允许后续弹出支付提示弹框
              _markExpectSubscribeDialog();
              context
                  .read<AccountManagementBloc>()
                  .add(const AccountManagementEvent.handleUpgradePay());
            },
            prefixText: '升级前请确认 ',
          ),
        ],
      ],
    );
  }

  Widget _buildAgreementActionRow({
    required BuildContext context,
    required bool agreedProtocols,
    required bool isProcessing,
    required String buttonText,
    required void Function(bool) onToggleAgreed,
    required VoidCallback onPressed,
    required String prefixText,
  }) {
    final enabled = agreedProtocols && !isProcessing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: GestureDetector(
            onTap: enabled ? onPressed : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      buttonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
        Row(
          children: [
            Checkbox(
              value: agreedProtocols,
              onChanged: (value) => onToggleAgreed(value ?? false),
              activeColor: Theme.of(context).colorScheme.primary,
            ),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF999999),
                ),
                children: [
                  TextSpan(text: prefixText),
                  TextSpan(
                    text: "《会员协议》",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    mouseCursor: SystemMouseCursors.click,
                    recognizer: () {
                      final recognizer = TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LegalDocumentScreen(
                                title: LocaleKeys.sidebar_appName.tr() +
                                    LocaleKeys.legal_userAgreement.tr(),
                                content:
                                    LocaleKeys.legal_userAgreementContent.tr(),
                              ),
                            ),
                          );
                        };
                      _gestureRecognizers.add(recognizer);
                      return recognizer;
                    }(),
                  ),
                  TextSpan(
                    text: "《${LocaleKeys.legal_privacyPolicy.tr()}》",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    mouseCursor: SystemMouseCursors.click,
                    recognizer: () {
                      final recognizer = TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LegalDocumentScreen(
                                title: LocaleKeys.legal_privacyPolicy.tr(),
                                content:
                                    LocaleKeys.legal_privacyPolicyContent.tr(),
                              ),
                            ),
                          );
                        };
                      _gestureRecognizers.add(recognizer);
                      return recognizer;
                    }(),
                  ),
                ],
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildUpgradePlanCards(
    BuildContext context,
    AccountManagementState state,
    WorkspacePlanPB? selectedPlan,
  ) {
    final theme = AppFlowyTheme.of(context);
    final selectedDuration = state.maybeWhen(
      orElse: () => PurchaseDurationOption.monthly,
      ready: (
        subscriptionInfo,
        planConfigs,
        addons,
        selectedPlan,
        selectedDuration,
        selectedTab,
        selectedAddonIndex,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isLoadingAddons,
        isProcessingPayment,
        error,
        paymentResult,
      ) =>
          selectedDuration,
    );
    final planConfigs = state.maybeWhen(
      orElse: () => <WorkspacePlanPB, RemotePlan>{},
      ready: (
        subscriptionInfo,
        planConfigs,
        addons,
        selectedPlan,
        selectedDuration,
        selectedTab,
        selectedAddonIndex,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isLoadingAddons,
        isProcessingPayment,
        error,
        paymentResult,
      ) =>
          planConfigs,
    );

    final plans = planConfigs.entries
        .where((e) => e.value.isActive)
        .map((e) => e.key)
        .toList();
    
    // 按照要求的顺序排序：标准版 > 专业版 > 高级版 > 免费版
    plans.sort((a, b) {
      final order = {
        WorkspacePlanPB.FreePlan: 1,
        WorkspacePlanPB.StandPlan: 2,
        WorkspacePlanPB.ProPlan: 3,
        WorkspacePlanPB.HiclassPlan: 4,
      };
      return (order[a] ?? 999).compareTo(order[b] ?? 999);
    });
    
    // 过滤掉免费版（如果需要）
    final filteredPlans = plans.where((e) => e != WorkspacePlanPB.FreePlan).toList();
    if (filteredPlans.isNotEmpty) {
      plans.clear();
      plans.addAll(filteredPlans);
    }

    final effectivePlan = state.effectivePlan;
    if (effectivePlan == null || plans.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = theme.spacing.m;
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
        const double minCardWidth = 180;
        int crossAxisCount = (maxWidth / (minCardWidth + spacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, plans.length);

        final cardWidth = (maxWidth - spacing * (crossAxisCount - 1)) / 4;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: plans.map((plan) {
            final config = state.getPlanConfig(plan);
            final isSelected = plan == effectivePlan;
            return GestureDetector(
              onTap: () {
                context.read<AccountManagementBloc>().add(
                      AccountManagementEvent.selectPlan(plan),
                    );
              },
              child: Container(
                width: cardWidth - 12,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFFFFF7F2)
                          : theme.surfaceColorScheme.layer02)
                      : theme.surfaceColorScheme.layer01,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : theme.borderColorScheme.primary,
                    width: isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FlowyText(
                        ((config?.planNameCn ?? '').isNotEmpty)
                            ? (config?.planNameCn ?? '')
                            : (config?.planName ?? ''),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorScheme.primary,
                      ),
                      const VSpace(12),
                      Builder(
                        builder: (context) {
                          final monthly = config?.monthlyPriceYuan ?? 0.0;
                          final yearly = config?.yearlyPriceYuan ?? 0.0;
                          final price =
                              selectedDuration == PurchaseDurationOption.monthly
                                  ? monthly
                                  : yearly;

                          final suffix =
                              selectedDuration == PurchaseDurationOption.monthly
                                  ? '/月'
                                  : '/年';
                          final raw = '¥${formatCurrency(price)}$suffix';
                          return Container(
                              width: cardWidth - 50,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                  color: colorPriceInit(config?.planCode),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(16))),
                              child: Column(
                                children: [
                                  FlowyText.regular(
                                    raw,
                                    color: config?.planCode?.contains("stand") == true ||
                                        config?.planCode?.contains("standard") == true
                                        ? Colors.white
                                        : Color(0xFFF9D8A7),
                                    fontSize: 18,
                                  ),
                                  VSpace(6),
                                  FlowyText.regular(
                                    selectedDuration ==
                                            PurchaseDurationOption.monthly
                                        ? "按月支付"
                                        : "按年支付",
                                    color: config?.planCode?.contains("stand") == true ||
                                        config?.planCode?.contains("standard") == true
                                        ? Colors.white
                                        : Color(0x99F9D8A7),
                                    fontSize: 12,
                                  ),
                                ],
                              ));
                        },
                      ),
                      const VSpace(12),
                      IntrinsicHeight(
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
                            HSpace(4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FlowyText(
                                    "每月${config?.cloudStorageGb}GB${LocaleKeys.settings_billingPage_storageSpace.tr()}",
                                    fontSize: 12,
                                    color: theme.textColorScheme.secondary,
                                  ),
                                  VSpace(8),
                                  FlowyText(
                                    "每月${config?.cloudStorageGb}GB${LocaleKeys.settings_billingPage_storageSpace.tr()}",
                                    fontSize: 12,
                                    color: theme.textColorScheme.secondary,
                                  ),
                                  VSpace(8),
                                  FlowyText(
                                    "每月${config?.cloudStorageGb}GB${LocaleKeys.settings_billingPage_storageSpace.tr()}",
                                    fontSize: 12,
                                    color: theme.textColorScheme.secondary,
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBenefitIcons(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final benefits = [
      {'label': '小马AI', 'icon': FlowySvgs.icon_rights_ai_xl},
      {'label': '小马日历', 'icon': FlowySvgs.icon_rights_calendar_xl},
      {'label': '小马收藏夹', 'icon': FlowySvgs.icon_rights_collect_xl},
      {'label': '云端同步', 'icon': FlowySvgs.icon_rights_cloud_xl},
      {'label': '云端空间', 'icon': FlowySvgs.icon_rights_storage_xl},
    ];

    Widget buildItem(Map<String, Object> benefit) {
      return SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white : null,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FlowySvg(
                  benefit['icon'] as FlowySvgData,
                  size: const Size(40, 40),
                  blendMode: null,
                ),
              ),
            ),
            const VSpace(8),
            FlowyText(
              benefit['label'] as String,
              fontSize: 13,
              color: theme.textColorScheme.secondary,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          '获赠权益',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.textColorScheme.primary,
        ),
        const VSpace(12),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: benefits.length,
            separatorBuilder: (_, __) => const SizedBox(width: 24),
            itemBuilder: (context, index) {
              return buildItem(benefits[index]);
            },
          ),
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

  Color colorPriceInit(id) {
    if (id == "stand") {
      return Color(0xFF2EACB2);
    } else if (id == "standard") {
      return Color(0xFF2EACB2);
    } else if (id == "profersor") {
      return Color(0xFF343543);
    } else {
      return Color(0xFF371A0D);
    }
  }
}
