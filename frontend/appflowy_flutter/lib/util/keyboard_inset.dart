import 'package:flowy_infra/platform_extension.dart';
import 'package:flutter/widgets.dart';

/// Bottom inset (in logical pixels) the on-screen keyboard currently occupies,
/// read from the engine instead of [MediaQuery].
///
/// `AppWidget` freezes `MediaQuery.viewInsets` to zero on tablets to avoid
/// rebuilding the whole tree while the IME animates. The side effect is that
/// `Scaffold.resizeToAvoidBottomInset` and any `MediaQuery.viewInsets` based
/// keyboard avoidance stop working there, so the keyboard ends up drawn on top
/// of the content.
///
/// [rawKeyboardBottomInset] returns the real value, and [KeyboardInsetBuilder]
/// rebuilds when it changes. Both return `0` on phones/desktop, where the
/// framework already handles the keyboard.
double rawKeyboardBottomInset(BuildContext context) {
  if (!PlatformInfo.isTablet) {
    return 0;
  }
  final view = View.of(context);
  final devicePixelRatio = view.devicePixelRatio;
  if (devicePixelRatio <= 0) {
    return 0;
  }
  return view.viewInsets.bottom / devicePixelRatio;
}

/// Rebuilds [builder] with the current keyboard bottom inset.
///
/// Use it for pages/dialogs that must stay usable while typing on a tablet:
///
/// ```dart
/// KeyboardInsetBuilder(
///   builder: (context, bottomInset) => Padding(
///     padding: EdgeInsets.only(bottom: bottomInset),
///     child: child,
///   ),
/// );
/// ```
class KeyboardInsetBuilder extends StatefulWidget {
  const KeyboardInsetBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, double bottomInset) builder;

  @override
  State<KeyboardInsetBuilder> createState() => _KeyboardInsetBuilderState();
}

class _KeyboardInsetBuilderState extends State<KeyboardInsetBuilder>
    with WidgetsBindingObserver {
  double _bottomInset = 0;

  @override
  void initState() {
    super.initState();
    if (PlatformInfo.isTablet) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // View.of() is only available from didChangeDependencies onwards, and the
    // value must be in place for the first build.
    _bottomInset = rawKeyboardBottomInset(context);
  }

  @override
  void dispose() {
    if (PlatformInfo.isTablet) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    final inset = rawKeyboardBottomInset(context);
    if ((inset - _bottomInset).abs() < 0.5) {
      return;
    }
    setState(() => _bottomInset = inset);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _bottomInset);
}
