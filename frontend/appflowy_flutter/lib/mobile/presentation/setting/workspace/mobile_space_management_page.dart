import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/share_tab/data/models/shared_user.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_create_space_sheet.dart';
import 'package:appflowy/mobile/presentation/home/space/space_change_notifier.dart';
import 'package:appflowy/mobile/presentation/widgets/show_flowy_mobile_confirm_dialog.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart' hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart' hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart' hide Icon;
import 'package:flutter/material.dart' as material;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';

class MobileSpaceManagementPage extends StatefulWidget {
  const MobileSpaceManagementPage({
    super.key,
    this.showAppBar = true,
  });

  static const routeName = '/space_management';

  final bool showAppBar;

  @override
  State<MobileSpaceManagementPage> createState() =>
      _MobileSpaceManagementPageState();
}

class _MobileSpaceManagementPageState extends State<MobileSpaceManagementPage> {
  bool _onlyOwnerCanCreate = true;
  bool _isLoading = true;
  UserProfilePB? _userProfile;
  WorkspacePB? _currentWorkspace;
  AFRolePB? _currentWorkspaceRole;
  SpaceBloc? _spaceBloc;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final profileRes = await UserBackendService.getCurrentUserProfile();
    profileRes.fold(
      (profile) async {
        _userProfile = profile;
        final workspacesRes = await UserBackendService(userId: profile.id).getWorkspaces();
        workspacesRes.fold(
          (workspaces) async {
            if (workspaces.isEmpty) {
              _done();
              return;
            }
            final ws = workspaces.firstWhere(
              (w) => w.workspaceId.isNotEmpty,
              orElse: () => workspaces.first,
            );
            _currentWorkspace = WorkspacePB.create()
              ..id = ws.workspaceId
              ..name = ws.name;
            _spaceBloc = SpaceBloc(
              userProfile: profile,
              workspaceId: ws.workspaceId,
            )..add(const SpaceEvent.initial(openFirstPage: false));
            _currentWorkspaceRole = ws.role;
            await _loadWorkspaceSetting();
          },
          (_) => _done(),
        );
      },
      (_) => _done(),
    );
  }

  Future<void> _loadWorkspaceSetting() async {
    if (_currentWorkspace == null) {
      _done();
      return;
    }
    try {
      final payload = UserWorkspaceIdPB(workspaceId: _currentWorkspace!.id);
      final result = await UserEventGetWorkspaceSetting(payload).send();
      result.fold(
        (settings) {
          if (mounted) {
            setState(() {
              _onlyOwnerCanCreate = settings.onlyOwnerCanCreateTeamWorkspace;
              _isLoading = false;
            });
          }
        },
        (err) {
          Log.error('Failed to load workspace settings: $err');
          _done();
        },
      );
    } catch (e) {
      Log.error('Exception loading workspace settings: $e');
      _done();
    }
  }

  void _done() {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _spaceBloc?.close();
    super.dispose();
  }

  Future<void> _updateOnlyOwnerCanCreate(bool value) async {
    if (_currentWorkspace == null) return;

    final message = value
        ? '限定此工作空间只有工作空间所有者可以创建团队协作区？'
        : '允许此工作空间的所有成员创建团队协作区？';

    final confirmed = await showFlowyCupertinoConfirmDialog(
      title: '',
      content: Text(message),
      leftButton: FlowyText(
        LocaleKeys.button_cancel.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF007AFF),
      ),
      rightButton: FlowyText(
        LocaleKeys.button_confirm.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF007AFF),
      ),
      onRightButtonPressed: (ctx) async {
        Navigator.of(ctx).pop(true);
      },
    );

    if (confirmed != true) return;

    try {
      final payload = UpdateUserWorkspaceSettingPB(
        workspaceId: _currentWorkspace!.id,
        onlyOwnerCanCreateTeamWorkspace: value,
      );
      final result =
          await UserEventUpdateWorkspaceSetting(payload).send();
      result.fold(
        (_) {
          if (mounted) {
            setState(() => _onlyOwnerCanCreate = value);
          }
          showToastNotification(message: '设置已更新');
        },
        (err) {
          Log.error('Update workspace setting failed: $err');
          showToastNotification(
            message: '设置更新失败',
            type: ToastificationType.error,
          );
        },
      );
    } catch (e) {
      Log.error('Exception updating workspace setting: $e');
      showToastNotification(
        message: '设置更新失败',
        type: ToastificationType.error,
      );
    }
  }

  bool _canCreateSpace() {
    if (!_onlyOwnerCanCreate) return true;
    if (_userProfile == null) return false;
    try {
      return _currentWorkspaceRole == AFRolePB.Owner;
    } catch (_) {
      return false;
    }
  }

  void _showCreateSpaceSheet() {
    if (_spaceBloc == null) return;
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: '新建团队协作区',
      enableDraggableScrollable: true,
      minChildSize: 0.6,
      maxChildSize: 0.9,
      initialChildSize: 0.6,
      builder: (_) => MobileCreateSpaceSheet(
        spaceBloc: _spaceBloc!,
        onCreated: () {
          // `_onCreate` 已经把新 space 写进 `state.spaces`，本页 UI
          // 会自动 rebuild。
          //
          // 通知 home 屏的 `SpaceBloc`（不同实例）刷新 spaces 列表。
          // Home 屏会 `SpaceEvent.initial` 重拉 backend —— backend
          // 的 `getPublicViews` 在 create 之后可能有几百毫秒滞后，
          // 偶尔会出现新 space 短暂消失，下次后台 listener
          // (`didReceiveSpaceUpdate`) 会再拉一次修复。
          MobileSpaceChangeNotifier.instance.notifySpacesChanged();
        },
      ),
    );
  }

  Widget _buildPermissionSection() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const FlowyText(
          '正在加载设置...',
          fontSize: 14,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText.medium(
                  '仅工作空间所有者可以创建团队协作区',
                  fontSize: 15,
                ),
                const SizedBox(height: 4),
                FlowyText(
                  '仅允许工作空间所有者创建团队协作区',
                  fontSize: 13,
                  color: const Color(0xFF8E8E93),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: _onlyOwnerCanCreate,
            onChanged: _updateOnlyOwnerCanCreate,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool embedMode = !widget.showAppBar;

    if (embedMode) {
      return _SpaceManagementContent(
        embedMode: true,
        spaceBloc: _spaceBloc,
        userProfile: _userProfile,
        currentWorkspaceRole: _currentWorkspaceRole,
        currentWorkspace: _currentWorkspace,
        isLoading: _isLoading,
      );
    }

    return _buildStandaloneLayout();
  }

  Widget _buildStandaloneLayout() {
    return Scaffold(
      appBar: MobileAppBar(title: '空间管理'),
      body: Column(
        children: [
          _buildPermissionSection(),
          const Divider(height: 1),
          Expanded(
            child: _SpaceManagementContent(
              embedMode: false,
              spaceBloc: _spaceBloc,
              userProfile: _userProfile,
              currentWorkspaceRole: _currentWorkspaceRole,
              currentWorkspace: _currentWorkspace,
              isLoading: _isLoading,
            ),
          ),
        ],
      ),
      floatingActionButton: _canCreateSpace()
          ? FloatingActionButton(
              onPressed: _showCreateSpaceSheet,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const material.Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}

/// 空间管理内容组件，支持嵌入模式和独立模式
class _SpaceManagementContent extends StatefulWidget {
  const _SpaceManagementContent({
    required this.embedMode,
    required this.spaceBloc,
    required this.userProfile,
    required this.currentWorkspaceRole,
    required this.currentWorkspace,
    required this.isLoading,
  });

  final bool embedMode;
  final SpaceBloc? spaceBloc;
  final UserProfilePB? userProfile;
  final AFRolePB? currentWorkspaceRole;
  final WorkspacePB? currentWorkspace;
  final bool isLoading;

  @override
  State<_SpaceManagementContent> createState() => _SpaceManagementContentState();
}

class _SpaceManagementContentState extends State<_SpaceManagementContent> {
  bool get _canCreateSpace {
    final parent = context.findAncestorStateOfType<_MobileSpaceManagementPageState>();
    if (parent == null) return false;
    return parent._canCreateSpace();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.spaceBloc == null || widget.isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return BlocBuilder<SpaceBloc, SpaceState>(
      bloc: widget.spaceBloc,
      buildWhen: (prev, curr) {
        // Only rebuild when the space list actually changes — otherwise
        // every state mutation (currentSpace, child views, etc.) thrashes
        // the UI.
        if (prev.spaces.length != curr.spaces.length) return true;
        final prevIds = prev.spaces.map((s) => s.id).toSet();
        final currIds = curr.spaces.map((s) => s.id).toSet();
        return !prevIds.difference(currIds).isEmpty ||
            !currIds.difference(prevIds).isEmpty;
      },
      builder: (context, state) {
        // Use `SpaceBloc.state.spaces` (sourced from `_getSpaces` RPC) so
        // freshly-created spaces show up here immediately: `_onCreate`
        // emits `[...state.spaces, space]` right after the backend
        // `createView` RPC returns. This mirrors the desktop sidebar's
        // rendering source.
        final spaces = widget.spaceBloc!.publicSpaces;
        Log.debug(
          '[SpaceCreate] _SpaceManagementContent.build: '
          'embedMode=${widget.embedMode}, '
          'blocHash=${widget.spaceBloc.hashCode}, '
          'spaceBloc.state.spaces.count=${widget.spaceBloc!.state.spaces.length}, '
          'publicSpaces.count=${spaces.length}, '
          'publicSpaces=${spaces.map((s) => "${s.name}(${s.id}, isSpace=${s.isSpace}, perm=${s.spacePermission})").toList()}',
        );

        if (spaces.isEmpty) {
          return SizedBox(
            height: widget.embedMode ? null : 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FlowySvg(
                    FlowySvgs.m_empty_trash_xl,
                    size: Size.square(46),
                  ),
                  const VSpace(16),
                  FlowyText.medium(
                    '暂无团队协作区',
                    fontSize: 16,
                  ),
                  const SizedBox(height: 8),
                  FlowyText(
                    widget.embedMode ? '暂无数据' : '点击右下角按钮创建',
                    fontSize: 14,
                  ),
                  const VSpace(80),
                ],
              ),
            ),
          );
        }

        Log.debug(
          '[SpaceCreate] _SpaceManagementContent: rendering ${spaces.length} spaces '
          'in embedMode=${widget.embedMode}',
        );

        return Column(
          mainAxisSize: widget.embedMode ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (widget.embedMode && _canCreateSpace) _buildEmbeddedHeader(context),
            if (widget.embedMode)
              // 在 SingleChildScrollView 等高度无限的父级中，不能用 Expanded
              // 改用 Flexible + shrinkWrap + NeverScrollableScrollPhysics，
              // 让 ListView 自适应内容高度。
              Flexible(
                fit: FlexFit.loose,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: spaces.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, index) {
                    final s = spaces[index];
                    return _SpaceListItem(
                      space: s,
                      userProfile: widget.userProfile,
                      currentWorkspaceRole: widget.currentWorkspaceRole,
                      workspaceId: widget.currentWorkspace?.id ?? '',
                      onDelete: () => _deleteSpace(s),
                      onPermissionChanged: (newPerm) =>
                          _updateSpacePermission(s, newPerm),
                      onManageMembers: () => _showMemberManagementSheet(s),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: spaces.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, index) {
                    final s = spaces[index];
                    return _SpaceListItem(
                      space: s,
                      userProfile: widget.userProfile,
                      currentWorkspaceRole: widget.currentWorkspaceRole,
                      workspaceId: widget.currentWorkspace?.id ?? '',
                      onDelete: () => _deleteSpace(s),
                      onPermissionChanged: (newPerm) =>
                          _updateSpacePermission(s, newPerm),
                      onManageMembers: () => _showMemberManagementSheet(s),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmbeddedHeader(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.primary,
        border: Border(
          bottom: BorderSide(color: theme.borderColorScheme.primary),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FlowyText.medium(
              '空间管理',
              fontSize: 17,
              color: theme.textColorScheme.primary,
            ),
          ),
          IconButton(
            icon: material.Icon(Icons.add, color: theme.textColorScheme.primary),
            onPressed: _showCreateSpaceSheet,
          ),
        ],
      ),
    );
  }

  void _showCreateSpaceSheet() {
    if (widget.spaceBloc == null) return;
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: '新建团队协作区',
      enableDraggableScrollable: true,
      minChildSize: 0.6,
      maxChildSize: 0.9,
      initialChildSize: 0.6,
      builder: (_) => MobileCreateSpaceSheet(
        spaceBloc: widget.spaceBloc!,
        onCreated: () {
          // `_onCreate` already emits the freshly-created space into
          // `state.spaces`; the management page UI rebuilds from that.
          //
          // We deliberately do NOT dispatch `SpaceEvent.initial` here:
          // `initial` re-pulls `getPublicViews` from the backend, which
          // returns a stale list right after the create (the in-memory
          // folder cache hasn't caught up yet), so the freshly-created
          // space would briefly disappear from the list. We let the
          // background listener (`didReceiveSpaceUpdate`) handle the
          // eventual sync.
          //
          // We still need to notify the *home* SpaceBloc (a different
          // instance) so the home page can render the new space. The
          // home page will dispatch its own `SpaceEvent.initial` in
          // response to this notification.
          MobileSpaceChangeNotifier.instance.notifySpacesChanged();
        },
      ),
    );
  }

  Future<void> _deleteSpace(ViewPB space) async {
    final confirmed = await showFlowyCupertinoConfirmDialog(
      title: '确认删除',
      content: Text('确认要删除团队协作区「${space.name}」吗？'),
      leftButton: FlowyText(
        LocaleKeys.button_cancel.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF007AFF),
      ),
      rightButton: FlowyText(
        LocaleKeys.button_confirm.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w400,
        color: const Color(0xFFFE0220),
      ),
      onRightButtonPressed: (ctx) async {
        Navigator.of(ctx).pop(true);
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    widget.spaceBloc?.add(SpaceEvent.delete(space));
    showToastNotification(message: '已删除「${space.name}」');
    // 通知首页 SpaceBloc 重新拉取
    MobileSpaceChangeNotifier.instance.notifySpacesChanged();
  }

  void _updateSpacePermission(ViewPB space, SpacePermission newPerm) {
    widget.spaceBloc?.add(
      SpaceEvent.update(space: space, permission: newPerm),
    );
    showToastNotification(message: '权限已更新');
    // 通知首页 SpaceBloc 重新拉取
    MobileSpaceChangeNotifier.instance.notifySpacesChanged();
  }

  void _showMemberManagementSheet(ViewPB space) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: space.name,
      enableDraggableScrollable: true,
      minChildSize: 0.7,
      maxChildSize: 0.95,
      initialChildSize: 0.8,
      builder: (_) => MobileSpaceMemberSheet(
        space: space,
        workspaceId: widget.currentWorkspace?.id ?? '',
        userProfile: widget.userProfile,
        currentWorkspaceRole: widget.currentWorkspaceRole,
      ),
    );
  }
}

class _SpaceListItem extends StatelessWidget {
  const _SpaceListItem({
    required this.space,
    required this.userProfile,
    required this.currentWorkspaceRole,
    required this.workspaceId,
    required this.onDelete,
    required this.onPermissionChanged,
    required this.onManageMembers,
  });

  final ViewPB space;
  final UserProfilePB? userProfile;
  final AFRolePB? currentWorkspaceRole;
  final String workspaceId;
  final VoidCallback onDelete;
  final void Function(SpacePermission) onPermissionChanged;
  final VoidCallback onManageMembers;

  String _permissionLabel(ViewPB s) {
    switch (s.spacePermission) {
      case SpacePermission.publicToAll:
        return '开放式';
      case SpacePermission.closed:
        return '封闭式';
      case SpacePermission.private:
        return '私人';
    }
  }

  bool get _canDelete {
    try {
      return currentWorkspaceRole == AFRolePB.Owner;
    } catch (_) {
      return false;
    }
  }

  bool get _canModifyPermission {
    try {
      return currentWorkspaceRole == AFRolePB.Owner;
    } catch (_) {
      return false;
    }
  }

  String _formatTime(int timestampMs) {
    if (timestampMs == 0) return '未知';
    if (timestampMs < 1000000000000) {
      timestampMs = timestampMs * 1000;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    return DateFormat('yyyy-MM-dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final createdAt = space.createTime.toInt();
    final updateTime = _formatTime(createdAt);

    return InkWell(
      onTap: onManageMembers,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildSpaceIcon(theme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlowyText.medium(
                    space.name,
                    fontSize: 15,
                    color: theme.textColorScheme.primary,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _PermissionChip(
                        label: _permissionLabel(space),
                        theme: theme,
                      ),
                      const SizedBox(width: 8),
                      FlowyText(
                        updateTime,
                        fontSize: 12,
                        color: theme.textColorScheme.secondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_canDelete || _canModifyPermission)
              PopupMenuButton<String>(
                icon: FlowySvg(
                  FlowySvgs.three_dots_s,
                  color: theme.iconColorScheme.secondary,
                  size: const Size.square(20),
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    onDelete();
                  } else if (value == 'permission') {
                    _showPermissionSheet(context);
                  } else if (value == 'members') {
                    onManageMembers();
                  }
                },
                itemBuilder: (context) => [
                  if (_canModifyPermission) ...[
                    PopupMenuItem(
                      value: 'permission',
                      child: const FlowyText('修改权限'),
                    ),
                    PopupMenuItem(
                      value: 'members',
                      child: const FlowyText('管理成员'),
                    ),
                    const PopupMenuDivider(),
                  ],
                  if (_canDelete)
                    PopupMenuItem(
                      value: 'delete',
                      child: FlowyText(
                        LocaleKeys.button_delete.tr(),
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceIcon(AppFlowyThemeData theme) {
    final icon = space.spaceIcon;
    final iconColor = space.spaceIconColor;

    if (icon == null || icon.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x1AFF9500),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const material.Icon(Icons.groups, size: 20, color: Colors.orange),
      );
    }

    Color color;
    try {
      color = Color(int.parse(iconColor ?? '0xFFA34AFD'));
    } catch (_) {
      color = const Color(0xFFA34AFD);
    }

    if (icon.contains('/')) {
      final svgContent = kIconGroups?.findSvgContent(icon);
      if (svgContent != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            color: color,
            child: Center(
              child: FlowySvg.string(
                svgContent,
                size: const Size.square(20),
                color: Colors.white,
              ),
            ),
          ),
        );
      }
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          icon,
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }

  void _showPermissionSheet(BuildContext context) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: '修改访问权限',
      builder: (_) => _PermissionSheet(
        currentPermission: space.spacePermission,
        onSelected: (newPerm) {
          Navigator.of(context).pop();
          onPermissionChanged(newPerm);
        },
      ),
    );
  }
}

class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({
    required this.currentPermission,
    required this.onSelected,
  });

  final SpacePermission currentPermission;
  final void Function(SpacePermission) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            context,
            theme,
            SpacePermission.publicToAll,
            '开放式',
            '所有工作空间成员可见并可访问',
          ),
          const SizedBox(height: 8),
          _buildOption(
            context,
            theme,
            SpacePermission.private,
            '私人',
            '仅被邀请的成员可见',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    AppFlowyThemeData theme,
    SpacePermission permission,
    String title,
    String description,
  ) {
    final isSelected = currentPermission == permission;

    return GestureDetector(
      onTap: () => onSelected(permission),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.surfaceColorScheme.layer01
              : theme.surfaceColorScheme.layer02,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.textColorScheme.primary
                : theme.borderColorScheme.primary,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.textColorScheme.primary
                      : theme.borderColorScheme.primary,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.textColorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlowyText.medium(
                    title,
                    fontSize: 14,
                    color: theme.textColorScheme.primary,
                  ),
                  const SizedBox(height: 2),
                  FlowyText(
                    description,
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
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.label,
    required this.theme,
  });

  final String label;
  final AppFlowyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.borderColorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: FlowyText(
        label,
        fontSize: 11,
        color: theme.textColorScheme.secondary,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// MobileSpaceMemberSheet — space member management
// ────────────────────────────────────────────────────────────────────────────

class MobileSpaceMemberSheet extends StatefulWidget {
  const MobileSpaceMemberSheet({
    super.key,
    required this.space,
    required this.workspaceId,
    required this.userProfile,
    required this.currentWorkspaceRole,
  });

  final ViewPB space;
  final String workspaceId;
  final UserProfilePB? userProfile;
  final AFRolePB? currentWorkspaceRole;

  @override
  State<MobileSpaceMemberSheet> createState() => _MobileSpaceMemberSheetState();
}

class _MobileSpaceMemberSheetState extends State<MobileSpaceMemberSheet> {
  List<CollabMember> _members = [];
  bool _isLoading = true;
  String? _errorMessage;

  final _searchController = TextEditingController();
  List<SharedUser> _searchResults = [];
  List<SharedUser> _selectedUsers = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _isAddingMember = false;
  AFRolePB _selectedRole = AFRolePB.Member;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    if (widget.userProfile == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userService = UserBackendService(userId: widget.userProfile!.id);
      final res = await userService.getCollabMembers(widget.workspaceId, widget.space.id);
      res.fold(
        (list) {
          if (mounted) {
            setState(() {
              _members = list;
              _isLoading = false;
            });
          }
        },
        (err) {
          Log.error('Failed to load collab members: $err');
          if (mounted) {
            setState(() {
              _errorMessage = '无法加载成员列表';
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      Log.error('Exception loading collab members: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '加载成员时出错';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final repo = RustShareWithUserRepositoryImpl();
      final res = await repo.searchUsers(query: query.trim());
      List<SharedUser> users = [];
      res.fold((u) => users = u, (e) => users = []);

      if (users.isEmpty) {
        final digitsOnly = query.replaceAll(RegExp(r'\D'), '');
        if (digitsOnly.isNotEmpty &&
            digitsOnly.length >= 6 &&
            digitsOnly.length <= 15) {
          final variants = <String>{};
          variants.add(digitsOnly);
          variants.add(digitsOnly.replaceFirst(RegExp(r'^0+'), ''));
          if (!digitsOnly.startsWith('86') && digitsOnly.length == 11) {
            variants.add('86$digitsOnly');
            variants.add('+86$digitsOnly');
          }
          if (!digitsOnly.startsWith('+')) {
            variants.add('+$digitsOnly');
          }
          for (final v in variants) {
            if (v.trim().isEmpty) continue;
            final r2 = await repo.searchUsers(query: v);
            r2.fold((u2) {
              if (u2.isNotEmpty) users = u2;
            }, (_) {});
            if (users.isNotEmpty) break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = users;
          _isSearching = false;
        });
      }
    } catch (e) {
      Log.error('Exception searching users: $e');
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _toggleUser(SharedUser user) {
    setState(() {
      final idx = _selectedUsers.indexWhere((u) => u.userId == user.userId);
      if (idx >= 0) {
        _selectedUsers.removeAt(idx);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  Future<void> _addMembers() async {
    if (_selectedUsers.isEmpty || widget.userProfile == null) return;

    setState(() => _isAddingMember = true);

    final userService = UserBackendService(userId: widget.userProfile!.id);
    bool allOk = true;

    for (final u in _selectedUsers) {
      final inviteRes = await userService.inviteWorkspaceMember(
        widget.workspaceId,
        u.email,
        role: _selectedRole,
      );
      await inviteRes.fold(
        (_) async {
          try {
            TeamACLPB? current;
            final aclRes = await userService.getTeamACL(widget.space.id);
            aclRes.fold((acl) => current = acl, (_) => current = null);
            final existing = current?.allowEmails.toList() ?? [];
            if (!existing.contains(u.email)) {
              final newAcl = TeamACLPB(
                teamId: widget.space.id,
                allowUserIds: [],
                allowEmails: [...existing, u.email],
              );
              await userService.updateTeamACL(newAcl);
            }
          } catch (e) {
            Log.error('Failed to update team ACL: $e');
          }
        },
        (err) {
          allOk = false;
        },
      );
    }

    if (mounted) {
      setState(() => _isAddingMember = false);
      if (allOk) {
        showToastNotification(message: '已添加 ${_selectedUsers.length} 位成员');
        _selectedUsers.clear();
        _searchResults.clear();
        _searchController.clear();
        _loadMembers();
      } else {
        showToastNotification(
          message: '部分成员添加失败',
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> _removeMember(CollabMember member) async {
    final confirmed = await showFlowyCupertinoConfirmDialog(
      title: '确认移除',
      content: Text('确认要移除成员「${member.name}」吗？'),
      leftButton: FlowyText(
        LocaleKeys.button_cancel.tr(),
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF007AFF),
      ),
      rightButton: const FlowyText(
        '移除',
        fontSize: 17.0,
        figmaLineHeight: 24.0,
        fontWeight: FontWeight.w400,
        color: Color(0xFFFE0220),
      ),
      onRightButtonPressed: (ctx) async {
        Navigator.of(ctx).pop(true);
      },
    );

    if (confirmed != true || widget.userProfile == null || !mounted) return;

    try {
      final userService = UserBackendService(userId: widget.userProfile!.id);
      final res = await userService.removeCollabMember(
        widget.workspaceId,
        widget.space.id,
        member.uid,
      );
      res.fold(
        (_) {
          setState(() {
            _members.removeWhere((m) => m.uid == member.uid);
          });
          showToastNotification(message: '已移除「${member.name}」');
        },
        (err) {
          showToastNotification(
            message: '移除失败',
            type: ToastificationType.error,
          );
        },
      );
    } catch (e) {
      showToastNotification(
        message: '移除失败',
        type: ToastificationType.error,
      );
    }
  }

  bool get _isOwner {
    try {
      return widget.currentWorkspaceRole == AFRolePB.Owner;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FlowyText(_errorMessage!, color: theme.textColorScheme.secondary),
                          const SizedBox(height: 12),
                          FlowyButton(
                            text: const FlowyText.regular('重试'),
                            onTap: _loadMembers,
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildAddMemberSection(theme),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                FlowyText(
                                  '成员列表',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textColorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.surfaceColorScheme.layer01,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: FlowyText(
                                    '${_members.length}',
                                    fontSize: 12,
                                    color: theme.textColorScheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _members.isEmpty
                            ? SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                    child: FlowyText(
                                      '暂无成员',
                                      color: theme.textColorScheme.secondary,
                                    ),
                                  ),
                                ),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final member = _members[index];
                                    return _buildMemberTile(member, theme);
                                  },
                                  childCount: _members.length,
                                ),
                              ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildAddMemberSection(AppFlowyThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowyText.medium(
            '添加成员',
            fontSize: 14,
            color: theme.textColorScheme.primary,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FlowyTextField(
                  controller: _searchController,
                  hintText: '搜索邮箱或手机号',
                  onChanged: _searchUsers,
                  onSubmitted: _searchUsers,
                ),
              ),
              const SizedBox(width: 8),
              if (_isSearching)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_selectedUsers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedUsers.map((u) {
                return Chip(
                  label: Text(u.name.isNotEmpty ? u.name : u.email),
                  onDeleted: () => _toggleUser(u),
                  deleteIconColor: theme.textColorScheme.secondary,
                );
              }).toList(),
            ),
          ],
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: theme.surfaceColorScheme.layer01,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.borderColorScheme.primary),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final user = _searchResults[idx];
                  final already = _selectedUsers.any((u) => u.userId == user.userId);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                    title: Text(user.name.isNotEmpty ? user.name : user.email),
                    subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
                    trailing: material.Icon(
                      already ? Icons.check_box : Icons.check_box_outline_blank,
                      color: already ? theme.textColorScheme.primary : null,
                    ),
                    onTap: () => _toggleUser(user),
                  );
                },
              ),
            ),
          ] else if (_hasSearched && _searchResults.isEmpty && !_isSearching) ...[
            const SizedBox(height: 8),
            FlowyText(
              '未找到用户',
              fontSize: 13,
              color: theme.textColorScheme.secondary,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FlowyText('权限级别', fontSize: 13, color: theme.textColorScheme.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleDropdown(
                  value: _selectedRole,
                  onChanged: (role) => setState(() => _selectedRole = role),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: AFFilledTextButton.primary(
              text: _isAddingMember
                  ? '添加中...'
                  : '添加选中成员 (${_selectedUsers.length})',
              onTap: _selectedUsers.isNotEmpty && !_isAddingMember
                  ? _addMembers
                  : () {},
              size: AFButtonSize.m,
              disabled: _selectedUsers.isEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(CollabMember member, AppFlowyThemeData theme) {
    final isOwner = member.permissionId == 4;
    final currentUserId = widget.userProfile?.id.toInt() ?? 0;
    final canRemove = _isOwner && member.uid != currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey.shade700,
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText(
                  member.name.isNotEmpty ? member.name : (member.email ?? ''),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.textColorScheme.primary,
                ),
                if (member.email != null && member.email!.isNotEmpty)
                  FlowyText(
                    member.email!,
                    fontSize: 12,
                    color: theme.textColorScheme.secondary,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isOwner
                  ? const Color(0xFFFB006D).withValues(alpha: 0.1)
                  : theme.surfaceColorScheme.layer01,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FlowyText(
              isOwner ? '所有者' : '成员',
              fontSize: 12,
              color: isOwner
                  ? const Color(0xFFFB006D)
                  : theme.textColorScheme.secondary,
            ),
          ),
          if (canRemove) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: material.Icon(Icons.remove_circle_outline,
                  color: theme.textColorScheme.error, size: 20),
              onPressed: () => _removeMember(member),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({
    required this.value,
    required this.onChanged,
  });

  final AFRolePB value;
  final void Function(AFRolePB) onChanged;

  String _label(AFRolePB role) {
    switch (role) {
      case AFRolePB.Owner:
        return '工作空间所有者';
      case AFRolePB.Member:
        return '成员';
      case AFRolePB.Guest:
        return '受限成员';
      default:
        return '成员';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderColorScheme.primary),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AFRolePB>(
          value: value,
          isExpanded: true,
          icon: const material.Icon(Icons.arrow_drop_down, size: 20),
          style: TextStyle(fontSize: 14, color: theme.textColorScheme.primary),
          dropdownColor: theme.surfaceColorScheme.primary,
          items: [
            DropdownMenuItem(
              value: AFRolePB.Owner,
              child: Text(_label(AFRolePB.Owner)),
            ),
            DropdownMenuItem(
              value: AFRolePB.Member,
              child: Text(_label(AFRolePB.Member)),
            ),
            DropdownMenuItem(
              value: AFRolePB.Guest,
              child: Text(_label(AFRolePB.Guest)),
            ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
