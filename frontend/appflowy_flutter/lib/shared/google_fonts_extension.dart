import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_ui/platform_font.dart';
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
      // Callers also use this style to identify font picker options. Keep the
      // default sentinel here; resolve the platform default when rendering.
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      fontFamilyFallback: platformFontFamilyFallback,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: fontColor,
      letterSpacing: letterSpacing,
      height: lineHeight,
    );
  } else {
    try {
      final style = GoogleFonts.getFont(
        fontFamily,
        fontWeight: fontWeight,
        fontSize: fontSize,
        color: fontColor,
        letterSpacing: letterSpacing,
        height: lineHeight,
      );
      final fallback = platformFontFamilyFallback;
      return fallback == null
          ? style
          : style.copyWith(
              fontFamilyFallback: [
                ...?style.fontFamilyFallback,
                ...fallback,
              ],
            );
    } catch (_) {}
  }

  return TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: platformFontFamilyFallback,
    fontWeight: fontWeight,
    fontSize: fontSize,
    color: fontColor,
    letterSpacing: letterSpacing,
    height: lineHeight,
  );
}
