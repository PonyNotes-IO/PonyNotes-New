import 'package:flutter/material.dart';

class HomeStackStableVisibility extends StatelessWidget {
  const HomeStackStableVisibility({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      child: child,
    );
  }
}
