import 'package:flutter/material.dart';

const _overlayContainerPadding = EdgeInsets.symmetric(vertical: 12);
const overlayContainerMaxWidth = 760.0;
const overlayContainerMinWidth = 320.0;
const _defaultInsetPadding =
    EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0);

class FlowyDialog extends StatelessWidget {
  const FlowyDialog({
    super.key,
    required this.child,
    this.title,
    this.showCloseButton = true,
    this.shape,
    this.constraints,
    this.padding = _overlayContainerPadding,
    this.backgroundColor,
    this.expandHeight = true,
    this.alignment,
    this.insetPadding,
    this.width,
    this.onClose,
  });

  final Widget? title;
  /// 是否显示右上角关闭按钮，默认显示
  final bool showCloseButton;
  final ShapeBorder? shape;
  final Widget child;
  final BoxConstraints? constraints;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final bool expandHeight;

  // Position of the Dialog
  final Alignment? alignment;

  // Inset of the Dialog
  final EdgeInsets? insetPadding;

  final double? width;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final windowSize = MediaQuery.of(context).size;
    final size = windowSize * 0.7;

    return SimpleDialog(
      alignment: alignment,
      insetPadding: insetPadding ?? _defaultInsetPadding,
      contentPadding: EdgeInsets.zero,
      backgroundColor: backgroundColor ?? Theme.of(context).cardColor,
      title: title,
      shape: shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      children: [
        Material(
          type: MaterialType.transparency,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 为右上角关闭按钮预留一点顶部空间，避免压住内容
              Container(
                height: expandHeight ? size.height : null,
                width: width ?? size.width,
                constraints: constraints,
                child: child,
              ),
              if (showCloseButton)
                Positioned(
                  top: 4,
                  right: 4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        onClose?.call();
                        Navigator.of(context).maybePop();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent, // keep no background
                        ),
                        child: Icon(
                          Icons.close,
                          size: 24,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        )
      ],
    );
  }
}
