import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/shared/share/_shared.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final workspaceBloc = context.read<UserWorkspaceBloc>();
    final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId ?? '';
    final workspaceType = workspaceBloc.state.currentWorkspace?.workspaceType;
    PageAccessLevelBloc? pageAccessLevelBloc;
    try {
      final contextPageAccessLevelBloc = context.read<PageAccessLevelBloc>();
      if (contextPageAccessLevelBloc.view.id == view.id) {
        pageAccessLevelBloc = contextPageAccessLevelBloc;
      }
    } catch (_) {
      pageAccessLevelBloc = null;
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              getIt<ShareBloc>(param1: view)..add(const ShareEvent.initial()),
        ),
        if (view.layout.isDatabaseView)
          BlocProvider(
            create: (context) => DatabaseTabBarBloc(
              view: view,
              compactModeId: view.id,
              enableCompactMode: false,
            )..add(const DatabaseTabBarEvent.initial()),
          ),
        BlocProvider(
          create: (context) {
            final bloc = ShareTabBloc(
              repository: RustShareWithUserRepositoryImpl(),
              pageId: view.id,
              workspaceId: workspaceId,
            );

            if (workspaceType != WorkspaceTypePB.LocalW) {
              bloc.add(ShareTabEvent.initialize());
            }

            return bloc;
          },
        ),
      ],
      child: BlocListener<ShareBloc, ShareState>(
        listener: (context, state) {
          if (!state.isLoading && state.exportResult != null) {
            state.exportResult!.fold(
              (data) => _handleExportSuccess(context, data),
              (error) => _handleExportError(context, error),
            );
          }
        },
        child: BlocBuilder<ShareBloc, ShareState>(
          builder: (context, state) {
            return FutureBuilder<SpacePermission>(
              future: getSpacePermission(),
              builder: (context, snapshot) {
                var spacePermission = SpacePermission.publicToAll;
                final isReadOnly = pageAccessLevelBloc != null &&
                    !pageAccessLevelBloc.state.isLoadingLockStatus &&
                    pageAccessLevelBloc.state.isReadOnly;

                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.hasData) {
                    spacePermission = snapshot.data!;
                  }
                }

                final tabs = [
                  if (!isReadOnly &&
                      state.enablePublish &&
                      spacePermission != SpacePermission.private)
                    ShareMenuTab.share,
                ];

                if (isReadOnly) {
                  return Tooltip(
                    message: '该文档为只读内容，不能再次共享',
                    child: Opacity(
                      opacity: 0.45,
                      child: AbsorbPointer(
                        child: ShareMenuButton(
                          tabs: const [],
                          pageAccessLevelBloc: pageAccessLevelBloc,
                          readPageAccessLevelFromContext: false,
                        ),
                      ),
                    ),
                  );
                }

                return ShareMenuButton(
                  tabs: tabs,
                  pageAccessLevelBloc: pageAccessLevelBloc,
                  readPageAccessLevelFromContext: false,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<SpacePermission> getSpacePermission() async {
    try {
      if (view.isSpace) {
        return view.spacePermission;
      }

      final ancestorsResult =
          await ViewBackendService.getViewAncestors(view.id);
      return ancestorsResult.fold((ancestors) {
        for (final ancestor in ancestors.items) {
          if (ancestor.isSpace) {
            return ancestor.spacePermission;
          }
        }
        return SpacePermission.publicToAll;
      }, (_) {
        return SpacePermission.publicToAll;
      });
    } catch (_) {
      return SpacePermission.publicToAll;
    }
  }

  void _handleExportSuccess(BuildContext context, ShareType shareType) {
    switch (shareType) {
      case ShareType.markdown:
      case ShareType.html:
      case ShareType.csv:
        showToastNotification(
          message: LocaleKeys.settings_files_exportFileSuccess.tr(),
        );
        break;
      default:
        break;
    }
  }

  void _handleExportError(BuildContext context, FlowyError error) {
    showToastNotification(
      message:
          '${LocaleKeys.settings_files_exportFileFail.tr()}: ${error.code}',
    );
  }
}
