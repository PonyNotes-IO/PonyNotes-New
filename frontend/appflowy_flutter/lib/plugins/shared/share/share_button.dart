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
                // 默认权限为publicToAll，确保在加载过程中也能显示分享按钮
                SpacePermission spacePermission = SpacePermission.publicToAll;
                
                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.hasData) {
                    spacePermission = snapshot.data!;
                    print('获取到空间权限: $spacePermission');
                  } else if (snapshot.hasError) {
                    print('获取空间权限失败: ${snapshot.error}');
                    // 错误时默认为publicToAll
                  }
                }

                final tabs = [
                  if (state.enablePublish) ...[
                    // 私有空间文档不支持共享和协作，只支持发布
                    if (spacePermission != SpacePermission.private) ...[
                      ShareMenuTab.share,
                    ],
                    ShareMenuTab.publish,
                  ],
                  // ShareMenuTab.exportAs,
                ];

                return ShareMenuButton(tabs: tabs);
              },
            );
          },
        ),
      ),
    );
  }

  // 异步获取空间权限
  Future<SpacePermission> getSpacePermission() async {
    try {
      // 检查视图是否是空间
      if (view.isSpace) {
        // 如果是空间，直接返回它的权限
        final viewPermission = view.spacePermission;
        print('视图是空间，权限: $viewPermission');
        return viewPermission;
      } else {
        // 如果不是空间，尝试获取其所属的空间
        final ancestorsResult = await ViewBackendService.getViewAncestors(view.id);
        
        return ancestorsResult.fold(
          (ancestors) {
            // 遍历祖先视图，找到第一个空间类型的视图
            for (final ancestor in ancestors.items) {
              if (ancestor.isSpace) {
                final spacePermission = ancestor.spacePermission;
                print('找到所属空间，权限: $spacePermission');
                return spacePermission;
              }
            }
            // 如果没有找到所属空间，默认为publicToAll
            print('未找到所属空间，默认视为公共空间');
            return SpacePermission.publicToAll;
          },
          (error) {
            print('获取祖先视图失败: $error');
            // 错误时默认为publicToAll
            return SpacePermission.publicToAll;
          }
        );
      }
    } catch (e) {
      print('获取空间权限失败: $e');
      // 异常时默认为publicToAll
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
