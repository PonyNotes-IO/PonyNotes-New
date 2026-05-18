import 'package:flowy_infra/size.dart';

class HomeSizes {
  static const double menuAddButtonHeight = 60;
  static const double topBarHeight = 44;
  static const double editPanelTopBarHeight = 60;
  static const double editPanelWidth = 400;
  static const double notificationPanelWidth = 380;
  static const double tabBarHeight = 40;
  static const double tabBarWidth = 200;
  static double get workspaceSectionHeight => 40 * Sizes.hitScale;
  static double get searchSectionHeight => 38 * Sizes.hitScale;
  static double get newPageSectionHeight => 38 * Sizes.hitScale;
  static const double minimumSidebarWidth = 200;
  static const double maximumSidebarResizeOffset = 96;
  static const double maximumSidebarWidth =
      minimumSidebarWidth + maximumSidebarResizeOffset;
}

class HomeInsets {
  static const double topBarTitleHorizontalPadding = 12;
  static const double topBarTitleVerticalPadding = 12;
}

class HomeSpaceViewSizes {
  static const double leftPadding = 16.0;
  static double get viewHeight => 38 * Sizes.hitScale;

  // mobile, m represents mobile
  static const double mViewHeight = 48.0;
  static const double mViewButtonDimension = 34.0;
  static const double mHorizontalPadding = 20.0;
  static const double mVerticalPadding = 12.0;
}
