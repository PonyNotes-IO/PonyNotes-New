library;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// NotebookPluginBuilder 用于创建笔记本类型的视图
/// 笔记本本质上是文档类型，但使用📓图标来区分
class NotebookPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      // 重用 DocumentPlugin，因为笔记本和文档功能完全一致
      return DocumentPlugin(pluginType: pluginType, view: data);
    }

    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "笔记本";

  @override
  FlowySvgData get icon => FlowySvgs.folder_m; // 临时使用 folder 图标，后续会通过 emoji 显示

  @override
  PluginType get pluginType => PluginType.notebook;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Notebook;
}


