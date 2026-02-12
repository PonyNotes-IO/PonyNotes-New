import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_publish_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';

import '../../application/view/view_service.dart';
import '../widgets/dialogs.dart';

/// 发布文档列表项
class PublishedItem {
  final String publishedViewId;
  final String viewId;
  final String workspaceId;
  final String name;
  final String publishName;
  final String? publisherEmail;
  final DateTime publishedAt;
  final bool isReceived;
  final bool isReadonly;

  PublishedItem({
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

class PublishPanel extends StatefulWidget {
  const PublishPanel({super.key});

  @override
  State<PublishPanel> createState() => _PublishPanelState();
}

class _PublishPanelState extends State<PublishPanel> {
  List<PublishedItem> _items = [];
  bool _loading = true;
  String? _error;
  
  void _onPublishPing() {
    if (!mounted) return;
    if (!_loading) {
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    PublishRefresh.notifier.addListener(_onPublishPing);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      // 刷新发布服务状态
      await ViewPublishService().refreshPublishedViews();
      
      // 使用新的全局发布列表API
      final result = await FolderEventListAllPublishedViews().send();
      
      setState(() {
        _items = result.fold((s) {
          final items = s.items.map((item) {
            return PublishedItem(
              publishedViewId: item.publishedViewId,
              viewId: item.viewId,
              workspaceId: item.workspaceId,
              name: item.name.isNotEmpty ? item.name : item.publishName,
              publishName: item.publishName,
              publisherEmail: item.publisherEmail,
              publishedAt: DateTime.fromMillisecondsSinceEpoch(
                item.publishedAt.millisecondsSinceEpoch,
              ),
              isReceived: item.isReceived,
              isReadonly: item.isReadonly,
            );
          }).toList();
          
          // 按发布时间倒序排序
          items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
          return items;
        }, (f) {
          Log.error('load published views failed: $f');
          _error = f.msg;
          return [];
        });
        _loading = false;
      });
    } catch (e, stackTrace) {
      Log.error('load published views error: $e', stackTrace);
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    PublishRefresh.notifier.removeListener(_onPublishPing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 340, child: _buildLeftList(context)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildRightPlaceholder(context)),
      ],
    );
  }

  Widget _buildLeftList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowyText(_error!),
            const VSpace(8),
            FlowyButton(text: const FlowyText('重试'), onTap: _load),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: FlowyText('暂无发布'));
    }
    
    // 分离自己发布的和接收的发布文档
    final myPublished = _items.where((item) => !item.isReceived).toList();
    final received = _items.where((item) => item.isReceived).toList();
    
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 自己发布的部分
        if (myPublished.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FlowyText.medium('我发布的', color: Theme.of(context).primaryColor),
          ),
          ...myPublished.map((item) => _buildPublishItem(context, item)),
          const Divider(height: 1),
        ],
        
        // 接收的部分
        if (received.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FlowyText.medium('我接收的', color: Theme.of(context).hintColor),
          ),
          ...received.map((item) => _buildPublishItem(context, item)),
        ],
      ],
    );
  }

  Widget _buildPublishItem(BuildContext context, PublishedItem item) {
    return ListTile(
      dense: true,
      leading: Icon(
        item.isReceived ? Icons.inbox : Icons.publish,
        size: 20,
        color: item.isReceived 
            ? Theme.of(context).hintColor 
            : Theme.of(context).primaryColor,
      ),
      title: FlowyText.regular(
        item.name.isNotEmpty ? item.name : item.publishName, 
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: FlowyText.small(
        item.publishName, 
        color: Theme.of(context).hintColor,
      ),
      trailing: item.isReadonly 
          ? Icon(Icons.lock_outline, size: 16, color: Theme.of(context).hintColor)
          : null,
      onTap: () async {
        try {
          final viewOrErr = await ViewBackendService.getView(item.viewId);
          viewOrErr.fold(
            (view) => context.read<TabsBloc>().openPlugin(view),
            (e) {
              Log.error('open published view failed: $e');
              showToastNotification(
                message: '打开发布笔记失败: ${e.msg}',
                type: ToastificationType.error,
              );
            },
          );
        } catch (e, stackTrace) {
          Log.error('open published view error: $e', stackTrace);
          showToastNotification(
            message: '打开发布笔记失败: $e',
            type: ToastificationType.error,
          );
        }
      },
    );
  }

  Widget _buildRightPlaceholder(BuildContext context) {
    return Center(
      child: FlowyText(
        '从左侧选择一个发布项查看内容',
        color: Theme.of(context).hintColor,
      ),
    );
  }
}
