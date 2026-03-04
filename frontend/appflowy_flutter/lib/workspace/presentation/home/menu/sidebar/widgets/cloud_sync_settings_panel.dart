import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 会员状态枚举
enum CloudSyncMembershipStatus {
  notSubscribed, // 未开通会员
  active, // 会员有效中
  expiringSoon, // 即将到期（7天内）
  gracePeriod, // 宽限期（到期或降级后15天内）
  expired, // 已过期（含宽限期已过）
  storageFull, // 空间使用满
}

class CloudSyncSettingsPanel extends StatefulWidget {
  const CloudSyncSettingsPanel({
    super.key,
    required this.isEnabled,
    required this.onToggle,
    required this.membershipStatus,
    this.subscriptionInfo,
    this.currentSubscription,
    this.onUpgrade,
    this.storageTotal = '200G',
    this.maxFileSize = '3GB',
  });

  final bool isEnabled;
  final Function(bool) onToggle;
  final CloudSyncMembershipStatus membershipStatus;
  final WorkspaceSubscriptionInfoPB? subscriptionInfo;
  final CurrentSubscription? currentSubscription;
  final VoidCallback? onUpgrade;
  final String storageTotal;
  final String maxFileSize;

  @override
  State<CloudSyncSettingsPanel> createState() => _CloudSyncSettingsPanelState();
}

class _CloudSyncSettingsPanelState extends State<CloudSyncSettingsPanel> {
  late bool _isEnabled;

  @override
  void initState() {
    super.initState();
    _isEnabled = widget.isEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FlowyText(
                LocaleKeys.newSettings_cloudSync_title.tr(),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.textColorScheme.primary,
              ),
              _buildToggleSwitch(theme, context),
            ],
          ),
          const SizedBox(height: 16),
          // 根据会员状态显示不同内容
          _buildContentByMembershipStatus(theme, context),
        ],
      ),
    );
  }

  Widget _buildContentByMembershipStatus(
      AppFlowyThemeData theme, BuildContext context) {
    switch (widget.membershipStatus) {
      case CloudSyncMembershipStatus.notSubscribed:
        return _buildNotSubscribedContent(theme, context);
      case CloudSyncMembershipStatus.active:
        return _buildActiveContent(theme, context);
      case CloudSyncMembershipStatus.expiringSoon:
        return _buildExpiringSoonContent(theme, context);
      case CloudSyncMembershipStatus.gracePeriod:
        return _buildGracePeriodContent(theme, context);
      case CloudSyncMembershipStatus.expired:
      case CloudSyncMembershipStatus.storageFull:
        return _buildExpiredOrFullContent(theme, context);
    }
  }

  /// 未开通会员的内容
  Widget _buildNotSubscribedContent(
      AppFlowyThemeData theme, BuildContext context) {
    final usage = widget.currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = usage?.storageTotalGb ?? 0.0;
    final remainingGb =
        (storageTotalGb - storageUsedGb).clamp(0.0, double.infinity);

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        FlowyText(
          LocaleKeys.newSettings_cloudSync_remainingSpace.tr(args: [fmt(remainingGb), fmt(storageTotalGb)]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 4),
        FlowyText(
          LocaleKeys.newSettings_cloudSync_maxUploadSize.tr(args: [widget.maxFileSize]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          LocaleKeys.newSettings_cloudSync_notSubscribedDesc.tr(),
          style: TextStyle(
            fontSize: 12,
            color: theme.textColorScheme.secondary,
            height: 1.4,
          ),
          softWrap: true,
          maxLines: null,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: LocaleKeys.newSettings_cloudSync_btnSubscribe.tr(),
            onTap: widget.onUpgrade ?? () {},
          ),
        ),
      ],
    );
  }

  /// 会员有效中的内容
  Widget _buildActiveContent(AppFlowyThemeData theme, BuildContext context) {
    final usage = widget.currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = usage?.storageTotalGb ?? 0.0;
    final remainingGb =
        (storageTotalGb - storageUsedGb).clamp(0.0, double.infinity);

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    final subscription = widget.currentSubscription?.subscription;
    final planName = subscription?.planNameCn ?? '';
    final planCode = subscription?.planCode?.toLowerCase() ?? '';
    final isFreePlan = planCode == 'mfb' || planCode.contains('free');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFE8F5E9)
                : theme.surfaceColorScheme.layer02,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 16,
                color: Color(0xFF4CAF50),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FlowyText(
                  LocaleKeys.newSettings_cloudSync_memberActive.tr(args: [planName]),
                  fontSize: 12,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FlowyText(
          LocaleKeys.newSettings_cloudSync_remainingSpace.tr(args: [fmt(remainingGb), fmt(storageTotalGb)]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 4),
        FlowyText(
          LocaleKeys.newSettings_cloudSync_maxUploadSize.tr(args: [widget.maxFileSize]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        if (isFreePlan) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AFFilledTextButton.primary(
              text: LocaleKeys.newSettings_cloudSync_btnUpgradeSpace.tr(),
              onTap: widget.onUpgrade ?? () {},
            ),
          ),
        ],
      ],
    );
  }

  /// 即将到期的内容（7天内到期）
  Widget _buildExpiringSoonContent(
      AppFlowyThemeData theme, BuildContext context) {
    final subscription = widget.currentSubscription?.subscription;
    final planName = subscription?.planNameCn ?? '';
    final daysLeft = subscription?.daysUntilExpiry ?? 0;
    final usage = widget.currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = usage?.storageTotalGb ?? 0.0;
    final remainingGb =
        (storageTotalGb - storageUsedGb).clamp(0.0, double.infinity);

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFFFF3E0)
                : theme.surfaceColorScheme.layer02,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 16,
                color: Color(0xFFFF9800),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FlowyText(
                  LocaleKeys.newSettings_cloudSync_expiringSoon.tr(args: [planName, '$daysLeft']),
                  fontSize: 12,
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FlowyText(
          LocaleKeys.newSettings_cloudSync_remainingSpace.tr(args: [fmt(remainingGb), fmt(storageTotalGb)]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 4),
        Text(
          LocaleKeys.newSettings_cloudSync_expiringSoonDesc.tr(),
          style: TextStyle(
            fontSize: 12,
            color: theme.textColorScheme.secondary,
            height: 1.4,
          ),
          softWrap: true,
          maxLines: null,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: LocaleKeys.newSettings_cloudSync_btnRenew.tr(),
            onTap: widget.onUpgrade ?? () {},
          ),
        ),
      ],
    );
  }

  /// 宽限期内的内容（到期或降级后15天宽限期）
  Widget _buildGracePeriodContent(
      AppFlowyThemeData theme, BuildContext context) {
    final subscription = widget.currentSubscription?.subscription;
    final isDowngraded = subscription?.isDowngraded ?? false;
    final graceDaysLeft = subscription?.daysUntilGracePeriodEnd ?? 0;
    final usage = widget.currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = usage?.storageTotalGb ?? 0.0;
    final remainingGb =
        (storageTotalGb - storageUsedGb).clamp(0.0, double.infinity);

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    final title = isDowngraded
        ? LocaleKeys.newSettings_cloudSync_gracePeriodDowngraded.tr(args: ['$graceDaysLeft'])
        : LocaleKeys.newSettings_cloudSync_gracePeriodExpired.tr(args: ['$graceDaysLeft']);
    final desc = isDowngraded
        ? LocaleKeys.newSettings_cloudSync_gracePeriodDowngradedDesc.tr()
        : LocaleKeys.newSettings_cloudSync_gracePeriodExpiredDesc.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFFFF8E1)
                : theme.surfaceColorScheme.layer02,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.hourglass_bottom,
                  size: 16,
                  color: Color(0xFFF57C00),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FlowyText(
                  title,
                  fontSize: 12,
                  color: const Color(0xFFF57C00),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FlowyText(
          LocaleKeys.newSettings_cloudSync_remainingSpace.tr(args: [fmt(remainingGb), fmt(storageTotalGb)]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 4),
        Text(
          desc,
          style: TextStyle(
            fontSize: 12,
            color: theme.textColorScheme.secondary,
            height: 1.4,
          ),
          softWrap: true,
          maxLines: null,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: isDowngraded
                ? LocaleKeys.newSettings_cloudSync_btnUpgradePlan.tr()
                : LocaleKeys.newSettings_cloudSync_btnRenew.tr(),
            onTap: widget.onUpgrade ?? () {},
          ),
        ),
      ],
    );
  }

  /// 已到期或空间使用满的内容
  Widget _buildExpiredOrFullContent(
      AppFlowyThemeData theme, BuildContext context) {
    final isExpired =
        widget.membershipStatus == CloudSyncMembershipStatus.expired;
    final usage = widget.currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = usage?.storageTotalGb ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFFFEBEE)
                : theme.surfaceColorScheme.layer02,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FlowyText(
                  isExpired
                      ? LocaleKeys.newSettings_cloudSync_memberExpired.tr()
                      : LocaleKeys.newSettings_cloudSync_storageFull.tr(),
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FlowyText(
          isExpired
              ? LocaleKeys.newSettings_cloudSync_memberExpiredDesc.tr()
              : LocaleKeys.newSettings_cloudSync_storageFullDesc.tr(args: [
                  '${storageUsedGb.toStringAsFixed(1)}G',
                  '${storageTotalGb.toStringAsFixed(1)}G',
                ]),
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: isExpired
                ? LocaleKeys.newSettings_cloudSync_btnRenew.tr()
                : LocaleKeys.newSettings_cloudSync_btnExpandSpace.tr(),
            onTap: widget.onUpgrade ?? () {},
          ),
        ),
      ],
    );
  }

  Widget _buildToggleSwitch(AppFlowyThemeData theme, BuildContext context) {
    return GestureDetector(
      onTap: _toggleSwitch,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _isEnabled
              ? Theme.of(context).colorScheme.primary // 红色激活状态
              : const Color(0xFFE0E0E0), // 灰色未激活状态
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: _isEnabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSwitch() {
    setState(() {
      _isEnabled = !_isEnabled;
    });
    widget.onToggle(_isEnabled);
  }
}
