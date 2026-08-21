import 'package:appflowy/generated/flowy_svgs.g.dart';
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

  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final entrance = CurvedAnimation(
      parent: _entranceController,
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
