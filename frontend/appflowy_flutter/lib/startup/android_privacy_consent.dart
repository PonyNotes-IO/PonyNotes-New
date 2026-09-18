import 'dart:async';

import 'package:appflowy/shared/adaptive_display.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/mobile_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_privacy_dialog.dart';

/// Only used by Android. The channel is available before plugin registration.
class AndroidPrivacyConsent {
  static const channel = MethodChannel('com.xiaomabiji.app.note/privacy');
  static bool acceptedThisLaunch = false;

  static bool takeFirstConsent() {
    final firstConsent = acceptedThisLaunch;
    acceptedThisLaunch = false;
    return firstConsent;
  }

  static Future<bool> ensureAccepted() async {
    if (await channel.invokeMethod<bool>('hasAccepted') == true) return true;
    final completion = Completer<bool>();
    runApp(AndroidPrivacyApp(onComplete: completion.complete));
    return completion.future;
  }

  static Future<void> initializePlugins() =>
      channel.invokeMethod<void>('initializePlugins');

  static Future<void> setReminderRestoreEnabled(bool enabled) =>
      channel.invokeMethod<void>(
        'setReminderRestoreEnabled',
        {'enabled': enabled},
      );

  static Future<void> setAssociationFlowEnabled(
    String flow,
    bool enabled,
  ) =>
      channel.invokeMethod<void>(
        'setAssociationFlowEnabled',
        {'flow': flow, 'enabled': enabled},
      );

  static Future<Map<String, dynamic>> deviceInfo() async =>
      await channel.invokeMapMethod<String, dynamic>('deviceInfo') ?? {};
}

class AndroidPrivacyApp extends StatelessWidget {
  const AndroidPrivacyApp({super.key, required this.onComplete});

  final ValueChanged<bool> onComplete;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final isTablet =
        view.physicalSize.shortestSide / view.devicePixelRatio >= 600;
    final BaseAppearance appearance =
        isTablet ? DesktopAppearance() : MobileAppearance();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appearance.getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      darkTheme: appearance.getThemeData(
        AppTheme.fallback,
        Brightness.dark,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler:
              TextScaler.linear(AdaptiveDisplayMetrics.of(context).textScale),
        ),
        child: child!,
      ),
      home: _ConsentPage(onComplete: onComplete),
    );
  }
}

class _ConsentPage extends StatefulWidget {
  const _ConsentPage({required this.onComplete});
  final ValueChanged<bool> onComplete;

  @override
  State<_ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<_ConsentPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestConsent());
  }

  Future<void> _requestConsent() async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AndroidPrivacyDialog(),
    );
    if (accepted != true) {
      widget.onComplete(false);
      await SystemNavigator.pop();
      return;
    }
    try {
      // Persist consent before allowing any plugin or business initialization.
      await AndroidPrivacyConsent.channel.invokeMethod<void>('accept');
      AndroidPrivacyConsent.acceptedThisLaunch = true;
      widget.onComplete(true);
    } on PlatformException {
      // Fail closed. A failed write must never allow startup to proceed.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法保存同意状态，请重试')),
        );
        await _requestConsent();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final asset = isTablet
        ? (isDark
            ? 'launch_screen_tablet_dark.png'
            : 'launch_screen_tablet_light.png')
        : (isDark ? 'launch_screen_dark.png' : 'launch_screen_light.png');
    return Scaffold(
      body: SizedBox.expand(
        child: Image.asset('assets/images/$asset', fit: BoxFit.cover),
      ),
    );
  }
}
