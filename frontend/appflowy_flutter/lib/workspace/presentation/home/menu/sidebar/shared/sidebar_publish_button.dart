import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../application/tabs/tabs_bloc.dart';
import '../../../../../application/view/view_service.dart';
import '../../../../../application/view/view_publish_service.dart';
import '../../../../widgets/dialogs.dart';

class SidebarPublishButton extends StatefulWidget {
  const SidebarPublishButton({super.key});

  @override
  State<SidebarPublishButton> createState() => _SidebarPublishButtonState();
}

/// 用于保存发布项的扩展信息
class PublishedItemData {
  final String publishedViewId;  // 原始发布文档的viewId
  final String viewId;           // 当前用户可以访问的viewId（接收后是新viewId）
  final String workspaceId;      // 工作区ID
  final String name;              // 文档名称
  final String publishName;       // 发布名称
  final String? publisherEmail;   // 发布者邮箱
  final DateTime publishedAt;   // 发布时间
  final bool isReceived;          // 是否是接收的发布
  final bool isReadonly;         // 是否只读

  PublishedItemData({
    required this.publishedViewId,
    required this.viewId,
    required this.workspaceId,
    required this.name,
    required this.publishName,
    this.publisherEmail,
    required this.publishedAt,
    required this.isReceived,
    required this.isReadonly,
  });
}

class _SidebarPublishButtonState extends State<SidebarPublishButton> {
  bool _isExpanded = false;
  List<PublishedItemData> _myPublishedItems = const [];
  List<PublishedItemData> _receivedPublishedItems = const [];
  bool _loading = false;
  bool _needsRefresh = true;
  String _workspaceId = '';
  void _onPublishPing() {
    if (!mounted) return;
    if (_isExpanded && !_loading) {
      _load();
    } else {
      _needsRefresh = true;
    }
  }

  @override
  void initState() {
    super.initState();
    PublishRefresh.notifier.addListener(_onPublishPing);
    _workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
  }

  @override
  void dispose() {
    PublishRefresh.notifier.removeListener(_onPublishPing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
      listenWhen: (previous, current) =>
          previous.currentWorkspace?.workspaceId !=
          current.currentWorkspace?.workspaceId,
      listener: (context, state) {
        _handleWorkspaceChanged(state.currentWorkspace?.workspaceId);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(
              height: 44,
              child: Stack(
                children: [
                  AFGhostIconTextButton.primary(
                    text: '发布',
                    mainAxisAlignment: MainAxisAlignment.start,
                    size: AFButtonSize.l,
                    onTap: () async {
                      setState(() => _isExpanded = !_isExpanded);
                      if (_isExpanded && !_loading && _needsRefresh) {
                        await _load();
                      }
                    },
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    borderRadius: theme.borderRadius.s,
                    iconBuilder: (context, isHover, disabled) => SizedBox.shrink(),
                  ),
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 16,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 4.0),
              child: _buildPublishedList(context),
            ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // 刷新发布服务状态
      await ViewPublishService().refreshPublishedViews();

      List<PublishedItemData> myPublishedItems = [];
      List<PublishedItemData> receivedPublishedItems = [];
      bool globalApiSuccess = false;

      // 优先使用全局发布列表 API（包含所有用户发布的笔记）
      // API返回的数据包含 is_received 标记，表示当前用户是否已接收
      try {
        final result = await FolderEventListAllPublishedViews().send();
        globalApiSuccess = result.fold((s) {
          for (final item in s.items) {
            // publishedAt 是 Int64 类型，需要转换为 int
            final publishedAtMs = item.publishedAt.toInt();
            final itemData = PublishedItemData(
              publishedViewId: item.publishedViewId,
              viewId: item.viewId,
              workspaceId: item.workspaceId,
              name: item.name.isNotEmpty ? item.name : item.publishName,
              publishName: item.publishName,
              publisherEmail: item.publisherEmail,
              publishedAt: DateTime.fromMillisecondsSinceEpoch(publishedAtMs),
              isReceived: item.isReceived,
              isReadonly: item.isReadonly,
            );

            // 根据 is_received 字段分别添加到对应的列表
            if (item.isReceived) {
              receivedPublishedItems.add(itemData);
            } else {
              myPublishedItems.add(itemData);
            }
          }
          return true;
        }, (f) {
          Log.error('ListAllPublishedViews API error: $f');
          return false;
        });
      } catch (e) {
        Log.error('ListAllPublishedViews exception: $e');
      }

      // 如果全局 API 失败，使用 workspace 级别的 API 作为备选
      // workspace 级别的 API 只返回当前用户发布的文档
      if (!globalApiSuccess) {
        Log.info('Fallback to ListPublishedViews (workspace-scoped)');
        try {
          final result = await FolderEventListPublishedViews().send();
          result.fold((s) {
            for (final item in s.items) {
              // publishTimestampSec 是 Int64 类型，需要转换为 int
              final publishedAtMs = item.info.publishTimestampSec.toInt();
              final itemData = PublishedItemData(
                publishedViewId: item.info.viewId,
                viewId: item.view.viewId,
                workspaceId: _workspaceId,
                name: item.view.name.isNotEmpty ? item.view.name : item.info.publishName,
                publishName: item.info.publishName,
                publisherEmail: item.info.publisherEmail,
                publishedAt: DateTime.fromMillisecondsSinceEpoch(publishedAtMs),
                isReceived: false,
                isReadonly: false,
              );
              myPublishedItems.add(itemData);
            }
          }, (f) {
            Log.error('ListPublishedViews fallback error: $f');
          });
        } catch (e) {
          Log.error('ListPublishedViews fallback exception: $e');
        }
      }

      // 按发布时间倒序排序
      myPublishedItems.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      receivedPublishedItems.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      if (!mounted) return;
      setState(() {
        _myPublishedItems = myPublishedItems;
        _receivedPublishedItems = receivedPublishedItems;
        _loading = false;
        _needsRefresh = false;
      });
    } catch (e, st) {
      Log.error('load published views unexpected error: $e', e, st);
      if (!mounted) return;
      setState(() {
        _myPublishedItems = [];
        _receivedPublishedItems = [];
        _loading = false;
        _needsRefresh = false;
      });
    }
  }

  Widget _buildPublishedList(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    // 合并两个列表
    final allItems = [..._myPublishedItems, ..._receivedPublishedItems];
    
    if (allItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 8.0, top: 6.0, bottom: 6.0),
        child: FlowyText.small(
          '暂无发布',
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 显示"我的发布"部分
        if (_myPublishedItems.isNotEmpty) ...[
          _buildSectionHeader(context, '我的发布', Icons.public),
          ..._myPublishedItems.map((item) => _buildPublishedItem(context, item)),
        ],
        // 显示"我接收的发布"部分
        if (_receivedPublishedItems.isNotEmpty) ...[
          if (_myPublishedItems.isNotEmpty)
            const SizedBox(height: 8),
          _buildSectionHeader(context, '我接收的发布', Icons.inbox),
          ..._receivedPublishedItems.map((item) => _buildReceivedItem(context, item)),
        ],
      ],
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 8, top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 通用的打开发布文档逻辑
  /// 1. 先尝试 getView（本地 Folder 中查找）
  /// 2. 如果找不到，说明是其他用户的文档，需要先调用 receive API 接收
  /// 3. 接收成功后，使用接收后的 viewId 打开
  Future<void> _openPublishedView(BuildContext context, PublishedItemData item) async {
    try {
      final viewOrErr = await ViewBackendService.getView(item.viewId);
      final opened = viewOrErr.fold(
        (view) {
          context.read<TabsBloc>().openPlugin(view);
          return true;
        },
        (e) => false,
      );
      if (opened) return;

      Log.info('[PublishButton] getView 失败，尝试接收发布文档: publishedViewId=${item.publishedViewId}');

      final result = await ViewPublishService.receivePublishedCollab(
        publishedViewId: item.publishedViewId,
        workspaceId: _workspaceId,
      );

      if (result.success) {
        Log.info('[PublishButton] 接收成功: receivedViewId=${result.receivedViewId}');
        final minimalView = ViewPB()
          ..id = result.receivedViewId
          ..name = item.name
          ..layout = ViewLayoutPB.Document
          ..isLocked = result.isReadonly;
        if (context.mounted) {
          context.read<TabsBloc>().openPlugin(minimalView);
          PublishRefresh.ping();
        }
      } else {
        Log.error('[PublishButton] 接收失败: ${result.error}');
        showToastNotification(
          message: '打开发布笔记失败: ${result.error}',
          type: ToastificationType.error,
        );
      }
    } catch (e, stackTrace) {
      Log.error('[PublishButton] 打开发布文档出错: $e', stackTrace);
      showToastNotification(
        message: '打开发布笔记失败: $e',
        type: ToastificationType.error,
      );
    }
  }

  /// 构建"我的发布"列表项
  Widget _buildPublishedItem(BuildContext context, PublishedItemData item) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 24, right: 8),
      title: FlowyText.regular(
        item.name,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.publishName.isNotEmpty
          ? FlowyText.small(
              item.publishName,
              color: Theme.of(context).hintColor,
            )
          : null,
      trailing: item.publisherEmail != null
          ? Text(
              item.publisherEmail!,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).hintColor,
              ),
            )
          : null,
      onTap: () => _openPublishedView(context, item),
    );
  }

  /// 构建"我接收的发布"列表项
  Widget _buildReceivedItem(BuildContext context, PublishedItemData item) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 24, right: 8),
      title: Row(
        children: [
          Expanded(
            child: FlowyText.regular(
              item.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.isReadonly)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '只读',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
        ],
      ),
      subtitle: item.publishName.isNotEmpty
          ? FlowyText.small(
              '来自: ${item.publisherEmail ?? "未知"}',
              color: Theme.of(context).hintColor,
            )
          : null,
      onTap: () => _openPublishedView(context, item),
    );
  }

  void _handleWorkspaceChanged(String? workspaceId) {
    final newWorkspaceId = workspaceId ?? '';
    if (newWorkspaceId.isEmpty || newWorkspaceId == _workspaceId) {
      return;
    }
    setState(() {
      _workspaceId = newWorkspaceId;
      _myPublishedItems = const [];
      _receivedPublishedItems = const [];
      _isExpanded = false;
      _loading = false;
      _needsRefresh = true;
    });
  }
}
