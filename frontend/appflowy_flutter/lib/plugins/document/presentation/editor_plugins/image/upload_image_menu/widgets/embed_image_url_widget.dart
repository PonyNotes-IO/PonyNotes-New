import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/patterns/common_patterns.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flowy_infra/platform_extension.dart';

class EmbedImageUrlWidget extends StatefulWidget {
  const EmbedImageUrlWidget({
    super.key,
    required this.onSubmit,
  });

  final void Function(String url) onSubmit;

  @override
  State<EmbedImageUrlWidget> createState() => _EmbedImageUrlWidgetState();
}

class _EmbedImageUrlWidgetState extends State<EmbedImageUrlWidget> {
  bool isUrlValid = true;
  String inputText = '';

  @override
  Widget build(BuildContext context) {
    final textField = FlowyTextField(
      hintText: LocaleKeys.document_imageBlock_embedLink_placeholder.tr(),
      onChanged: (value) => inputText = value,
      onEditingComplete: submit,
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
          ),
      hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).hintColor,
            fontSize: 14,
          ),
    );
    return Column(
      children: [
        const VSpace(12),
        PlatformInfo.isDesktopOrTablet
            ? textField
            : SizedBox(
                height: 42,
                child: textField,
              ),
        if (!isUrlValid) ...[
          const VSpace(12),
          FlowyText(
            LocaleKeys.document_plugins_cover_invalidImageUrl.tr(),
            color: Theme.of(context).colorScheme.error,
          ),
        ],
        const VSpace(20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: FlowyButton(
            backgroundColor: Theme.of(context).colorScheme.primary,
            hoverColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
            decoration: PlatformInfo.isMobile
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius:
                        const BorderRadius.all(Radius.circular(100)),
                  )
                : null,
            text: Container(
              margin: const EdgeInsets.all(4.0),
              alignment: Alignment.center,
              child: FlowyText(
                LocaleKeys.document_imageBlock_embedLink_label.tr(),
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            onTap: submit,
          ),
        ),
        const VSpace(8),
      ],
    );
  }

  void submit() {
    if (checkUrlValidity(inputText)) {
      return widget.onSubmit(inputText);
    }

    setState(() => isUrlValid = false);
  }

  bool checkUrlValidity(String url) => imgUrlRegex.hasMatch(url);
}
