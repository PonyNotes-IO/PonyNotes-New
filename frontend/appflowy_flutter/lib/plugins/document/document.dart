library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
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
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/unified_view_top_right_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

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

    final widget = Provider<ViewPluginNotifier>.value(
      value: notifier,
      child: MultiBlocProvider(
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
              // 永久删除由 DocumentPage 的 forceClose 状态触发；移入回收站
              // 则由外层 PluginDeletionListener 转发。
              onDeleted: () => context.onDeleted?.call(view, deletedViewIndex),
              initialSelection: initialSelection,
              initialBlockId: blockId,
              fixedTitle: fixedTitle,
              tabs: tabs,
              viewInfoBloc: bloc, // 传入 ViewInfoBloc
            ),
          ),
        ),
      ),
    );
    return PluginDeletionListener(
      notifier: notifier,
      onDeleted: context.onDeleted,
      child: widget,
    );
  }

  Widget _buildContentWithToolbar({
    required ViewPB view,
    required ViewInfoBloc viewInfoBloc,
    required PageAccessLevelBloc pageAccessLevelBloc,
    required Widget child,
  }) {
    final isWhiteboard = view.layout == ViewLayoutPB.Whiteboard;

    // On mobile, the floating top-left/right action overlays are not used:
    //   - the inner DocumentPage._buildTopBar renders the back button + the
    //     collaborators / share / favorite / more actions on a single row;
    //   - the legacy _SidebarExpandFloatingButton assumes a HomeSettingBloc
    //     (desktop only) and would otherwise render a no-op "expand sidebar"
    //     icon on mobile.
    // Stacking these Positioned overlays on top of the inner toolbar would
    // also cause vertical misalignment, since the toolbar lives inside the
    // editor Column (under the status bar) while the overlays are pinned to
    // (top: 0).
    if (PlatformInfo.isMobile) {
      return child;
    }

    return Stack(
      children: [
        child,
        // 侧边栏收起后，在文档左上角显示"展开侧边栏"按钮。
        // 仅当顶层文档（最爱/共享/最近等，直接打开为标签页）使用，
        // SpaceHub 内嵌文档由中间栏头部的展开按钮负责，不走此分支。
        Positioned(
          top: 0,
          left: UniversalPlatform.isMacOS ? 100 : 16,
          child: _SidebarExpandFloatingButton(
            iconColorOverride: isWhiteboard ? const Color(0xFF111111) : null,
          ),
        ),
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
        Log.info(
          '[Back] view=${view.name}(${view.id}), isSpace=${view.isSpace}, ancestors=${ancestors.map((a) => "${a.name}(${a.id}, isSpace=${a.isSpace})").join(" -> ")}, hasParent=$hasParent',
        );

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
      ViewTabBarItem(
        view: notifier.view,
        shortForm: shortForm,
        viewNotifier: notifier.viewNotifier,
      );

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

/// 文档左上角的"展开侧边栏"浮动按钮。
///
/// 仅在以下条件同时满足时显示：
///   - 侧边栏处于收起状态（[HomeSettingBloc.isMenuHidden]）；
///   - 不处于应用内全窗口模式（全窗口模式下由右上角"退出应用内全屏"按钮负责）。
///
/// 用于最爱/共享/最近等直接作为标签页打开的顶层文档：这些页面没有 SpaceHub
/// 中间栏，收起侧边栏后需要一个就地的入口重新展开。
class _SidebarExpandFloatingButton extends StatelessWidget {
  const _SidebarExpandFloatingButton({this.iconColorOverride});

  final Color? iconColorOverride;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FullWindowController.isFullWindow,
      builder: (context, isFullWindow, _) {
        if (isFullWindow) {
          return const SizedBox.shrink();
        }

        bool isMenuHidden = true;
        try {
          isMenuHidden = context.select<HomeSettingBloc, bool>(
            (bloc) => bloc.isMenuHidden,
          );
        } catch (_) {
          // HomeSettingBloc not available (mobile mode)
        }
        if (!isMenuHidden) {
          return const SizedBox.shrink();
        }

        final iconColor =
            iconColorOverride ?? Theme.of(context).colorScheme.onSurface;
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: HomeSizes.topActionBarHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: FlowyTooltip(
              // 统一使用标准翻译键，与顶栏/其它页面的"打开侧边栏"文案一致
              message: LocaleKeys.sideBar_openSidebar.tr(),
              child: SizedBox.square(
                dimension: HomeSizes.topActionBarItemExtent,
                child: FlowyButton(
                  margin: EdgeInsets.zero,
                  text: FlowySvg(
                    FlowySvgs.sidebar_collapse_custom_m,
                    size: const Size.square(20),
                    color: iconColor,
                  ),
                  onTap: () {
                    try {
                      context.read<HomeSettingBloc>().collapseMenu();
                    } catch (_) {
                      // HomeSettingBloc not available (mobile mode)
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
