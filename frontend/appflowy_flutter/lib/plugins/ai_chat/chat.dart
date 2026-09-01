import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_select_message_bloc.dart';
import 'package:appflowy/plugins/ai_chat/chat_page.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/common_view_action.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AIChatPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return AIChatPagePlugin(view: data);
    }

    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "AI 对话";

  @override
  FlowySvgData get icon => FlowySvgs.chat_ai_page_s;

  @override
  PluginType get pluginType => PluginType.chat;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Chat;
}

class AIChatPluginConfig implements PluginConfig {
  @override
  bool get creatable => true;
}

class AIChatPagePlugin extends Plugin {
  AIChatPagePlugin({
    required ViewPB view,
  }) : notifier = ViewPluginNotifier(view: view);

  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;
  late final _chatMessageSelectorBloc =
      ChatSelectMessageBloc(viewNotifier: notifier);

  @override
  final ViewPluginNotifier notifier;

  @override
  PluginWidgetBuilder get widgetBuilder => AIChatPagePluginWidgetBuilder(
        viewInfoBloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
        chatMessageSelectorBloc: _chatMessageSelectorBloc,
        notifier: notifier,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => PluginType.chat;

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
    _chatMessageSelectorBloc.close();
    notifier.dispose();
  }
}

class AIChatPagePluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  AIChatPagePluginWidgetBuilder({
    required this.viewInfoBloc,
    required this.pageAccessLevelBloc,
    required this.chatMessageSelectorBloc,
    required this.notifier,
  });

  final ViewInfoBloc viewInfoBloc;
  final PageAccessLevelBloc pageAccessLevelBloc;
  final ChatSelectMessageBloc chatMessageSelectorBloc;
  final ViewPluginNotifier notifier;

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    return BlocProvider.value(
      value: pageAccessLevelBloc,
      child: ViewTitleBar(key: ValueKey(notifier.view.id), view: notifier.view),
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    if (context.userProfile == null) {
      Log.error("User profile is null when opening AI Chat plugin");
      return const SizedBox();
    }

    final widget = MultiBlocProvider(
      providers: [
        BlocProvider.value(value: chatMessageSelectorBloc),
        BlocProvider.value(value: viewInfoBloc),
        BlocProvider.value(value: pageAccessLevelBloc),
      ],
      child: AIChatPage(
        userProfile: context.userProfile!,
        key: ValueKey(notifier.view.id),
        view: notifier.view,
        onDeleted: () {},
      ),
    );
    return PluginDeletionListener(
      notifier: notifier,
      onDeleted: context.onDeleted,
      child: widget,
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget get topActionBarLeadingItem => const _AIChatSidebarExpandButton();

  @override
  Widget? get rightBarItem => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: viewInfoBloc),
          BlocProvider.value(value: pageAccessLevelBloc),
          BlocProvider.value(value: chatMessageSelectorBloc),
        ],
        child: BlocBuilder<ChatSelectMessageBloc, ChatSelectMessageState>(
          builder: (context, state) {
            if (state.isSelectingMessages) {
              return const SizedBox.shrink();
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ViewFavoriteButton(
                  key: ValueKey('favorite_button_${notifier.view.id}'),
                  view: notifier.view,
                ),
                const HSpace(4),
                MoreViewActions(
                  key: ValueKey(notifier.view.id),
                  view: notifier.view,
                  customActions: [
                    CustomViewAction(
                      view: notifier.view,
                      disabled: !state.enabled,
                      leftIcon: FlowySvgs.ai_add_to_page_s,
                      label: LocaleKeys.moreAction_saveAsNewPage.tr(),
                      tooltipMessage: state.enabled
                          ? null
                          : LocaleKeys.moreAction_saveAsNewPageDisabled.tr(),
                      onTap: () {
                        chatMessageSelectorBloc.add(
                          const ChatSelectMessageEvent
                              .toggleSelectingMessages(),
                        );
                      },
                    ),
                    ViewAction(
                      type: ViewMoreActionType.divider,
                      view: notifier.view,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

  @override
  Widget? get fullWindowMoreItem => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: viewInfoBloc),
          BlocProvider.value(value: pageAccessLevelBloc),
          BlocProvider.value(value: chatMessageSelectorBloc),
        ],
        child: BlocBuilder<ChatSelectMessageBloc, ChatSelectMessageState>(
          builder: (context, state) {
            if (state.isSelectingMessages) {
              return const SizedBox.shrink();
            }

            return MoreViewActions(
              key: ValueKey(notifier.view.id),
              view: notifier.view,
              customActions: [
                CustomViewAction(
                  view: notifier.view,
                  disabled: !state.enabled,
                  leftIcon: FlowySvgs.ai_add_to_page_s,
                  label: LocaleKeys.moreAction_saveAsNewPage.tr(),
                  tooltipMessage: state.enabled
                      ? null
                      : LocaleKeys.moreAction_saveAsNewPageDisabled.tr(),
                  onTap: () {
                    chatMessageSelectorBloc.add(
                      const ChatSelectMessageEvent.toggleSelectingMessages(),
                    );
                  },
                ),
                ViewAction(
                  type: ViewMoreActionType.divider,
                  view: notifier.view,
                ),
              ],
            );
          },
        ),
      );
}

class _AIChatSidebarExpandButton extends StatelessWidget {
  const _AIChatSidebarExpandButton();

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
