import 'package:appflowy/plugins/space_hub/space_hub_plugin_view.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps one plugin instance across parent rebuilds',
      (tester) async {
    final lifecycle = _PluginLifecycle();
    var builderCalls = 0;
    final view = ViewPB.create()
      ..id = 'view-a'
      ..layout = ViewLayoutPB.Whiteboard;

    Widget build(ViewPB currentView) {
      return MaterialApp(
        home: SpaceHubPluginView(
          key: ValueKey(
            'space_hub_plugin_${currentView.id}_${currentView.layout.value}',
          ),
          view: currentView,
          createPlugin: () => _CountingPlugin(currentView.id, lifecycle),
          builder: (_, __) {
            builderCalls++;
            return const SizedBox();
          },
        ),
      );
    }

    await tester.pumpWidget(build(view));
    await tester.pumpWidget(build(ViewPB.fromBuffer(view.writeToBuffer())));

    expect(lifecycle.created, 1);
    expect(lifecycle.initialized, 1);
    expect(lifecycle.disposed, 0);
    expect(builderCalls, 1);

    final nextView = ViewPB.create()
      ..id = 'view-b'
      ..layout = ViewLayoutPB.Whiteboard;
    await tester.pumpWidget(build(nextView));

    expect(lifecycle.created, 2);
    expect(lifecycle.initialized, 2);
    expect(lifecycle.disposed, 1);

    await tester.pumpWidget(const SizedBox());
    expect(lifecycle.disposed, 2);
  });
}

class _PluginLifecycle {
  int created = 0;
  int initialized = 0;
  int disposed = 0;
}

class _CountingPlugin extends Plugin {
  _CountingPlugin(this.id, this.lifecycle) {
    lifecycle.created++;
  }

  @override
  final String id;

  final _PluginLifecycle lifecycle;

  @override
  PluginType get pluginType => PluginType.whiteboard;

  @override
  PluginWidgetBuilder get widgetBuilder => throw UnimplementedError();

  @override
  void init() => lifecycle.initialized++;

  @override
  void dispose() => lifecycle.disposed++;
}
