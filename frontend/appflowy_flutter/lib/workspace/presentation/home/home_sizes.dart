import 'package:flowy_infra/size.dart';

class HomeSizes {
  static const double menuAddButtonHeight = 60;
  static const double topBarHeight = 48;
  static const double editPanelTopBarHeight = 60;
  static const double editPanelWidth = 420;
  static const double notificationPanelWidth = 392;
  static const double tabBarHeight = 42;
  static const double tabBarWidth = 216;
  static const double dialogMaxWidth = 420;
  static const double dialogMaxHeight = 272;
  static const double okCancelDialogMaxWidth = 520;
  static double get workspaceSectionHeight => 42 * Sizes.hitScale;
  static double get searchSectionHeight => 40 * Sizes.hitScale;
  static double get newPageSectionHeight => 40 * Sizes.hitScale;
  static double get topActionBarHeight => 40 * Sizes.hitScale;
  static double get topActionBarItemExtent => 36 * Sizes.hitScale;
  static const double minimumSidebarWidth = 224;
  static const double maximumSidebarResizeOffset = 112;
  static const double maximumSidebarWidth =
      minimumSidebarWidth + maximumSidebarResizeOffset;
}

class HomeInsets {
  static const double topBarTitleHorizontalPadding = 16;
  static const double topBarTitleVerticalPadding = 8;
  static const double sidebarHorizontalPadding = 12;
  static const double sidebarBottomPadding = 10;
  static const double dialogHorizontalPadding = 24;
  static const double dialogVerticalPadding = 20;
}

class HomeRadii {
  static const double dialog = 14;
  static const double floatingSurface = 999;
  static const double input = 8;
}

class HomeSpaceViewSizes {
  static const double leftPadding = 16.0;
  static double get viewHeight => 40 * Sizes.hitScale;

  // mobile, m represents mobile
  static const double mViewHeight = 48.0;
  static const double mViewButtonDimension = 34.0;
  static const double mHorizontalPadding = 20.0;
  static const double mVerticalPadding = 12.0;
}
