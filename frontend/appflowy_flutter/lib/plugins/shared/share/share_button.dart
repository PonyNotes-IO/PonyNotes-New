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
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ShareButton extends StatefulWidget {
  const ShareButton({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton> {
  // 缓存 Future，避免 BlocBuilder 重建时 FutureBuilder 重置导致闪烁
  late Future<SpacePermission> _spacePermissionFuture;

  @override
  void initState() {
    super.initState();
    _spacePermissionFuture = _getSpacePermission();
  }

  @override
  void didUpdateWidget(ShareButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当视图 ID 变化时重新获取空间权限
    if (oldWidget.view.id != widget.view.id) {
      _spacePermissionFuture = _getSpacePermission();
    }
  }

  // 异步获取空间权限
  Future<SpacePermission> _getSpacePermission() async {
    try {
      if (widget.view.isSpace) {
        return widget.view.spacePermission;
      }
      final ancestorsResult =
          await ViewBackendService.getViewAncestors(widget.view.id);
      return ancestorsResult.fold(
        (ancestors) {
          for (final ancestor in ancestors.items) {
            if (ancestor.isSpace) {
              return ancestor.spacePermission;
            }
          }
          return SpacePermission.publicToAll;
        },
        (_) => SpacePermission.publicToAll,
      );
    } catch (_) {
      return SpacePermission.publicToAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceBloc = context.read<UserWorkspaceBloc>();
    final workspaceType = workspaceBloc.state.currentWorkspace?.workspaceType;
    PageAccessLevelBloc? pageAccessLevelBloc;
    try {
      final bloc = context.read<PageAccessLevelBloc>();
      // 只使用与当前视图 ID 严格匹配的 bloc，避免读取到父级（如空间）的 bloc，
      // 否则空间级别的 readOnly 会导致 AbsorbPointer 遮蔽按钮，点击无反应。
      if (bloc.view.id == widget.view.id) {
        pageAccessLevelBloc = bloc;
      }
    } catch (_) {
      pageAccessLevelBloc = null;
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => getIt<ShareBloc>(param1: widget.view)
            ..add(const ShareEvent.initial()),
        ),
        if (widget.view.layout.isDatabaseView)
          BlocProvider(
            create: (context) => DatabaseTabBarBloc(
              view: widget.view,
              compactModeId: widget.view.id,
              enableCompactMode: false,
            )..add(const DatabaseTabBarEvent.initial()),
          ),
        BlocProvider(
          create: (context) {
            final bloc = ShareTabBloc(
              repository: RustShareWithUserRepositoryImpl(),
              pageId: widget.view.id,
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
            // 使用缓存的 Future，避免 BlocBuilder 每次重建都重新发起后端请求
            return FutureBuilder<SpacePermission>(
              future: _spacePermissionFuture,
              builder: (context, snapshot) {
                SpacePermission spacePermission = SpacePermission.publicToAll;
                final isReadOnly = pageAccessLevelBloc != null &&
                    !pageAccessLevelBloc.state.isLoadingLockStatus &&
                    pageAccessLevelBloc.state.isReadOnly;

                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  spacePermission = snapshot.data!;
                }

                Log.debug(
                  'ShareButton build: viewId=${widget.view.id}, enablePublish=${state.enablePublish}, isReadOnly=$isReadOnly, spacePermission=$spacePermission',
                );

                final tabs = [
                  if (!isReadOnly && state.enablePublish) ...[
                    // 私有空间文档不支持共享和协作，只支持发布
                    if (spacePermission != SpacePermission.private) ...[
                      ShareMenuTab.share,
                    ],
                    ShareMenuTab.publish,
                  ],
                  // ShareMenuTab.exportAs,
                ];

                if (isReadOnly) {
                  return Tooltip(
                    message: '该文档为只读内容，不能再次共享或发布',
                    child: Opacity(
                      opacity: 0.45,
                      child: AbsorbPointer(
                        child: ShareMenuButton(tabs: const []),
                      ),
                    ),
                  );
                }

                return ShareMenuButton(tabs: tabs);
              },
            );
          },
        ),
      ),
    );
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
