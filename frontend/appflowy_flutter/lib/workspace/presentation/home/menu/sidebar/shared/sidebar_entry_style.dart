import 'package:flutter/material.dart';

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
        ? const Color(0xFF2C2C2B)      // 亮色模式
        : const Color(0xFFBBC3CD),     // 暗黑模式
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
}

TextStyle sidebarTextStyle(BuildContext context) {
  return TextStyle(
    color: Theme
        .of(context)
        .brightness == Brightness.light
        ? const Color(0xFF5F5E5A) // 亮色模式
        : const Color(0xFFBBC3CD), // 暗黑模式
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}