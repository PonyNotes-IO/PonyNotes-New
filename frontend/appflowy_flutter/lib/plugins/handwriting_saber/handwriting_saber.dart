library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'presentation/handwriting_saber_poc_page.dart';

class HandwritingSaberPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return HandwritingSaberPlugin(
        pluginType: pluginType,
        view: data,
      );
    }
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => '手写笔记';

  @override
  FlowySvgData get icon => FlowySvgs.icon_board_s;

  @override
  PluginType get pluginType => PluginType.handwritingSaber;

  @override
  ViewLayoutPB? get layoutType => ViewLayoutPB.Document;
}

class HandwritingSaberPlugin extends Plugin {
  HandwritingSaberPlugin({
    required ViewPB view,
    required PluginType pluginType,
  }) : notifier = ViewPluginNotifier(view: view) {
    _pluginType = pluginType;
  }

  @override
  late final ViewPluginNotifier notifier;
  late final PluginType _pluginType;
  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginWidgetBuilder get widgetBuilder => HandwritingSaberPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        notifier: notifier,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => _pluginType;

  @override
  void init() {
    _viewInfoBloc = ViewInfoBloc(view: notifier.view)
      ..add(const ViewInfoEvent.started());
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class HandwritingSaberPluginWidgetBuilder extends PluginWidgetBuilder {
  HandwritingSaberPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    required this.pageAccessLevelBloc,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  ViewPB get view => notifier.view;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: HandwritingSaberPocPage(
        key: ValueKey('handwriting_saber_poc_page_${notifier.view.id}'),
        view: notifier.view,
        onViewChanged: (view) => notifier.view = view,
      ),
    );
  }

  @override
  List<NavigationItem> get navigationItems => <NavigationItem>[this];

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem => BlocProvider<PageAccessLevelBloc>.value(
        value: pageAccessLevelBloc,
        child: ViewTitleBar(
          key: ValueKey(notifier.view.id),
          view: notifier.view,
        ),
      );

  @override
  Widget? get rightBarItem {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...FeatureFlag.syncDocument.isOn
              ? [
                  DocumentCollaborators(
                    key: ValueKey('collaborators_${view.id}'),
                    width: 120,
                    height: 32,
                    view: view,
                  ),
                  const HSpace(16),
                ]
              : [const HSpace(8)],
          _ConditionalShareButton(view: view),
          ViewFavoriteButton(
            key: ValueKey('favorite_button_${view.id}'),
            view: view,
          ),
          const HSpace(4),
          ValueListenableBuilder<bool>(
            valueListenable: FullWindowController.isFullWindow,
            builder: (context, isFullWindow, _) {
              return SizedBox.square(
                dimension: 28,
                child: FlowyButton(
                  margin: EdgeInsets.zero,
                  text: Icon(
                    isFullWindow
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onTap: FullWindowController.toggle,
                ),
              );
            },
          ),
          const HSpace(4),
          MoreViewActions(view: view),
        ],
      ),
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);
}

/// 私有空间内隐藏分享按钮的包装组件
class _ConditionalShareButton extends StatefulWidget {
  const _ConditionalShareButton({required this.view});

  final ViewPB view;

  @override
  State<_ConditionalShareButton> createState() =>
      _ConditionalShareButtonState();
}

class _ConditionalShareButtonState extends State<_ConditionalShareButton> {
  late Future<SpacePermission> _spacePermissionFuture;

  @override
  void initState() {
    super.initState();
    _spacePermissionFuture = _getSpacePermission();
  }

  @override
  void didUpdateWidget(_ConditionalShareButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id) {
      _spacePermissionFuture = _getSpacePermission();
    }
  }

  Future<SpacePermission> _getSpacePermission() async {
    try {
      if (widget.view.isSpace) {
        return widget.view.spacePermission;
      }
      final ancestorsResult =
          await ViewBackendService.getViewAncestors(widget.view.id);
      return ancestorsResult.fold(
        (ancestors) {
          for (final ancestor in ancestors.items) {
            if (ancestor.isSpace) {
              return ancestor.spacePermission;
            }
          }
          return SpacePermission.publicToAll;
        },
        (_) => SpacePermission.publicToAll,
      );
    } catch (_) {
      return SpacePermission.publicToAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpacePermission>(
      future: _spacePermissionFuture,
      builder: (context, snapshot) {
        final isPrivate = snapshot.data == SpacePermission.private;
        if (isPrivate) {
          return const SizedBox.shrink();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShareButton(
              key: ValueKey('share_button_${widget.view.id}'),
              view: widget.view,
            ),
            const HSpace(10),
          ],
        );
      },
    );
  }
}
