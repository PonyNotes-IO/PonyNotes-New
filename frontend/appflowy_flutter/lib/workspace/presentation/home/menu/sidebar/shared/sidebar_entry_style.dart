import 'package:flutter/material.dart';

const sidebarSearchTopGap = 6.0;
const sidebarSearchToEntryGroupGap = 0.0;
const sidebarEntryGroupTopGap = 0.0;
const sidebarPrimaryEntryGap = 2.0;

const sidebarEntryPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 8,
);
const sidebarHomeEntryPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 8,
);
const sidebarEntryIconTextGap = 7.0;

TextStyle? sidebarEntryTextStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
      );
}
