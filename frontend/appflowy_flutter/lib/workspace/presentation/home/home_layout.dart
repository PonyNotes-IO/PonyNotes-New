import 'dart:io' show Platform;
import 'dart:math';

import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:flowy_infra/size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:sized_context/sized_context.dart';

import 'home_sizes.dart';

class HomeLayout {
  HomeLayout(BuildContext context) {
    final homeSetting = context.read<HomeSettingBloc>().state;
    showEditPanel = homeSetting.panelContext != null;

    menuWidth = min(
      max(
        HomeSizes.minimumSidebarWidth + homeSetting.resizeOffset,
        HomeSizes.minimumSidebarWidth,
      ),
      HomeSizes.maximumSidebarWidth,
    );

    final screenWidthPx = context.widthPx;
    context
        .read<HomeSettingBloc>()
        .add(HomeSettingEvent.checkScreenSize(screenWidthPx));

    showMenu = homeSetting.menuStatus == MenuStatus.expanded;
    menuIsDrawer = showMenu &&
        !Platform.isWindows &&
        context.widthPx < PageBreaks.tabletLandscape;

    showNotificationPanel = !homeSetting.isNotificationPanelCollapsed;

    homePageLOffset = (showMenu && !menuIsDrawer) ? menuWidth : 0.0;

    // ===== 窗口控制按钮避让：Windows 与 macOS 分别处理 =====
    // macOS：关闭/最小化/最大化（红绿灯）按钮固定在窗口【左上角】。
    //   收起左侧边栏(showMenu == false)后，中间栏移到窗口左上角，其顶端
    //   会与红绿灯按钮重叠。因此 macOS 下收起侧栏时需要两种避让：
    //   · menuSpacing    —— 顶部 Tab 栏的水平左间距（横向避让，仅在显示 Tab 栏时有效）；
    //   · menuTopSpacing —— 中间栏内容顶端的垂直下移量（纵向避让，无论是否显示 Tab 栏都生效）。
    // Windows：窗口控制按钮在【右上角】且有独立系统标题栏，左上角无按钮，
    //   因此完全不需要避让，相关间距全部为 0。
    if (Platform.isMacOS) {
      menuSpacing = !showMenu ? 80.0 : 0.0;
      menuTopSpacing =
          !showMenu ? HomeSizes.macOSTrafficLightsTopInset : 0.0;
    } else {
      // Windows / Linux：左上角不存在窗口按钮，无需避让。
      menuSpacing = 0.0;
      menuTopSpacing = 0.0;
    }
    animDuration = homeSetting.resizeType.duration();
    editPanelWidth = HomeSizes.editPanelWidth;
    notificationPanelWidth = MediaQuery.of(context).size.width -
        (showEditPanel ? editPanelWidth : 0);
    homePageROffset = showEditPanel ? editPanelWidth : 0;
  }

  late bool showEditPanel;
  late double menuWidth;
  late bool showMenu;
  late bool menuIsDrawer;
  late bool showNotificationPanel;
  late double homePageLOffset;
  late double menuSpacing;
  // macOS 收起侧栏时，中间栏内容顶端的垂直下移量（避免与左上角红绿灯按钮重叠）；
  // Windows/Linux 恒为 0。
  late double menuTopSpacing;
  late Duration animDuration;
  late double editPanelWidth;
  late double notificationPanelWidth;
  late double homePageROffset;
}
