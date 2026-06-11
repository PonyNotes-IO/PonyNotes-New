import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart' hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarNewPageButton extends StatefulWidget {
  const SidebarNewPageButton({
    super.key,
  });

  @override
  State<SidebarNewPageButton> createState() => _SidebarNewPageButtonState();
}

class _SidebarNewPageButtonState extends State<SidebarNewPageButton> {
  @override
  void initState() {
    super.initState();
    createNewPageNotifier.addListener(_createNewPage);
  }

  @override
  void dispose() {
    createNewPageNotifier.removeListener(_createNewPage);
    super.dispose();
  }

  /// 当前用户是否为受限成员（Guest）
  /// 由 build() 中 context.watch 驱动重建
  late bool _isRestrictedMember;

  @override
  Widget build(BuildContext context) {
    try {
      _isRestrictedMember = context.watch<UserWorkspaceBloc>().state.currentUserRole == AFRolePB.Guest;
    } catch (_) {
      _isRestrictedMember = false;
    }
    // 受限成员按钮禁用（保留在 tree 中，context.watch 实时响应权限变化）
    final button = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: HomeSizes.newPageSectionHeight,
      child: FlowyButton(
        onTap: () async => _createNewPage(),
        mainAxisAlignment: MainAxisAlignment.start,
        leftIcon: const FlowySvg(
          FlowySvgs.new_app_m,
          blendMode: null,
        ),
        leftIconSize: const Size.square(24.0),
        margin: const EdgeInsets.only(left: 4.0),
        iconPadding: 8.0,
        text: FlowyText.regular(
          LocaleKeys.newPageText.tr(),
          lineHeight: 1.15,
        ),
      ),
    );

    if (_isRestrictedMember) {
      return IgnorePointer(
        child: Opacity(opacity: 0.3, child: button),
      );
    }
    return button;
  }

  Future<void> _createNewPage() async {
    // if the workspace is collaborative, create the view in the private section by default.
    final section = context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn
        ? ViewSectionPB.Private
        : ViewSectionPB.Public;
    final spaceState = context.read<SpaceBloc>().state;
    if (spaceState.spaces.isNotEmpty) {
      context.read<SpaceBloc>().add(
            SpaceEvent.createPage(
              name: ViewLayoutPB.Document.defaultName,
              index: 0,
              layout: ViewLayoutPB.Document,
              openAfterCreate: true,
            ),
          );
    } else {
      context.read<SidebarSectionsBloc>().add(
            SidebarSectionsEvent.createRootViewInSection(
              name: ViewLayoutPB.Document.defaultName,
              viewSection: section,
              index: 0,
            ),
          );
    }
  }
}
