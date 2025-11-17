import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ShareTab extends StatefulWidget {
  const ShareTab({
    super.key,
    required this.workspaceId,
    required this.pageId,
    required this.workspaceName,
    required this.workspaceIcon,
    required this.isInProPlan,
    required this.onUpgradeToPro,
  });

  final String workspaceId;
  final String pageId;

  // these 2 values should be provided by the share tab bloc
  final String workspaceName;
  final String workspaceIcon;

  final bool isInProPlan;
  final VoidCallback onUpgradeToPro;

  @override
  State<ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<ShareTab> {
  final TextEditingController controller = TextEditingController();
  late final ShareTabBloc shareTabBloc;

  @override
  void initState() {
    super.initState();

    shareTabBloc = context.read<ShareTabBloc>();
  }

  @override
  void dispose() {
    controller.dispose();
    shareTabBloc.add(ShareTabEvent.clearState());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return BlocConsumer<ShareTabBloc, ShareTabState>(
      listener: (context, state) {
        _onListenShareWithUserState(context, state);
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const SizedBox.shrink();
        }

        // final currentUser = state.currentUser;
        // final accessLevel = state.users
        //     .firstWhereOrNull(
        //       (user) => user.email == currentUser?.email,
        //     )
        //     ?.accessLevel;
        // final isFullAccess = accessLevel == ShareAccessLevel.fullAccess;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // share page with user by email
            // only user with full access can invite others
            VSpace(theme.spacing.l),
            Row(
              children: [
                FlowyText("当前文档为私密，仅自己和协作者可访问"),
              ],
            ),
            VSpace(theme.spacing.m),
            _buildLinkAndCopyButton(state.shareLink),

            // ShareWithUserWidget(
            //   controller: controller,
            //   disabled: !isFullAccess,
            //   onInvite: (emails) => _onSharePageWithUser(
            //     context,
            //     emails: emails,
            //     accessLevel: ShareAccessLevel.readOnly,
            //   ),
            // ),

            // if (!widget.isInProPlan && !state.hasClickedUpgradeToPro) ...[
            //   UpgradeToProWidget(
            //     onClose: () {
            //       context.read<ShareTabBloc>().add(
            //             ShareTabEvent.upgradeToProClicked(),
            //           );
            //     },
            //     onUpgrade: widget.onUpgradeToPro,
            //   ),
            // ],

            // shared users
            // if (state.users.isNotEmpty) ...[
            //   VSpace(theme.spacing.l),
            //   PeopleWithAccessSection(
            //     isInPublicPage: state.sectionType == SharedSectionType.public,
            //     currentUserEmail: state.currentUser?.email ?? '',
            //     users: state.users,
            //     callbacks: _buildPeopleWithAccessSectionCallbacks(context),
            //   ),
            // ],

            // general access
            // if (state.sectionType == SharedSectionType.public) ...[
            //   VSpace(theme.spacing.m),
            //   GeneralAccessSection(
            //     group: SharedGroup(
            //       id: widget.workspaceId,
            //       name: widget.workspaceName,
            //       icon: widget.workspaceIcon,
            //     ),
            //   ),
            // ],

            // copy link
            // VSpace(theme.spacing.xl),
            // CopyLinkWidget(shareLink: state.shareLink),
            // VSpace(theme.spacing.m),
          ],
        );
      },
    );
  }

  // Detailed per-user access management handlers are kept in the original
  // implementation (commented out above) and can be restored when the full
  // "People with access" section is re-enabled.

  void _onListenShareWithUserState(
    BuildContext context,
    ShareTabState state,
  ) {
    final shareResult = state.shareResult;
    if (shareResult != null) {
      shareResult.fold((success) {
        // clear the controller to avoid showing the previous emails
        controller.clear();

        showToastNotification(
          message: LocaleKeys.shareTab_invitationSent.tr(),
        );
      }, (error) {
        String message;
        switch (error.code) {
          case ErrorCode.InvalidGuest:
            message = LocaleKeys.shareTab_emailAlreadyInList.tr();
            break;
          case ErrorCode.FreePlanGuestLimitExceeded:
            message = LocaleKeys.shareTab_upgradeToProToInviteGuests.tr();
            break;
          case ErrorCode.PaidPlanGuestLimitExceeded:
            message = LocaleKeys.shareTab_maxGuestsReached.tr();
            break;
          default:
            message = error.msg;
        }
        showToastNotification(
          message: message,
          type: ToastificationType.error,
        );
      });
    }

    final removeResult = state.removeResult;
    if (removeResult != null) {
      removeResult.fold((success) {
        showToastNotification(
          message: LocaleKeys.shareTab_removedGuestSuccessfully.tr(),
        );
      }, (error) {
        showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        );
      });
    }

    final updateAccessLevelResult = state.updateAccessLevelResult;
    if (updateAccessLevelResult != null) {
      updateAccessLevelResult.fold((success) {
        showToastNotification(
          message: LocaleKeys.shareTab_updatedAccessLevelSuccessfully.tr(),
        );
      }, (error) {
        showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        );
      });
    }

    final turnIntoMemberResult = state.turnIntoMemberResult;
    if (turnIntoMemberResult != null) {
      turnIntoMemberResult.fold((success) {
        showToastNotification(
          message: LocaleKeys.shareTab_turnedIntoMemberSuccessfully.tr(),
        );
      }, (error) {
        showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        );
      });
    }
  }

  Widget _buildLinkAndCopyButton(String shareLink) {
    final theme = AppFlowyTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(theme.spacing.l),
      decoration: BoxDecoration(
        color: isDark
            ? theme.surfaceContainerColorScheme.layer01
            : Colors.white,
        borderRadius: BorderRadius.circular(theme.spacing.l),
        border: Border.all(
          color: theme.borderColorScheme.primary.withValues(alpha: 0.15),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.brandColorScheme.skyline,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: FlowySvg(
                FlowySvgs.share_tab_icon_s,
                color: Colors.white,
              ),
            ),
          ),
          HSpace(theme.spacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowyText.medium(
                  LocaleKeys.shareAction_shareTabTitle.tr(),
                  figmaLineHeight: 18.0,
                  color: theme.textColorScheme.primary,
                ),
                VSpace(theme.spacing.xs),
                FlowyText.regular(
                  LocaleKeys.shareAction_shareTabDescription.tr(),
                  fontSize: 13.0,
                  figmaLineHeight: 18.0,
                  color: Theme.of(context).hintColor,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          HSpace(theme.spacing.m),
          _RoundIconButton(
            icon: FlowySvgs.toolbar_link_m,
            tooltip: LocaleKeys.shareTab_copyLink.tr(),
            onTap: () {
              context.read<ShareTabBloc>().add(
                    ShareTabEvent.copyShareLink(link: shareLink),
                  );

              if (FlowyRunner.currentMode.isUnitTest) {
                return;
              }

              showToastNotification(
                message: LocaleKeys.shareTab_copiedLinkToClipboard.tr(),
              );
            },
          ),
          HSpace(theme.spacing.s),
          _RoundIconButton(
            icon: FlowySvgs.share_tab_icon_s,
            tooltip: LocaleKeys.shareAction_shareTabTitle.tr(),
            onTap: () {
              // Placeholder for future invite-collaborator action.
            },
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final FlowySvgData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final bgColor = theme.surfaceContainerColorScheme.layer02;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: FlowySvg(
              icon,
              color: theme.iconColorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
