import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';

class SpaceHubPluginView extends StatefulWidget {
  const SpaceHubPluginView({
    super.key,
    required this.view,
    required this.createPlugin,
    required this.builder,
  });

  final ViewPB view;
  final Plugin Function() createPlugin;
  final Widget Function(BuildContext context, Plugin plugin) builder;

  @override
  State<SpaceHubPluginView> createState() => _SpaceHubPluginViewState();
}

class _SpaceHubPluginViewState extends State<SpaceHubPluginView> {
  late final Plugin _plugin;

  @override
  void initState() {
    super.initState();
    _plugin = widget.createPlugin()..init();
  }

  @override
  void didUpdateWidget(SpaceHubPluginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.view.id == widget.view.id);
    assert(oldWidget.view.layout == widget.view.layout);
    final notifier = _plugin.notifier;
    if (notifier is ViewPluginNotifier) {
      notifier.view = widget.view;
    }
  }

  @override
  void dispose() {
    _plugin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _plugin);
}
