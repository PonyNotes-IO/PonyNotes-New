import 'dart:async';

import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class UpgradeSuccessToast extends StatefulWidget {
  const UpgradeSuccessToast({
    super.key,
    required this.planName,
    required this.onDismiss,
  });

  final String planName;
  final VoidCallback onDismiss;

  @override
  State<UpgradeSuccessToast> createState() => _UpgradeSuccessToastState();
}

class _UpgradeSuccessToastState extends State<UpgradeSuccessToast> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return IntrinsicWidth(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 80, right: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: isDarkMode ? Colors.white : const Color(0xFF333333),
            ),
            child: FlowyText.medium(
              widget.planName,
              fontSize: FontSizes.s16,
              color: isDarkMode ? const Color(0xFF333333) : Colors.white,
            ),
          ),
          Positioned(
            left: 15,
            bottom: 0,
            child: Image.asset(
              "assets/images/icon_upgrade_success.png",
              width: 50,
              height: 50,
            ),
          ),
        ],
      ),
    );
  }
}

class UpgradeSuccessOverlay extends StatelessWidget {
  const UpgradeSuccessOverlay({
    super.key,
    required this.planName,
    required this.onDismiss,
  });

  final String planName;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.none,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.only(bottom: 60),
            clipBehavior: Clip.none,
            child: UpgradeSuccessToast(
              planName: planName,
              onDismiss: onDismiss,
            ),
          ),
        ),
      ),
    );
  }
}