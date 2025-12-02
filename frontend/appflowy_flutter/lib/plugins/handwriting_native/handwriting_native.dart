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
import 'package:appflowy/plugins/handwriting_native/presentation/handwriting_native_page.dart';

class HandwritingNativePluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    print('🏗️ [HandwritingNativePluginBuilder] build() called');
    print('🏗️ [HandwritingNativePluginBuilder] data type: ${data.runtimeType}');
    
    if (data is ViewPB) {
      print('🏗️ [HandwritingNativePluginBuilder] Creating HandwritingNativePlugin for view: ${data.id}');
      print('🏗️ [HandwritingNativePluginBuilder] View name: ${data.name}');
      print('🏗️ [HandwritingNativePluginBuilder] View layout: ${data.layout}');
      return HandwritingNativePlugin(pluginType: pluginType, view: data);
    }

    print('❌ [HandwritingNativePluginBuilder] Invalid data type, throwing exception');
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "手写笔记（原生）";

  @override
  FlowySvgData get icon => FlowySvgs.icon_board_s; // 暂时使用看板图标，后续可替换为专用手写图标

  @override
  PluginType get pluginType => PluginType.handwritingNative;

  @override
  ViewLayoutPB? get layoutType => ViewLayoutPB.Document; // 使用Document布局，通过extra字段标识
}

class HandwritingNativePlugin extends Plugin {
  HandwritingNativePlugin({
    required ViewPB view,
    required PluginType pluginType,
  }) : notifier = ViewPluginNotifier(view: view) {
    print('🎯 [HandwritingNativePlugin] Constructor called for view: ${view.id}');
    _pluginType = pluginType;
  }

  @override
  late final ViewPluginNotifier notifier;
  late final PluginType _pluginType;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginWidgetBuilder get widgetBuilder => HandwritingNativePluginWidgetBuilder(
        notifier: notifier,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => _pluginType;

  @override
  void init() {
    print('🔧 [HandwritingNativePlugin] init() called for view: ${notifier.view.id}');
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
    print('✅ [HandwritingNativePlugin] init() completed');
  }

  @override
  void dispose() {
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class HandwritingNativePluginWidgetBuilder extends PluginWidgetBuilder {
  HandwritingNativePluginWidgetBuilder({
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
    print('🎨 [HandwritingNativePluginWidgetBuilder] buildWidget() called');
    print('🎨 [HandwritingNativePluginWidgetBuilder] view: ${notifier.view.id}');
    print('🎨 [HandwritingNativePluginWidgetBuilder] view name: ${notifier.view.name}');
    
    print('🎨 [HandwritingNativePluginWidgetBuilder] Creating HandwritingNativePage...');
    final widget = BlocProvider<PageAccessLevelBloc>.value(
      value: pageAccessLevelBloc,
      child: HandwritingNativePage(
        key: ValueKey('handwriting_native_page_${notifier.view.id}'),
        view: notifier.view,
        onViewChanged: (view) => notifier.view = view,
      ),
    );
    print('🎨 [HandwritingNativePluginWidgetBuilder] HandwritingNativePage created, returning widget');
    return widget;
  }

  @override
  List<NavigationItem> get navigationItems => [this];

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

