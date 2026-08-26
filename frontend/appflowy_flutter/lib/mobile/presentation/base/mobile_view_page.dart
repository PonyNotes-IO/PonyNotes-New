import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';
import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy/mobile/application/mobile_view_migration_handoff.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/base/view_page/app_bar_buttons.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_mobile_state_container.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/application/document_sync_bloc.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class MobileViewPage extends StatefulWidget {
  const MobileViewPage({
    super.key,
    required this.id,
    required this.viewLayout,
    this.title,
    this.arguments,
    this.fixedTitle,
    this.showMoreButton = true,
    this.blockId,
    this.bodyPaddingTop = 0.0,
    this.tabs = const [PickerTabType.emoji, PickerTabType.icon],
  });

  /// view id
  final String id;
  final ViewLayoutPB viewLayout;
  final String? title;
  final Map<String, dynamic>? arguments;
  final bool showMoreButton;
  final String? blockId;
  final double bodyPaddingTop;
  final List<PickerTabType> tabs;

  // only used in row page
  final String? fixedTitle;

  @override
  State<MobileViewPage> createState() => _MobileViewPageState();
}

class _MobileViewPageState extends State<MobileViewPage> {
  static const String _folderObservableSource = 'Workspace';
  StreamSubscription? _sharedAccessRevocationSubscription;
  bool _isLeavingRevokedView = false;

  // 缓存 plugin 实例，避免输入法动画期间反复 init
  Plugin? _cachedPlugin;
  String? _cachedViewId;

  @override
  void initState() {
    super.initState();

    getIt<ReminderBloc>().add(const ReminderEvent.started());
    _listenForSharedAccessRevocation();
  }

  @override
  void dispose() {
    _cachedPlugin?.dispose();
    _cachedPlugin = null;
    _sharedAccessRevocationSubscription?.cancel();
    super.dispose();
  }

  void _listenForSharedAccessRevocation() {
    _sharedAccessRevocationSubscription =
        RustStreamReceiver.listen((observable) {
      if (!mounted || _isLeavingRevokedView) {
        return;
      }
      if (observable.source != _folderObservableSource ||
          observable.ty != FolderNotification.DidRemoveMySharedView.value ||
          observable.id != widget.id) {
        return;
      }

      if (MobileViewMigrationHandoff.isExpectedRemoval(widget.id)) {
        Log.info(
          '[WhiteboardMigrationUI] 忽略迁移中的源白板删除通知: '
          'removed=${widget.id} replacement='
          '${MobileViewMigrationHandoff.replacementViewId(widget.id)}',
        );
        return;
      }

      // 门闩处理“删除通知早于 replace”的主竞态；这里继续处理 replace 已提交、
      // 门闩已清理后才到达的延迟通知。latestOpenView 已切到新 ID 时，旧页面不能
      // 再执行 go('/home') 把已经打开的新白板覆盖掉。
      final latestOpenViewId = getIt<MenuSharedState>().latestOpenView?.id;
      if (latestOpenViewId != null && latestOpenViewId != widget.id) {
        Log.info(
          '[WhiteboardMigrationUI] 忽略非当前页面的删除通知: '
          'removed=${widget.id} latestOpen=$latestOpenViewId',
        );
        return;
      }

      _isLeavingRevokedView = true;
      context.go(MobileHomeScreen.routeName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final latestOpenView = getIt<MenuSharedState>().latestOpenView;
    final fallbackView =
        latestOpenView?.id == widget.id ? latestOpenView : null;
    return BlocProvider(
      key: ValueKey('mobile_view_page_bloc_${widget.id}'),
      create: (_) => MobileViewPageBloc(
        viewId: widget.id,
        fallbackView: fallbackView,
      )..add(const MobileViewPageEvent.initial()),
      child: BlocBuilder<MobileViewPageBloc, MobileViewPageState>(
        // 只在 result 或 isLoading 变化时重建，避免输入法动画期间的无效重建
        buildWhen: (previous, current) =>
            previous.result != current.result ||
            previous.isLoading != current.isLoading,
        builder: (context, state) {
          final view = state.result?.fold((s) => s, (f) => null);
          final body = _buildBody(context, state);

          if (view == null) {
            return _buildApp(context, null, body);
          }

          return MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    FavoriteBloc()..add(const FavoriteEvent.initial()),
              ),
              BlocProvider(
                create: (_) =>
                    ViewBloc(view: view)..add(const ViewEvent.initial()),
              ),
              BlocProvider.value(
                value: getIt<ReminderBloc>(),
              ),
              BlocProvider(
                create: (_) =>
                    ShareBloc(view: view)..add(const ShareEvent.initial()),
              ),
              if (state.userProfilePB != null)
                BlocProvider(
                  create: (_) => UserWorkspaceBloc(
                    userProfile: state.userProfilePB!,
                    repository: RustWorkspaceRepositoryImpl(
                      userId: state.userProfilePB!.id,
                    ),
                  )..add(UserWorkspaceEvent.initialize()),
                ),
              if (view.layout.isDocumentView)
                BlocProvider(
                  create: (_) => DocumentPageStyleBloc(view: view)
                    ..add(const DocumentPageStyleEvent.initial()),
                ),
              if (view.layout.isDocumentView)
                BlocProvider(
                  create: (_) => DocumentSyncBloc(view: view)
                    ..add(DocumentSyncEvent.initial()),
                ),
              if (view.layout.isDocumentView || view.layout.isDatabaseView)
                BlocProvider(
                  create: (_) => PageAccessLevelBloc(view: view)
                    ..add(const PageAccessLevelEvent.initial()),
                ),
            ],
            child: Builder(
              builder: (context) {
                final view = context.watch<ViewBloc>().state.view;
                return _buildApp(context, view, body);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildApp(
    BuildContext context,
    ViewPB? view,
    Widget child,
  ) {
    // NOTE: MobileViewPageImmersiveAppBar / MobileAppBar have been intentionally
    // hidden on mobile so that the document page can render its own toolbar at
    // the top without producing a stacked dual AppBar. The body sits flush
    // against the status bar; the inner DocumentPage toolbar adds its own
    // status-bar padding.
    //
    // HandwritingSaberPocPage is layout=Document so it falls into the same
    // branch as DocumentPlugin. Unlike the document editor, however, it does
    // not pad the bottom for the system navigation bar, which produced a
    // visible white gap above the gesture pill on mobile. Wrap only the
    // handwriting plugin's body with `SafeArea(top: false, ...)` so its
    // existing `VSpace(40)` continues to manage the status bar while the
    // bottom inset is now respected. Pure DocumentPlugin keeps its current
    // behaviour unchanged.
    final isDocument = view?.layout.isDocumentView ?? false;
    final isAIChat = view?.layout == ViewLayoutPB.Chat;
    final isHandwritingSaber = view?.pluginType == PluginType.handwritingSaber;
    // MobileChatScreen already provides the AI conversation's navigation bar.
    // Do not render the generic view actions underneath it.
    final showAppBar = !isDocument && !isAIChat && view != null;
    final appBarHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      appBar: showAppBar
          ? MobileViewPageImmersiveAppBar(
              preferredSize: Size(double.infinity, appBarHeight),
              appBarOpacity: const AlwaysStoppedAnimation(1.0),
              actions: _buildAppBarActions(view),
              view: view,
            )
          : null,
      body: (isDocument && !isHandwritingSaber)
          ? child
          : SafeArea(
              top: false,
              child: child,
            ),
    );
  }

  List<Widget> _buildAppBarActions(ViewPB view) {
    return [
      if (FeatureFlag.syncDocument.isOn)
        DocumentCollaborators(
          key: ValueKey('collaborators_${view.id}'),
          width: 60,
          height: 32,
          view: view,
        ),
      ViewFavoriteButton(
        key: ValueKey('favorite_button_${view.id}'),
        view: view,
      ),
      if (view.layout != ViewLayoutPB.Whiteboard &&
          view.layout != ViewLayoutPB.Grid &&
          view.layout != ViewLayoutPB.Board)
        ShareButton(
          key: ValueKey('share_button_${view.id}'),
          view: view,
        ),
      if (widget.showMoreButton) MoreViewActions(view: view),
    ];
  }

  Widget _buildBody(BuildContext context, MobileViewPageState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final result = state.result;
    if (result == null) {
      return FlowyMobileStateContainer.error(
        emoji: '😔',
        title: LocaleKeys.error_weAreSorry.tr(),
        description: LocaleKeys.error_loadingViewError.tr(),
        errorMsg: '',
      );
    }

    return result.fold(
      (view) {
        // 缓存 plugin 实例，避免输入法动画期间反复创建和 init
        // 只有当 view.id 变化时才重新创建
        if (_cachedPlugin == null || _cachedViewId != view.id) {
          _cachedPlugin = view.plugin(arguments: widget.arguments ?? const {})
            ..init();
          _cachedViewId = view.id;
        }

        return _cachedPlugin!.widgetBuilder.buildWidget(
          shrinkWrap: false,
          context: PluginContext(userProfile: state.userProfilePB),
          data: {
            MobileDocumentScreen.viewFixedTitle: widget.fixedTitle,
            MobileDocumentScreen.viewBlockId: widget.blockId,
            MobileDocumentScreen.viewSelectTabs: widget.tabs,
          },
        );
      },
      (error) {
        return FlowyMobileStateContainer.error(
          emoji: '😔',
          title: LocaleKeys.error_weAreSorry.tr(),
          description: LocaleKeys.error_loadingViewError.tr(),
          errorMsg: error.toString(),
        );
      },
    );
  }
}
