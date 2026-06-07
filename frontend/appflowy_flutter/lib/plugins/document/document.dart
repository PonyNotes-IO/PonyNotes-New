library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart'
    show showToastNotification, ToastificationType;
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/unified_view_top_right_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DocumentPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return DocumentPlugin(pluginType: pluginType, view: data);
    }

    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "文档";

  @override
  FlowySvgData get icon => FlowySvgs.icon_document_s;

  @override
  PluginType get pluginType => PluginType.document;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class DocumentPlugin extends Plugin {
  DocumentPlugin({
    required ViewPB view,
    required PluginType pluginType,
    this.initialSelection,
    this.initialBlockId,
  }) : notifier = ViewPluginNotifier(view: view) {
    _pluginType = pluginType;
  }

  late PluginType _pluginType;
  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  final ViewPluginNotifier notifier;

  // the initial selection of the document
  final Selection? initialSelection;

  // the initial block id of the document
  final String? initialBlockId;

  @override
  PluginWidgetBuilder get widgetBuilder => DocumentPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
        notifier: notifier,
        initialSelection: initialSelection,
        initialBlockId: initialBlockId,
      );

  @override
  PluginType get pluginType => _pluginType;

  @override
  PluginId get id => notifier.view.id;

  @override
  void init() {
    _viewInfoBloc = ViewInfoBloc(view: notifier.view)
      ..add(const ViewInfoEvent.started());
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class DocumentPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  DocumentPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    this.initialSelection,
    this.initialBlockId,
    required this.pageAccessLevelBloc,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  ViewPB get view => notifier.view;
  int? deletedViewIndex;
  final Selection? initialSelection;
  final String? initialBlockId;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    notifier.isDeleted.addListener(() {
      final deletedView = notifier.isDeleted.value;
      if (deletedView != null && deletedView.hasIndex()) {
        deletedViewIndex = deletedView.index;
      }
    });

    final fixedTitle = data?[MobileDocumentScreen.viewFixedTitle];
    final blockId = initialBlockId ?? data?[MobileDocumentScreen.viewBlockId];
    final tabs = data?[MobileDocumentScreen.viewSelectTabs] ??
        const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ];

    return MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: BlocBuilder<DocumentAppearanceCubit, DocumentAppearance>(
        builder: (_, state) => _buildContentWithToolbar(
          view: view,
          viewInfoBloc: bloc,
          pageAccessLevelBloc: pageAccessLevelBloc,
          child: DocumentPage(
            key: ValueKey(view.id),
            view: view,
            onDeleted: () => context.onDeleted?.call(view, deletedViewIndex),
            initialSelection: initialSelection,
            initialBlockId: blockId,
            fixedTitle: fixedTitle,
            tabs: tabs,
            isInSpaceHub: false, // 默认为 false，单独打开时使用
            viewInfoBloc: bloc, // 传入 ViewInfoBloc
          ),
        ),
      ),
    );
  }

  Widget _buildContentWithToolbar({
    required ViewPB view,
    required ViewInfoBloc viewInfoBloc,
    required PageAccessLevelBloc pageAccessLevelBloc,
    required Widget child,
  }) {
    final isWhiteboard = view.layout == ViewLayoutPB.Whiteboard;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: UnifiedViewTopRightActions(
            view: view,
            viewInfoBloc: viewInfoBloc,
            pageAccessLevelBloc: pageAccessLevelBloc,
            showCollaborators: FeatureFlag.syncDocument.isOn && !isWhiteboard,
            useFloatingSurface: true,
            showShareButton: !isWhiteboard,
            iconColorOverride: isWhiteboard ? const Color(0xFF111111) : null,
          ),
        ),
      ],
    );
  }

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    return FutureBuilder<List<ViewPB>>(
      future: ViewBackendService.getViewAncestors(view.id)
          .then((result) => result.fold((s) => s.items, (f) => [])),
      builder: (context, snapshot) {
        final ancestors = snapshot.data ?? [];
        final hasParent = ancestors.length > 2; // workspace + parent + current

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 16),
            FlowyIconButton(
              width: 32,
              height: 32,
              tooltipText: hasParent ? '返回上一级' : '返回空间',
              icon: const FlowySvg(FlowySvgs.back_m),
              onPressed: () {
                try {
                  if (hasParent) {
                    // Navigate to parent view
                    final parentView = ancestors[ancestors.length - 2];
                    // Validate parentView before opening
                    if (parentView.id.isEmpty) {
                      Log.warn(
                          'Back navigation skipped: parentView has empty id');
                      showToastNotification(
                        message: '无法返回上级：视图数据不完整',
                        type: ToastificationType.warning,
                      );
                      return;
                    }
                    final tabsBloc = getIt<TabsBloc>();
                    tabsBloc.openPlugin(parentView);
                  } else {
                    // Navigate to space hub
                    final tabsBloc = getIt<TabsBloc>();
                    tabsBloc.add(
                      TabsEvent.openPlugin(
                        plugin: makePlugin(pluginType: PluginType.folder),
                      ),
                    );
                  }
                } catch (e) {
                  Log.error('Failed to navigate back: $e');
                  showToastNotification(
                    message: '导航失败，请重试',
                    type: ToastificationType.error,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);

  @override
  Widget? get rightBarItem => null;

  @override
  Widget? get fullWindowMoreItem => MultiBlocProvider(
        providers: [
          BlocProvider<ViewInfoBloc>.value(
            value: bloc,
          ),
          BlocProvider<PageAccessLevelBloc>.value(
            value: pageAccessLevelBloc,
          ),
        ],
        child: MoreViewActions(view: view, viewInfoBloc: bloc),
      );

  @override
  List<NavigationItem> get navigationItems => [this];
}
