import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:appflowy/mobile/presentation/home/mobile_home_page.dart';
import 'package:appflowy/workspace/presentation/home/desktop_home_screen.dart';

extension NavigatorContext on BuildContext {
  void popToHome() {
    // 使用 GoRouter 的 go 方法导航到首页，而不是 popUntil
    // 这样可以避免路由栈为空的问题
    try {
      if (UniversalPlatform.isMobile) {
        // 移动端导航到 MobileHomeScreen
        go(MobileHomeScreen.routeName);
      } else {
        // 桌面端导航到 DesktopHomeScreen
        go(DesktopHomeScreen.routeName);
      }
    } catch (e) {
      // 如果 GoRouter 不可用，回退到 Navigator 方法
      // 但先检查路由栈是否为空
      final navigator = Navigator.of(this, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.popUntil((route) {
          if (route.settings.name == '/') {
            return true;
          }
          // 如果找不到 '/' 路由，至少保留一个路由
          return false;
        });
      } else {
        // 如果路由栈为空，使用 pushReplacement 导航到首页
        navigator.pushReplacementNamed('/');
      }
    }
  }
}
