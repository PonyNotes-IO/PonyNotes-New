import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/guest_tag.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_actions.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/widgets/cloud_sync_settings_panel.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/members/workspace_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/shared/settings/show_settings.dart' as settings;
import 'package:appflowy_popover/appflowy_popover.dart';
import '../../../../../application/subscription/membership_checker_service.dart';
import '_sidebar_import_notion.dart';

@visibleForTesting
const createWorkspaceButtonKey = ValueKey('createWorkspaceButton');

@visibleForTesting
const importNotionButtonKey = ValueKey('importNotionButton');

class WorkspacesMenu extends StatefulWidget {
  const WorkspacesMenu({
    super.key,
    required this.userProfile,
    required this.currentWorkspace,
    required this.workspaces,
  });

  final UserProfilePB userProfile;
  final UserWorkspacePB currentWorkspace;
  final List<UserWorkspacePB> workspaces;

  @override
  State<WorkspacesMenu> createState() => _WorkspacesMenuState();
}

class _WorkspacesMenuState extends State<WorkspacesMenu> {
  final popoverMutex = PopoverMutex();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppFlowyTheme.of(context).backgroundColorScheme.primary,
          borderRadius: BorderRadius.all(
              Radius.circular(theme.borderRadius.l))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context,widget.currentWorkspace),
          const VSpace(6.0),
          // user email
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: FlowyText.medium(
                    _getUserInfo(),
                    fontSize: 12.0,
                    overflow: TextOverflow.ellipsis,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const HSpace(4.0),
                WorkspaceMoreButton(
                  popoverMutex: popoverMutex,
                ),
                const HSpace(8.0),
              ],
            ),
          ),
          // const Padding(
          //   padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 6.0),
          //   child: Divider(height: 1.0),
          // ),
          // workspace list
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final workspace in widget.workspaces) ...[
                    WorkspaceMenuItem(
                      key: ValueKey(workspace.workspaceId),
                      workspace: workspace,
                      userProfile: widget.userProfile,
                      isSelected: workspace.workspaceId ==
                          widget.currentWorkspace.workspaceId,
                      popoverMutex: popoverMutex,
                    ),
                    const VSpace(6.0),
                  ],
                ],
              ),
            ),
          ),
          // add new workspace
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0),
            child: _CreateWorkspaceButton(),
          ),

          // if (UniversalPlatform.isDesktop) ...[
          //   const Padding(
          //     padding: EdgeInsets.only(left: 6.0, top: 6.0, right: 6.0),
          //     child: _ImportNotionButton(),
          //   ),
          // ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 20.0),
            child: Divider(height: 1.0),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 8, right: 8),
            child: FlowyButton(
              margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 7.0),
              leftIcon: const FlowySvg(FlowySvgs.workspace_logout_s),
              iconPadding: 10.0,
              text: FlowyText.regular(LocaleKeys.button_logout.tr()),
              onTap: () async {
                // 先关闭工作区弹框
                PopoverContainer.of(context).closeAll();
                
                final userProfile =
                    context.read<UserWorkspaceBloc>().state.userProfile;
                final isQuickEntryUser =
                    userProfile.userAuthType != AuthTypePB.Server;

                if (isQuickEntryUser) {
                  await showCancelAndConfirmDialog(
                    context: context,
                    title: '退出快速进入',
                    description:
                        '是否清除当前快速进入产生的数据？\n\n选择"清除并退出"会删除本地快速进入数据，下次进入将从空白开始；\n选择"保留数据退出"则仅重启应用，下次快速进入会尝试继续加载当前数据。',
                    confirmLabel: '清除并退出',
                    cancelLabel: '保留并退出',
                    onConfirm: (_) async {
                      await getIt<AuthService>().signOut();
                      // 清除并退出后，重启应用到登录页面，不自动登录
                      await runAppFlowy();
                    },
                    onCancel: () async {
                    // 保留数据退出，不调用signOut()，重启应用到登录页面
                    await runAppFlowy(isAnon: true);
                  },
                  );
                  return;
                }

                await getIt<AuthService>().signOut();
                await runAppFlowy();
              },
            ),
          )
        ],
      ),
    );
  }

  String _getUserInfo() {
    if (widget.userProfile.name.isNotEmpty) {
      return widget.userProfile.name;
    }

    if (widget.userProfile.email.isNotEmpty) {
      return widget.userProfile.email;
    }

    return LocaleKeys.defaultUsername.tr();
  }

  Widget _buildHeader(BuildContext context,UserWorkspacePB currentWorkspace) {
    final theme = AppFlowyTheme.of(context);
    final memberCount = widget.currentWorkspace.memberCount.toInt();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(theme.borderRadius.l),
            topRight: Radius.circular(theme.borderRadius.l)),
        // border: Border.all(
        //   color: theme.borderColorScheme.primary,
        // ),
      ),
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        children: [
          Row(children: [
            WorkspaceIcon(
                workspaceName: widget.currentWorkspace.name,
                workspaceIcon: widget.currentWorkspace.icon,
                iconSize: 40,
                emojiSize: 36.0,
                fontSize: 20.0,
                figmaLineHeight: 26.0,
                borderRadius: 6.0,
                isEditable: true,
                onSelected: (result) => () {}),
            HSpace(6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // workspace name
                  FlowyText.medium(
                    widget.currentWorkspace.name,
                    fontSize: 16.0,
                    figmaLineHeight: 17.0,
                    overflow: TextOverflow.ellipsis,
                    withTooltip: true,
                  ),
                  VSpace(6),
                  if (widget.currentWorkspace.role != AFRolePB.Guest) ...[
                    // workspace members count
                    FlowyText.regular(
                      memberCount == 0
                          ? ''
                          : LocaleKeys.settings_appearance_members_membersCount
                              .plural(
                              memberCount,
                            ),
                      fontSize: 12.0,
                      figmaLineHeight: 12.0,
                      color: Theme.of(context).hintColor,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.currentWorkspace.role == AFRolePB.Guest) ...[
              const HSpace(6.0),
              GuestTag(),
            ],
          ]),
          VSpace(12),
          Row(
            children: [
              _buildButton(context, LocaleKeys.settings_title.tr(),
                  FlowySvgs.icon_settings_s, (){
                    // 先关闭工作区弹框
                    PopoverContainer.of(context).closeAll();
                    // 打开设置弹框
                    settings.showSettingsDialog(
                      context,
                      widget.userProfile,
                      context.read<UserWorkspaceBloc>(),
                    );
                  }
              ),
              HSpace(8),
              _buildButton(
                  context,
                  LocaleKeys.settings_appearance_members_inviteMembers.tr(),
                  FlowySvgs.workspace_add_member_s,
                  (){
                    // 先关闭工作区弹框
                    PopoverContainer.of(context).closeAll();
                    // 打开设置弹框并跳转到成员管理页面
                    settings.showSettingsDialog(
                      context,
                      widget.userProfile,
                      context.read<UserWorkspaceBloc>(),
                      SettingsPage.member,
                    );
                  }
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, String name, FlowySvgData svg,
      GestureTapCallback? onTap) {
    final theme = AppFlowyTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.surfaceColorScheme.layer02,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.borderColorScheme.primary),
        ),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            FlowySvg(
              svg,
              size: Size.square(18),
              color: theme.textColorScheme.primary,
            ),
            HSpace(4),
            FlowyText.regular(
              name,
              color: theme.textColorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftIcon(BuildContext context) {
    return FlowySvg(
      FlowySvgs.icon_settings_s,
      color: Theme.of(context).colorScheme.primary,
      size: Size.square(30),
    );
  }
}

class WorkspaceMenuItem extends StatefulWidget {
  const WorkspaceMenuItem({
    super.key,
    required this.workspace,
    required this.userProfile,
    required this.isSelected,
    required this.popoverMutex,
  });

  final UserProfilePB userProfile;
  final UserWorkspacePB workspace;
  final bool isSelected;
  final PopoverMutex popoverMutex;

  @override
  State<WorkspaceMenuItem> createState() => _WorkspaceMenuItemState();
}

class _WorkspaceMenuItemState extends State<WorkspaceMenuItem> {
  final ValueNotifier<bool> isHovered = ValueNotifier(false);
  late final WorkspaceMemberBloc _memberBloc;

  @override
  void initState() {
    super.initState();
    _memberBloc = WorkspaceMemberBloc(
      userProfile: widget.userProfile,
      workspace: widget.workspace,
    )..add(const WorkspaceMemberEvent.initial());
  }

  @override
  void dispose() {
    isHovered.dispose();
    _memberBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _memberBloc,
      child: BlocBuilder<WorkspaceMemberBloc, WorkspaceMemberState>(
        builder: (context, state) {
          // settings right icon inside the flowy button will
          //  cause the popover dismiss intermediately when click the right icon.
          // so using the stack to put the right icon on the flowy button.
          return SizedBox(
            height: 36,
            child: MouseRegion(
              onEnter: (_) => isHovered.value = true,
              onExit: (_) => isHovered.value = false,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _WorkspaceInfo(
                    isSelected: widget.isSelected,
                    workspace: widget.workspace,
                  ),
                  Positioned(left: 4, child: _buildLeftIcon(context)),
                  Positioned(
                    right: 4.0,
                    child: Align(child: _buildRightIcon(context, isHovered)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeftIcon(BuildContext context) {
    return FlowyTooltip(
      message: LocaleKeys.document_plugins_cover_changeIcon.tr(),
      child: WorkspaceIcon(
        workspaceName: widget.workspace.name,
        workspaceIcon: widget.workspace.icon,
        iconSize: 28,
        emojiSize: 18.0,
        fontSize: 16.0,
        figmaLineHeight: 26.0,
        borderRadius: 6.0,
        isEditable: true,
        onSelected: (result) => context.read<UserWorkspaceBloc>().add(
              UserWorkspaceEvent.updateWorkspaceIcon(
                workspaceId: widget.workspace.workspaceId,
                icon: result.emoji,
              ),
            ),
      ),
    );
  }

  Widget _buildRightIcon(BuildContext context, ValueNotifier<bool> isHovered) {
    return Row(
      children: [
        // only the owner can update or delete workspace.
        if (!context.read<WorkspaceMemberBloc>().state.isLoading)
          ValueListenableBuilder(
            valueListenable: isHovered,
            builder: (context, value, child) {
              return Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Opacity(
                  opacity: value ? 1.0 : 0.0,
                  child: child,
                ),
              );
            },
            child: WorkspaceMoreActionList(
              workspace: widget.workspace,
              popoverMutex: widget.popoverMutex,
            ),
          ),
        // const HSpace(8.0),
        // if (widget.isSelected) ...[
        //   const Padding(
        //     padding: EdgeInsets.all(5.0),
        //     child: FlowySvg(
        //       FlowySvgs.workspace_selected_s,
        //       blendMode: null,
        //       size: Size.square(14.0),
        //     ),
        //   ),
        //   const HSpace(8.0),
        // ],
      ],
    );
  }
}

class _WorkspaceInfo extends StatelessWidget {
  const _WorkspaceInfo({
    required this.isSelected,
    required this.workspace,
  });

  final bool isSelected;
  final UserWorkspacePB workspace;

  @override
  Widget build(BuildContext context) {
    final memberCount = workspace.memberCount.toInt();
    return FlowyButton(
      onTap: () => _openWorkspace(context),
      iconPadding: 6.0,
      leftIconSize: const Size.square(24),
      leftIcon: const SizedBox.square(dimension: 24),
      rightIcon: const HSpace(32.0),
      text: Row(
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // workspace name
                FlowyText.medium(
                  workspace.name,
                  fontSize: 14.0,
                  figmaLineHeight: 17.0,
                  overflow: TextOverflow.ellipsis,
                  withTooltip: true,
                ),
                // if (workspace.role != AFRolePB.Guest) ...[
                //   // workspace members count
                //   FlowyText.regular(
                //     memberCount == 0
                //         ? ''
                //         : LocaleKeys.settings_appearance_members_membersCount
                //             .plural(
                //             memberCount,
                //           ),
                //     fontSize: 10.0,
                //     figmaLineHeight: 12.0,
                //     color: Theme.of(context).hintColor,
                //   ),
                // ],
              ],
            ),
          ),
          if (workspace.role == AFRolePB.Guest) ...[
            const HSpace(6.0),
            GuestTag(),
          ],
        ],
      ),
    );
  }

  void _openWorkspace(BuildContext context) {
    if (!isSelected) {
      Log.info('open workspace: ${workspace.workspaceId}');

      // Only trigger workspace opening - TabsBloc will be handled in UserWorkspaceBloc
      context.read<UserWorkspaceBloc>().add(
            UserWorkspaceEvent.openWorkspace(
              workspaceId: workspace.workspaceId,
              workspaceType: workspace.workspaceType,
            ),
          );

      PopoverContainer.of(context).closeAll();
    }
  }
}

class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({
    super.key,
    required this.onConfirm,
    this.title,
  });

  final void Function(String name) onConfirm;
  final String? title;

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  @override
  Widget build(BuildContext context) {
    return BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
      listenWhen: (previous, current) {
        return previous.actionResult?.actionType !=
                current.actionResult?.actionType ||
            previous.actionResult?.isLoading != current.actionResult?.isLoading;
      },
      listener: (context, state) {
        final actionResult = state.actionResult;
        if (actionResult != null &&
            actionResult.actionType == WorkspaceActionType.create &&
            !actionResult.isLoading) {
          // 工作空间创建完成，检查context是否仍然mounted
          if (context.mounted) {
            // 使用SchedulerBinding确保在下一帧执行，避免Navigator状态冲突
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            });
          }

          // 如果创建失败，记录错误信息
          actionResult.result?.fold(
            (success) {
              Log.info('Workspace created successfully');
            },
            (error) {
              Log.error('Failed to create workspace: ${error.msg}');
            },
          );
        }
      },
      child: _WorkspaceDialogContent(
        onConfirm: widget.onConfirm,
      ),
    );
  }
}

class _WorkspaceDialogContent extends StatelessWidget {
  const _WorkspaceDialogContent({
    required this.onConfirm,
    this.title,
  });

  final void Function(String) onConfirm;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return NavigatorTextFieldDialog(
      title: title ?? '新建团队协作区',
      value: '',
      hintText: '',
      autoSelectAllText: true,
      onConfirm: (name, _) => onConfirm(name),
    );
  }
}

class _CreateWorkspaceButton extends StatelessWidget {
  const _CreateWorkspaceButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: FlowyButton(
        key: createWorkspaceButtonKey,
        onTap: () async {
          Log.info('Create workspace button clicked');
          
          // 先获取最新的订阅信息
          context.read<UserWorkspaceBloc>().add(UserWorkspaceEvent.fetchCurrentSubscription());

          // 检查工作区数量限制
          final canCreate = await _checkWorkspaceLimit(context);
          if (!canCreate) {
            PopoverContainer.of(context).closeAll();
            return;
          }
          PopoverContainer.of(context).closeAll();
          // 等待一个微任务，确保 popover 关闭完成
          await Future.delayed(Duration.zero);
          if (context.mounted) {
            await _showCreateWorkspaceDialog(context);
          }
        },
        // margin: const EdgeInsets.symmetric(horizontal: 4.0),
        text: Row(
          children: [
            _buildLeftIcon(context),
            const HSpace(4.0),
            FlowyText.regular(
              LocaleKeys.workspace_create.tr(),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  // 检查工作区数量限制
  Future<bool> _checkWorkspaceLimit(BuildContext context) async {
    try {
      final workspaceBloc = context.read<UserWorkspaceBloc>();
      final state = workspaceBloc.state;
      
      // 只计算自己创建的工作区（role 为 Owner），不包含加入的工作区（Member/Guest）
      final ownedWorkspaceCount = state.workspaces
          .where((ws) => ws.role == AFRolePB.Owner)
          .length;
      Log.info('Owned workspace count: $ownedWorkspaceCount (total: ${state.workspaces.length})');

      // 检查是否有权限创建更多工作区
      final canCreate = await context.checkAndHandleWorkspaceCreation(
          workspaceId: state.currentWorkspace?.workspaceId,
          currentWorkspaceCount: ownedWorkspaceCount,
      );
      return canCreate;
    } catch (e) {
      Log.error('Error checking workspace limit: $e');
      // 如果检查失败，默认允许创建工作区
      return true;
    }
  }

  Widget _buildLeftIcon(BuildContext context) {
    return Container(
      // width: 36.0,
      // height: 36.0,
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      // decoration: BoxDecoration(
      //   borderRadius: BorderRadius.circular(12),
      //   border: Border.all(
      //     color: const Color(0x01717171).withValues(alpha: 0.12),
      //     width: 0.8,
      //   ),
      // ),
      child: FlowySvg(
        FlowySvgs.icon_add_circle_s,
        color: Theme.of(context).colorScheme.primary,
        size: Size.square(30),
      ),
    );
  }

  Future<void> _showCreateWorkspaceDialog(BuildContext context) async {
    if (!context.mounted) {
      Log.warn(
          'Context is not mounted when trying to show create workspace dialog');
      return;
    }

    try {
      final workspaceBloc = context.read<UserWorkspaceBloc>();
      final userProfile = workspaceBloc.state.userProfile;
      final isCloudSyncEnabled = workspaceBloc.state.isCloudSyncEnabled;

      Log.info(
          'Showing create workspace dialog for user: ${userProfile.email}, auth type: ${userProfile.userAuthType}, isCloudSyncEnabled: $isCloudSyncEnabled');

      // 检查云同步状态：如果云同步关闭，不能创建工作区
      if (!isCloudSyncEnabled) {
        Log.warn('云同步已关闭，不能创建工作区');
        // 显示提示对话框，引导用户开启云同步
        if (!context.mounted) return;
        await showConfirmDialog(
          context: context,
          title: LocaleKeys.workspace_create.tr(),
          description: '云同步已关闭，无法创建工作区。请先开启云同步功能。',
          confirmLabel: '知道了',
        );
        return;
      }

      final dialog = CreateWorkspaceDialog(
        title: LocaleKeys.workspace_create.tr(),
        onConfirm: (name) {
          // DEBUG BREAKPOINT 3: onConfirm 回调被调用
          Log.info('=== DEBUG BREAKPOINT 3 === onConfirm 回调被调用，工作空间名称: $name');

          if (name.trim().isEmpty) {
            Log.warn('Workspace name is empty, cannot create workspace');
            return;
          }

          // 智能选择工作空间类型：
          // 1. 默认创建 ServerW 类型的工作区（cloud 保存），与 AppFlowy 的默认行为一致
          // 2. 如果云同步开启，创建服务器工作空间（会同步到服务端）
          // 3. 如果云同步关闭，创建本地工作空间（不同步到服务端）
          // 4. 如果用户是本地认证类型，强制创建本地工作空间
          final isCloudSyncEnabled = workspaceBloc.state.isCloudSyncEnabled;
          final workspaceType = userProfile.userAuthType == AuthTypePB.Local
              ? WorkspaceTypePB.LocalW
              : WorkspaceTypePB
                  .ServerW; // 默认创建 ServerW 类型（cloud 保存），与 AppFlowy 的默认行为一致

          Log.info(
              'Creating workspace: name="$name", type=$workspaceType, isCloudSyncEnabled=$isCloudSyncEnabled');

          // DEBUG BREAKPOINT 4: 即将发送创建工作空间事件
          Log.info('=== DEBUG BREAKPOINT 4 === 即将发送创建工作空间事件到 BLoC');

          workspaceBloc.add(
            UserWorkspaceEvent.createWorkspace(
              name: name,
              workspaceType: workspaceType,
            ),
          );

          // DEBUG BREAKPOINT 5: 创建工作空间事件已发送
          Log.info('=== DEBUG BREAKPOINT 5 === 创建工作空间事件已发送到 BLoC');
        },
      );

      Log.info('About to show dialog...');

      // 确保键盘状态清理以避免输入问题
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 50));

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => BlocProvider.value(
            value: workspaceBloc,
            child: dialog,
          ),
        );
      }
      Log.info('Dialog shown successfully');
    } catch (e, stackTrace) {
      Log.error('Failed to show create workspace dialog: $e');
      Log.error('Stack trace: $stackTrace');

      // 如果对话框显示失败，尝试使用Flutter原生的showDialog作为后备方案
      if (context.mounted) {
        try {
          Log.info('Trying fallback dialog approach...');
          await showDialog(
            context: context,
            builder: (dialogContext) => BlocProvider.value(
              value: context.read<UserWorkspaceBloc>(),
              child: CreateWorkspaceDialog(
                title: LocaleKeys.workspace_create.tr(),
                onConfirm: (name) {
                  if (name.trim().isEmpty) {
                    Log.warn(
                        'Workspace name is empty, cannot create workspace');
                    return;
                  }

                  final workspaceBloc = context.read<UserWorkspaceBloc>();
                  final userProfile = workspaceBloc.state.userProfile;
                  final isCloudSyncEnabled =
                      workspaceBloc.state.isCloudSyncEnabled;
                  final workspaceType = userProfile.userAuthType ==
                          AuthTypePB.Local
                      ? WorkspaceTypePB.LocalW
                      : WorkspaceTypePB
                          .ServerW; // 默认创建 ServerW 类型（cloud 保存），与 AppFlowy 的默认行为一致

                  Log.info(
                      'Creating workspace via fallback: name="$name", type=$workspaceType, isCloudSyncEnabled=$isCloudSyncEnabled');

                  workspaceBloc.add(
                    UserWorkspaceEvent.createWorkspace(
                      name: name,
                      workspaceType: workspaceType,
                    ),
                  );
                },
              ),
            ),
          );
          Log.info('Fallback dialog worked');
        } catch (fallbackError) {
          Log.error('Fallback dialog also failed: $fallbackError');
        }
      }
    }
  }
}

class _ImportNotionButton extends StatelessWidget {
  const _ImportNotionButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FlowyButton(
        key: importNotionButtonKey,
        onTap: () {
          _showImportNotinoDialog(context);
        },
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        text: Row(
          children: [
            _buildLeftIcon(context),
            const HSpace(8.0),
            FlowyText.regular(
              LocaleKeys.workspace_importFromNotion.tr(),
            ),
          ],
        ),
        rightIcon: FlowyTooltip(
          message: LocaleKeys.workspace_learnMore.tr(),
          preferBelow: true,
          child: FlowyIconButton(
            icon: const FlowySvg(
              FlowySvgs.information_s,
            ),
            onPressed: () {
              afLaunchUrlString(
                'https://docs.appflowy.io/docs/guides/import-from-notion',
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLeftIcon(BuildContext context) {
    return Container(
      width: 36.0,
      height: 36.0,
      padding: const EdgeInsets.all(7.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0x01717171).withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: const FlowySvg(FlowySvgs.add_workspace_s),
    );
  }

  Future<void> _showImportNotinoDialog(BuildContext context) async {
    final result = await getIt<FilePickerService>().pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final path = result.files.first.path;
    if (path == null) {
      return;
    }

    if (context.mounted) {
      PopoverContainer.of(context).closeAll();
      await showDialog(
        context: context,
        builder: (context) => NavigatorCustomDialog(
          hideCancelButton: true,
          confirm: () {},
          child: NotionImporter(
            filePath: path,
          ),
        ),
      );
    } else {
      Log.error('context is not mounted when showing import notion dialog');
    }
  }
}

@visibleForTesting
class WorkspaceMoreButton extends StatelessWidget {
  const WorkspaceMoreButton({
    super.key,
    required this.popoverMutex,
  });

  final PopoverMutex popoverMutex;

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 6),
      mutex: popoverMutex,
      asBarrier: true,
      popupBuilder: (_) => FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 7.0),
        leftIcon: const FlowySvg(FlowySvgs.workspace_logout_s),
        iconPadding: 10.0,
        text: FlowyText.regular(LocaleKeys.button_logout.tr()),
        onTap: () async {
          // 先关闭更多按钮的弹出菜单
          PopoverContainer.maybeOf(context)?.closeAll();
          
          // 再关闭工作区弹框
          PopoverContainer.of(context).closeAll();
          
          final userProfile =
              context.read<UserWorkspaceBloc>().state.userProfile;
          final isQuickEntryUser =
              userProfile.userAuthType != AuthTypePB.Server;

          if (isQuickEntryUser) {
            await showCancelAndConfirmDialog(
              context: context,
              title: '退出快速进入',
              description:
                  '是否清除当前快速进入产生的数据？\n\n选择"清除并退出"会删除本地快速进入数据，下次进入将从空白开始；\n选择"保留数据退出"则仅重启应用，下次快速进入会尝试继续加载当前数据。',
              confirmLabel: '清除并退出',
              cancelLabel: '保留并退出',
              onConfirm: (_) async {
                  await getIt<AuthService>().signOut();
                  // 清除并退出后，重启应用到登录页面，不自动登录
                  await runAppFlowy();
                },
              onCancel: () async {
                await runAppFlowy(isAnon: true);
              },
            );
            return;
          }

          await getIt<AuthService>().signOut();
          await runAppFlowy();
        },
      ),
      child: SizedBox.square(
        dimension: 24.0,
        child: FlowyButton(
          useIntrinsicWidth: true,
          margin: EdgeInsets.zero,
          text: const FlowySvg(
            FlowySvgs.workspace_three_dots_s,
            size: Size.square(16.0),
          ),
          onTap: () {},
        ),
      ),
    );
  }
}
