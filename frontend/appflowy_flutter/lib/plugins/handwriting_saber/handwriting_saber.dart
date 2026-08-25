library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/unified_view_top_right_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import 'presentation/handwriting_saber_poc_page.dart';

class HandwritingSaberPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return HandwritingSaberPlugin(
        pluginType: pluginType,
        view: data,
      );
    }
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => '手写笔记';

  @override
  FlowySvgData get icon => FlowySvgs.icon_board_s;

  @override
  PluginType get pluginType => PluginType.handwritingSaber;

  @override
  ViewLayoutPB? get layoutType => ViewLayoutPB.Document;
}

class HandwritingSaberPlugin extends Plugin {
  HandwritingSaberPlugin({
    required ViewPB view,
    required PluginType pluginType,
  }) : notifier = ViewPluginNotifier(view: view) {
    _pluginType = pluginType;
  }

  @override
  late final ViewPluginNotifier notifier;
  late final PluginType _pluginType;
  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginWidgetBuilder get widgetBuilder => HandwritingSaberPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        notifier: notifier,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => _pluginType;

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

class HandwritingSaberPluginWidgetBuilder extends PluginWidgetBuilder {
  HandwritingSaberPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    required this.pageAccessLevelBloc,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  ViewPB get view => notifier.view;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    final content = MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: HandwritingSaberPocPage(
        key: ValueKey('handwriting_saber_poc_page_${notifier.view.id}'),
        view: notifier.view,
        onViewChanged: (view) => notifier.view = view,
      ),
    );

    final preferHostTopRightActions =
        data?['preferHostTopRightActions'] == true;
    // Tablets use the desktop handwriting surface while retaining the mobile
    // navigation/business flow. Keep the compact mobile surface for phones.
    final isPhone = PlatformInfo.isMobile && !PlatformInfo.isTablet;
    if (isPhone || preferHostTopRightActions) {
      return content;
    }

    return Stack(
      children: [
        content,
        Positioned(
          top: 0,
          left: UniversalPlatform.isMacOS ? 100 : 16,
          child: const _HandwritingSidebarExpandButton(),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: UnifiedViewTopRightActions(
            view: view,
            viewInfoBloc: bloc,
            pageAccessLevelBloc: pageAccessLevelBloc,
            showCollaborators: FeatureFlag.syncDocument.isOn,
            useFloatingSurface: true,
            showShareButton: false,
          ),
        ),
      ],
    );
  }

  @override
  List<NavigationItem> get navigationItems => <NavigationItem>[this];

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem => BlocProvider<PageAccessLevelBloc>.value(
        value: pageAccessLevelBloc,
        child: ViewTitleBar(
          key: ValueKey(notifier.view.id),
          view: notifier.view,
        ),
      );

  @override
  Widget? get rightBarItem => null;

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);
}

class _HandwritingSidebarExpandButton extends StatelessWidget {
  const _HandwritingSidebarExpandButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FullWindowController.isFullWindow,
      builder: (context, isFullWindow, _) {
        if (isFullWindow) {
          return const SizedBox.shrink();
        }

        final isMenuHidden = context.select<HomeSettingBloc, bool>(
          (bloc) => bloc.isMenuHidden,
        );
        if (!isMenuHidden) {
          return const SizedBox.shrink();
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: HomeSizes.topActionBarHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: FlowyTooltip(
              message: LocaleKeys.sideBar_openSidebar.tr(),
              child: SizedBox.square(
                dimension: HomeSizes.topActionBarItemExtent,
                child: FlowyButton(
                  margin: EdgeInsets.zero,
                  text: FlowySvg(
                    FlowySvgs.sidebar_collapse_custom_m,
                    size: const Size.square(20),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onTap: () => context.read<HomeSettingBloc>().collapseMenu(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
