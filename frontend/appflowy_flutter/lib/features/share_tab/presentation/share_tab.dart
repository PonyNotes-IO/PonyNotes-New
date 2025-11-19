import 'dart:async';

import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/people_with_access_section.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/shared_user_widget.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';

import 'package:appflowy/plugins/shared/share/share_bloc.dart';

import '../../../workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import '../data/models/share_access_level.dart';

class ShareTab extends StatefulWidget {
  const ShareTab({
    super.key,
    required this.workspaceId,
    required this.pageId,
    required this.workspaceName,
    required this.workspaceIcon,
    required this.isInProPlan,
    required this.onUpgradeToPro,
  });

  final String workspaceId;
  final String pageId;

  // these 2 values should be provided by the share tab bloc
  final String workspaceName;
  final String workspaceIcon;

  final bool isInProPlan;
  final VoidCallback onUpgradeToPro;

  @override
  State<ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<ShareTab> {
  final TextEditingController controller = TextEditingController();
  late final ShareTabBloc shareTabBloc;

  @override
  void initState() {
    super.initState();

    shareTabBloc = context.read<ShareTabBloc>();
  }

  @override
  void dispose() {
    controller.dispose();
    shareTabBloc.add(ShareTabEvent.clearState());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return BlocConsumer<ShareTabBloc, ShareTabState>(
      listener: (context, state) {
        _onListenShareWithUserState(context, state);
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const SizedBox.shrink();
        }

        // final currentUser = state.currentUser;
        // final accessLevel = state.users
        //     .firstWhereOrNull(
        //       (user) => user.email == currentUser?.email,
        //     )
        //     ?.accessLevel;
        // final isFullAccess = accessLevel == ShareAccessLevel.fullAccess;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // share page with user by email
            // only user with full access can invite others
            VSpace(theme.spacing.l),
            Row(
              children: [
                FlowyText("当前文档为私密，仅自己和协作者可访问"),
              ],
            ),
            VSpace(theme.spacing.m),
            _buildLinkAndCopyButton(
              state.shareLink,
              state.users.isNotEmpty,
            ),

            // ShareWithUserWidget(
            //   controller: controller,
            //   disabled: !isFullAccess,
            //   onInvite: (emails) => _handleShareWithUser(
            //     emails: emails,
            //   ),
            // ),

            // if (!widget.isInProPlan && !state.hasClickedUpgradeToPro) ...[
            //   UpgradeToProWidget(
            //     onClose: () {
            //       context.read<ShareTabBloc>().add(
            //             ShareTabEvent.upgradeToProClicked(),
            //           );
            //     },
            //     onUpgrade: widget.onUpgradeToPro,
            //   ),
            // ],


            // general access
            // if (state.sectionType == SharedSectionType.public) ...[
            //   VSpace(theme.spacing.m),
            //   GeneralAccessSection(
            //     group: SharedGroup(
            //       id: widget.workspaceId,
            //       name: widget.workspaceName,
            //       icon: widget.workspaceIcon,
            //     ),
            //   ),
            // ],

            // copy link
            // VSpace(theme.spacing.xl),
            // CopyLinkWidget(shareLink: state.shareLink),
            // VSpace(theme.spacing.m),
          ],
        );
      },
    );
  }

  PeopleWithAccessSectionCallbacks _buildPeopleWithAccessSectionCallbacks(
    BuildContext context,
  ) {
    return PeopleWithAccessSectionCallbacks(
      onSelectAccessLevel: (user, accessLevel) {
        context.read<ShareTabBloc>().add(
              ShareTabEvent.updateUserAccessLevel(
                email: user.email,
                accessLevel: accessLevel,
              ),
            );
      },
      onTurnIntoMember: (user) {
        context.read<ShareTabBloc>().add(
              ShareTabEvent.convertToMember(email: user.email),
            );
      },
      onRemoveAccess: (user) {
        // show a dialog to confirm the action when removing self access
        final theme = AppFlowyTheme.of(context);
        final shareTabBloc = context.read<ShareTabBloc>();
        final removingSelf =
            user.email == shareTabBloc.state.currentUser?.email;
        if (removingSelf) {
          showConfirmDialog(
            context: context,
            title: 'Remove your own access',
            titleStyle: theme.textStyle.body.standard(
              color: theme.textColorScheme.primary,
            ),
            description: '',
            style: ConfirmPopupStyle.cancelAndOk,
            confirmLabel: 'Remove',
            onConfirm: (_) {
              shareTabBloc.add(
                ShareTabEvent.removeUsers(emails: [user.email]),
              );
            },
          );
        } else {
          shareTabBloc.add(
            ShareTabEvent.removeUsers(emails: [user.email]),
          );
        }
      },
    );
  }

  void _handleShareWithUser({required List<String> emails}) {
    shareTabBloc.add(
      ShareTabEvent.inviteUsers(
        emails: emails,
        accessLevel: ShareAccessLevel.readAndWrite,
      ),
    );
  }

  /// 构建包含拥有者的完整用户列表，拥有者始终在最前面
  List<SharedUser> _buildUsersListWithOwner({
    required SharedUsers users,
    required UserProfilePB? currentUser,
  }) {
    if (currentUser == null) {
      return users;
    }

    // 查找是否已有拥有者
    final owner = users.firstWhereOrNull(
      (user) => user.role == ShareRole.owner,
    );

    // 如果已有拥有者，将其放在最前面，其他用户放在后面
    if (owner != null) {
      final otherUsers = users.where((user) => user.role != ShareRole.owner).toList();
      return [owner, ...otherUsers];
    }

    // 如果没有拥有者，创建拥有者对象（使用当前用户信息）
    final ownerUser = SharedUser(
      email: currentUser.email,
      name: currentUser.name.isNotEmpty ? currentUser.name : currentUser.email,
      role: ShareRole.owner,
      accessLevel: ShareAccessLevel.fullAccess,
      avatarUrl: currentUser.iconUrl.isNotEmpty ? currentUser.iconUrl : null,
    );

    // 检查当前用户是否已在列表中
    final currentUserInList = users.firstWhereOrNull(
      (user) => user.email == currentUser.email,
    );

    if (currentUserInList != null) {
      // 如果当前用户已在列表中，将其替换为拥有者，并放在最前面
      final otherUsers = users.where((user) => user.email != currentUser.email).toList();
      return [ownerUser, ...otherUsers];
    } else {
      // 如果当前用户不在列表中，将拥有者放在最前面
      return [ownerUser, ...users];
    }
  }

  void _onListenShareWithUserState(
    BuildContext context,
    ShareTabState state,
  ) {
    final shareResult = state.shareResult;
    if (shareResult != null) {
      shareResult.fold((success) {
        // clear the controller to avoid showing the previous emails
        controller.clear();

        showToastNotification(
          message: LocaleKeys.shareTab_invitationSent.tr(),
        );
      }, (error) {
        String message;
        switch (error.code) {
          case ErrorCode.InvalidGuest:
            message = LocaleKeys.shareTab_emailAlreadyInList.tr();
            break;
          case ErrorCode.FreePlanGuestLimitExceeded:
            message = LocaleKeys.shareTab_upgradeToProToInviteGuests.tr();
            break;
          case ErrorCode.PaidPlanGuestLimitExceeded:
            message = LocaleKeys.shareTab_maxGuestsReached.tr();
            break;
          default:
            message = error.msg;
        }
        showToastNotification(
          message: message,
          type: ToastificationType.error,
        );
      });
    }

    final removeResult = state.removeResult;
    if (removeResult != null) {
      removeResult.fold((success) {
        showToastNotification(
          message: LocaleKeys.shareTab_removedGuestSuccessfully.tr(),
        );
      }, (error) {
        showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        );
      });
    }

    final updateAccessLevelResult = state.updateAccessLevelResult;
    if (updateAccessLevelResult != null) {
      updateAccessLevelResult.fold((success) {
        showToastNotification(
          message: LocaleKeys.shareTab_updatedAccessLevelSuccessfully.tr(),
        );
      }, (error) {
        showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        );
      });
    }

    final turnIntoMemberResult = state.turnIntoMemberResult;
    if (turnIntoMemberResult != null) {
      turnIntoMemberResult.fold((success) {
        showToastNotification(
          message: LocaleKeys.shareTab_turnedIntoMemberSuccessfully.tr(),
        );
      }, (error) {
        showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        );
      });
    }
  }

  Widget _buildPermissionDescription(AppFlowyThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText.medium(
          '权限说明',
          color: theme.textColorScheme.primary,
        ),
        VSpace(theme.spacing.xs),
        ...ShareAccessLevel.values.map(
          (level) => Padding(
            padding: EdgeInsets.only(bottom: theme.spacing.xs),
            child: Text(
              '${level.title}: ${level.subtitle}',
              style: theme.textStyle.caption.standard(
                color: theme.textColorScheme.secondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCollaboratorsDialog(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final inviteController = TextEditingController();

    // 清空搜索结果
    shareTabBloc.add(ShareTabEvent.searchAvailableUsers(query: ''));

    showDialog(
      context: context,
      builder: (dialogContext) {
        return BlocProvider.value(
          value: shareTabBloc,
          child: BlocConsumer<ShareTabBloc, ShareTabState>(
            listener: (context, state) {
              _onListenShareWithUserState(context, state);
              // Clear invite controller when invitation is sent successfully
              final shareResult = state.shareResult;
              if (shareResult != null) {
                shareResult.fold((success) {
                  inviteController.clear();
                  // 清空搜索结果
                  shareTabBloc.add(ShareTabEvent.searchAvailableUsers(query: ''));
                }, (error) {});
              }
            },
            builder: (context, state) {
              final currentUser = state.currentUser;
              final users = state.users;

              // 构建完整的用户列表，确保拥有者始终在最前面
              final List<SharedUser> allUsers = _buildUsersListWithOwner(
                users: users,
                currentUser: currentUser,
              );

              // 从完整列表中查找当前用户（包括拥有者）
              final currentSharedUser = allUsers.firstWhereOrNull(
                (user) => user.email == currentUser?.email,
              );

              return Dialog(
                insetPadding: const EdgeInsets.all(24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: const FlowySvg(FlowySvgs.arrow_left_s),
                            ),
                            HSpace(theme.spacing.s),
                            FlowyText.medium(
                              '文档协作者',
                              color: theme.textColorScheme.primary,
                            ),
                          ],
                        ),
                        VSpace(theme.spacing.m),
                        const Divider(height: 1),
                        VSpace(theme.spacing.m),

                        // Search input
                        _UserSearchField(
                          controller: inviteController,
                          onSearch: (query) {
                            if (query.isNotEmpty) {
                              context.read<ShareTabBloc>().add(
                                    ShareTabEvent.searchAvailableUsers(query: query),
                                  );
                            } else {
                              context.read<ShareTabBloc>().add(
                                    ShareTabEvent.searchAvailableUsers(query: ''),
                                  );
                            }
                          },
                          onUserSelected: (user) {
                            _handleShareWithUser(emails: [user.email]);
                            inviteController.clear();
                            context.read<ShareTabBloc>().add(
                                  ShareTabEvent.searchAvailableUsers(query: ''),
                                );
                          },
                          availableUsers: state.availableUsers,
                          existingUsers: allUsers,
                        ),
                        VSpace(theme.spacing.m),

                        // Users list
                        Expanded(
                          child: allUsers.isEmpty
                              ? Center(
                                  child: FlowyText.regular(
                                    '暂无协作者，邀请后即可在此查看权限明细。',
                                    color: theme.textColorScheme.secondary,
                                  ),
                                )
                              : currentSharedUser == null
                                  ? Center(
                                      child: FlowyText.regular(
                                        '无法获取当前用户信息',
                                        color: theme.textColorScheme.error,
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: allUsers.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        color: theme.borderColorScheme.primary
                                            .withValues(alpha: 0.15),
                                      ),
                                      itemBuilder: (context, index) {
                                        final user = allUsers[index];
                                        return SharedUserWidget(
                                          user: user,
                                          currentUser: currentSharedUser,
                                          isInPublicPage: state.sectionType ==
                                              SharedSectionType.public,
                                          callbacks: AccessLevelListCallbacks(
                                            onSelectAccessLevel: (accessLevel) {
                                              context.read<ShareTabBloc>().add(
                                                    ShareTabEvent
                                                        .updateUserAccessLevel(
                                                      email: user.email,
                                                      accessLevel: accessLevel,
                                                    ),
                                                  );
                                            },
                                            onTurnIntoMember: () {
                                              context.read<ShareTabBloc>().add(
                                                    ShareTabEvent.convertToMember(
                                                      email: user.email,
                                                    ),
                                                  );
                                            },
                                            onRemoveAccess: () {
                                              final removingSelf = user.email ==
                                                  currentUser?.email;
                                              if (removingSelf) {
                                                showConfirmDialog(
                                                  context: context,
                                                  title: 'Remove your own access',
                                                  titleStyle: theme.textStyle.body
                                                      .standard(
                                                    color: theme
                                                        .textColorScheme.primary,
                                                  ),
                                                  description: '',
                                                  style:
                                                      ConfirmPopupStyle.cancelAndOk,
                                                  confirmLabel: 'Remove',
                                                  onConfirm: (_) {
                                                    context
                                                        .read<ShareTabBloc>()
                                                        .add(
                                                          ShareTabEvent
                                                              .removeUsers(
                                                            emails: [user.email],
                                                          ),
                                                        );
                                                  },
                                                );
                                              } else {
                                                context
                                                    .read<ShareTabBloc>()
                                                    .add(
                                                      ShareTabEvent.removeUsers(
                                                        emails: [user.email],
                                                      ),
                                                    );
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ).then((_) {
      // Clean up controller when dialog is closed
      inviteController.dispose();
    });
  }

  Widget _buildLinkAndCopyButton(String shareLink, bool hasSharedUsers) {
    final theme = AppFlowyTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(theme.spacing.l),
      decoration: BoxDecoration(
        color: isDark
            ? theme.surfaceContainerColorScheme.layer01
            : Colors.white,
        borderRadius: BorderRadius.circular(theme.spacing.l),
        border: Border.all(
          color: theme.borderColorScheme.primary.withValues(alpha: 0.15),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.brandColorScheme.skyline,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: FlowySvg(
                FlowySvgs.share_tab_icon_s,
                color: Colors.white,
              ),
            ),
          ),
          HSpace(theme.spacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowyText.medium(
                  LocaleKeys.shareAction_shareTabTitle.tr(),
                  figmaLineHeight: 18.0,
                  color: theme.textColorScheme.primary,
                ),
                VSpace(theme.spacing.xs),
                FlowyText.regular(
                  LocaleKeys.shareAction_shareTabDescription.tr(),
                  fontSize: 13.0,
                  figmaLineHeight: 18.0,
                  color: Theme.of(context).hintColor,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          HSpace(theme.spacing.m),
          _RoundIconButton(
            icon: FlowySvgs.toolbar_link_m,
            tooltip: LocaleKeys.shareTab_copyLink.tr(),
            onTap: () {
              final enableCloudShare =
                  context.read<ShareBloc?>()?.state.enablePublish ?? false;

              // 当前工作区未连接云服务或不支持发布，同步状态未知，阻止分享
              if (!enableCloudShare) {
                showToastNotification(
                  message: '当前笔记未同步到云端，无法生成分享链接',
                  description: '请先在设置中连接云服务并开启同步，然后再尝试分享此笔记。',
                  type: ToastificationType.warning,
                );
                return;
              }

              // 已连接云服务，视为已同步或会自动同步，允许复制链接
              context.read<ShareTabBloc>().add(
                    ShareTabEvent.copyShareLink(link: shareLink),
                  );

              if (FlowyRunner.currentMode.isUnitTest) {
                return;
              }

              showToastNotification(
                message: LocaleKeys.shareTab_copiedLinkToClipboard.tr(),
              );
            },
          ),
          HSpace(theme.spacing.s),
          _RoundIconButton(
            icon: FlowySvgs.share_tab_icon_s,
            tooltip: LocaleKeys.shareAction_shareTabTitle.tr(),
            onTap: () {
              _showCollaboratorsDialog(context);
            },
          ),
        ],
      ),
    );
  }
}

class _UserSearchField extends StatefulWidget {
  const _UserSearchField({
    required this.controller,
    required this.onSearch,
    required this.onUserSelected,
    required this.availableUsers,
    required this.existingUsers,
  });

  final TextEditingController controller;
  final void Function(String query) onSearch;
  final void Function(SharedUser user) onUserSelected;
  final SharedUsers availableUsers;
  final List<SharedUser> existingUsers;

  @override
  State<_UserSearchField> createState() => _UserSearchFieldState();
}

class _UserSearchFieldState extends State<_UserSearchField> {
  final _focusNode = FocusNode();
  bool _showResults = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    final query = widget.controller.text.trim();
    
    if (query.isNotEmpty) {
      // 防抖处理，延迟300ms后执行搜索
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          widget.onSearch(query);
          setState(() {
            _showResults = true;
          });
        }
      });
    } else {
      widget.onSearch('');
      setState(() {
        _showResults = false;
      });
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // 延迟隐藏，以便点击结果时能触发
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _showResults = false;
          });
        }
      });
    } else if (widget.controller.text.trim().isNotEmpty) {
      setState(() {
        _showResults = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    
    // 过滤掉已经在协作者列表中的用户
    final existingEmails = widget.existingUsers.map((u) => u.email).toSet();
    final filteredUsers = widget.availableUsers
        .where((user) => !existingEmails.contains(user.email))
        .toList();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AFTextField(
          controller: widget.controller,
          focusNode: _focusNode,
          size: AFTextFieldSize.m,
          hintText: '输入用户名邀请协作',
        ),
        if (_showResults && filteredUsers.isNotEmpty)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: theme.surfaceContainerColorScheme.layer01,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: filteredUsers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: theme.borderColorScheme.primary.withValues(alpha: 0.15),
                  ),
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    return InkWell(
                      onTap: () {
                        widget.onUserSelected(user);
                        _focusNode.unfocus();
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: theme.spacing.m,
                          vertical: theme.spacing.s,
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: theme.surfaceContainerColorScheme.layer02,
                              child: user.avatarUrl != null
                                  ? ClipOval(
                                      child: Image.network(
                                        user.avatarUrl!,
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildAvatarFallback(user),
                                      ),
                                    )
                                  : _buildAvatarFallback(user),
                            ),
                            HSpace(theme.spacing.s),
                            // Name and email
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FlowyText.medium(
                                    user.name,
                                    color: theme.textColorScheme.primary,
                                  ),
                                  if (user.email != user.name)
                                    FlowyText.regular(
                                      user.email,
                                      fontSize: 12,
                                      color: theme.textColorScheme.secondary,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatarFallback(SharedUser user) {
    final theme = AppFlowyTheme.of(context);
    final initial = user.name.isNotEmpty
        ? user.name[0].toUpperCase()
        : (user.email.isNotEmpty ? user.email[0].toUpperCase() : '?');
    return Text(
      initial,
      style: TextStyle(
        color: theme.textColorScheme.primary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final FlowySvgData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final bgColor = theme.surfaceContainerColorScheme.layer02;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: FlowySvg(
              icon,
              color: theme.iconColorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
