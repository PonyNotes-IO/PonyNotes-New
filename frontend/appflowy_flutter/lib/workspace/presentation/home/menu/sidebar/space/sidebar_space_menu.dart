import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/create_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/buttons/primary_button.dart';
import 'package:flowy_infra_ui/widget/buttons/secondary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarSpaceMenu extends StatelessWidget {
  const SidebarSpaceMenu({
    super.key,
    required this.showCreateButton,
  });

  final bool showCreateButton;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpaceBloc, SpaceState>(
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VSpace(4.0),
            for (final space in state.spaces)
              SizedBox(
                height: HomeSpaceViewSizes.viewHeight,
                child: SidebarSpaceMenuItem(
                  space: space,
                  isSelected: state.currentSpace?.id == space.id,
                ),
              ),
            if (showCreateButton) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: FlowyDivider(),
              ),
              const SizedBox(
                height: HomeSpaceViewSizes.viewHeight,
                child: _CreateSpaceButton(),
              ),
            ],
          ],
        );
      },
    );
  }
}

class SidebarSpaceMenuItem extends StatefulWidget {
  const SidebarSpaceMenuItem({
    super.key,
    required this.space,
    required this.isSelected,
  });

  final ViewPB space;
  final bool isSelected;

  @override
  State<SidebarSpaceMenuItem> createState() => _SidebarSpaceMenuItemState();
}

class _SidebarSpaceMenuItemState extends State<SidebarSpaceMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: BlocBuilder<SpaceBloc, SpaceState>(
        builder: (context, state) {
          final pending = state.joinRequestPending[space.id] ?? false;
          return FlowyButton(
            text: Row(
              children: [
                Flexible(
                  child: FlowyText.regular(
                    space.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const HSpace(6.0),
                if (space.spacePermission == SpacePermission.private)
                  FlowyTooltip(
                    message: LocaleKeys.space_privatePermissionDescription.tr(),
                    child: const FlowySvg(
                      FlowySvgs.space_lock_s,
                    ),
                  ),
              ],
            ),
            iconPadding: 10,
            leftIcon: SpaceIcon(
              dimension: 20,
              space: space,
              svgSize: 12.0,
              cornerRadius: 6.0,
            ),
            leftIconSize: const Size.square(20),
            rightIcon: widget.isSelected
                ? const FlowySvg(
                    FlowySvgs.workspace_selected_s,
                    blendMode: null,
                  )
                : (pending
                    ? Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FlowyText.regular('已申请', fontSize: 12),
                          ),
                          const HSpace(6.0),
                          GestureDetector(
                            onTap: () {
                              context.read<SpaceBloc>().add(SpaceEvent.cancelJoinRequest(spaceId: space.id));
                            },
                            child: const FlowySvg(FlowySvgs.close_s),
                          ),
                        ],
                      )
                    : (_isHovered ? _buildActionButton(context, space) : null)),
            onTap: () {
              context.read<SpaceBloc>().add(SpaceEvent.open(space: space));
              PopoverContainer.of(context).close();
            },
          );
        },
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, ViewPB space) {
    // Decide label/action based on permission
    switch (space.spacePermission) {
      case SpacePermission.publicToAll:
        return GestureDetector(
          onTap: () {
            _showJoinDialog(context, space, isRequest: false);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FlowySvg(
              FlowySvgs.space_add_s,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      case SpacePermission.closed:
        return GestureDetector(
          onTap: () {
            _showJoinDialog(context, space, isRequest: true);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FlowySvg(
              FlowySvgs.space_permission_dropdown_s,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      case SpacePermission.private:
        return const SizedBox.shrink();
    }
  }

  void _showJoinDialog(BuildContext context, ViewPB space, {required bool isRequest}) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowyText.medium(isRequest ? '申请加入' : '加入空间', fontSize: 16),
                const VSpace(12),
                FlowyText.regular(
                  isRequest
                      ? '此空间为封闭式，提交加入请求后需要管理员审批。'
                      : '确定要加入此开放式协作区吗？',
                  fontSize: 14,
                ),
                const VSpace(16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SecondaryTextButton(
                      LocaleKeys.button_cancel.tr(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const HSpace(12),
                    PrimaryTextButton(
                      LocaleKeys.button_ok.tr(),
                      onPressed: () {
                        // TODO: call backend join / request API
                        showToastNotification(message: isRequest ? '已发送加入请求' : '已加入空间（模拟）');
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CreateSpaceButton extends StatelessWidget {
  const _CreateSpaceButton();

  @override
  Widget build(BuildContext context) {
    return FlowyButton(
      text: FlowyText.regular(LocaleKeys.space_createNewSpace.tr()),
      iconPadding: 10,
      leftIcon: const FlowySvg(
        FlowySvgs.space_add_s,
      ),
      onTap: () {
        PopoverContainer.of(context).close();
        _showCreateSpaceDialog(context);
      },
    );
  }

  void _showCreateSpaceDialog(BuildContext context) {
    final spaceBloc = context.read<SpaceBloc>();
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: BlocProvider.value(
            value: spaceBloc,
            child: const CreateSpacePopup(),
          ),
        );
      },
    );
  }
}
