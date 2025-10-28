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

class PublishPanel extends StatefulWidget {
  const PublishPanel({super.key});

  @override
  State<PublishPanel> createState() => _PublishPanelState();
}

class _PublishPanelState extends State<PublishPanel> {
  List<PublishInfoViewPB> _items = const [];
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
    // 刷新发布服务状态
    await ViewPublishService().refreshPublishedViews();
    
    final result = await FolderEventListPublishedViews().send();
    setState(() {
      _items = result.fold((s) {
        final items = List<PublishInfoViewPB>.from(s.items);
        items.sort((a, b) => b.info.publishTimestampSec.toInt() - a.info.publishTimestampSec.toInt());
        return items;
      }, (f) {
        Log.error('load published views failed: $f');
        _error = f.msg;
        return [];
      });
      _loading = false;
    });
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final item = _items[index];
        final title = item.view.name.isNotEmpty ? item.view.name : item.info.publishName;
        return ListTile(
          dense: true,
          title: FlowyText.regular(title, overflow: TextOverflow.ellipsis),
          subtitle: item.info.publishName.isNotEmpty
              ? FlowyText.small(item.info.publishName, color: Theme.of(context).hintColor)
              : null,
          onTap: () async {
            final viewOrErr = await ViewBackendService.getView(item.info.viewId);
            viewOrErr.fold(
              (view) => context.read<TabsBloc>().openPlugin(view),
              (e) => Log.error('open published view failed: $e'),
            );
          },
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: _items.length,
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


