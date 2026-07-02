import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';
import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/base/mobile_view_page_bloc.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/base/view_page/app_bar_buttons.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_mobile_state_container.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  @override
  void initState() {
    super.initState();

    getIt<ReminderBloc>().add(const ReminderEvent.started());
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MobileViewPageBloc(viewId: widget.id)
        ..add(const MobileViewPageEvent.initial()),
      child: BlocBuilder<MobileViewPageBloc, MobileViewPageState>(
        builder: (context, state) {
          final view = state.result?.fold((s) => s, (f) => null);
          final body = _buildBody(context, state);

          if (view == null) {
            return SizedBox.shrink();
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
    final isDocument = view?.layout.isDocumentView ?? false;
    return Scaffold(
      body: isDocument ? child : SafeArea(child: child),
    );
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
        final plugin = view.plugin(arguments: widget.arguments ?? const {})
          ..init();
        return plugin.widgetBuilder.buildWidget(
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
