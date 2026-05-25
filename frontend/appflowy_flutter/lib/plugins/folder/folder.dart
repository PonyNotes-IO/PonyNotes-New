library;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// FolderPluginBuilder 用于创建文件夹类型的视图
/// 文件夹本质上是文档类型，但使用📂图标来区分
class FolderPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      // 重用 DocumentPlugin，因为文件夹和文档功能完全一致
      return DocumentPlugin(pluginType: pluginType, view: data);
    }

    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "文件夹";

  @override
  FlowySvgData get icon => FlowySvgs.folder_m;

  @override
  PluginType get pluginType => PluginType.folder;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Folder;
}


