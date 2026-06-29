import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';

const sidebarSearchTopGap = 6.0;
const sidebarSearchToEntryGroupGap = 0.0;
const sidebarEntryGroupTopGap = 4.0;
const sidebarPrimaryEntryGap = 1.0;

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

TextStyle sidebarEntryTextStyle(BuildContext context) {
  return TextStyle(
    color: Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF5F5E5A)
        : const Color(0xFFBCBAB7),
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
}

TextStyle sidebarTextStyle(BuildContext context) {
  return TextStyle(
    color: Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF91918E)
        : const Color(0xFFBBC3CD),
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}

ViewItemStyle sidebarViewItemStyle(BuildContext context) => ViewItemStyle(
  selectedTextColor: Theme.of(context).brightness == Brightness.light
      ? const Color(0xFF5F5E5A)
      : const Color(0xFFFFFFFF),
  selectedBackgroundColor: Theme.of(context).brightness == Brightness.light
      ? Color(0xFFF1F0EF) : const Color(0xFF383838),
  hoverColor: Theme.of(context).brightness == Brightness.light
      ? Color(0xFFF1F0EF) : Color(0xFF2C2C2C),
);