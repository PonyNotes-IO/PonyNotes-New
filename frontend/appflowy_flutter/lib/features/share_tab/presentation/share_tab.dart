import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/people_with_access_section.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/shared_user_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/edit_access_level_widget.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/colorscheme/default_colorscheme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';

import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';

import '../../../util/log_utils.dart';
import '../../../workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'build_users_list_with_owner.dart';

String? _extractCurrentUserUuid(UserProfilePB? user) {
  if (user == null) return null;
  final rawToken = user.token;
  if (rawToken.isEmpty) return null;

  String? accessToken = rawToken;
  if (rawToken.trimLeft().startsWith('{')) {
    try {
      final tokenMap = jsonDecode(rawToken) as Map<String, dynamic>;
      accessToken = tokenMap['access_token'] as String?;
    } catch (_) {
      accessToken = null;
    }
  }
  if (accessToken == null || accessToken.isEmpty) return null;

  final parts = accessToken.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = parts[1];
    final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
    final padding = (4 - normalized.length % 4) % 4;
    final padded = normalized + ('=' * padding);
    final decoded = utf8.decode(base64Decode(padded));
    final payloadMap = jsonDecode(decoded) as Map<String, dynamic>;
    final sub = payloadMap['sub']?.toString();
    if (sub != null && sub.isNotEmpty) {
      return sub;
    }
  } catch (_) {}

  return null;
}

class ShareTab extends StatefulWidget {
  const ShareTab({super.key});

  @override
  State<ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<ShareTab> {
  final _inviteController = TextEditingController();
  late final ShareTabBloc _bloc;
  String? _selectedUserId;
  ShareAccessLevel _inviteAccess = ShareAccessLevel.readAndWrite;
  bool _inviting = false;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<ShareTabBloc>();
    _bloc.add(ShareTabEvent.searchAvailableUsers(query: ''));
    if (_bloc.state.selectedPermissionId !=
        ShareAccessLevel.readAndWrite.permissionId) {
      _bloc.add(ShareTabEvent.updateShareLinkPermission(
        permissionId: ShareAccessLevel.readAndWrite.permissionId,
      ));
    }
  }

  @override
  void dispose() {
    _inviteController.dispose();
    if (!_bloc.isClosed) {
      _bloc.add(ShareTabEvent.clearState());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ShareTabBloc, ShareTabState>(
      listenWhen: (previous, current) =>
          !previous.linkCopied && current.linkCopied,
      listener: (_, __) => showToastNotification(
        message: LocaleKeys.shareTab_copiedLinkToClipboard.tr(),
      ),
      child: BlocConsumer<ShareTabBloc, ShareTabState>(
        listenWhen: (previous, current) =>
            previous.addCollaboratorResult != current.addCollaboratorResult ||
            previous.errorMessage != current.errorMessage ||
            previous.removeResult != current.removeResult ||
            previous.updateAccessLevelResult !=
                current.updateAccessLevelResult ||
            previous.turnIntoMemberResult != current.turnIntoMemberResult,
        listener: _onListenShareWithUserState,
        builder: (context, state) {
          final theme = AppFlowyTheme.of(context);
          if (_isShareManagementReadOnly(context, state)) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '该文档为接收的只读发布内容，不能复制分享链接或邀请协作者。',
                style: theme.textStyle.body
                    .standard(color: theme.textColorScheme.secondary),
              ),
            );
          }

          final searching = _inviteController.text.trim().isNotEmpty;
          final members = state.users.isEmpty
              ? state.users
              : buildUsersListWithOwner(
                  users: state.users, currentUser: state.currentUser);
          final memberIds = members.map((user) => user.userId).toSet();
          final results = searching
              ? state.availableUsers
                  .where(
                    (user) =>
                        user.userId != null &&
                        user.userId!.isNotEmpty &&
                        !memberIds.contains(user.userId),
                  )
                  .toList()
              : const <SharedUser>[];
          final selected = results
              .firstWhereOrNull((user) => user.userId == _selectedUserId);
          final callbacks = _buildPeopleWithAccessSectionCallbacks(context);
          final currentUser = state.currentUser;
          final viewer = SharedUser(
            userId: _extractCurrentUserUuid(currentUser) ??
                currentUser?.id.toString(),
            uid: currentUser?.id.toString(),
            name: currentUser?.name ?? '',
            email: currentUser?.email ?? '',
            role: ShareRole.member,
            accessLevel:
                _currentShareAccessLevel(state) ?? ShareAccessLevel.readOnly,
          );
          final rows = searching ? results : members;
          final input = _buildInviteField(context, selected);
          final footer = _buildLinkAndCopyButton(state);
          final showList = rows.isNotEmpty || state.isLoading || searching;
          final list = showList
              ? ListView(
                  key: ValueKey(
                      searching ? 'share-search-results' : 'share-members'),
                  primary: false,
                  shrinkWrap: true,
                  padding:
                      EdgeInsets.only(top: 12, bottom: rows.isEmpty ? 0 : 32),
                  children: [
                    if (state.isLoading ||
                        (searching && state.isSearchingUsers))
                      const LinearProgressIndicator(minHeight: 2)
                    else if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Text(
                          'shareTab.noMatchingUsers'.tr(),
                          style: theme.textStyle.caption
                              .standard(color: theme.textColorScheme.secondary),
                        ),
                      )
                    else
                      for (final user in rows)
                        if (searching)
                          _buildSearchResult(context, user)
                        else
                          SharedUserWidget(
                            compact: true,
                            user: user,
                            currentUser: viewer,
                            callbacks: AccessLevelListCallbacks(
                              onSelectAccessLevel: (level) =>
                                  callbacks.onSelectAccessLevel(user, level),
                              onRemoveAccess: () =>
                                  callbacks.onRemoveAccess(user),
                              onTurnIntoMember: () =>
                                  callbacks.onTurnIntoMember(user),
                            ),
                          ),
                  ],
                )
              : null;

          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxHeight < 163) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    input,
                    if (list != null) SizedBox(height: 120, child: list),
                    const SizedBox(height: 16),
                    footer,
                  ]),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 19),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    input,
                    if (list != null) Flexible(child: list),
                    const SizedBox(height: 16),
                    footer,
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInviteField(BuildContext context, SharedUser? selected) {
    final theme = AppFlowyTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    void invite() {
      if (selected == null || _inviting) return;
      setState(() => _inviting = true);
      _bloc.add(ShareTabEvent.addCollaborator(
          user: selected, accessLevel: _inviteAccess));
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inviteController,
            enabled: !_inviting,
            textInputAction: TextInputAction.done,
            style: theme.textStyle.body
                .standard(color: theme.textColorScheme.primary),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              hintText: 'shareTab.collaboratorSearch'.tr(),
              hintStyle: theme.textStyle.body
                  .standard(color: theme.textColorScheme.secondary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: _inviteController.text.isEmpty
                        ? theme.textColorScheme.primary.withValues(alpha: .16)
                        : colors.primary.withValues(alpha: .55)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _selectedUserId = null;
                _inviteAccess = ShareAccessLevel.readAndWrite;
              });
              _bloc.add(ShareTabEvent.searchAvailableUsers(query: value));
            },
            onSubmitted: (_) => invite(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: selected == null || _inviting ? null : invite,
          style: FilledButton.styleFrom(
            minimumSize: const Size(76, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(LocaleKeys.shareTab_invite.tr()),
        ),
      ],
    );
  }

  Widget _buildSearchResult(BuildContext context, SharedUser user) {
    final theme = AppFlowyTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    final accent = colors.primary;
    final dark = colors.brightness == Brightness.dark;
    final selected = user.userId == _selectedUserId;
    return Material(
      color: selected
          ? (dark ? const Color(0xFF343434) : _subtleShareSurface(context))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          overlayColor: WidgetStatePropertyAll(
            theme.textColorScheme.primary.withValues(alpha: .06),
          ),
          borderRadius: BorderRadius.circular(12),
          onTap: _inviting
              ? null
              : () => setState(() {
                    _selectedUserId = selected ? null : user.userId;
                    _inviteAccess = ShareAccessLevel.readAndWrite;
                  }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                AFAvatar(
                    name: user.name, url: user.avatarUrl, size: AFAvatarSize.l),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyle.body.standard(
                              weight: FontWeight.w600,
                              color: theme.textColorScheme.primary)),
                      Text(user.phone ?? user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyle.caption.standard(
                              color: theme.textColorScheme.secondary)),
                    ],
                  ),
                ),
                if (selected)
                  EditAccessLevelWidget(
                    compact: true,
                    disabled: _inviting,
                    selectedAccessLevel: _inviteAccess,
                    supportedAccessLevels: const [
                      ShareAccessLevel.readOnly,
                      ShareAccessLevel.readAndWrite,
                      ShareAccessLevel.fullAccess
                    ],
                    additionalUserManagementOptions: const [],
                    callbacks: AccessLevelListCallbacks.none().copyWith(
                      onSelectAccessLevel: (level) =>
                          setState(() => _inviteAccess = level),
                    ),
                  ),
                const SizedBox(width: 18),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent
                        : _subtleShareSurface(context, opacity: .08),
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(Icons.check,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isShareManagementReadOnly(
    BuildContext context,
    ShareTabState state,
  ) {
    final currentShareAccessLevel = _currentShareAccessLevel(state);
    if (currentShareAccessLevel != null) {
      return currentShareAccessLevel == ShareAccessLevel.readOnly;
    }

    try {
      final pageAccessLevelBloc = context.read<PageAccessLevelBloc>();
      return !pageAccessLevelBloc.state.isLoadingLockStatus &&
          pageAccessLevelBloc.state.isReadOnly;
    } catch (_) {
      return false;
    }
  }

  ShareAccessLevel? _currentShareAccessLevel(ShareTabState state) {
    final currentUser = state.currentUser;
    if (currentUser == null) {
      return null;
    }

    final currentUid = _extractCurrentUserUuid(currentUser);
    final currentEmail = currentUser.email.trim().toLowerCase();
    final currentNumericId = currentUser.id.toString();

    final usersWithOwner = buildUsersListWithOwner(
      users: state.users,
      currentUser: currentUser,
    );
    final currentSharedUser = usersWithOwner.firstWhereOrNull((user) {
      final idMatch = currentUid != null &&
          currentUid.isNotEmpty &&
          user.userId == currentUid;
      final uidMatch =
          currentNumericId.isNotEmpty && user.uid == currentNumericId;
      final emailMatch = currentEmail.isNotEmpty &&
          user.email.trim().toLowerCase() == currentEmail;
      return idMatch || uidMatch || emailMatch;
    });
    if (currentSharedUser != null) {
      return currentSharedUser.accessLevel;
    }

    if (usersWithOwner.isNotEmpty &&
        usersWithOwner.first.accessLevel == ShareAccessLevel.fullAccess) {
      LogUtils.debug(
        '[ShareTab] Current user not matched in share list; '
        'using owner fallback for share management. currentUid=$currentUid, '
        'currentEmail=$currentEmail',
      );
      return ShareAccessLevel.fullAccess;
    }

    return null;
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
              ShareTabEvent.convertToMember(email: user.phone ?? user.email),
            );
      },
      onRemoveAccess: (user) {
        final theme = AppFlowyTheme.of(context);
        final shareTabBloc = context.read<ShareTabBloc>();
        final currentUser = shareTabBloc.state.currentUser;
        final currentUid = currentUser?.id.toString();
        final currentUuid = _extractCurrentUserUuid(currentUser);
        final currentEmail = currentUser?.email.trim().toLowerCase();
        final removingSelf = (currentUid != null &&
                (user.userId == currentUid || user.uid == currentUid)) ||
            (currentUuid != null && user.userId == currentUuid) ||
            (currentEmail?.isNotEmpty == true &&
                user.email.trim().toLowerCase() == currentEmail);
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
                ShareTabEvent.removeCollabMember(user: user),
              );
            },
          );
        } else {
          shareTabBloc.add(
            ShareTabEvent.removeCollabMember(user: user),
          );
        }
      },
    );
  }

  void _onListenShareWithUserState(
    BuildContext context,
    ShareTabState shareState,
  ) {
    if (shareState.errorMessage.isNotEmpty) {
      showToastNotification(
        message: shareState.errorMessage,
        type: ToastificationType.error,
      );
    }

    final addResult = shareState.addCollaboratorResult;
    if (_inviting && addResult != null) {
      setState(() => _inviting = false);
      addResult.fold((_) {
        setState(() {
          _inviteController.clear();
          _selectedUserId = null;
          _inviteAccess = ShareAccessLevel.readAndWrite;
        });
        _bloc.add(ShareTabEvent.searchAvailableUsers(query: ''));
        showToastNotification(message: LocaleKeys.shareTab_invitationSent.tr());
      }, (_) {});
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

  Color _subtleShareSurface(BuildContext context, {double opacity = .045}) {
    final theme = AppFlowyTheme.of(context);
    return Color.alphaBlend(
      theme.textColorScheme.primary.withValues(alpha: opacity),
      theme.surfaceContainerColorScheme.layer01,
    );
  }

  Widget _buildLinkAndCopyButton(ShareTabState state) {
    final theme = AppFlowyTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    final accent = colors.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _subtleShareSurface(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 380) ...[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.surfaceContainerColorScheme.layer01,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Icons.group_rounded,
                  size: 18,
                  color: colors.brightness == Brightness.dark
                      ? Colors.white
                      : ColorSchemeConstants.lightMain1,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('shareTab.inviteByLink'.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyle.body.standard(
                        weight: FontWeight.w600,
                        color: theme.textColorScheme.primary)),
                Text(LocaleKeys.shareAction_shareTabDescription.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyle.caption
                        .standard(color: theme.textColorScheme.secondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.textColorScheme.primary,
              backgroundColor: theme.surfaceContainerColorScheme.layer01,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                  color: theme.textColorScheme.primary.withValues(alpha: .16)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: FlowySvg(FlowySvgs.toolbar_link_m,
                size: const Size.square(16), color: accent),
            label: Text(LocaleKeys.shareTab_copyLink.tr()),
            onPressed: state.shareLink.isEmpty ||
                    state.selectedPermissionId !=
                        ShareAccessLevel.readAndWrite.permissionId
                ? null
                : () {
                    if (!(context.read<ShareBloc?>()?.state.enablePublish ??
                        false)) {
                      showToastNotification(
                          message: '当前笔记未同步到云端，无法生成分享链接',
                          description: '请先在设置中连接云服务并开启同步，然后再尝试分享此笔记。',
                          type: ToastificationType.warning);
                      return;
                    }
                    _bloc.add(
                        ShareTabEvent.copyShareLink(link: state.shareLink));
                  },
          ),
        ],
      ),
    );
  }
}

class CollaboratorsDialog extends StatefulWidget {
  const CollaboratorsDialog({
    super.key,
    required this.workspaceId,
    required this.pageId,
  });

  final String workspaceId;
  final String pageId;

  @override
  State<CollaboratorsDialog> createState() => _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends State<CollaboratorsDialog> {
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

        // 监听成员权限更新结果（updateMemberPermission）
        final updateAccessLevelResult = state.updateAccessLevelResult;
        if (updateAccessLevelResult != null) {
          updateAccessLevelResult.fold(
            (_) {},
            (error) {
              showToastNotification(
                message: error.msg.isNotEmpty ? error.msg : '权限修改失败',
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
        // 接口/FFI 返回的是显式协作者；文档拥有者可能不在 af_collab_member 中。
        // 只有存在真实成员数据时才补 owner，避免取数失败时误展示成“只有自己”。
        final allUsers = users.isEmpty
            ? users
            : buildUsersListWithOwner(
                users: users,
                currentUser: currentUser,
              );

        // 从完整列表中查找当前登录用户（可能是拥有者，也可能是被邀请者）
        final currentUid =
            _extractCurrentUserUuid(currentUser) ?? currentUser?.id.toString();
        final currentEmail = currentUser?.email.trim().toLowerCase();
        final currentNumericId = currentUser?.id.toString();
        // 通过 userId / uid / email 任一匹配定位当前登录用户。
        // 仅靠 userId 容易失败：本地缓存返回的 user_id 可能为空，
        // 或 JWT sub 与后端成员 uuid 格式不一致，导致找不到当前用户而
        // 兜底成 readOnly，使权限下拉菜单整体不可操作。
        // 多种字段兜底匹配，确保能找到当前用户。
        final currentSharedUser = currentUser == null
            ? null
            : allUsers.firstWhereOrNull(
                (user) {
                  final idMatch = currentUid != null &&
                      currentUid.isNotEmpty &&
                      user.userId == currentUid;
                  final uidMatch = currentNumericId != null &&
                      currentNumericId.isNotEmpty &&
                      user.uid == currentNumericId;
                  final emailMatch = currentEmail != null &&
                      currentEmail.isNotEmpty &&
                      user.email.trim().toLowerCase() == currentEmail;
                  return idMatch || uidMatch || emailMatch;
                },
              );
        // 兜底：接口返回成员里找不到当前用户时，也要展示列表，避免整块空白。
        // 智能判断权限：如果第一条拥有 fullAccess（约定第一条为拥有者），
        // 则当前用户大概率是拥有者，赋予 fullAccess；否则使用 readOnly。
        ShareAccessLevel fallbackAccessLevel = ShareAccessLevel.readOnly;
        if (currentSharedUser == null && currentUser != null) {
          if (allUsers.isNotEmpty &&
              allUsers.first.accessLevel == ShareAccessLevel.fullAccess) {
            // 接口约定第一条为拥有者；匹配失败说明 userId/email 格式不一致，
            // 但当前用户大概率就是拥有者，赋予 fullAccess 避免权限按钮变灰。
            fallbackAccessLevel = ShareAccessLevel.fullAccess;
            LogUtils.debug(
              '[ShareTab] Current user not matched in collab list, '
              'but first member has fullAccess — assuming owner, '
              'fallback to fullAccess. currentUid=$currentUid, '
              'currentEmail=$currentEmail, '
              'firstMemberEmail=${allUsers.first.email}',
            );
          } else {
            LogUtils.warning(
              '[ShareTab] Current user not matched in collab list and '
              'first member is NOT owner. Falling back to readOnly. '
              'currentUid=$currentUid, currentEmail=$currentEmail, '
              'usersCount=${allUsers.length}',
            );
          }
        }
        final effectiveCurrentSharedUser = currentSharedUser ??
            SharedUser(
              email: currentUser?.email ?? '',
              name: (currentUser?.name.isNotEmpty ?? false)
                  ? currentUser!.name
                  : (currentUser?.email ?? 'current_user'),
              role: ShareRole.member,
              accessLevel: fallbackAccessLevel,
              userId: currentUid,
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
                                currentUser: effectiveCurrentSharedUser,

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
                                        email: user.email,
                                      ),
                                    );
                                  },
                                  onRemoveAccess: () {
                                    final removingSelf = currentUid != null &&
                                        currentUid.isNotEmpty &&
                                        user.userId == currentUid;
                                    if (removingSelf) {
                                      showConfirmDialog(
                                        context: context,
                                        title: LocaleKeys
                                            .shareAction_removeOwnAccess
                                            .tr(),
                                        titleStyle:
                                            theme.textStyle.body.standard(
                                          color: theme.textColorScheme.primary,
                                        ),
                                        description: '',
                                        style: ConfirmPopupStyle.cancelAndOk,
                                        confirmLabel:
                                            LocaleKeys.button_delete.tr(),
                                        onConfirm: (_) {
                                          _bloc.add(
                                            ShareTabEvent.removeCollabMember(
                                              user: user,
                                            ),
                                          );
                                        },
                                      );
                                    } else {
                                      _bloc.add(
                                        ShareTabEvent.removeCollabMember(
                                          user: user,
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
                  .where((level) => level != ShareAccessLevel.readAndComment)
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
