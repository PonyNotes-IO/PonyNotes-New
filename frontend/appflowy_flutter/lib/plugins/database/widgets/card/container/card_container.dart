import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:provider/provider.dart';

import 'accessory.dart';

class RowCardContainer extends StatelessWidget {
  const RowCardContainer({
    super.key,
    required this.child,
    required this.onTap,
    required this.openAccessory,
    required this.accessories,
    this.buildAccessoryWhen,
    this.onShiftTap,
  });

  final Widget child;
  final void Function(BuildContext) onTap;
  final void Function(BuildContext)? onShiftTap;
  final void Function(AccessoryType) openAccessory;
  final List<CardAccessory> accessories;
  final bool Function()? buildAccessoryWhen;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => _CardContainerNotifier(),
      child: Consumer<_CardContainerNotifier>(
        builder: (context, notifier, _) {
          final shouldBuildAccessory = buildAccessoryWhen?.call() ?? true;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (HardwareKeyboard.instance.isShiftPressed) {
                onShiftTap?.call(context);
              } else {
                onTap(context);
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: _CardEnterRegion(
                shouldBuildAccessory: shouldBuildAccessory,
                accessories: accessories,
                onTapAccessory: openAccessory,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CardEnterRegion extends StatelessWidget {
  const _CardEnterRegion({
    required this.shouldBuildAccessory,
    required this.child,
    required this.accessories,
    required this.onTapAccessory,
  });

  final bool shouldBuildAccessory;
  final Widget child;
  final List<CardAccessory> accessories;
  final void Function(AccessoryType) onTapAccessory;

  @override
  Widget build(BuildContext context) {
    return Selector<_CardContainerNotifier, bool>(
      selector: (context, notifier) => notifier.onEnter,
      builder: (context, onEnter, _) {
        final shouldShowAccessory = PlatformInfo.isTablet || onEnter;
        final content = accessories.isEmpty
            // Calendar event cards have no accessories. Let their text fields
            // determine the height directly instead of relying on an intrinsic
            // Stack measurement, which can be shorter on macOS font metrics.
            ? child
            : IntrinsicHeight(
                child: Stack(
                  alignment: AlignmentDirectional.topEnd,
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (shouldShowAccessory && shouldBuildAccessory)
                      Positioned(
                        top: 7.0,
                        right: 7.0,
                        child: CardAccessoryContainer(
                          accessories: accessories,
                          onTapAccessory: onTapAccessory,
                        ),
                      ),
                  ],
                ),
              );

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (p) =>
              Provider.of<_CardContainerNotifier>(context, listen: false)
                  .onEnter = true,
          onExit: (p) {
            if (!PlatformInfo.isTablet) {
              Provider.of<_CardContainerNotifier>(context, listen: false)
                  .onEnter = false;
            }
          },
          child: content,
        );
      },
    );
  }
}

class _CardContainerNotifier extends ChangeNotifier {
  _CardContainerNotifier();

  bool _onEnter = false;

  set onEnter(bool value) {
    if (_onEnter != value) {
      _onEnter = value;
      notifyListeners();
    }
  }

  bool get onEnter => _onEnter;
}
