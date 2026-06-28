import 'package:flowy_infra/size.dart';

class HomeSizes {
  static const double menuAddButtonHeight = 60;
  static const double topBarHeight = 48;
  // macOS 窗口左上角红绿灯（关闭/最小化/最大化）按钮所占的垂直高度。
  // 收起左侧边栏后，中间栏顶端需下移此值，避免与这些窗口按钮重叠。
  // 仅 macOS 使用；Windows/Linux 的窗口控制按钮不在左上角，无需此偏移。
  static const double macOSTrafficLightsTopInset = 28;
  static const double editPanelTopBarHeight = 60;
  static const double editPanelWidth = 420;
  static const double notificationPanelWidth = 320;
  static const double tabBarHeight = 42;
  static const double tabBarWidth = 216;
  static const double dialogMaxWidth = 420;
  static const double dialogMaxHeight = 272;
  static const double okCancelDialogMaxWidth = 520;
  static double get workspaceSectionHeight => 38 * Sizes.hitScale;
  static double get searchSectionHeight => 36 * Sizes.hitScale;
  static double get newPageSectionHeight => 36 * Sizes.hitScale;
  static double get topActionBarHeight => 40 * Sizes.hitScale;
  static double get topActionBarItemExtent => 36 * Sizes.hitScale;
  static const double minimumSidebarWidth = 224;
  static const double maximumSidebarResizeOffset = 112;
  static const double maximumSidebarWidth =
      minimumSidebarWidth + maximumSidebarResizeOffset;
  static const double minimumSpaceHubMiddlePaneWidth = 182;
  static const double defaultSpaceHubMiddlePaneWidth = 220;
  static const double spaceHubDividerWidth = 4;
  static const double spaceHubTopTabsLeadingWidth =
      defaultSpaceHubMiddlePaneWidth + spaceHubDividerWidth;
  static const double minimumThirdPaneActionPeekWidth = 640;
  static const double minimumWindowShellSafetyWidth = 200;
  static const double minimumSpaceHubContentPeekWidth =
      minimumThirdPaneActionPeekWidth;
  // App-level minimum width: first sidebar + second pane + enough third-pane
  // room for the top-right action icons, plus dividers and title-bar slack.
  // App zhengti zuixiao kuandu: di yi lan + di er lan + di san lan you shang
  // jiao an niu qu + fenge xian he bianju yuliang.
  static const double minimumAppWindowWidth = maximumSidebarWidth +
      minimumSpaceHubMiddlePaneWidth +
      minimumThirdPaneActionPeekWidth +
      spaceHubDividerWidth +
      minimumWindowShellSafetyWidth;
  static const double minimumThreePaneWindowWidth = minimumAppWindowWidth;
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
  static const double leftPadding = 6.0;
  static double get viewHeight => 32 * Sizes.hitScale;

  // mobile, m represents mobile
  static const double mViewHeight = 48.0;
  static const double mViewButtonDimension = 34.0;
  static const double mHorizontalPadding = 20.0;
  static const double mVerticalPadding = 12.0;
}
