import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/edit_access_level_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/guest_tag.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/turn_into_member_widget.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Widget to display a single shared user row as per the UI design, using AFMenuItem.
class SharedUserWidget extends StatelessWidget {
  const SharedUserWidget({
    super.key,
    required this.user,
    required this.currentUser,
    this.isInPublicPage = false,
    this.callbacks,
    this.compact = false,
  });

  final bool compact;
  final SharedUser user;
  final SharedUser currentUser;
  final AccessLevelListCallbacks? callbacks;
  final bool? isInPublicPage;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            AFAvatar(name: user.name, url: user.avatarUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildTitle(context), _buildSubtitle(context)],
              ),
            ),
            _buildTrailing(context),
          ],
        ),
      );
    }

    return AFMenuItem(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.s,
        horizontal: theme.spacing.m,
      ),
      leading: AFAvatar(
        name: user.name,
        url: user.avatarUrl,
      ),
      title: _buildTitle(context),
      subtitle: _buildSubtitle(context),
      trailing: _buildTrailing(context),
      onTap: () {
        // callbacks?.onSelectAccessLevel.call(user, user.accessLevel);
      },
    );
  }

  bool get isCurrentUser => !compact
      ? user.userId == currentUser.userId
      : (user.userId?.isNotEmpty == true &&
              user.userId == currentUser.userId) ||
          (user.uid?.isNotEmpty == true && user.uid == currentUser.uid) ||
          (user.email.trim().isNotEmpty &&
              user.email.trim().toLowerCase() ==
                  currentUser.email.trim().toLowerCase());

  Widget _buildTitle(
    BuildContext context,
  ) {
    final theme = AppFlowyTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            user.name,
            style: theme.textStyle.body.standard(
              color: theme.textColorScheme.primary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // if the user is the current user, show '(You)'
        if (isCurrentUser) ...[
          HSpace(theme.spacing.xs),
          Flexible(
            child: Text(
              LocaleKeys.shareTab_you.tr(),
              style: theme.textStyle.caption.standard(
                color: theme.textColorScheme.secondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        // if the user is a guest, show 'Guest'
        if (user.role == ShareRole.guest) ...[
          HSpace(theme.spacing.m),
          const GuestTag(),
        ],
      ],
    );
  }

  Widget _buildSubtitle(
    BuildContext context,
  ) {
    final theme = AppFlowyTheme.of(context);
    final subtitle = compact && user.phone?.isNotEmpty == true
        ? user.phone!
        : user.email.trim().isNotEmpty
            ? user.email
            : user.uid ?? '';

    if (subtitle.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      subtitle,
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      style: theme.textStyle.caption.standard(
        color: theme.textColorScheme.secondary,
      ),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final currentAccessLevel = currentUser.accessLevel;

    Widget disabledAccessButton() => AFGhostTextButton.disabled(
          text: user.accessLevel.title,
          textStyle: theme.textStyle.body.standard(
            color: theme.textColorScheme.secondary,
          ),
        );

    Widget editAccessWidget(List<ShareAccessLevel> supported) =>
        EditAccessLevelWidget(
          compact: compact,
          selectedAccessLevel: user.accessLevel,
          supportedAccessLevels: supported,
          additionalUserManagementOptions: [
            AdditionalUserManagementOptions.removeAccess,
          ],
          callbacks: callbacks ?? AccessLevelListCallbacks.none(),
        );

    // In public page, member/owner permissions are fixed
    if (isInPublicPage == true &&
        (user.role == ShareRole.member || user.role == ShareRole.owner)) {
      return disabledAccessButton();
    }

    if (compact && user.role == ShareRole.owner) return disabledAccessButton();

    // Full access user can turn a guest into a member
    if (user.role == ShareRole.guest &&
        currentAccessLevel == ShareAccessLevel.fullAccess) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TurnIntoMemberWidget(
            onTap: () => callbacks?.onTurnIntoMember.call(),
          ),
          editAccessWidget([
            ShareAccessLevel.readOnly,
            ShareAccessLevel.readAndWrite,
          ]),
        ],
      );
    }

    // Self-management
    if (isCurrentUser) {
      if (currentAccessLevel == ShareAccessLevel.readOnly ||
          currentAccessLevel == ShareAccessLevel.readAndWrite) {
        // Can only remove self
        return editAccessWidget([]);
      } else if (currentAccessLevel == ShareAccessLevel.fullAccess) {
        // Full access user cannot change own access
        return disabledAccessButton();
      }
    }

    // Owner's permissions can never be edited by others
    if (user.role == ShareRole.owner && isCurrentUser) {
      return disabledAccessButton();
    }

    // Managing others
    if (currentAccessLevel == ShareAccessLevel.readOnly ||
        currentAccessLevel == ShareAccessLevel.readAndWrite) {
      // Cannot change others' access
      return disabledAccessButton();
    } else {
      // Full access user can manage others
      final supportedAccessLevels = [
        ShareAccessLevel.readOnly,
        ShareAccessLevel.readAndWrite,
        ShareAccessLevel.fullAccess,
      ];
      return editAccessWidget(supportedAccessLevels);
    }
  }
}
