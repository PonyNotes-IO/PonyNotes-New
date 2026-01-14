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

class _AccountManagementViewState extends State<AccountManagementView> {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(paymentResult),
                    duration: const Duration(seconds: 2),
                  ),
                );
                // 支付成功后刷新订阅信息
                if (paymentResult.contains('成功')) {
                  context.read<SettingsDialogBloc>().add(
                        const SettingsDialogEvent.initial(),
                      );
                  try {
                    final workspaceBloc = context.read<UserWorkspaceBloc?>();
                    if (workspaceBloc != null) {
                      workspaceBloc.add(
                        UserWorkspaceEvent.updateCloudSyncEnabled(
                            enabled: true),
                      );
                      workspaceBloc.add(
                        UserWorkspaceEvent.fetchCurrentSubscription(),
                      );
                    }
                  } catch (e) {
                    Log.warn('无法刷新 UserWorkspaceBloc: $e');
                  }
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
                title: "我的账户",
                headerTrailingBuilder: (_) =>
                selectedTab == MembershipTab.upgrade ?
                    OutlinedRoundedButton(
                  text: '充值记录',
                  onTap: () =>
                      widget.changeSelectedPage(SettingsPage.rechargeRecords),
                ) : OutlinedRoundedButton(
                  text: '购买记录',
                  onTap: () => context.read<SettingsDialogBloc>().add(
                    const SettingsDialogEvent.setSelectedPage(
                      SettingsPage.addonPurchaseRecords,
                    ),
                  ),
                ),
                children: [
                  _buildTabSwitcher(
                    context,
                    selectedTab,
                    (tab) => context.read<AccountManagementBloc>().add(
                          AccountManagementEvent.switchTab(tab),
                        ),
                  ),
                  if (selectedTab == MembershipTab.upgrade)
                    _buildUpgradeContent(
                      context,
                      state,
                      hasPlans,
                      isLoading,
                      selectedPlan,
                      selectedDuration,
                      agreedProtocols,
                      isProcessingPayment,
                    )
                  else
                    _buildAddonContent(
                      context,
                      state,
                      addons,
                      isLoadingAddons,
                      selectedAddonIndex,
                      agreedProtocols,
                      isProcessingPayment,
                    ),
                ],
              ),
            ),
            if (selectedTab == MembershipTab.upgrade)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: GestureDetector(
                  onTap: () async {
                    // 重置 SignInBloc 状态（如果可用）
                    try {
                      final signInBloc = getIt<SignInBloc>();
                      if (!signInBloc.isClosed) {
                        signInBloc.add(const SignInEvent.reset());
                      }
                    } catch (e) {
                      // SignInBloc 不可用，忽略
                    }
                    await getIt<AuthService>().signOut();
                    await runAppFlowy();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: theme.spacing.m),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(theme.spacing.s),
                    ),
                    child: Center(
                      child: FlowyText(
                        '退出登录',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const Center(child: CircularProgressIndicator()),
    );
  }

  // 所有业务逻辑已移至 AccountManagementBloc
  Widget _buildTabSwitcher(
    BuildContext context,
    MembershipTab selectedTab,
    void Function(MembershipTab) onTabChanged,
  ) {
    final theme = AppFlowyTheme.of(context);
    final bool isUpgrade = selectedTab == MembershipTab.upgrade;
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
            label: LocaleKeys.settings_billingPage_membershipUpgrades.tr(),
            selected: isUpgrade,
            onTap: () => onTabChanged(MembershipTab.upgrade),
          ),
          _buildTabItem(
            context: context,
            label: LocaleKeys.settings_billingPage_storageAddon.tr(),
            selected: !isUpgrade,
            onTap: () => onTabChanged(MembershipTab.addon),
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
          _buildPurchaseDurationSection(
            context,
            state,
            selectedDuration,
            agreedProtocols,
            isProcessingPayment,
          ),
        ],
        const VSpace(24),
        _buildCommonInfoList(context),
      ],
    );
  }

  Widget _buildAddonContent(
    BuildContext context,
    AccountManagementState state,
    List<AddonPlan> addons,
    bool isLoadingAddons,
    int selectedAddonIndex,
    bool agreedProtocols,
    bool isProcessingPayment,
  ) {
    final theme = AppFlowyTheme.of(context);
    final hasAddons = addons.isNotEmpty;
    final storageAddons = addons.where((e) => e.isStorage).toList();
    final tokenAddons = addons.where((e) => e.isAiToken).toList();
    final selectedAddon = hasAddons
        ? addons[selectedAddonIndex.clamp(0, addons.length - 1)]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoadingAddons)
          const Center(child: CircularProgressIndicator())
        else if (!hasAddons) ...[
          const SizedBox(height: 12),
          const Center(child: Text('暂无可用的补充包')),
          const SizedBox(height: 12),
        ] else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAddonGrid(
                context,
                state,
                storageAddons,
                '云存储空间',
                theme,
                selectedAddonIndex,
              ),
              const VSpace(16),
              _buildAddonGrid(
                context,
                state,
                tokenAddons,
                '小马AI对话',
                theme,
                selectedAddonIndex,
              ),
            ],
          ),
        const VSpace(16),
        if (hasAddons && selectedAddon != null)
          _buildAgreementActionRow(
            context: context,
            agreedProtocols: agreedProtocols,
            isProcessing: isProcessingPayment,
            buttonText: '确认协议并扩充',
            onToggleAgreed: (value) => context.read<AccountManagementBloc>().add(
                  AccountManagementEvent.setAgreedProtocols(value),
                ),
            onPressed: () => context.read<AccountManagementBloc>().add(
                  const AccountManagementEvent.handleAddonPay(),
                ),
            prefixText: '升级前请确认 ',
          ),
        const VSpace(24),
        _buildCommonInfoList(context),
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

    return Row(
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
        const Spacer(),
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
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => LegalDocumentScreen(
                          title: LocaleKeys.sidebar_appName.tr() +
                              LocaleKeys.legal_userAgreement.tr(),
                          content: LocaleKeys.legal_userAgreementContent.tr(),
                        ),
                      ),
                    );
                  },
              ),
              TextSpan(
                text: "《${LocaleKeys.legal_privacyPolicy.tr()}》",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
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
      ],
    );
  }

  Widget _buildCommonInfoList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFeatureItem(
          context,
          LocaleKeys.settings_billingPage_storageSpace.tr(),
          _buildStorageUsageSubtitle(),
          showArrow: true,
        ),
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
          child: _buildFeatureItem(context, '绑定手机', '修改',
              showButton: true, buttonText: '修改'),
        ),
        GestureDetector(
          onTap: () => _showEmailVerificationDialog(context),
          child: _buildFeatureItem(context, '邮箱', '修改',
              showButton: true, buttonText: '修改'),
        ),
      ],
    );
  }

  Widget _buildUpgradePlanCards(
    BuildContext context,
    AccountManagementState state,
    WorkspacePlanPB? selectedPlan,
  ) {
    final theme = AppFlowyTheme.of(context);
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
        .where((e) => e.value.isActive && e.key != WorkspacePlanPB.FreePlan)
        .map((e) => e.key)
        .toList();

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
                width: cardWidth,
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
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FlowyText(
                        config['title'] as String,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorScheme.primary,
                      ),
                      const VSpace(6),
                      Builder(
                        builder: (context) {
                          final raw = (config['price'] as String?) ?? '';
                          final text = raw.trim();
                          final hasYuan = text.startsWith('¥');
                          final symbol = hasYuan ? '¥' : '';
                          final amount = hasYuan ? text.substring(1) : text;

                          return Text.rich(
                            TextSpan(
                              children: [
                                if (symbol.isNotEmpty)
                                  TextSpan(
                                    text: symbol,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textColorScheme.primary,
                                    ),
                                  ),
                                TextSpan(
                                  text: amount,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: theme.textColorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const VSpace(6),
                      FlowyText(
                        config['tag']?.toString() ?? '',
                        fontSize: 12,
                        color: theme.textColorScheme.secondary,
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
    final benefits = [
      {'label': '小马AI', 'icon': FlowySvgs.icon_rights_ai_xl},
      {'label': '小马日历', 'icon': FlowySvgs.icon_rights_calendar_xl},
      {'label': '小马收藏夹', 'icon': FlowySvgs.icon_rights_collect_xl},
      {'label': '云端同步', 'icon': FlowySvgs.icon_rights_cloud_xl},
      {'label': '100T空间', 'icon': FlowySvgs.icon_rights_storage_xl},
    ];

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: benefits.map((b) {
        return Expanded(
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
                    b['icon'] as FlowySvgData,
                    size: const Size(40, 40),
                    blendMode: null,
                  ),
                ),
              ),
              const VSpace(8),
              FlowyText(
                b['label'] as String,
                fontSize: 13,
                color: theme.textColorScheme.secondary,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddonGrid(
    BuildContext context,
    AccountManagementState state,
    List<AddonPlan> plans,
    String title,
    AppFlowyThemeData theme,
    int selectedAddonIndex,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          title,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.textColorScheme.primary,
        ),
        const VSpace(12),
        if (plans.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '暂无可用的$title',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textColorScheme.tertiary,
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = theme.spacing.m;
              final maxWidth =
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
              const double minCardWidth = 180;
              int crossAxisCount =
                  (maxWidth / (minCardWidth + spacing)).floor();
              crossAxisCount = crossAxisCount.clamp(1, plans.length);

              final cardWidth =
                  (maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: List.generate(plans.length, (index) {
                  final plan = plans[index];
                  final allAddons = state.maybeWhen(
                    orElse: () => <AddonPlan>[],
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
                        addons,
                  );
                  final realIndex = allAddons.indexOf(plan);
                  final isSelected = selectedAddonIndex == realIndex;
                  return GestureDetector(
                    onTap: () {
                      if (realIndex >= 0) {
                        context.read<AccountManagementBloc>().add(
                              AccountManagementEvent.selectAddon(realIndex),
                            );
                      }
                    },
                    child: Container(
                      width: cardWidth,
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
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FlowyText(
                              plan.name,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.textColorScheme.primary,
                              textAlign: TextAlign.center,
                            ),
                            const VSpace(8),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: "¥",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textColorScheme.primary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '${plan.priceYuanStr}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: theme.textColorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
      ],
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

  String _buildStorageUsageSubtitle() {
    final usage = widget.currentSubscription?.usage;
    final usedGb = usage?.storageUsedGb;
    final totalGb = usage?.storageTotalGb;
    if (usedGb == null || totalGb == null) {
      return '';
    }

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    // 按“已用/总量”展示（与“我的账户”右侧展示保持一致的简洁风格）
    return '${fmt(usedGb)}/${fmt(totalGb)}';
  }

  Widget _buildPurchaseDurationSection(
    BuildContext context,
    AccountManagementState state,
    PurchaseDurationOption selectedDuration,
    bool agreedProtocols,
    bool isProcessingPayment,
  ) {
    final effectivePlan = state.effectivePlan;
    if (effectivePlan == null) {
      return const SizedBox.shrink();
    }
    final theme = AppFlowyTheme.of(context);
    final monthlyPrice = state.getDurationPrice(PurchaseDurationOption.monthly);
    final yearlyPrice = state.getDurationPrice(PurchaseDurationOption.yearly);
    final options = [
      {
        'type': PurchaseDurationOption.monthly,
        'title': '30天',
        'price': monthlyPrice,
      },
      {
        'type': PurchaseDurationOption.yearly,
        'title': '365天',
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
            final isSelected = type == selectedDuration;
            final price = option['price'] as double;
            return GestureDetector(
              onTap: () {
                context.read<AccountManagementBloc>().add(
                      AccountManagementEvent.selectDuration(type),
                    );
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
                      ? (Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFFFFF3EC)
                          : theme.surfaceColorScheme.layer02)
                      : theme.surfaceColorScheme.layer01,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : theme.borderColorScheme.primary,
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
                            ? Theme.of(context).colorScheme.primary
                            : theme.textColorScheme.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final amount = price == price.truncateToDouble()
                            ? price.toInt().toString()
                            : price.toStringAsFixed(2);
                        final suffix = type == PurchaseDurationOption.monthly
                            ? '/月'
                            : '/年';
                        return Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '¥',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textColorScheme.primary,
                                ),
                              ),
                              TextSpan(
                                text: amount,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textColorScheme.primary,
                                ),
                              ),
                              TextSpan(
                                text: suffix,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textColorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
            Opacity(
              opacity: (agreedProtocols && !isProcessingPayment) ? 1 : 0.5,
              child: GestureDetector(
                onTap: (agreedProtocols && !isProcessingPayment)
                    ? () => context.read<AccountManagementBloc>().add(
                  const AccountManagementEvent.handleUpgradePay(),
                )
                    : null,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: isProcessingPayment
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text(
                    '确认协议开通',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Spacer(),
            Checkbox(
              value: agreedProtocols,
              onChanged: (value) {
                context.read<AccountManagementBloc>().add(
                      AccountManagementEvent.setAgreedProtocols(value ?? false),
                    );
              },
              activeColor: Theme.of(context).colorScheme.primary,
            ),
            RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                  ),
                  children: [
                    const TextSpan(text: "升级前请确认 "),
                    TextSpan(
                      text: "《会员协议》",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: TapGestureRecognizer()
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
                        },
                    ),
                    TextSpan(
                      text: "《${LocaleKeys.legal_privacyPolicy.tr()}》",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: TapGestureRecognizer()
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
                        },
                    ),
                  ],
                ),
              )
          ],
        )
      ],
    );
  }

  // 业务逻辑已移至 AccountManagementBloc

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
    // 从 SettingsDialogBloc 获取最新的用户资料，而不是使用 widget.userProfile
    final settingsBloc = context.read<SettingsDialogBloc>();
    final latestUserProfile = settingsBloc.state.userProfile;

    // 调试：打印用户资料信息
    Log.info(
        '用户资料 - email: ${latestUserProfile.email}, name: ${latestUserProfile.name}');

    // 从用户资料中获取手机号
    // 优先使用 phone 字段，如果没有则检查 email 字段
    String phoneNumber = '';

    if (latestUserProfile.hasPhone() && latestUserProfile.phone.isNotEmpty) {
      // 优先使用 phone 字段
      phoneNumber = latestUserProfile.phone;
      Log.info('从用户资料的 phone 字段获取到手机号: $phoneNumber');
    } else if (latestUserProfile.email.isNotEmpty &&
        !latestUserProfile.email.contains('@') &&
        Validator.isValidPhone(latestUserProfile.email)) {
      // 兼容旧数据：检查 email 字段是否包含手机号
      phoneNumber = latestUserProfile.email;
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
              final hasPhone =
                  newProfile.hasPhone() && newProfile.phone.isNotEmpty;
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

// 所有业务逻辑已移至 AccountManagementBloc
}
