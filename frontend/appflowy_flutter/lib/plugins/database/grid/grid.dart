import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

class GridPluginBuilder implements PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return DatabaseTabBarViewPlugin(pluginType: pluginType, view: data);
    } else {
      throw FlowyPluginException.invalidData;
    }
  }

  @override
  String get menuName => "网格";

  @override
  FlowySvgData get icon => FlowySvgs.icon_grid_s;

  @override
  PluginType get pluginType => PluginType.grid;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Grid;
}

class GridPluginConfig implements PluginConfig {
  @override
  bool get creatable => true;
}
