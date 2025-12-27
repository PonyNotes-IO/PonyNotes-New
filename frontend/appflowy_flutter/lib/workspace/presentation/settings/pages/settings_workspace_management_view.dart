import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';


class SettingsWorkspaceManagementView extends StatefulWidget {
  const SettingsWorkspaceManagementView({
    super.key,
    required this.userProfile,
  });

  final UserProfilePB userProfile;

  @override
  State<SettingsWorkspaceManagementView> createState() => _SettingsWorkspaceManagementViewState();
}

class _SettingsWorkspaceManagementViewState extends State<SettingsWorkspaceManagementView> {
  bool _onlyOwnerCanCreateTeamWorkspace = true;

  @override
  Widget build(BuildContext context) {
    return SettingsBody(
      title: '空间管理',
      description: '管理您的工作空间设置和配置',
      children: [
        // 创建团队协作区权限设置
        _buildCreatePermissionSection(),
        const VSpace(24),
        // 团队协作区列表
        _buildTeamWorkspaceList(),
      ],
    );
  }

  Widget _buildCreatePermissionSection() {
    return SettingsCategory(
      title: '仅工作空间所有者可以创建团队协作区',
      description: '仅允许工作空间所有者创建团队协作区',
      actions: [
        Toggle(
          value: _onlyOwnerCanCreateTeamWorkspace,
          onChanged: (value) {
            setState(() {
              _onlyOwnerCanCreateTeamWorkspace = value;
            });
          },
        ),
      ],
      children: const [],
    );
  }

  Widget _buildTeamWorkspaceList() {
    return SettingsCategory(
      title: '团队协作区',
      children: [
        _buildTeamWorkspaceTable(),
      ],
    );
  }

  Widget _buildTeamWorkspaceTable() {
    return BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
      builder: (context, workspaceState) {
        // 获取所有协作区（Server 类型的工作空间）
        final collaborativeWorkspaces = workspaceState.workspaces
            .where((workspace) => workspace.workspaceType == WorkspaceTypePB.ServerW)
            .toList();

        if (collaborativeWorkspaces.isEmpty) {
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
            // 表格内容 - 动态生成
            ...collaborativeWorkspaces.map((workspace) {
              return _TeamWorkspaceRow(
                workspace: workspace,
                userProfile: widget.userProfile,
              );
            }).toList(),
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
            flex: 3,
            child: FlowyText(
              '团队协作区',
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              '所有者',
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              '访问权限',
              fontSize: 12,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                FlowyText(
                  '更新时间',
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w500,
                ),
                const HSpace(4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: Theme.of(context).hintColor,
                ),
              ],
            ),
          ),
        ],
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
            _ownerName = owner?.name.isNotEmpty == true
                ? owner!.name
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
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
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
          Expanded(
            flex: 2,
            child: FlowyText(
              updateTime,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}



