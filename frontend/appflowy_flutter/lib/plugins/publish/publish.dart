import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/panels/publish_panel.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/widgets.dart';

import '../../workspace/presentation/home/home_stack.dart';

class PublishPanelPlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => PublishPanelWidgetBuilder();

  @override
  PluginId get id => 'publish_panel';

  @override
  PluginType get pluginType => PluginType.blank;
}

class PublishPanelWidgetBuilder extends PluginWidgetBuilder with NavigationItem {
  @override
  String? get viewName => '发布';

  @override
  Widget get leftBarItem => const FlowyText.medium('发布');

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const PublishPanel();

  @override
  List<NavigationItem> get navigationItems => [this];
}


