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

class _SidebarPublishButtonState extends State<SidebarPublishButton> {
  bool _isExpanded = false;
  List<PublishInfoViewPB> _items = const [];
  bool _loading = false;
  String _workspaceId = '';
  void _onPublishPing() {
    if (!mounted) return;
    if (_isExpanded && !_loading) {
      _load();
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
                      if (_isExpanded && _items.isEmpty && !_loading) {
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
    setState(() => _loading = true);
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
        return [];
      });
      _loading = false;
    });
  }

  Widget _buildPublishedList(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (_items.isEmpty) {
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
      children: _items.map((item) {
        final title = item.view.name.isNotEmpty ? item.view.name : item.info.publishName;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 24, right: 8),
          title: FlowyText.regular(title, overflow: TextOverflow.ellipsis),
          subtitle: item.info.publishName.isNotEmpty
              ? FlowyText.small(item.info.publishName, color: Theme.of(context).hintColor)
              : null,
          onTap: () async {
            final viewOrErr = await ViewBackendService.getView(item.info.viewId);
            viewOrErr.fold(
              (view) => context.read<TabsBloc>().openPlugin(view),
              (e) {
                Log.error('open published view failed: $e');
                // 显示错误提示
                showToastNotification(
                  message: '打开发布笔记失败: ${e.msg}',
                  type: ToastificationType.error,
                );
              },
            );
          },
        );
      }).toList(),
    );
  }

  void _handleWorkspaceChanged(String? workspaceId) {
    final newWorkspaceId = workspaceId ?? '';
    if (newWorkspaceId.isEmpty || newWorkspaceId == _workspaceId) {
      return;
    }
    setState(() {
      _workspaceId = newWorkspaceId;
      _items = const [];
      _isExpanded = false;
      _loading = false;
    });
  }
}
