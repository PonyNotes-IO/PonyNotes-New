import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_publish_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum PanelMode { favorite, publish }

class FavoritePublishPanel extends StatelessWidget {
  const FavoritePublishPanel({super.key, required this.mode});

  final PanelMode mode;

  @override
  Widget build(BuildContext context) {
    return FlowyDialog(
      width: MediaQuery.of(context).size.width * 0.8,
      constraints: const BoxConstraints(maxWidth: 1024, minWidth: 720, minHeight: 520),
      child: SizedBox(
        height: 560,
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: mode == PanelMode.favorite
                  ? _FavoriteList(onOpen: (v) => context.read<TabsBloc>().openPlugin(v))
                  : _PublishedList(onOpen: (v) => context.read<TabsBloc>().openPlugin(v)),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: FlowyText(
                  mode == PanelMode.favorite ? '选择左侧最爱项查看内容' : '选择左侧发布项查看内容',
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteList extends StatelessWidget {
  const _FavoriteList({required this.onOpen});
  final void Function(ViewPB) onOpen;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FavoriteBloc()..add(const FavoriteEvent.initial()),
      child: BlocBuilder<FavoriteBloc, FavoriteState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (state.views.isEmpty) {
            return const Center(child: FlowyText('暂无最爱'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final view = state.views.reversed.toList()[index].item;
              return ListTile(
                dense: true,
                title: FlowyText.regular(view.name, overflow: TextOverflow.ellipsis),
                onTap: () => onOpen(view),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: state.views.length,
          );
        },
      ),
    );
  }
}

class _PublishedList extends StatefulWidget {
  const _PublishedList({required this.onOpen});
  final void Function(ViewPB) onOpen;

  @override
  State<_PublishedList> createState() => _PublishedListState();
}

class _PublishedListState extends State<_PublishedList> {
  List<PublishInfoViewPB> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 初始化发布服务
    await ViewPublishService().initialize();
    
    final result = await FolderEventListPublishedViews().send();
    setState(() {
      _items = result.fold((s) => s.items, (f) {
        Log.error('load published views failed: $f');
        return [];
      });
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_items.isEmpty) {
      return const Center(child: FlowyText('暂无发布'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final item = _items[index];
        final view = ViewPB()
          ..id = item.info.viewId
          ..name = item.info.publishName;
        return ListTile(
          dense: true,
          title: FlowyText.regular(item.view.name.isNotEmpty ? item.view.name : item.info.publishName,
              overflow: TextOverflow.ellipsis),
          subtitle: FlowyText.small(item.info.publishName, color: Theme.of(context).hintColor),
          onTap: () => widget.onOpen(view),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: _items.length,
    );
  }
}




