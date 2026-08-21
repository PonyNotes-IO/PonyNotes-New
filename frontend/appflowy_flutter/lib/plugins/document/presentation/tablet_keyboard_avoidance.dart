const double tabletKeyboardClearance = 24.0;

double tabletKeyboardScrollDelta({
  required double selectionBottom,
  required double viewportHeight,
  required double keyboardInset,
  double clearance = tabletKeyboardClearance,
}) {
  if (keyboardInset <= 0 || viewportHeight <= 0) {
    return 0;
  }

  final safeBottom = viewportHeight - keyboardInset - clearance;
  final delta = selectionBottom - safeBottom;
  return delta > 0 ? delta : 0;
}
