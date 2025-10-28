import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/shared/share/publish_tab.dart';
import 'package:appflowy/workspace/application/view/view_publish_service.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ShareSettingsDialog extends StatefulWidget {
  const ShareSettingsDialog({
    super.key,
    required this.viewName,
    required this.workspaceId,
    required this.pageId,
    required this.workspaceName,
    required this.workspaceIcon,
    required this.isInProPlan,
  });

  final String viewName;
  final String workspaceId;
  final String pageId;
  final String workspaceName;
  final String workspaceIcon;
  final bool isInProPlan;

  @override
  State<ShareSettingsDialog> createState() => _ShareSettingsDialogState();
}

class _ShareSettingsDialogState extends State<ShareSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          minHeight: 400,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            _buildTabBar(context),
            Flexible(
              child: _buildTabContent(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          // 帮助图标
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.help_outline,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Text(
              '共享设置',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          // 关闭按钮
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.close,
                size: 20,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(4), // 添加内边距，让TabBar比背景小
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.black87,
        unselectedLabelColor: Colors.grey[600],
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        tabs: const [
          Tab(text: '共享'),
          Tab(text: '发布'),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildShareTab(context),
        _buildPublishTab(context),
      ],
    );
  }

  Widget _buildShareTab(BuildContext context) {
    return BlocBuilder<ShareTabBloc, ShareTabState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 搜索输入框
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索邀请成员、电子邮箱、群组...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 当前用户信息
              _buildCurrentUserInfo(context),
              const SizedBox(height: 20),

              // 通用访问权限
              _buildGeneralAccessSection(context),
              const SizedBox(height: 20),

              // 发送邀请按钮
              _buildSendInvitationButton(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentUserInfo(BuildContext context) {
    // 模拟用户列表数据
    final users = [
      {'name': 'qin (你)', 'email': 'qin@example.com', 'permission': '全部权限', 'avatar': '周', 'isOwner': true},
      {'name': '张三', 'email': 'zhangsan@example.com', 'permission': '可编辑', 'avatar': '张', 'isOwner': false},
      {'name': '李四', 'email': 'lisi@example.com', 'permission': '只读', 'avatar': '李', 'isOwner': false},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '已邀请用户',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ...users.map((user) => _buildUserItem(context, user)).toList(),
      ],
    );
  }

  Widget _buildUserItem(BuildContext context, Map<String, dynamic> user) {
    final isOwner = user['isOwner'] as bool;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // 用户头像
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                user['avatar'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 用户信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user['permission'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // 更多选项（只有非所有者才显示）
          if (!isOwner)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_horiz,
                size: 20,
                color: Colors.grey[600],
              ),
              onSelected: (value) {
                if (value == 'remove') {
                  _removeUser(context, user['email'] as String);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.remove_circle_outline, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('取消邀请', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            )
          else
            // 所有者显示锁定图标
            Icon(
              Icons.lock,
              size: 20,
              color: Colors.grey[400],
            ),
        ],
      ),
    );
  }

  void _removeUser(BuildContext context, String email) {
    // 显示确认对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消邀请'),
        content: Text('确定要取消对 $email 的邀请吗？取消后该用户将无法访问此笔记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: 实现取消邀请的逻辑
              _performRemoveUser(email);
            },
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performRemoveUser(String email) {
    // TODO: 实现取消邀请的具体逻辑
    // 这里应该调用相应的 API 来取消用户访问权限
    print('取消用户 $email 的访问权限');
  }

  Widget _buildGeneralAccessSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '通用访问权限',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '仅限受邀者访问',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Colors.grey[600],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSendInvitationButton(BuildContext context) {
    return BlocBuilder<ShareTabBloc, ShareTabState>(
      builder: (context, state) {
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: state.isLoading ? null : () {
              _sendInvitation(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '发送邀请',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        );
      },
    );
  }

  void _sendInvitation(BuildContext context) async {
    try {
      // 模拟邀请用户（这里可以添加实际的用户选择逻辑）
      final emails = ['user1@example.com', 'user2@example.com'];
      
      // 发送邀请事件
      context.read<ShareTabBloc>().add(
        ShareTabEvent.inviteUsers(
          emails: emails,
          accessLevel: ShareAccessLevel.readAndWrite,
        ),
      );
      
      // 等待分享操作完成
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 刷新发布服务状态，标记当前笔记为已发布
      ViewPublishService().markViewAsPublished(widget.pageId);
      
      // 通知发布列表刷新
      PublishRefresh.ping();
      
      // 显示成功提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('邀请已发送，笔记已标记为分享'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // 关闭对话框
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 显示错误提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送邀请失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildPublishTab(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: PublishTab(
        viewName: widget.viewName,
      ),
    );
  }

}
