import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category_spacer.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/create_space_popup.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:appflowy/shared/af_role_pb_extension.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';

import '../../../../generated/locale_keys.g.dart';
import '../../widgets/pop_up_action.dart';

class SettingsWorkspaceManagementView extends StatefulWidget {
  const SettingsWorkspaceManagementView({
    super.key,
    required this.userProfile,
    required this.workspace,
  });

  final UserProfilePB userProfile;
  final UserWorkspacePB workspace;

  @override
  State<SettingsWorkspaceManagementView> createState() =>
      _SettingsWorkspaceManagementViewState();
}

class _SettingsWorkspaceManagementViewState
    extends State<SettingsWorkspaceManagementView> {
  bool _onlyOwnerCanCreateTeamWorkspace = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 延迟加载设置，避免在应用启动初期调用 API
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadWorkspaceSettings();
      }
    });
  }

  Future<void> _loadWorkspaceSettings() async {
    try {
      final payload =
          UserWorkspaceIdPB(workspaceId: widget.workspace.workspaceId);
      final result = await UserEventGetWorkspaceSetting(payload).send();

      if (mounted) {
        result.fold(
          (settings) {
            setState(() {
              _onlyOwnerCanCreateTeamWorkspace =
                  settings.onlyOwnerCanCreateTeamWorkspace;
              _isLoading = false;
            });
          },
          (err) {
            Log.error('Failed to load workspace settings: $err');
            // 即使失败也设置加载完成，避免界面卡住
            setState(() {
              _isLoading = false;
            });
          },
        );
      }
    } catch (e) {
      Log.error('Exception loading workspace settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateWorkspaceSetting(bool value) async {
    try {
      final payload = UpdateUserWorkspaceSettingPB(
        workspaceId: widget.workspace.workspaceId,
        onlyOwnerCanCreateTeamWorkspace: value,
      );

      final result = await UserEventUpdateWorkspaceSetting(payload).send();

      result.fold(
        (ok) {
          Log.info('Update workspace setting success');
          if (mounted) {
            setState(() {
              _onlyOwnerCanCreateTeamWorkspace = value;
            });
          }
        },
        (err) {
          Log.error('Update workspace setting failed: $err');
          // 显示用户友好的错误提示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('设置更新失败: ${err.msg}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } catch (e) {
      Log.error('Exception updating workspace setting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置更新失败，请稍后重试'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(
      title: '空间管理',
      description: '管理您的工作空间设置和配置',
      autoSeparate:
          false, // control separators manually to avoid duplicate dividers
      headerTrailingBuilder: (context) => _buildRightButton(),
      children: [
        // 创建团队协作区权限设置
        _buildCreatePermissionSection(),
        // keep a single visual separator between the two sections
        const SettingsCategorySpacer(),
        // 团队协作区列表
        _buildTeamWorkspaceTable()
      ],
    );
  }

  Widget _buildCreatePermissionSection() {
    if (_isLoading) {
      return const SettingsCategory(
        title: '正在加载设置...',
        children: [],
      );
    }

    return SettingsCategory(
      title: '仅工作空间所有者可以创建团队协作区',
      description: '仅允许工作空间所有者创建团队协作区',
      actions: [
            Toggle(
              value: _onlyOwnerCanCreateTeamWorkspace,
              onChanged: (value) {
            // value == true means turning on (limit to owners)
            // value == false means turning off (allow all members)
            final message =
                value ? '限定此工作空间只有工作空间所有者可以创建团队协作区？' : '允许此工作空间的所有成员创建团队协作区？';

            showSimpleConfirmDialog(
              context: context,
              message: message,
              confirmText: '确认',
              onConfirm: () {
                _updateWorkspaceSetting(value);
              },
            );
              },
            ),
          ],
      children: const [],
    );
  }

  /// 判断当前用户是否有权限创建团队协作区
  bool _canCreateTeamWorkspace() {
    if (!_onlyOwnerCanCreateTeamWorkspace) return true;
    try {
      final role = widget.workspace.role;
      return role == AFRolePB.Owner;
    } catch (_) {
      return false;
    }
  }

  Widget _buildTeamWorkspaceTable() {
    return BlocBuilder<SpaceBloc, SpaceState>(
      builder: (context, spaceState) {
        final spaces = context.read<SpaceBloc>().publicSpaces;

        if (spaces.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: FlowyText(
                '暂无团队协作区',
                fontSize: 14,
                color: Theme.of(context).hintColor,
              ),
            ),
          );
        }

        return Column(
          children: [
            // 表格头部
            _buildTableHeader(),
            // 表格内容 - 使用 Space 行组件
            ...spaces.map((space) {
              return _SpaceRow(
                space: space,
                userProfile: widget.userProfile,
                workspaceId: widget.workspace.workspaceId,
                role: widget.workspace.role,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: FlowyText(
              '团队协作区',
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            flex: 4,
            child: FlowyText(
              '所有者',
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            flex: 4,
            child: FlowyText(
              '访问权限',
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            flex: 3,
            child: FlowyText(
                  '更新时间',
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w500,
            ),
          ),
          // 管理 列 header保持占位以保证列宽对齐（省略号位于该列）
          Expanded(
            flex: 2,
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildRightButton() {
    return SizedBox(
      width: 140,
      height: 28,
      child: FlowyButton(
        onTap: () async {
          PopoverContainer.maybeOf(context)?.closeAll();
          await Future.delayed(Duration.zero);
          if (!mounted) return;
          final spaceBloc = context.read<SpaceBloc>();
          await showDialog(
            context: context,
            builder: (dialogCtx) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: BlocProvider.value(
                value: spaceBloc,
                child: const CreateSpacePopup(),
              ),
            ),
          );
        },
        margin: EdgeInsets.zero,
        text: Center(child: FlowyText.regular('新建团队协作区', fontSize: 12,color: Theme.of(context).colorScheme.primary,)),
      ),
    );
  }
}

// 团队协作区表格行组件
class _TeamWorkspaceRow extends StatefulWidget {
  const _TeamWorkspaceRow({
    required this.workspace,
    required this.userProfile,
  });

  final UserWorkspacePB workspace;
  final UserProfilePB userProfile;

  @override
  State<_TeamWorkspaceRow> createState() => _TeamWorkspaceRowState();
}

class _TeamWorkspaceRowState extends State<_TeamWorkspaceRow> {
  String? _ownerName;
  int _memberCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkspaceInfo();
  }

  Future<void> _loadWorkspaceInfo() async {
    try {
      final userService = UserBackendService(userId: widget.userProfile.id);
      final result = await userService.getWorkspaceMembers(
        widget.workspace.workspaceId,
      );

      result.fold(
        (members) {
          setState(() {
            _memberCount = members.items.length;
            // 查找所有者
            final owner = members.items.firstWhereOrNull(
              (member) => member.role == AFRolePB.Owner,
            );
            _ownerName = (owner != null && owner.name.isNotEmpty)
                ? owner.name
                : owner?.email ?? '未知';
            _isLoading = false;
          });
        },
        (error) {
          Log.error('Failed to get workspace members: $error');
          setState(() {
            _memberCount = widget.workspace.memberCount.toInt();
            _ownerName = '未知';
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      Log.error('Error loading workspace info: $e');
      setState(() {
        _memberCount = widget.workspace.memberCount.toInt();
        _ownerName = '未知';
        _isLoading = false;
      });
    }
  }

  String _formatUpdateTime(Int64 timestamp) {
    if (timestamp.toInt() == 0) {
      return '未知';
    }
    try {
      // Int64 时间戳通常是秒，需要转换为毫秒
      final date =
          DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return '今天';
      } else if (difference.inDays == 1) {
        return '昨天';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}天前';
      } else {
        return DateFormat('d/M/yy').format(date);
      }
    } catch (e) {
      return '未知';
    }
  }

  String _getAccessPermission() {
    // 根据工作空间类型判断访问权限
    // 这里可以根据实际需求调整逻辑
    return '开放式'; // 默认值，可以根据实际业务逻辑修改
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final status = '$_memberCount名成员·已加入';
    final owner = _ownerName ?? '未知';
    final access = _getAccessPermission();
    final updateTime = _formatUpdateTime(widget.workspace.createdAtTimestamp);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // 团队协作区图标
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.groups,
                    size: 16,
                    color: Colors.orange,
                  ),
                ),
                const HSpace(12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FlowyText(
                      widget.workspace.name,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    const VSpace(2),
                    FlowyText(
                      status,
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: FlowyText(
                      owner.isNotEmpty ? owner.substring(0, 1) : '?',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                ),
                const HSpace(8),
                Expanded(
                  child: FlowyText(
                    owner,
                    fontSize: 14,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              access,
              fontSize: 14,
            ),
          ),
          // 将更新时间与管理按钮放在同一列内以减小二者间距，最后一列保留占位用于对齐表头
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                FlowyText(
              updateTime,
              fontSize: 14,
            ),
                const HSpace(8),
                SizedBox(
                  width: 36,
                  height: 28,
                  child: FlowyButton(
                    text: Center(child: FlowyText.regular('管理', fontSize: 12)),
                    onTap: () => _openManageDialog(context),
                    margin: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _openManageDialog(BuildContext context) async {
    // load workspace members
    final userService = UserBackendService(userId: widget.userProfile.id);
    List<WorkspaceMemberPB> members = [];
    try {
      final res =
          await userService.getWorkspaceMembers(widget.workspace.workspaceId);
      res.fold((s) {
        members = s.items;
      }, (e) {
        Log.error('Failed to load workspace members for manage dialog: $e');
      });
    } catch (e) {
      Log.error('Exception loading members for manage dialog: $e');
    }

    // Initially select all members as allowed (placeholder until backend ACL exists)
    final Map<String, bool> selected = {
      for (final m in members) m.email: true,
    };

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 640,
            height: 480,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FlowyText('管理团队协作区访问权限',
                          fontSize: 16, fontWeight: FontWeight.w600),
                      SizedBox(
                        width: 72,
                        child: FlowyButton(
                          text: const FlowyText.regular('关闭'),
                          onTap: () => Navigator.of(ctx).pop(),
                          margin: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const VSpace(12),
                  const Divider(),
                  const VSpace(12),
                  Expanded(
                    child: members.isEmpty
                        ? Center(child: FlowyText('无法加载成员或无成员', fontSize: 14))
                        : ListView(
                            children: members.map((m) {
                              final email = m.email;
                              return CheckboxListTile(
                                title: Text(m.name.isNotEmpty ? m.name : email),
                                subtitle: Text(email),
                                value: selected[email] ?? false,
                                onChanged: (v) {
                                  if (v == null) return;
                                  selected[email] = v;
                                  // trigger rebuild of dialog
                                  (ctx as Element).markNeedsBuild();
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  const VSpace(12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedRoundedButton(
                        text: '取消',
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                      const HSpace(12),
                      AFFilledTextButton.primary(
                        text: '保存',
                        onTap: () {
                          // TODO: call backend to save ACL for this team
                          Navigator.of(ctx).pop();
                          showToastNotification(message: '已保存（示例，仅前端）');
                        },
                      ),
                    ],
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

class _SpaceRow extends StatefulWidget {
  const _SpaceRow({
    required this.space,
    required this.userProfile,
    required this.workspaceId,
    required this.role,
  });

  final ViewPB space;
  final UserProfilePB userProfile;
  final String workspaceId;
  final AFRolePB role;

  @override
  State<_SpaceRow> createState() => _SpaceRowState();
}

class _SpaceRowState extends State<_SpaceRow> {
  late SpacePermission _selectedPermission;
  bool _isUpdating = false;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _selectedPermission = widget.space.spacePermission;
    _checkVisibility();
  }

  Future<void> _checkVisibility() async {
    // For private spaces, only show if current user is in team ACL allowEmails
    try {
      if (widget.space.spacePermission == SpacePermission.private) {
        final userService = UserBackendService(userId: widget.userProfile.id);
        final res = await userService.getTeamACL(widget.space.id);
        res.fold((acl) {
          final allowed = acl.allowEmails.contains(widget.userProfile.email) ||
              acl.allowUserIds.contains(widget.userProfile.id.toInt());
          setState(() {
            _isVisible = allowed;
          });
        }, (err) {
          // if cannot fetch ACL, default to hidden for privacy
          setState(() {
            _isVisible = false;
          });
        });
      } else {
        setState(() {
          _isVisible = true;
        });
      }
    } catch (e) {
      setState(() {
        _isVisible = false;
      });
    }
  }

  String _permissionLabel(SpacePermission p) {
    switch (p) {
      case SpacePermission.publicToAll:
        return '开放式';
      case SpacePermission.closed:
        return '封闭式';
      case SpacePermission.private:
        return '私人';
    }
  }

  int _normalizeCreateTime(Object? createTime) {
    if (createTime == null) return 0;
    if (createTime is Int64) return createTime.toInt();
    if (createTime is int) return createTime;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();
    final name = widget.space.name;
    final createdAt = _normalizeCreateTime(widget.space.createTime);

    String updateTime;
    if (createdAt == 0) {
      updateTime = '未知';
    } else {
      var ms = createdAt;
      if (ms < 1000000000000) {
        ms = ms * 1000;
      }
      final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      updateTime = DateFormat('yyyy-MM-dd').format(date);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(12))
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.groups,
                    size: 16,
                    color: Colors.orange,
                  ),
                ),
                const HSpace(12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FlowyText(
                      name,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    const VSpace(2),
                    FlowyText(
                      '协作区',
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: FlowyText(
              widget.userProfile.name.isNotEmpty
                  ? widget.userProfile.name
                  : widget.userProfile.email,
              fontSize: 14,
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<SpacePermission>(
                    isDense: true,
                    isExpanded: false,
                    value: _selectedPermission,
                    items: [
                      DropdownMenuItem(
                        value: SpacePermission.publicToAll,
                        child: FlowyText(
                            _permissionLabel(SpacePermission.publicToAll),
                            fontSize: 14),
                      ),
                      // DropdownMenuItem(
                      //   value: SpacePermission.closed,
                      //   child: FlowyText(
                      //       _permissionLabel(SpacePermission.closed),
                      //       fontSize: 14),
                      // ),
                      DropdownMenuItem(
                        value: SpacePermission.private,
                        child: FlowyText(
                            _permissionLabel(SpacePermission.private),
                            fontSize: 14),
                      ),
                    ],
                    onChanged: _isUpdating
                        ? null
                        : (newPerm) async {
                            if (newPerm == null) return;
                            setState(() {
                              _isUpdating = true;
                              _selectedPermission = newPerm;
                            });

                            try {
                              context.read<SpaceBloc>().add(
                                    SpaceEvent.update(
                                      space: widget.space,
                                      permission: newPerm,
                                    ),
                                  );
                              // optimistic UI; small delay to improve UX
                              await Future.delayed(
                                  const Duration(milliseconds: 200));
                              showToastNotification(message: '权限已更新');
                            } catch (e) {
                              // revert on error
                              setState(() {
                                _selectedPermission =
                                    widget.space.spacePermission;
                              });
                              Log.error(
                                  'Failed to update space permission: $e');
                              showToastNotification(
                                  message: '更新失败，请重试',
                                  type: ToastificationType.error);
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isUpdating = false;
                                });
                              }
                            }
                          },
                  ),
                ),
                if (_isUpdating) ...[
                  const HSpace(8),
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: FlowyText(
              updateTime,
              fontSize: 14,
            ),
          ),
          Expanded(
            flex: 2,
            child:

            widget.role.canDelete
                //  && widget.space. != widget.userProfile.name // can't delete self
                ? _WorkspaceMoreActionList(viewPB: widget.space)
                : SizedBox(width: 24.0),
            // Align(
            //   alignment: Alignment.centerRight,
            //   child: SizedBox.square(
            //     dimension: 28.0,
            //     child: FlowyButton(
            //       useIntrinsicWidth: true,
            //       margin: EdgeInsets.zero,
            //       text: Center(child: FlowySvg(FlowySvgs.three_dots_s)),
            //       onTap: () => _openSpaceManageDialog(context),
            //     ),
            //   ),
            // ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSpaceManageDialog(BuildContext context) async {
    // Load members who have joined this collab (space) via new API
    final userService = UserBackendService(userId: widget.userProfile.id);
    List<dynamic> members = [];
    try {
      final res = await userService.getCollabMembers(widget.workspaceId, widget.space.id);
      res.fold((list) {
        members = list;
      }, (e) {
        Log.error('Failed to load collab members for manage dialog: $e');
      });
    } catch (e) {
      Log.error('Exception loading collab members for manage dialog: $e');
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        final TextEditingController _searchController = TextEditingController();
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 760,
            height: 560,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FlowyText('协作区：${widget.space.name}',
                              fontSize: 16, fontWeight: FontWeight.w600),
                          const VSpace(6),
                          FlowyText('管理该协作区的访问权限',
                              fontSize: 12, color: Theme.of(ctx).hintColor),
                        ],
                      ),
                      SizedBox(
                        width: 72,
                        child: FlowyButton(
                          text: const FlowyText.regular('关闭'),
                          onTap: () => Navigator.of(ctx).pop(),
                          margin: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const VSpace(12),
                  const Divider(),
                  const VSpace(12),
                  // Search + add member row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索成员',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (_) {
                            (ctx as Element).markNeedsBuild();
                          },
                        ),
                      ),
                      const HSpace(12),
                      SizedBox(
                        width: 140,
                        height: 36,
                        child: FlowyButton(
                          text: const FlowyText.regular('添加成员', fontSize: 12),
                          onTap: () async {
                            // Reuse invite flow: display searchable invite dialog.

                            // Reuse full invite dialog logic (searchable user selection).
                            final repo = RustShareWithUserRepositoryImpl();
                            List<SharedUser> searchResults = [];
                            List<SharedUser> selectedUsers = [];
                            bool isSearching = false;
                            bool hasSearched = false;

                            await showDialog(
                              context: ctx,
                              builder: (dctx) {
                                return StatefulBuilder(
                                  builder: (dctx2, setStateDialog) {
                                    Future<void> performSearch(String q) async {
                                      final normalized = q
                                          .replaceAll(
                                              RegExp(
                                                  r'[\u200B-\u200D\uFEFF\u200E\u200F\u00A0]'),
                                              '')
                                          .trim();
                                      hasSearched = true;
                                      if (normalized.isEmpty) {
                                        setStateDialog(() {
                                          searchResults = [];
                                        });
                                        return;
                                      }
                                      setStateDialog(() {
                                        isSearching = true;
                                      });
                                      FlowyResult<SharedUsers, FlowyError> res =
                                          await repo.searchUsers(
                                              query: normalized);
                                      List<SharedUser> users = [];
                                      res.fold(
                                          (u) => users = u, (e) => users = []);

                                      if (users.isEmpty) {
                                        final digitsOnly = normalized
                                            .replaceAll(RegExp(r'\D'), '');
                                        final looksLikePhone =
                                            digitsOnly.isNotEmpty &&
                                                digitsOnly.length >= 6 &&
                                                digitsOnly.length <= 15;
                                        if (looksLikePhone) {
                                          final variants = <String>{};
                                          variants.add(digitsOnly);
                                          variants.add(digitsOnly.replaceFirst(
                                              RegExp(r'^0+'), ''));
                                          if (!digitsOnly.startsWith('86') &&
                                              digitsOnly.length == 11) {
                                            variants.add('86$digitsOnly');
                                            variants.add('+86$digitsOnly');
                                          }
                                          if (!digitsOnly.startsWith('+')) {
                                            variants.add('+$digitsOnly');
                                          }
                                          for (final v in variants) {
                                            if (v.trim().isEmpty) continue;
                                            final r2 = await repo.searchUsers(
                                                query: v);
                                            r2.fold((u2) {
                                              if (u2.isNotEmpty) {
                                                users = u2;
                                              }
                                            }, (_) {});
                                            if (users.isNotEmpty) break;
                                          }
                                        }
                                      }

                                      setStateDialog(() {
                                        searchResults = users;
                                        isSearching = false;
                                      });
                                    }

                                    void toggleSelectUser(SharedUser user) {
                                      final exists = selectedUsers.indexWhere(
                                              (u) => u.email == user.email) >=
                                          0;
                                      setStateDialog(() {
                                        if (exists) {
                                          selectedUsers.removeWhere(
                                              (u) => u.email == user.email);
                                        } else {
                                          selectedUsers.add(user);
                                        }
                                      });
                                    }

                                    AFRolePB dialogSelectedRole =
                                        AFRolePB.Member;
                                    final TextEditingController
                                        searchController = TextEditingController();

                                    return Dialog(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0)),
                                      child: SizedBox(
                                        width: 520,
                                        child: Padding(
                                          padding: const EdgeInsets.all(20.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('添加成员',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: TextField(
                                                      controller:
                                                          searchController,
                                                      decoration:
                                                          const InputDecoration(
                                                              hintText:
                                                                  '搜索邮箱或手机号'),
                                                      autofocus: true,
                                                      onSubmitted: (q) =>
                                                          performSearch(q),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  IconButton(
                                                    tooltip: '搜索',
                                                    icon: isSearching
                                                        ? const CircularProgressIndicator(
                                                            strokeWidth: 2)
                                                        : const Icon(
                                                            Icons.search),
                                                    onPressed: () async {
                                                      await performSearch(
                                                          searchController
                                                              .text);
                                                    },
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              if (selectedUsers.isNotEmpty) ...[
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children:
                                                      selectedUsers.map((u) {
                                                    return Chip(
                                                      label: Text(
                                                          u.name.isNotEmpty
                                                              ? u.name
                                                              : u.email),
                                                      onDeleted: () {
                                                        setStateDialog(() {
                                                          selectedUsers
                                                              .removeWhere(
                                                                  (s) =>
                                                                      s.email ==
                                                                      u.email);
                                                        });
                                                      },
                                                    );
                                                  }).toList(),
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                              if (searchResults.isNotEmpty)
                                                ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                          maxHeight: 220),
                                                  child: ListView.separated(
                                                    shrinkWrap: true,
                                                    itemCount:
                                                        searchResults.length,
                                                    separatorBuilder: (_, __) =>
                                                        const Divider(
                                                            height: 1),
                                                    itemBuilder:
                                                        (context, idx) {
                                                      final user =
                                                          searchResults[idx];
                                                      final already =
                                                          selectedUsers.any(
                                                              (u) =>
                                                                  u.email ==
                                                                  user.email);
                                                      return ListTile(
                                                        leading: CircleAvatar(
                                                            child: Text(user
                                                                    .name
                                                                    .isNotEmpty
                                                                ? user.name[0]
                                                                    .toUpperCase()
                                                                : '?')),
                                                        title: Text(
                                                            user.name.isNotEmpty
                                                                ? user.name
                                                                : user.email),
                                                        subtitle:
                                                            Text(user.email),
                                                        trailing: Icon(already
                                                            ? Icons.check_box
                                                            : Icons
                                                                .check_box_outline_blank),
                                                        onTap: () {
                                                          toggleSelectUser(
                                                              user);
                                                        },
                                                      );
                                                    },
                                                  ),
                                                )
                                              else if (isSearching)
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 12.0),
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator()),
                                                )
                                              else if (hasSearched &&
                                                  searchResults.isEmpty)
                                                Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 12.0),
                                                  child: Center(
                                                      child: Text('未找到用户',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall)),
                                                )
                                              else
                                                const SizedBox.shrink(),
                                              const SizedBox(height: 12),
                                              Text('权限级别',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .cardColor,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child:
                                                    PopupMenuButton<AFRolePB>(
                                                  padding: EdgeInsets.zero,
                                                  color: Theme.of(context)
                                                      .cardColor,
                                                  onSelected: (v) {
                                                    dialogSelectedRole = v;
                                                    setStateDialog(() {});
                                                  },
                                                  itemBuilder: (ctx2) => [
                                                    const PopupMenuItem(
                                                        value: AFRolePB.Owner,
                                                        child: Text('工作空间所有者')),
                                                    const PopupMenuItem(
                                                        value: AFRolePB.Member,
                                                        child: Text('成员')),
                                                    const PopupMenuItem(
                                                        value: AFRolePB.Guest,
                                                        child: Text('受限成员')),
                                                  ],
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                          dialogSelectedRole ==
                                                                  AFRolePB.Owner
                                                              ? '工作空间所有者'
                                                              : dialogSelectedRole ==
                                                                      AFRolePB
                                                                          .Guest
                                                                  ? '受限成员'
                                                                  : '成员',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium),
                                                      const SizedBox(width: 8),
                                                      const Icon(Icons
                                                          .arrow_drop_down),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 18),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(dctx2)
                                                              .pop(),
                                                      child: const Text('取消')),
                                                  const SizedBox(width: 12),
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      // If user didn't select from results but typed, include typed as single target
                                                      // For simplicity, use selectedUsers only here.
                                                      if (selectedUsers
                                                          .isEmpty) {
                                                        showToastNotification(
                                                            type:
                                                                ToastificationType
                                                                    .error,
                                                            message:
                                                                '请先选择要邀请的用户');
                                                        return;
                                                      }
                                                      bool allOk = true;
                                                      for (final u
                                                          in selectedUsers) {
                                                        final inviteRes = await userService
                                                            .inviteWorkspaceMember(
                                                                widget
                                                                    .workspaceId,
                                                                u.email,
                                                                role:
                                                                    dialogSelectedRole);
                                                        inviteRes.fold(
                                                            (_) async {
                                                          // On success, try to append invitee email to team ACL (best-effort)
                                                          try {
                                                            TeamACLPB? current;
                                                            final aclRes = await userService.getTeamACL(widget.space.id);
                                                            aclRes.fold((acl) {
                                                              current = acl;
                                                            }, (e) {
                                                              current = null;
                                                            });
                                                            final List<String> existing =
                                                                current?.allowEmails.toList() ?? [];
                                                            if (!existing.contains(u.email)) {
                                                              final newAcl = TeamACLPB(
                                                                  teamId: widget.space.id,
                                                                  allowUserIds: [],
                                                                  allowEmails: [
                                                                    ...existing,
                                                                    u.email
                                                                  ]);
                                                              final saveRes = await userService.updateTeamACL(newAcl);
                                                              saveRes.fold((_) {
                                                                // noop
                                                              }, (e) {
                                                                Log.error('Failed to update team ACL after invite: $e');
                                                              });
                                                            }
                                                          } catch (e) {
                                                            Log.error('Exception updating team ACL after invite: $e');
                                                          }
                                                        }, (err) {
                                                          allOk = false;
                                                          showDialog(
                                                              context: dctx2,
                                                        builder: (_) =>
                                                                  NavigatorOkCancelDialog(
                                                                      message: err.msg));
                                                        });
                                                      }
                                                      if (allOk) {
                                                        showToastNotification(
                                                            message: '邀请已发送');
                                                        // refresh members list
                                                        try {
                                                          final updated =
                                                              await userService
                                                                  .getCollabMembers(
                                                                      widget
                                                                          .workspaceId,
                                                                      widget.space.id);
                                                          updated.fold((s) {
                                                            members = s;
                                                            (ctx as Element).markNeedsBuild();
                                                          }, (e) {
                                                            Log.error('Failed to refresh collab members after invite: $e');
                                                          });
                                                        } catch (_) {}
                                                        Navigator.of(dctx2)
                                                            .pop();
                                                      }
                                                    },
                                                    child: const Text('邀请'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const VSpace(12),
                  // Members list header row (only Name + Role)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 6,
                            child: FlowyText('名称',
                                fontSize: 12, color: Theme.of(ctx).hintColor)),
                        Expanded(
                            flex: 4,
                            child: FlowyText('角色',
                                fontSize: 12, color: Theme.of(ctx).hintColor)),
                      ],
                    ),
                  ),
                  const Divider(),
                  const VSpace(8),
                  // Members list (show members who have joined this collab)
                  Expanded(
                        child: members.isEmpty
                        ? Center(child: FlowyText('无法加载成员或无成员', fontSize: 14))
                        : ListView.builder(
                            itemCount: members.length,
                            itemBuilder: (i, idx) {
                              final m = members[idx];
                              final email = (m.email ?? '').toString();
                              // filter by search
                              final q =
                                  _searchController.text.trim().toLowerCase();
                              if (q.isNotEmpty &&
                                  !(m.name.toLowerCase().contains(q) ||
                                      email.toLowerCase().contains(q))) {
                                return const SizedBox.shrink();
                              }
                              final bool isOwner = (m.permissionId ?? 0) == 4;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                  children: [
                                    // Name column
                                    Expanded(
                                      flex: 6,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor:
                                                Colors.grey.shade800,
                                            child: Text(
                                              m.name.isNotEmpty
                                                  ? m.name[0]
                                                  : email.isNotEmpty
                                                      ? email[0]
                                                      : '?',
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                          const HSpace(12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                FlowyText(
                                                    m.name.isNotEmpty
                                                        ? m.name
                                                        : email,
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w500),
                                                const VSpace(2),
                                                FlowyText(email,
                                                    fontSize: 12,
                                                    color: Theme.of(ctx)
                                                        .hintColor),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Role column (styled popover similar to "访问权限")
                                    Expanded(
                                      flex: 4,
                                      child: Builder(builder: (roleCtx) {
                                        final int currentUid = widget.userProfile.id.toInt();
                                        final ownersCount = members
                                            .where((mm) => (mm.permissionId ?? 0) == 4)
                                            .length;
                                        final currentIsOwner = members.any((mm) =>
                                            mm.uid == currentUid && (mm.permissionId ?? 0) == 4);

                                        final popoverController = AFPopoverController();

                                        Widget buildMenu() {
                                          final List<Widget> items = [];
                                          final canChangeRole =
                                              currentIsOwner && m.uid != currentUid;

                                          items.add(IgnorePointer(
                                            ignoring: !canChangeRole,
                                            child: AFTextMenuItem(
                                              title: '团队协作区所有者',
                                              titleColor: canChangeRole
                                                  ? null
                                                  : Theme.of(ctx).hintColor,
                                              onTap: () {
                                                userService
                                                    .updateCollabMemberPermission(
                                                        widget.workspaceId,
                                                        widget.space.id,
                                                        m.uid,
                                                        4)
                                                    .then((res) {
                                                  res.fold((_) {
                                                    m.permissionId = 4;
                                                    try {
                                                      (ctx as Element)
                                                          .markNeedsBuild();
                                                    } catch (_) {}
                                                  }, (e) {
                                                    Log.error(
                                                        'Failed to set owner: $e');
                                                  });
                                                }).whenComplete(
                                                    () => popoverController.hide());
                                              },
                                            ),
                                          ));

                                          items.add(IgnorePointer(
                                            ignoring: !canChangeRole,
                                            child: AFTextMenuItem(
                                              title: '团队协作区成员',
                                              titleColor: canChangeRole
                                                  ? null
                                                  : Theme.of(ctx).hintColor,
                                              onTap: () {
                                                userService
                                                    .updateCollabMemberPermission(
                                                        widget.workspaceId,
                                                        widget.space.id,
                                                        m.uid,
                                                        3)
                                                    .then((res) {
                                                  res.fold((_) {
                                                    m.permissionId = 3;
                                                    try {
                                                      (ctx as Element)
                                                          .markNeedsBuild();
                                                    } catch (_) {}
                                                  }, (e) {
                                                    Log.error(
                                                        'Failed to set member: $e');
                                                  });
                                                }).whenComplete(
                                                    () => popoverController.hide());
                                              },
                                            ),
                                          ));

                                          items.add(AFDivider());

                                          bool removeEnabled = false;
                                          if (currentIsOwner) {
                                            if ((m.permissionId ?? 0) == 4 &&
                                                ownersCount == 1 &&
                                                m.uid == currentUid) {
                                              removeEnabled = false;
                                            } else {
                                              removeEnabled = true;
                                            }
                                          } else {
                                            removeEnabled = (m.uid == currentUid);
                                          }

                                          items.add(IgnorePointer(
                                            ignoring: !removeEnabled,
                                            child: AFTextMenuItem(
                                              title: '移除',
                                              titleColor: removeEnabled
                                                  ? Theme.of(ctx).colorScheme.error
                                                  : Theme.of(ctx).hintColor,
                                              onTap: () {
                                                showDialog<bool>(
                                                        context: roleCtx,
                                                        builder: (_) =>
                                                            NavigatorOkCancelDialog(
                                                                message:
                                                                    '确认要移除该成员吗？'))
                                                    .then((confirm) {
                                                  if (confirm != true) {
                                                    popoverController.hide();
                                                    return;
                                                  }
                                                  userService
                                                      .removeCollabMember(
                                                          widget.workspaceId,
                                                          widget.space.id,
                                                          m.uid)
                                                      .then((res) {
                                                    res.fold((_) {
                                                      members.removeAt(idx);
                                                      try {
                                                        (ctx as Element)
                                                            .markNeedsBuild();
                                                      } catch (_) {}
                                                    }, (e) {
                                                      Log.error(
                                                          'Failed to remove collab member: $e');
                                                    });
                                                  }).whenComplete(
                                                      () => popoverController.hide());
                                                });
                                              },
                                            ),
                                          ));

                                          return AFMenu(children: items, width: 220);
                                        }

                                        return AFPopover(
                                          controller: popoverController,
                                          popover: (_) => buildMenu(),
                                          child: AFGhostButton.normal(
                                            onTap: () {
                                              popoverController.show();
                                            },
                                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            builder: (bCtx, isHovering, disabled) {
                                              return SizedBox(
                                                width: double.infinity,
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: FlowyText.regular(
                                                        isOwner ? '团队协作区所有者' : '团队协作区成员',
                                                      ),
                                                    ),
                                                    FlowySvg(
                                                      FlowySvgs.arrow_down_s,
                                                      color: Theme.of(ctx).hintColor,
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const VSpace(12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedRoundedButton(
                        text: '取消',
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                      const HSpace(12),
                      AFFilledTextButton.primary(
                        text: '保存',
                        onTap: () async {
                          // Build new ACL from current members list
                          final newAcl = TeamACLPB(
                            teamId: widget.space.id,
                            allowUserIds: [], // WorkspaceMemberPB doesn't have id field, use emails only
                            allowEmails: members.where((m) => (m.email ?? '').toString().isNotEmpty).map((m) => m.email as String).toList(),
                          );

                          try {
                            final saveRes =
                                await userService.updateTeamACL(newAcl);
                            saveRes.fold((_) {
                              Navigator.of(ctx).pop();
                              showToastNotification(message: '团队协作区权限已保存');
                            }, (e) {
                              Log.error('Failed to save team ACL: $e');
                              showToastNotification(message: '保存失败：$e');
                            });
                          } catch (e) {
                            Log.error('Exception saving team ACL: $e');
                            showToastNotification(message: '保存失败：$e');
                          }
                        },
                      ),
                    ],
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


enum _WorkspaceMoreAction {
  delete,
}


class _WorkspaceMoreActionList extends StatelessWidget {
  const _WorkspaceMoreActionList({
    required this.viewPB,
  });

  final ViewPB viewPB;

  @override
  Widget build(BuildContext context) {
    return PopoverActionList<_WorkspaceMoreActionWrapper>(
      asBarrier: true,
      direction: PopoverDirection.bottomWithCenterAligned,
      actions: _WorkspaceMoreAction.values
          .map((e) => _WorkspaceMoreActionWrapper(e, viewPB))
          .toList(),
      buildChild: (controller) {
        return FlowyButton(
          useIntrinsicWidth: true,
          text: const FlowySvg(
            FlowySvgs.three_dots_s,
          ),
          onTap: () {
            controller.show();
          },
        );
      },
      onSelected: (action, controller) {
        switch (action.inner) {
          case _WorkspaceMoreAction.delete:
            showCancelAndConfirmDialog(
              context: context,
              title: LocaleKeys.settings_workspacePage_deleteWorkspacePrompt_title.tr(),
              description: LocaleKeys
                  .settings_workspacePage_deleteWorkspacePrompt_content
                  .tr(),
              confirmLabel: LocaleKeys.button_yes.tr(),
              onConfirm: (_) => context.read<SpaceBloc>().add(
                SpaceEvent.delete(viewPB)
              ),
            );
            break;
        }
        controller.close();
      },
    );
  }
}

class _WorkspaceMoreActionWrapper extends ActionCell {
  _WorkspaceMoreActionWrapper(this.inner, this.viewPB);

  final _WorkspaceMoreAction inner;
  final ViewPB viewPB;

  @override
  String get name {
    switch (inner) {
      case _WorkspaceMoreAction.delete:
        return LocaleKeys.settings_workspacePage_deleteWorkspacePrompt_title.tr();
    }
  }
}