library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
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
  String get menuName => '手写笔记（Saber PoC）';

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
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginWidgetBuilder get widgetBuilder => HandwritingSaberPluginWidgetBuilder(
        notifier: notifier,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => _pluginType;

  @override
  void init() {
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class HandwritingSaberPluginWidgetBuilder extends PluginWidgetBuilder {
  HandwritingSaberPluginWidgetBuilder({
    required this.notifier,
    required this.pageAccessLevelBloc,
  });

  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    return BlocProvider<PageAccessLevelBloc>.value(
      value: pageAccessLevelBloc,
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
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);
}


