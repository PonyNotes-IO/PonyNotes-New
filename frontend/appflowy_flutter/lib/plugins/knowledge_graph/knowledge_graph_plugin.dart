import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/knowledge_graph/knowledge_graph_strings.dart';
import 'package:appflowy/plugins/knowledge_graph/presentation/knowledge_graph_page.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

class KnowledgeGraphPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => KnowledgeGraphPlugin();

  @override
  String get menuName => 'knowledgeGraph.title'.tr();

  @override
  FlowySvgData get icon => FlowySvgs.icon_share_m;

  @override
  PluginType get pluginType => PluginType.knowledgeGraph;

  @override
  ViewLayoutPB? get layoutType => null;
}

class KnowledgeGraphPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class KnowledgeGraphPlugin extends Plugin {
  @override
  PluginId get id => 'knowledge_graph';

  @override
  PluginType get pluginType => PluginType.knowledgeGraph;

  @override
  PluginWidgetBuilder get widgetBuilder => KnowledgeGraphWidgetBuilder();
}

class KnowledgeGraphWidgetBuilder extends PluginWidgetBuilder {
  @override
  String get viewName => 'knowledgeGraph.title'.tr();

  @override
  Widget get leftBarItem => Builder(
        builder: (context) => Text(graphText(context, 'title')),
      );

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  bool get handlesFullWindowOverlayActionsInternally => true;

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const KnowledgeGraphPage();
}
