import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_section_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_ai_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_calendar_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_home_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_settings_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_favorite_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_share_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_publish_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_file_library_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_inbox_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_template_new_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_trash_item.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarFolder extends StatelessWidget {
  const SidebarFolder({
    super.key,
    this.isHoverEnabled = true,
    required this.userProfile,
  });

  final bool isHoverEnabled;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    Log.debug('SidebarFolder.build() called');
    const sectionPadding = 4.0;
    return ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (context, value, child) {
        Log.debug('SidebarFolder building menu items');
        return Column(
          children: [
            const VSpace(sectionPadding),
            // home button
            const SidebarHomeButton(),
            // AI button
            const VSpace(sectionPadding),
            const SidebarAiButton(),
            // calendar button
            const VSpace(sectionPadding),
            const SidebarCalendarButton(),
            // inbox button
            const VSpace(sectionPadding),
            const SidebarInboxButton(),
            // favorite
            const VSpace(sectionPadding),
            const SidebarFavoriteButton(),
            // BlocBuilder<SidebarSectionsBloc, SidebarSectionsState>(
            //   builder: (context, state) {
            //     // 在非协作工作空间模式下显示个人空间（重命名为我的空间）
            //     final isCollaborativeWorkspace =
            //         context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn;
            //
            //     if (!isCollaborativeWorkspace) {
            //       return PersonalSectionFolder(
            //         views: state.section.publicViews,
            //       );
            //     }
            //     return const SizedBox.shrink();
            //   },
            // ),
            // public or private (只在协作工作空间显示)
            BlocBuilder<SidebarSectionsBloc, SidebarSectionsState>(
              builder: (context, state) {
                // only show public and private section if the workspace is collaborative and not local
                final isCollaborativeWorkspace =
                    context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn;

                // only show public and private section if the workspace is collaborative
                return Column(
                  children: isCollaborativeWorkspace
                      ? [
                    // private
                    PrivateSectionFolder(
                      views: state.section.privateViews,
                    ),
                    // public
                    PublicSectionFolder(views: state.section.publicViews),
                  ]
                      : [
                  PersonalSectionFolder(
                          views: state.section.publicViews,
                        ),
                  ], // 非协作工作空间不显示底部的个人空间（已移至上方）
                );
              },
            ),
            // 共享
            const SidebarShareButton(),
            // 发布
            const VSpace(sectionPadding),
            const SidebarPublishButton(),
            // 文件库
            const VSpace(sectionPadding),
            const SidebarFileLibraryButton(),
            // 模板
            // const VSpace(4.0),
            // const SidebarTemplateNewButton(),
            // 回收站
            const VSpace(sectionPadding),
            const SidebarTrashItem(),
            // 设置
            const VSpace(sectionPadding),
            const SidebarSettingsButton(),
            const VSpace(200),
          ],
        );
      },
    );
  }
}

class PrivateSectionFolder extends SectionFolder {
  PrivateSectionFolder({super.key, required super.views})
      : super(
          title: LocaleKeys.space_mySpace.tr(),
          spaceType: FolderSpaceType.private,
          expandButtonTooltip: LocaleKeys.sideBar_clickToHidePrivate.tr(),
          addButtonTooltip: LocaleKeys.sideBar_addAPageToPrivate.tr(),
        );
}

class PublicSectionFolder extends SectionFolder {
  PublicSectionFolder({super.key, required super.views})
      : super(
          title: LocaleKeys.sideBar_workspace.tr(),
          spaceType: FolderSpaceType.public,
          expandButtonTooltip: LocaleKeys.sideBar_clickToHideWorkspace.tr(),
          addButtonTooltip: LocaleKeys.sideBar_addAPageToWorkspace.tr(),
        );
}

class PersonalSectionFolder extends SectionFolder {
  PersonalSectionFolder({super.key, required super.views})
      : super(
          title: LocaleKeys.space_mySpace.tr(),
          spaceType: FolderSpaceType.public,
          expandButtonTooltip: LocaleKeys.sideBar_clickToHidePersonal.tr(),
          addButtonTooltip: LocaleKeys.sideBar_addAPage.tr(),
        );
}
