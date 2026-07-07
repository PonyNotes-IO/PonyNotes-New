import 'dart:io';

import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.iconUrl,
    required this.name,
    required this.size,
    this.isHovering = false,
    this.decoration,
    this.userProfilePB,
  });

  final String iconUrl;
  final String name;

  final AFAvatarSize size;
  final Decoration? decoration;

  // If true, a border will be applied on top of the avatar
  final bool isHovering;

  final UserProfilePB? userProfilePB;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return SizedBox.square(
      dimension: size.size,
      child: DecoratedBox(
        decoration: decoration ??
            BoxDecoration(
              shape: BoxShape.circle,
              border: isHovering
                  ? Border.all(
                      color: theme.iconColorScheme.primary,
                      width: 4,
                    )
                  : null,
            ),
        child: _buildAvatar(),
      ),
    );
  }

  Widget _buildAvatar() {
    if (iconUrl.isEmpty) {
      return AFAvatar(
        name: name,
        size: size,
      );
    }

    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) {
      return ClipOval(
        child: FlowyNetworkImage(
          url: iconUrl,
          userProfilePB: userProfilePB,
          width: size.size,
          height: size.size,
          fit: BoxFit.cover,
          errorWidgetBuilder: (context, url, error) => AFAvatar(
            name: name,
            size: size,
          ),
        ),
      );
    } else {
      final file = File(iconUrl);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(
            file,
            width: size.size,
            height: size.size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => AFAvatar(
              name: name,
              size: size,
            ),
          ),
        );
      }
      return AFAvatar(
        name: name,
        size: size,
      );
    }
  }
}
