import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/note_graph/presentation/note_graph_page.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

class NoteGraphPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) =>
      NoteGraphPlugin(focusView: data is ViewPB ? data : null);
  @override
  String get menuName => '双链图谱';
  @override
  FlowySvgData get icon => FlowySvgs.icon_share_m;
  @override
  PluginType get pluginType => PluginType.noteGraph;
  @override
  ViewLayoutPB? get layoutType => null;
}

class NoteGraphPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class NoteGraphPlugin extends Plugin {
  NoteGraphPlugin({this.focusView});
  final ViewPB? focusView;
  @override
  PluginId get id => 'note_graph:${focusView?.id ?? 'global'}';
  @override
  PluginType get pluginType => PluginType.noteGraph;
  @override
  PluginWidgetBuilder get widgetBuilder =>
      NoteGraphWidgetBuilder(focusView: focusView);
}

class NoteGraphWidgetBuilder extends PluginWidgetBuilder {
  NoteGraphWidgetBuilder({this.focusView});
  final ViewPB? focusView;
  @override
  String get viewName => '双链图谱';
  @override
  Widget get leftBarItem => Builder(
        builder: (context) =>
            Text(noteGraphText(context, '双链图谱', 'Note link graph')),
      );
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
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
      NoteGraphPage(focusView: focusView);
}
