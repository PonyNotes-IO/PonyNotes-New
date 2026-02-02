import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/settings/show_settings.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/widgets/cloud_sync_settings_panel.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarCloudSyncButton extends StatefulWidget {
  const SidebarCloudSyncButton({
    super.key,
    this.isHover = false,
  });

  final bool isHover;

  @override
  State<SidebarCloudSyncButton> createState() => _SidebarCloudSyncButtonState();
}

class _SidebarCloudSyncButtonState extends State<SidebarCloudSyncButton> {
  final GlobalKey _buttonKey = GlobalKey(); // 用于获取按钮位置

  @override
  Widget build(BuildContext context) {
    // 尝试获取 UserWorkspaceBloc，如果不存在则直接显示按钮
    try {
      final workspaceBloc = context.read<UserWorkspaceBloc>();
      // 使用 BlocBuilder 监听 UserWorkspaceBloc，获取最新的会员订阅信息和云同步开关状态
      return BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
        bloc: workspaceBloc,
        builder: (context, workspaceState) {
          // 确保会员信息已加载
          final currentSubscription = workspaceState.currentSubscription;
          final subscriptionInfo = workspaceState.workspaceSubscriptionInfo;
          final isCloudSyncEnabled =
              workspaceState.isCloudSyncEnabled; // 从 Bloc 状态中获取云同步开关状态

          // 如果会员信息还没有加载，触发获取
          if (currentSubscription == null) {
            workspaceBloc.add(UserWorkspaceEvent.fetchCurrentSubscription());
          }

          // 如果工作空间订阅信息还没有加载，触发获取
          if (subscriptionInfo == null) {
            final workspaceId = workspaceState.currentWorkspace?.workspaceId;
            if (workspaceId != null && workspaceId.isNotEmpty) {
              workspaceBloc.add(
                UserWorkspaceEvent.fetchWorkspaceSubscriptionInfo(
                    workspaceId: workspaceId),
              );
            }
          }

          return _buildCloudSyncIcon(
            context,
            () => _showCloudSyncSettings(
              context,
              subscriptionInfo: subscriptionInfo,
              currentSubscription: currentSubscription,
              isCloudSyncEnabled: isCloudSyncEnabled,
            ),
            folderSyncState: workspaceState.folderSyncState,
            isCloudSyncEnabled: isCloudSyncEnabled,
          );
        },
      );
    } catch (e) {
      // 如果 UserWorkspaceBloc 不存在，直接显示按钮（不传递会员信息）
      Log.warn('[云同步按钮] UserWorkspaceBloc 不可用: $e');
      return _buildCloudSyncIcon(
        context,
        () => _showCloudSyncSettings(
          context,
          subscriptionInfo: null,
          currentSubscription: null,
          isCloudSyncEnabled: false,
        ),
        folderSyncState: null,
        isCloudSyncEnabled: false,
      );
    }
  }

  Future<void> _showCloudSyncSettings(
    BuildContext context, {
    required WorkspaceSubscriptionInfoPB? subscriptionInfo,
    required CurrentSubscription? currentSubscription,
    required bool isCloudSyncEnabled,
  }) async {
    // 获取按钮的位置信息
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset buttonPosition = renderBox.localToGlobal(Offset.zero);
    final Size buttonSize = renderBox.size;

    Log.info(
        '[云同步] 显示弹框，会员信息状态: subscriptionInfo=${subscriptionInfo?.plan}, currentSubscription=${currentSubscription?.subscription?.planCode}');

    // 判断会员状态
    final membershipStatus = _determineMembershipStatus(
      subscriptionInfo,
      currentSubscription,
    );

    Log.info('[云同步] 判断会员状态: $membershipStatus');

    if (!mounted) return;

    // 保存原始 context，用于后续打开设置对话框
    final originalContext = context;

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        // 尝试获取 UserWorkspaceBloc，如果存在则监听状态变化
        try {
          final workspaceBloc = originalContext.read<UserWorkspaceBloc>();
          // 使用 BlocBuilder 监听 UserWorkspaceBloc 状态变化，自动更新会员信息
          return BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
            bloc: workspaceBloc,
            builder: (builderContext, state) {
              // 获取最新的会员信息（优先使用状态中的最新数据）
              final latestSubscriptionInfo =
                  state.workspaceSubscriptionInfo ?? subscriptionInfo;
              final latestCurrentSubscription =
                  state.currentSubscription ?? currentSubscription;
              final latestIsCloudSyncEnabled =
                  state.isCloudSyncEnabled; // 从 Bloc 状态中获取最新的云同步开关状态

              // 重新判断会员状态（使用最新的数据）
              final latestMembershipStatus = _determineMembershipStatus(
                latestSubscriptionInfo,
                latestCurrentSubscription,
              );

              Log.info(
                  '[云同步弹框] 更新会员信息: subscriptionInfo=${latestSubscriptionInfo?.plan}, currentSubscription=${latestCurrentSubscription?.subscription?.planCode}, status=$latestMembershipStatus, isCloudSyncEnabled=$latestIsCloudSyncEnabled');

              return _buildDialogContent(
                originalContext, // 使用原始 context，用于访问 UserWorkspaceBloc
                dialogContext, // dialog context，用于关闭弹框
                buttonPosition,
                buttonSize,
                latestMembershipStatus,
                latestSubscriptionInfo,
                latestCurrentSubscription,
                latestIsCloudSyncEnabled,
              );
            },
          );
        } catch (e) {
          // 如果 UserWorkspaceBloc 不存在，使用传入的会员信息
          Log.warn('[云同步弹框] UserWorkspaceBloc 不可用，使用传入的会员信息: $e');
          final membershipStatus = _determineMembershipStatus(
            subscriptionInfo,
            currentSubscription,
          );
          return _buildDialogContent(
            originalContext, // 使用原始 context
            dialogContext,
            buttonPosition,
            buttonSize,
            membershipStatus,
            subscriptionInfo,
            currentSubscription,
            isCloudSyncEnabled,
          );
        }
      },
    );
  }

  Widget _buildDialogContent(
    BuildContext context, // 原始 context，用于访问 UserWorkspaceBloc
    BuildContext dialogContext, // dialog context，用于关闭弹框
    Offset buttonPosition,
    Size buttonSize,
    CloudSyncMembershipStatus membershipStatus,
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
    CurrentSubscription? currentSubscription,
    bool isCloudSyncEnabled,
  ) {
    return Stack(
      children: [
        Positioned(
          left: buttonPosition.dx,
          top: buttonPosition.dy + buttonSize.height,
          child: Material(
            color: Colors.transparent,
            child: CloudSyncSettingsPanel(
              isEnabled: isCloudSyncEnabled,
              membershipStatus: membershipStatus,
              subscriptionInfo: subscriptionInfo,
              currentSubscription: currentSubscription,
              onToggle: (enabled) {
                // 更新 UserWorkspaceBloc 中的云同步开关状态
                try {
                  final workspaceBloc = context.read<UserWorkspaceBloc>();
                  workspaceBloc.add(
                    UserWorkspaceEvent.updateCloudSyncEnabled(enabled: enabled),
                  );
                  Log.info('[云同步] 更新云同步开关状态: $enabled');
                } catch (e, stackTrace) {
                  Log.error('[云同步] 无法更新云同步开关状态: $e', e, stackTrace);
                }
                debugPrint('云同步状态: ${enabled ? "已启用" : "已禁用"}');
                Navigator.of(dialogContext).pop();
              },
              onUpgrade: () {
                // 关闭云同步弹框
                Navigator.of(dialogContext).pop();
                // 打开设置对话框，并跳转到会员升级页面
                try {
                  // 使用原始 context（不是 dialogContext）来打开设置对话框
                  final userProfile =
                      context.read<UserWorkspaceBloc>().state.userProfile;
                  final workspaceBloc = context.read<UserWorkspaceBloc>();
                  showSettingsDialog(
                    context,
                    userProfile,
                    workspaceBloc,
                    SettingsPage.accountManagement,
                  );
                } catch (e, stackTrace) {
                  Log.error('无法打开设置对话框并跳转到会员升级页面: $e', e, stackTrace);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 判断会员状态
  CloudSyncMembershipStatus _determineMembershipStatus(
    WorkspaceSubscriptionInfoPB? subscriptionInfo,
    CurrentSubscription? currentSubscription,
  ) {
    // 优先使用 currentSubscription 判断会员状态（更准确，包含使用量信息）
    final subscription = currentSubscription?.subscription;
    final usage = currentSubscription?.usage;

    // 如果 currentSubscription 有数据，优先使用它判断
    if (subscription != null &&
        subscription.planCode != null &&
        subscription.planCode!.isNotEmpty) {
      // 检查计划代码是否为免费版
      final planCode = subscription.planCode!.toLowerCase();
      if (planCode == 'free' || planCode == 'freeplan' || planCode == 'fmb') {
        return CloudSyncMembershipStatus.notSubscribed;
      }

      // 检查是否已到期
      final endDate = subscription.endDate;
      if (endDate != null && endDate.isBefore(DateTime.now())) {
        return CloudSyncMembershipStatus.expired;
      }

      // 检查空间是否已满
      final storageUsedGb = usage?.storageUsedGb;
      final storageTotalGb = usage?.storageTotalGb;
      if (storageUsedGb != null &&
          storageTotalGb != null &&
          storageUsedGb >= storageTotalGb) {
        return CloudSyncMembershipStatus.storageFull;
      }

      // 会员有效中
      return CloudSyncMembershipStatus.active;
    }

    // 如果 currentSubscription 没有数据，使用 subscriptionInfo 判断（降级方案）
    if (subscriptionInfo != null) {
      if (subscriptionInfo.plan == WorkspacePlanPB.FreePlan) {
        return CloudSyncMembershipStatus.notSubscribed;
      }
      // subscriptionInfo 有数据但不是免费版，认为会员有效中
      // 注意：subscriptionInfo 不包含到期时间和使用量信息，所以无法判断过期和空间满
      return CloudSyncMembershipStatus.active;
    }

    // 两个数据源都没有，认为未开通会员
    return CloudSyncMembershipStatus.notSubscribed;
  }

  Widget _buildCloudSyncIcon(
    BuildContext context,
    VoidCallback onTap, {
    required FolderSyncStatePB? folderSyncState,
    required bool isCloudSyncEnabled,
  }) {
    // 如果云同步未启用，只显示默认图标
    if (!isCloudSyncEnabled) {
      return SizedBox.square(
        key: _buttonKey,
        dimension: 28.0,
        child: FlowyButton(
          useIntrinsicWidth: true,
          margin: EdgeInsets.zero,
          text: FlowySvg(
            FlowySvgs.cloud_sync_m,
            color:
                widget.isHover ? Theme.of(context).colorScheme.onSurface : null,
            opacity: 0.7,
          ),
          onTap: onTap,
        ),
      );
    }

    // 根据同步状态选择图标和样式
    FlowySvgData iconData;
    Color iconColor;
    Color labelColor;
    String labelText;

    // 根据同步状态选择图标
    if (folderSyncState == null) {
      // 状态未知，使用默认图标
      iconData = FlowySvgs.cloud_sync_m;
      iconColor = Colors.grey;
      labelColor = Colors.grey;
      labelText = LocaleKeys.newSettings_syncState_syncing.tr();
    } else if (folderSyncState.isSyncing) {
      // 同步中，使用同步中图标（红色）
      iconData = FlowySvgs.cloud_syncing_m;
      iconColor = Colors.red;
      labelColor = Colors.red;
      labelText = LocaleKeys.newSettings_syncState_syncing.tr();
    } else if (folderSyncState.isFinish) {
      // 已同步，使用同步完成图标（绿色）
      iconData = FlowySvgs.cloud_sync_finish_m;
      iconColor = Colors.green;
      labelColor = Colors.green;
      labelText = LocaleKeys.newSettings_syncState_synced.tr();
    } else {
      // 其他状态，使用默认图标
      iconData = FlowySvgs.cloud_sync_m;
      iconColor = Colors.grey;
      labelColor = Colors.grey;
      labelText = LocaleKeys.newSettings_syncState_syncing.tr();
    }

    return SizedBox.square(
      key: _buttonKey,
      dimension: 28.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            child: FlowyButton(
              useIntrinsicWidth: true,
              margin: EdgeInsets.zero,
              text: FlowySvg(
                iconData,
                color: widget.isHover
                    ? Theme.of(context).colorScheme.onSurface
                    : iconColor,
                opacity: widget.isHover ? 0.7 : 1.0,
              ),
              onTap: onTap,
            ),
          ),
          // 右上角文字标签
          Positioned(
            top: -8.0,
            right: -12.0,
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 40.0,
                minWidth: 20.0,
                maxHeight: 14.0,
              ),
              padding:
                  const EdgeInsets.only(left: 5.0, top: 2.0,right: 5.0,bottom: 1.0),
              decoration: BoxDecoration(
                color: labelColor,
                borderRadius: BorderRadius.circular(7.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 2.0,
                    offset: const Offset(0, 1.0),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  labelText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
