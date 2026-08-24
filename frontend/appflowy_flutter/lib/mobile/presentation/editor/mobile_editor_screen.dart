import 'package:appflowy/mobile/presentation/base/mobile_view_page.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// `/docs` 同时承载文档、文件夹、笔记本和白板。
///
/// 路径相同而 viewId 变化时，Page 必须使用不同 key，否则 Navigator 会把新 Page
/// 当作旧 Page 的配置更新并复用原 Route。白板跨空间迁移会生成新 viewId，路由级
/// key 是确保旧白板 Route、State 和 PlatformView 真正销毁的边界。
ValueKey<String> mobileDocumentRouteKey(
  String routerPageKey,
  String viewId,
) =>
    ValueKey<String>('mobile_document_route_${routerPageKey}_$viewId');

class MobileDocumentScreen extends StatelessWidget {
  const MobileDocumentScreen({
    super.key,
    required this.id,
    this.title,
    this.showMoreButton = true,
    this.fixedTitle,
    this.blockId,
    this.tabs = const [PickerTabType.emoji, PickerTabType.icon],
  });

  /// view id
  final String id;
  final String? title;
  final bool showMoreButton;
  final String? fixedTitle;
  final String? blockId;
  final List<PickerTabType> tabs;

  static const routeName = '/docs';
  static const viewId = 'id';
  static const viewTitle = 'title';
  static const viewShowMoreButton = 'show_more_button';
  static const viewFixedTitle = 'fixed_title';
  static const viewBlockId = 'block_id';
  static const viewSelectTabs = 'select_tabs';

  @override
  Widget build(BuildContext context) {
    return MobileViewPage(
      key: ValueKey('mobile_view_page_$id'),
      id: id,
      title: title,
      viewLayout: ViewLayoutPB.Document,
      showMoreButton: showMoreButton,
      fixedTitle: fixedTitle,
      blockId: blockId,
      tabs: tabs,
    );
  }
}
