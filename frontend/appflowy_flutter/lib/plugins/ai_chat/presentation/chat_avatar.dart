import 'dart:io';
import 'package:flutter/material.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/util/built_in_svgs.dart';
import 'package:appflowy/util/color_generator/color_generator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:string_validator/string_validator.dart';

import 'layout_define.dart';

class ChatAIAvatar extends StatelessWidget {
  const ChatAIAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesktopAIChatSizes.avatarSize,
      height: DesktopAIChatSizes.avatarSize,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      foregroundDecoration: ShapeDecoration(
        shape: CircleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: const CircleAvatar(
        backgroundColor: Colors.transparent,
        child: FlowySvg(
          FlowySvgs.app_logo_s,
          size: Size.square(16),
          blendMode: null,
        ),
      ),
    );
  }
}

class ChatUserAvatar extends StatelessWidget {
  const ChatUserAvatar({
    super.key,
    required this.iconUrl,
    required this.name,
    this.defaultName,
  });

  final String iconUrl;
  final String name;
  final String? defaultName;

  @override
  Widget build(BuildContext context) {
    late final Widget child;
    if (iconUrl.isEmpty) {
      child = _buildEmptyAvatar(context);
    } else if (isURL(iconUrl)) {
      child = _buildNetworkAvatar(context);
    } else if (_isLocalFile(iconUrl)) {
      child = _buildLocalAvatar(context);
    } else {
      child = _buildEmojiAvatar(context);
    }
    return Container(
      width: DesktopAIChatSizes.avatarSize,
      height: DesktopAIChatSizes.avatarSize,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      foregroundDecoration: ShapeDecoration(
        shape: CircleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: child,
    );
  }

  bool _isLocalFile(String url) {
    return !isURL(url) && File(url).existsSync();
  }

  Widget _buildNetworkAvatar(BuildContext context) {
    return Image.network(
      iconUrl,
      fit: BoxFit.cover,
      width: DesktopAIChatSizes.avatarSize,
      height: DesktopAIChatSizes.avatarSize,
      errorBuilder: (context, error, stackTrace) =>
          _buildEmptyAvatar(context),
    );
  }

  Widget _buildLocalAvatar(BuildContext context) {
    return Image.file(
      File(iconUrl),
      fit: BoxFit.cover,
      width: DesktopAIChatSizes.avatarSize,
      height: DesktopAIChatSizes.avatarSize,
      errorBuilder: (context, error, stackTrace) =>
          _buildEmptyAvatar(context),
    );
  }

  Widget _buildEmptyAvatar(BuildContext context) {
    final String nameOrDefault = _userName(name, defaultName);

    final Color color = ColorGenerator(name).toColor();
    const initialsCount = 2;

    // Taking the first letters of the name components and limiting to 2 elements
    final nameInitials = nameOrDefault
        .split(' ')
        .where((element) => element.isNotEmpty)
        .take(initialsCount)
        .map((element) => element[0].toUpperCase())
        .join();

    return ColoredBox(
      color: color,
      child: Center(
        child: FlowyText.regular(
          nameInitials,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildEmojiAvatar(BuildContext context) {
    return builtInSVGIcons.contains(iconUrl)
        ? FlowySvg(
            FlowySvgData('emoji/$iconUrl'),
            blendMode: null,
          )
        : FlowyText.emoji(
            iconUrl,
            fontSize: 24, // cannot reduce
            optimizeEmojiAlign: true,
          );
  }

  /// Return the user name.
  ///
  /// If the user name is empty, return the default user name.
  String _userName(String name, String? defaultName) =>
      name.isEmpty ? (defaultName ?? LocaleKeys.defaultUsername.tr()) : name;
}
