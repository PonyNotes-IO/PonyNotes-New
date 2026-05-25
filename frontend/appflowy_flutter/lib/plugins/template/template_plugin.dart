import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:flutter/material.dart';
import 'template_page.dart';

class TemplatePluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    return TemplatePlugin();
  }

  @override
  String get menuName => "模板";

  @override
  FlowySvgData get icon => FlowySvgs.icon_template_s;

  @override
  PluginType get pluginType => PluginType.template;

  @override
  ViewLayoutPB? get layoutType => null;
}

class TemplatePlugin extends Plugin {
  @override
  String get id => "template";

  @override
  PluginWidgetBuilder get widgetBuilder => TemplatePluginWidgetBuilder();

  @override
  PluginType get pluginType => PluginType.template;
}

class TemplatePluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  @override
  String? get viewName => "模板";

  @override
  Widget get leftBarItem => const Text('模板');

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget? get rightBarItem => null;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero; // 去除所有留白

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    return const TemplatePage();
  }

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  NavigationCallback get action => (id) {};
}

class TemplatePluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

