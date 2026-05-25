import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

class BoardPluginBuilder implements PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return DatabaseTabBarViewPlugin(pluginType: pluginType, view: data);
    } else {
      throw FlowyPluginException.invalidData;
    }
  }

  @override
  String get menuName => "看板";

  @override
  FlowySvgData get icon => FlowySvgs.icon_board_s;

  @override
  PluginType get pluginType => PluginType.board;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Board;
}

class BoardPluginConfig implements PluginConfig {
  @override
  bool get creatable => true;
}
