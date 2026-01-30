import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 会员状态枚举
enum CloudSyncMembershipStatus {
  notSubscribed, // 未开通会员
  active, // 会员有效中
  expired, // 已到期
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
          // 标题和开关（未开通会员时不显示开关）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FlowyText(
                '云同步',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.textColorScheme.primary,
              ),
              _buildToggleSwitch(theme,context),
            ],
          ),
          const SizedBox(height: 16),
          // 根据会员状态显示不同内容
          _buildContentByMembershipStatus(theme,context),
        ],
      ),
    );
  }

  Widget _buildContentByMembershipStatus(AppFlowyThemeData theme, BuildContext context) {
    switch (widget.membershipStatus) {
      case CloudSyncMembershipStatus.notSubscribed:
        return _buildNotSubscribedContent(theme,context);
      case CloudSyncMembershipStatus.active:
        return _buildActiveContent(theme,context);
      case CloudSyncMembershipStatus.expired:
      case CloudSyncMembershipStatus.storageFull:
        return _buildExpiredOrFullContent(theme,context);
    }
  }

  /// 未开通会员的内容
  Widget _buildNotSubscribedContent(AppFlowyThemeData theme, BuildContext context) {
    final usage = widget.currentSubscription?.usage;
    final storageUsedGb = usage?.storageUsedGb ?? 0.0;
    final storageTotalGb = usage?.storageTotalGb ?? 0.0;
    final remainingGb = (storageTotalGb - storageUsedGb).clamp(0.0, double.infinity);

    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    final subscription = widget.currentSubscription?.subscription;
    final planName = subscription?.planNameCn ?? '会员';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        FlowyText(
          '剩余空间：${fmt(remainingGb)} / ${fmt(storageTotalGb)}',
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 4),
        FlowyText(
          '最大可上传${widget.maxFileSize}文件',
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          '开通会员后即可享受云同步功能，数据安全备份，多设备同步',
          style: TextStyle(
            fontSize: 12,
            color: theme.textColorScheme.secondary,
            height: 1.4, // 行高
          ),
          softWrap: true, // 允许换行
          maxLines: null, // 不限制行数
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: '立即开通',
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
    final remainingGb = (storageTotalGb - storageUsedGb).clamp(0.0, double.infinity);
    
    String fmt(double gb) {
      if (gb < 1) {
        final mb = gb * 1024;
        return '${mb.toStringAsFixed(0)}M';
      }
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)}G';
    }

    final subscription = widget.currentSubscription?.subscription;
    final planName = subscription?.planNameCn ?? '会员';

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
                  '$planName有效中',
                  fontSize: 12,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FlowyText(
          '剩余空间：${fmt(remainingGb)} / ${fmt(storageTotalGb)}',
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 4),
        FlowyText(
          '最大可上传${widget.maxFileSize}文件',
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
      ],
    );
  }

  /// 已到期或空间使用满的内容
  Widget _buildExpiredOrFullContent(AppFlowyThemeData theme, BuildContext context) {
    final isExpired = widget.membershipStatus == CloudSyncMembershipStatus.expired;
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
                  isExpired ? '会员已到期' : '空间使用已满',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary ,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FlowyText(
          isExpired
              ? '您的会员已到期，请续费以继续使用云同步功能'
              : '已使用 ${storageUsedGb.toStringAsFixed(1)}G / ${storageTotalGb.toStringAsFixed(1)}G，空间已满',
          fontSize: 12,
          color: theme.textColorScheme.secondary,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: AFFilledTextButton.primary(
            text: isExpired ? '立即续费' : '扩容空间',
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
