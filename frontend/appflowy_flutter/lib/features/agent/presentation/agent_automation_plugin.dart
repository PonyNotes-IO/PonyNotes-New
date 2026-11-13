import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'agent_automations_page.dart';

class AgentAutomationPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => AgentAutomationPlugin();
  @override
  String get menuName => '自动化任务';
  @override
  FlowySvgData get icon => FlowySvgs.icon_file_library_s;
  @override
  PluginType get pluginType => PluginType.agentAutomations;
  @override
  ViewLayoutPB? get layoutType => null;
}

class AgentAutomationPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class AgentAutomationPlugin extends Plugin {
  @override
  PluginId get id => 'agent_automations';
  @override
  PluginType get pluginType => PluginType.agentAutomations;
  @override
  PluginWidgetBuilder get widgetBuilder => _AutomationWidgetBuilder();
}

class _AutomationWidgetBuilder extends PluginWidgetBuilder {
  @override
  String get viewName => '自动化任务';
  @override
  Widget get leftBarItem => const Text('自动化任务');
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
  @override
  List<NavigationItem> get navigationItems => [this];
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const AgentAutomationsPage(embedded: true);
}
