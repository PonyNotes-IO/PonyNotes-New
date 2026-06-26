import 'package:flutter/material.dart';

const sidebarSearchTopGap = 6.0;
const sidebarSearchToEntryGroupGap = 0.0;
const sidebarEntryGroupTopGap = 4.0;
const sidebarPrimaryEntryGap = 2.0;

const sidebarEntryPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 6,
);

const sidebarEntryPaddingNoIcon = EdgeInsets.symmetric(
  horizontal: 2,
  vertical: 6,
);
const sidebarHomeEntryPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 6,
);
const sidebarEntryIconTextGap = 7.0;

TextStyle? sidebarEntryTextStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w800,
      );
}
