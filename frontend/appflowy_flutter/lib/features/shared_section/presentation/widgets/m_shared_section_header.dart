import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class MSharedSectionHeader extends StatelessWidget {
  const MSharedSectionHeader({
    super.key,
    required this.isExpanded,
    required this.onTap,
  });

  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
          Expanded(
            child: FlowyButton(
              text: FlowyText.medium(
                LocaleKeys.shareSection_shared.tr(),
                lineHeight: 1.15,
                fontSize: 16.0,
              ),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              expandText: false,
              iconPadding: 2,
              mainAxisAlignment: MainAxisAlignment.start,
              rightIcon: AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: isExpanded ? 0 : -0.25,
                child: const FlowySvg(FlowySvgs.m_spaces_expand_s),
              ),
              onTap: onTap,
            ),
          ),
          const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
        ],
      ),
    );
  }
}
