import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _defaultFontFamilies = [
  defaultFontFamily,
  builtInCodeFontFamily,
];

// if the font family is not available, google fonts packages will throw an exception
// this method will return the system font family if the font family is not available
TextStyle getGoogleFontSafely(
  String fontFamily, {
  FontWeight? fontWeight,
  double? fontSize,
  Color? fontColor,
  double? letterSpacing,
  double? lineHeight,
}) {
  // if the font family is the built-in font family or system Chinese font, use it directly
  if (_defaultFontFamilies.contains(fontFamily) ||
      systemChineseFontKeys.contains(fontFamily)) {
    return TextStyle(
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: fontColor,
      letterSpacing: letterSpacing,
      height: lineHeight,
    );
  } else {
    try {
      return GoogleFonts.getFont(
        fontFamily,
        fontWeight: fontWeight,
        fontSize: fontSize,
        color: fontColor,
        letterSpacing: letterSpacing,
        height: lineHeight,
      );
    } catch (_) {}
  }

  return TextStyle(
    fontFamily: fontFamily,
    fontWeight: fontWeight,
    fontSize: fontSize,
    color: fontColor,
    letterSpacing: letterSpacing,
    height: lineHeight,
  );
}
