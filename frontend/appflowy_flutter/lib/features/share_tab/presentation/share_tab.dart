import 'dart:async';

import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/people_with_access_section.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/shared_user_widget.dart';
import 'package:appflowy/features/util/extensions.dart';
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
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';

import '../../../util/log_utils.dart';
import '../../../workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import '../data/repositories/rust_share_with_user_repository_impl.dart';
import 'build_users_list_with_owner.dart';
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
  final TextEditingController _inviteController = TextEditingController();
  late final ShareTabBloc _bloc;

  int _permissionIdFromAccessLevel(ShareAccessLevel level) {
    switch (level) {
      case ShareAccessLevel.readOnly:
        return 1;
      case ShareAccessLevel.readAndComment:
        return 2;
      case ShareAccessLevel.readAndWrite:
        return 3;
      case ShareAccessLevel.fullAccess:
        return 4;
    }
  }

  @override
  void initState() {
    super.initState();

    _bloc = context.read<ShareTabBloc>();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    _bloc.add(ShareTabEvent.clearState());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isReadOnly = _isReadOnlyFromContext(context);

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
            if (isReadOnly) ...[
              VSpace(theme.spacing.l),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(theme.spacing.m),
                decoration: BoxDecoration(
                  color: theme.surfaceContainerColorScheme.layer01,
                  borderRadius: BorderRadius.circular(theme.spacing.m),
                ),
                child: FlowyText.regular(
                  '该文档为接收的只读发布内容，不能复制分享链接或邀请协作者。',
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ] else ...[
            // share page with user by email
            // only user with full access can invite others
            VSpace(theme.spacing.l),
            Row(
              children: [
                FlowyText("当前文档为私密，仅自己和协作者可访问"),
              ],
            ),
            VSpace(theme.spacing.m),
            
            // 添加权限选择器
            _buildPermissionSelector(context, state),
            
            VSpace(theme.spacing.m),
            _buildLinkAndCopyButton(
              state.shareLink,
              state.users.isNotEmpty,
            ),
            ],

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

  bool _isReadOnlyFromContext(BuildContext context) {
    try {
      final pageAccessLevelBloc = context.read<PageAccessLevelBloc>();
      return !pageAccessLevelBloc.state.isLoadingLockStatus &&
          pageAccessLevelBloc.state.isReadOnly;
    } catch (_) {
      return false;
    }
  }

  PeopleWithAccessSectionCallbacks _buildPeopleWithAccessSectionCallbacks(
    BuildContext context,
  ) {
    return PeopleWithAccessSectionCallbacks(
      onSelectAccessLevel: (user, accessLevel) {
        context.read<ShareTabBloc>().add(
              ShareTabEvent.updateMemberPermission(
                user: user,
                accessLevel: accessLevel,
              ),
            );
      },
      onTurnIntoMember: (user) {
        context.read<ShareTabBloc>().add(
              ShareTabEvent.convertToMember(email: user.phone ?? user.email ?? ""),
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
            title: LocaleKeys.shareAction_removeOwnAccess.tr(),
            titleStyle: theme.textStyle.body.standard(
              color: theme.textColorScheme.primary,
            ),
            description: '',
            style: ConfirmPopupStyle.cancelAndOk,
            confirmLabel: LocaleKeys.button_delete.tr(),
            onConfirm: (_) {
              shareTabBloc.add(
                ShareTabEvent.removeUsers(emails: [user.phone ?? user.email]),
              );
            },
          );
        } else {
          shareTabBloc.add(
            ShareTabEvent.removeUsers(emails: [user.phone ?? user.email]),
          );
        }
      },
    );
  }

  void _handleShareWithUser({required List<String> emails}) {
    _bloc.add(
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
  }) =>
      buildUsersListWithOwner(users: users, currentUser: currentUser);

  void _onListenShareWithUserState(
    BuildContext context,
    ShareTabState shareState,
  ) {
    final shareResult = shareState.shareResult;
    if (shareResult != null) {
      shareResult.fold((success) {
        // clear the controller to avoid showing the previous emails
        _inviteController.clear();

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

    final removeResult = shareState.removeResult;
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

    final updateAccessLevelResult = shareState.updateAccessLevelResult;
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

    final turnIntoMemberResult = shareState.turnIntoMemberResult;
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
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return BlocProvider(
          create: (context) => ShareTabBloc(
            repository: RustShareWithUserRepositoryImpl(),
            pageId: widget.pageId,
            workspaceId: widget.workspaceId,
          )..add(ShareTabEvent.initialize()),
          child: _CollaboratorsDialog(
            workspaceId: widget.workspaceId,
            pageId: widget.pageId,
          ),
        );
      },
    );
  }

  /// 构建权限选择器
  Widget _buildPermissionSelector(BuildContext context, ShareTabState state) {
    final theme = AppFlowyTheme.of(context);
    final permissions = ShareAccessLevel.values
        .where((level) => level != ShareAccessLevel.readAndComment)
        .toList();
    final permissionItems = permissions
        .map((level) => MapEntry(_permissionIdFromAccessLevel(level), level))
        .fold<Map<int, ShareAccessLevel>>(<int, ShareAccessLevel>{},
            (acc, entry) {
      acc.putIfAbsent(entry.key, () => entry.value);
      return acc;
    }).entries.toList();

    final selectedPermissionId =
        permissionItems.any((entry) => entry.key == state.selectedPermissionId)
            ? state.selectedPermissionId
            : (permissionItems.isNotEmpty ? permissionItems.first.key : null);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.m,
        vertical: theme.spacing.s,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceContainerColorScheme.layer01,
        borderRadius: BorderRadius.circular(theme.spacing.m),
        border: Border.all(
          color: theme.borderColorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          FlowyText(
            '链接权限：',
            color: theme.textColorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int>(
              value: selectedPermissionId,
              isExpanded: true,
              underline: const SizedBox(),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
              dropdownColor: theme.surfaceContainerColorScheme.layer01,
              borderRadius: BorderRadius.circular(8),
              items: permissionItems.map((entry) {
                final level = entry.value;
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Row(
                    children: [
                      FlowySvg(
                    level.icon,
                        size: const Size(18, 18),
                        color: theme.textColorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      FlowyText(
                        level.title,
                        color: theme.textColorScheme.primary,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  context.read<ShareTabBloc>().add(
                    ShareTabEvent.updateShareLinkPermission(permissionId: value),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkAndCopyButton(String shareLink, bool hasSharedUsers) {
    final theme = AppFlowyTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(theme.spacing.l),
      decoration: BoxDecoration(
        color:
            isDark ? theme.surfaceContainerColorScheme.layer01 : Colors.white,
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

class _CollaboratorsDialog extends StatefulWidget {
  const _CollaboratorsDialog({
    required this.workspaceId,
    required this.pageId,
  });

  final String workspaceId;
  final String pageId;

  @override
  State<_CollaboratorsDialog> createState() => _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends State<_CollaboratorsDialog> {
  late final TextEditingController _inviteController;
  late final ShareTabBloc _bloc;

  @override
  void initState() {
    super.initState();
    _inviteController = TextEditingController();
    _bloc = context.read<ShareTabBloc>();

    // 打开弹窗时清空搜索结果
    _bloc.add(ShareTabEvent.searchAvailableUsers(query: ''));
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  void _inviteUser(SharedUser user) {
    _bloc.add(
      ShareTabEvent.inviteUsers(
        emails: [user.email],
        accessLevel: ShareAccessLevel.readOnly,
      ),
    );
  }

  void _addCollaborator(SharedUser user, ShareAccessLevel accessLevel) {
    // 调用 bloc 事件添加协作用户，使用选定的权限
    _bloc.add(
      ShareTabEvent.addCollaborator(
        user: user,
        accessLevel: accessLevel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return BlocConsumer<ShareTabBloc, ShareTabState>(
      listener: (context, state) {
        // 邀请成功后清空输入框和搜索结果
        final shareResult = state.shareResult;
        if (shareResult != null) {
          shareResult.fold((success) {
            _inviteController.clear();
            _bloc.add(ShareTabEvent.searchAvailableUsers(query: ''));
          }, (error) {});
        }

        // 监听添加协作用户的结果
        final addCollaboratorResult = state.addCollaboratorResult;
        if (addCollaboratorResult != null) {
          addCollaboratorResult.fold(
            (success) {
              _inviteController.clear();
              _bloc.add(
                ShareTabEvent.searchAvailableUsers(query: ''),
              );
              showToastNotification(
                message: '已成功添加协作用户',
              );
            },
            (error) {
              showToastNotification(
                message: error.msg.isNotEmpty ? error.msg : '添加协作用户失败',
                type: ToastificationType.error,
              );
            },
          );
        }
      },
      builder: (context, state) {
        final currentUser = state.currentUser;
        final users = state.users;

        // 构建完整的用户列表：
        // 接口返回的顺序即为展示顺序，约定第一条为拥有者，其余为被邀请者
        final List<SharedUser> allUsers = users;

        // 从完整列表中查找当前登录用户（可能是拥有者，也可能是被邀请者）
        final currentSharedUser = currentUser == null
            ? null
            : allUsers.firstWhereOrNull(
                (user) => user.name == currentUser.name,
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
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).pop();
                        },
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

                  // 权限选择和搜索框
                  _AccessLevelSelector(
                    inviteController: _inviteController,
                    bloc: _bloc,
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
                                    /// 因为当前协作区都是公开，所有分享都是公开的文档，导致分享后不能编辑权限。
                                    // isInPublicPage: state.sectionType ==
                                    //     SharedSectionType.public,
                                    callbacks: AccessLevelListCallbacks(
                                      onSelectAccessLevel: (accessLevel) {
                                        _bloc.add(
                                          ShareTabEvent.updateMemberPermission(
                                            user: user,
                                            accessLevel: accessLevel,
                                          ),
                                        );
                                      },
                                      onTurnIntoMember: () {
                                        _bloc.add(
                                          ShareTabEvent.convertToMember(
                                            email: user.name,
                                          ),
                                        );
                                      },
                                      onRemoveAccess: () {
                                        final removingSelf =
                                            user.name == currentUser?.name;
                                        if (removingSelf) {
                                          showConfirmDialog(
                                            context: context,
                                            title: LocaleKeys
                                                .shareAction_removeOwnAccess
                                                .tr(),
                                            titleStyle:
                                                theme.textStyle.body.standard(
                                              color:
                                                  theme.textColorScheme.primary,
                                            ),
                                            description: '',
                                            style:
                                                ConfirmPopupStyle.cancelAndOk,
                                            confirmLabel:
                                                LocaleKeys.button_delete.tr(),
                                            onConfirm: (_) {
                                              _bloc.add(
                                                ShareTabEvent.removeUsers(
                                                  emails: [user.email],
                                                ),
                                              );
                                            },
                                          );
                                        } else {
                                          _bloc.add(
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
  final _layerLink = LayerLink();
  Timer? _debounceTimer;
  OverlayEntry? _overlayEntry;
  bool _isCreatingOverlay = false; // 防止重复创建 overlay

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_UserSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当搜索结果更新时，重新创建 overlay 以确保显示最新结果
    if (!mounted) {
      return;
    }

    // 只有当搜索结果真正变化时才更新 overlay
    if (oldWidget.availableUsers != widget.availableUsers) {
      try {
        final hasText = widget.controller.text.trim().isNotEmpty;
        if (hasText && _focusNode.hasFocus && mounted) {
          // 移除旧的 overlay 并重新创建，确保显示最新的搜索结果
          if (_overlayEntry != null) {
            // 先移除旧的 overlay
            _removeOverlay();
            // 在下一帧重新创建，确保使用最新的 widget.availableUsers
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isCreatingOverlay) {
                _createOverlay();
              }
            });
          } else {
            // 如果 overlay 不存在，创建新的
            _showOverlay();
          }
        }
      } catch (e) {
        // Controller 可能已被销毁，忽略
      }
    }
  }

  @override
  void dispose() {
    // Remove overlay entry
    _removeOverlay();

    // Cancel any pending timers first
    _debounceTimer?.cancel();
    _debounceTimer = null;

    // Remove focus listener and unfocus before disposing
    // This must be done before removing controller listener to prevent callbacks
    try {
      _focusNode.removeListener(_onFocusChanged);
      // Unfocus synchronously to prevent any async callbacks
      if (_focusNode.hasFocus) {
        _focusNode.unfocus();
      }
    } catch (e) {
      // Focus node may have issues, ignore
    }

    // Dispose focus node before controller to prevent focus callbacks
    try {
      _focusNode.dispose();
    } catch (e) {
      // Focus node may have already been disposed, ignore
    }

    // Remove controller listener last
    try {
      widget.controller.removeListener(_onTextChanged);
    } catch (e) {
      // Controller may have already been disposed, ignore
    }

    super.dispose();
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      try {
        _overlayEntry!.remove();
      } catch (e) {
        // Overlay 可能已经被移除，忽略错误
      }
      _overlayEntry = null;
    }
    _isCreatingOverlay = false; // 重置创建标志
  }

  void _showOverlay() {
    // 如果 overlay 已存在，使用 markNeedsBuild 更新内容（避免闪烁）
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    // 防止重复创建
    if (_isCreatingOverlay) {
      return;
    }

    _createOverlay();
  }

  void _createOverlay() {
    if (!mounted || _isCreatingOverlay) {
      return;
    }

    // 检查输入框是否有内容
    String searchText;
    try {
      searchText = widget.controller.text.trim();
    } catch (e) {
      // Controller 可能已被销毁
      return;
    }

    if (searchText.isEmpty) {
      return;
    }

    _isCreatingOverlay = true;

    // 创建新的 overlay entry，builder 中使用最新的 widget 数据
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        // 检查 widget 是否仍然有效
        if (!mounted) {
          return const SizedBox.shrink();
        }

        // 使用最新的 widget 数据，确保每次 builder 执行时都获取最新数据
        final theme = AppFlowyTheme.of(context);
        final controller = widget.controller;
        final availableUsers = widget.availableUsers; // 使用最新的 widget 数据
        final existingUsers = widget.existingUsers; // 使用最新的 widget 数据
        final onUserSelected = widget.onUserSelected;

        // 再次检查输入框内容（可能已改变）
        String currentText;
        try {
          currentText = controller.text.trim();
        } catch (e) {
          return const SizedBox.shrink();
        }

        if (currentText.isEmpty) {
          return const SizedBox.shrink();
        }

        // 过滤用户列表 - 使用最新的数据
        // 注意：这里使用 name 来过滤，因为用户修改了代码使用 name 而不是 email
        final existingNames = existingUsers.map((u) => u.name).toSet();
        final filteredUsers = availableUsers
            .where((user) => !existingNames.contains(user.name))
            .toList();

        // 添加调试日志，确保数据正确
        LogUtils.info(
            'Overlay builder: searchText=$currentText, availableUsers=${availableUsers.length}, filteredUsers=${filteredUsers.length}');

        // 计算弹框宽度：对话框最大宽度 500，减去左右 padding (20*2)，等于输入框宽度
        final screenWidth = MediaQuery.of(overlayContext).size.width;
        final dialogMaxWidth = 500.0;
        final dialogInsetPadding = 24.0 * 2; // Dialog 的 insetPadding 左右各 24px
        final dialogInternalPadding = 20.0 * 2; // Dialog 内部的 padding 左右各 20px
        final inputFieldWidth = dialogMaxWidth - dialogInternalPadding; // 460px

        // 计算弹框宽度：如果屏幕宽度足够，使用输入框宽度；否则使用屏幕宽度减去所有间距
        final popupWidth = screenWidth >= dialogMaxWidth + dialogInsetPadding
            ? inputFieldWidth
            : screenWidth - dialogInsetPadding - dialogInternalPadding;

        return Positioned(
          width: popupWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 8), // 紧贴输入框下方，8px 间距
            followerAnchor: Alignment.topLeft,
            targetAnchor: Alignment.bottomLeft,
            child: Material(
              elevation: 16,
              borderRadius: BorderRadius.circular(8),
              color: theme.surfaceContainerColorScheme.layer01,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: filteredUsers.isNotEmpty
                    ? ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: filteredUsers.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: theme.borderColorScheme.primary
                              .withValues(alpha: 0.15),
                        ),
                        itemBuilder: (overlayContext, index) {
                          final user = filteredUsers[index];
                          return InkWell(
                            onTap: () {
                              if (mounted) {
                                onUserSelected(user);
                                _focusNode.unfocus();
                                _removeOverlay();
                              }
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
                                    backgroundColor: theme
                                        .surfaceContainerColorScheme.layer02,
                                    child: user.avatarUrl != null
                                        ? ClipOval(
                                            child: Image.network(
                                              user.avatarUrl!,
                                              width: 32,
                                              height: 32,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _buildAvatarFallback(user),
                                            ),
                                          )
                                        : _buildAvatarFallback(user),
                                  ),
                                  HSpace(theme.spacing.s),
                                  // Name and email
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            color:
                                                theme.textColorScheme.secondary,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : _buildEmptyState(overlayContext),
              ),
            ),
          ),
        );
      },
    );

    if (mounted && _overlayEntry != null) {
      try {
        final overlay = Overlay.of(context, rootOverlay: false);
        overlay.insert(_overlayEntry!);
        _isCreatingOverlay = false; // 创建完成，重置标志
      } catch (e) {
        // Context 可能无效，清理 overlay entry
        _overlayEntry = null;
        _isCreatingOverlay = false;
      }
    } else {
      _isCreatingOverlay = false;
    }
  }

  void _onTextChanged() {
    if (!mounted) {
      return;
    }

    _debounceTimer?.cancel();

    // Check if controller is still valid before using it
    String query;
    try {
      query = widget.controller.text.trim();
    } catch (e) {
      // Controller may have been disposed, ignore
      if (!mounted) {
        return;
      }
      // If still mounted but controller is disposed, it's a real error
      return;
    }

    LogUtils.info('search user: $query');
    if (query.isNotEmpty) {
      // 防抖处理，延迟150ms后执行搜索
      final searchQuery = query; // Capture query value for timer
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) {
          return;
        }
        try {
          // 先调用搜索接口（立即触发搜索）
          widget.onSearch(searchQuery);
          // 搜索请求发送后，确保 overlay 显示
          // 注意：新的搜索结果返回后，didUpdateWidget 会重新创建 overlay 显示最新结果
          if (mounted && _focusNode.hasFocus) {
            // 如果 overlay 不存在，创建新的（显示当前搜索结果或等待状态）
            if (_overlayEntry == null) {
              _showOverlay();
            }
            // 如果 overlay 已存在，暂时不更新（等待搜索结果返回后通过 didUpdateWidget 更新）
            // 这样可以避免显示旧的搜索结果
          }
        } catch (e) {
          // Controller may have been disposed, ignore
          if (!mounted) {
            return;
          }
        }
      });
    } else {
      if (mounted) {
        try {
          widget.onSearch('');
          if (mounted) {
            _removeOverlay();
          }
        } catch (e) {
          if (!mounted) {
            return;
          }
        }
      }
    }
  }

  void _onFocusChanged() {
    if (!mounted) {
      return;
    }

    // Check if focus node is still valid
    bool hasFocus;
    try {
      hasFocus = _focusNode.hasFocus;
    } catch (e) {
      // Focus node may have been disposed, ignore
      if (!mounted) {
        return;
      }
      return;
    }

    if (!hasFocus) {
      // 延迟隐藏，以便点击结果时能触发
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) {
          return;
        }
        // Check again if focus node is still valid
        try {
          if (!_focusNode.hasFocus && mounted) {
            _removeOverlay();
          }
        } catch (e) {
          // Focus node or controller may have been disposed, ignore
          if (!mounted) {
            return;
          }
        }
      });
    } else {
      // Check if controller is still valid before using it
      try {
        final text = widget.controller.text.trim();
        if (text.isNotEmpty && mounted) {
          // 如果 overlay 已存在，使用 markNeedsBuild 更新（避免闪烁）
          if (_overlayEntry != null) {
            _overlayEntry!.markNeedsBuild();
          } else {
            // 如果 overlay 不存在，创建新的
            _showOverlay();
          }
        }
      } catch (e) {
        // Controller may have been disposed, ignore
        if (!mounted) {
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: AFTextField(
        controller: widget.controller,
        focusNode: _focusNode,
        size: AFTextFieldSize.m,
        hintText: '输入用户名邀请协作',
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlowySvg(
            FlowySvgs.search_icon_m,
            color: theme.iconColorScheme.tertiary,
            size: const Size.square(24),
          ),
          VSpace(theme.spacing.s),
          FlowyText.regular(
            '搜索结果为空',
            color: theme.textColorScheme.secondary,
            fontSize: 14,
          ),
        ],
      ),
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

/// 权限选择和搜索组件
class _AccessLevelSelector extends StatefulWidget {
  const _AccessLevelSelector({
    required this.inviteController,
    required this.bloc,
    required this.availableUsers,
    required this.existingUsers,
  });

  final TextEditingController inviteController;
  final ShareTabBloc bloc;
  final List<SharedUser> availableUsers;
  final List<SharedUser> existingUsers;

  @override
  State<_AccessLevelSelector> createState() => _AccessLevelSelectorState();
}

class _AccessLevelSelectorState extends State<_AccessLevelSelector> {
  ShareAccessLevel _selectedLevel = ShareAccessLevel.readAndWrite;

  String _getAccessLevelLabel(ShareAccessLevel level) {
    switch (level) {
      case ShareAccessLevel.readOnly:
        return '仅查看';
      case ShareAccessLevel.readAndComment:
        return '查看和评论';
      case ShareAccessLevel.readAndWrite:
        return '查看和编辑';
      case ShareAccessLevel.fullAccess:
        return '完全访问';
    }
  }

  void _addCollaborator(SharedUser user, ShareAccessLevel accessLevel) {
    widget.bloc.add(
      ShareTabEvent.addCollaborator(
        user: user,
        accessLevel: accessLevel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Row(
      children: [
        FlowyText.medium(
          '权限:',
          color: theme.textColorScheme.primary,
        ),
        const HSpace(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.surfaceContainerColorScheme.layer02,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.borderColorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ShareAccessLevel>(
              value: _selectedLevel,
              icon: FlowySvg(
                FlowySvgs.arrow_down_s,
                size: const Size.square(16),
                color: theme.iconColorScheme.primary,
              ),
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
              dropdownColor: theme.surfaceContainerColorScheme.layer01,
              borderRadius: BorderRadius.circular(8),
              items: ShareAccessLevel.values
                  .where((level) =>
                      level != ShareAccessLevel.readAndComment)
                  .map((level) {
                  return DropdownMenuItem(
                    value: level,
                    child: Text(_getAccessLevelLabel(level)),
                  );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedLevel = value;
                  });
                }
              },
            ),
          ),
        ),
        const HSpace(8),
        Expanded(
          child: _UserSearchField(
            controller: widget.inviteController,
            onSearch: (query) {
              widget.bloc.add(
                ShareTabEvent.searchAvailableUsers(query: query),
              );
            },
            onUserSelected: (user) {
              _addCollaborator(user, _selectedLevel);
              widget.inviteController.clear();
              widget.bloc.add(
                ShareTabEvent.searchAvailableUsers(query: ''),
              );
            },
            availableUsers: widget.availableUsers,
            existingUsers: widget.existingUsers,
          ),
        ),
      ],
    );
  }
}
