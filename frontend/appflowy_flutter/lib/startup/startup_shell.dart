import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A lightweight first Flutter frame that bridges Android's native splash and
/// the app's dependency-heavy startup sequence.
class StartupShell extends StatefulWidget {
  const StartupShell({super.key});

  @override
  State<StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<StartupShell>
    with SingleTickerProviderStateMixin {
  static const _brandColor = Color(0xFFFF3800);
  static const _darkBackground = Color(0xFF121212);

  static bool get _isMobileTarget =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // On mobile we never render the entrance animation, so creating an
  // AnimationController would start a ticker whose only lifetime is the brief
  // window before this widget is replaced. Disposing that unused ticker from
  // inside `dispose()` walks the (already deactivated) TickerMode ancestor and
  // throws. Skip the controller entirely on mobile.
  late final AnimationController? _entranceController = () {
    if (_isMobileTarget) {
      return null;
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    controller.forward();
    return controller;
  }();

  @override
  void dispose() {
    _entranceController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    if (_isMobileTarget) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox.expand(
            child: Image.asset(
              isDark
                  ? 'assets/images/launch_screen_dark.png'
                  : 'assets/images/launch_screen_light.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    final entrance = CurvedAnimation(
      parent: _entranceController!,
      curve: Curves.easeOutCubic,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: isDark ? _darkBackground : Colors.white,
        body: Center(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.72, end: 1).animate(entrance),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(entrance),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  FlowySvg(
                    FlowySvgs.app_logo_xl,
                    size: Size.square(76),
                    blendMode: null,
                  ),
                  SizedBox(height: 24),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: _brandColor,
                      strokeWidth: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}