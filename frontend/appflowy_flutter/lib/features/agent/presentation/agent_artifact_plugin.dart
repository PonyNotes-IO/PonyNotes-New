import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'agent_artifact_library.dart';

class AgentArtifactPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => AgentArtifactPlugin();
  @override
  String get menuName => '产物';
  @override
  FlowySvgData get icon => FlowySvgs.icon_file_library_s;
  @override
  PluginType get pluginType => PluginType.agentArtifacts;
  @override
  ViewLayoutPB? get layoutType => null;
}

class AgentArtifactPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class AgentArtifactPlugin extends Plugin {
  @override
  PluginId get id => 'agent_artifacts';
  @override
  PluginType get pluginType => PluginType.agentArtifacts;
  @override
  PluginWidgetBuilder get widgetBuilder => _ArtifactWidgetBuilder();
}

class _ArtifactWidgetBuilder extends PluginWidgetBuilder {
  @override
  String get viewName => '产物';
  @override
  Widget get leftBarItem => const Text('产物');
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
      const AgentArtifactLibrary(embedded: true);
}
