import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_page.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

class KnowledgeBasePluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => KnowledgeBasePlugin(
        switch (data) {
          KnowledgeBaseCategory category => category,
          KnowledgeBase base => base.visibility == 'private'
              ? KnowledgeBaseCategory.private
              : KnowledgeBaseCategory.shared,
          _ => null,
        },
        base: data is KnowledgeBase ? data : null,
      );

  @override
  String get menuName => '知识库';

  @override
  FlowySvgData get icon => FlowySvgs.icon_share_m;

  @override
  PluginType get pluginType => PluginType.knowledgeBase;

  @override
  ViewLayoutPB? get layoutType => null;
}

class KnowledgeBasePluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class KnowledgeBasePlugin extends Plugin {
  KnowledgeBasePlugin(this.category, {this.base});
  final KnowledgeBaseCategory? category;
  final KnowledgeBase? base;

  @override
  PluginId get id =>
      'knowledge_base:${base?.id ?? category?.name ?? 'current'}';

  @override
  PluginType get pluginType => PluginType.knowledgeBase;

  @override
  PluginWidgetBuilder get widgetBuilder =>
      _KnowledgeBaseWidgetBuilder(category, base);
}

class _KnowledgeBaseWidgetBuilder extends PluginWidgetBuilder {
  _KnowledgeBaseWidgetBuilder(this.category, this.base);
  final KnowledgeBaseCategory? category;
  final KnowledgeBase? base;

  @override
  String get viewName => base?.name ?? '知识库';

  @override
  Widget get leftBarItem => Builder(
        builder: (context) => Text(
          base?.name ??
              category?.label(context) ??
              kbText(context, '知识库', 'Knowledge bases'),
        ),
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
      KnowledgeBasePage(category: category, baseId: base?.id);
}
