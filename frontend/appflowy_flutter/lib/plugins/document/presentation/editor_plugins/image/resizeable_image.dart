import 'dart:io';
import 'dart:math';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:string_validator/string_validator.dart';

enum ResizableImageState {
  loading,
  loaded,
  failed,
}

class ResizableImage extends StatefulWidget {
  const ResizableImage({
    super.key,
    required this.type,
    required this.alignment,
    required this.editable,
    required this.onResize,
    required this.width,
    required this.src,
    this.height,
    this.onDoubleTap,
    this.onStateChange,
  });

  final String src;
  final CustomImageType type;
  final double width;
  final double? height;
  final Alignment alignment;
  final bool editable;
  final VoidCallback? onDoubleTap;
  final ValueChanged<ResizableImageState>? onStateChange;

  final void Function(double width, double? height) onResize;

  @override
  State<ResizableImage> createState() => _ResizableImageState();
}

const _kImageBlockComponentMinWidth = 30.0;
const _kImageBlockComponentMinHeight = 30.0;

/// 立即接受横向拖动，避免被父级 ScrollView 抢走手势
class _ImmediateHorizontalDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 立即接受纵向拖动（与横向一致，保证角点双向都能赢）
class _ImmediateVerticalDragGestureRecognizer extends VerticalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 立即接受的 Pan，用于四角同时拖宽高
class _ImmediatePanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _ResizableImageState extends State<ResizableImage> {
  final documentService = DocumentService();
  final _imageKey = GlobalKey();

  double initialOffsetX = 0;
  double initialOffsetY = 0;
  double moveDistanceX = 0;
  double moveDistanceY = 0;
  double _cornerAccumulatedX = 0;
  double _cornerAccumulatedY = 0;
  Widget? _cacheImage;

  late double imageWidth;
  double? imageHeight;
  double? _computedHeight;
  bool _hasSetInitialHeight = false;

  @visibleForTesting
  bool onFocus = false;

  UserProfilePB? _userProfilePB;

  @override
  void initState() {
    super.initState();

    imageWidth = widget.width;
    imageHeight = widget.height;

    _userProfilePB = context.read<UserWorkspaceBloc?>()?.state.userProfile ??
        context.read<DocumentBloc>().state.userProfilePB;
  }

  void _ensureInitialHeight() {
    if (!_hasSetInitialHeight && imageHeight == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateHeightFromRenderBox();
      });
    }
  }

  void _updateHeightFromRenderBox() {
    if (!_hasSetInitialHeight && imageHeight == null && mounted) {
      final renderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize && renderBox.size.height > 0) {
        setState(() {
          _computedHeight = renderBox.size.height;
          _hasSetInitialHeight = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialHeight();

    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: max(_kImageBlockComponentMinWidth, imageWidth - moveDistanceX),
        height: _computedHeight != null
            ? max(_kImageBlockComponentMinHeight,
                _computedHeight! - moveDistanceY)
            : imageHeight != null
                ? max(_kImageBlockComponentMinHeight,
                    imageHeight! - moveDistanceY)
                : null,
        child: MouseRegion(
          onEnter: (_) => setState(() => onFocus = true),
          onExit: (_) => setState(() => onFocus = false),
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: KeyedSubtree(
              key: _imageKey,
              child: _buildResizableImage(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResizableImage(BuildContext context) {
    Widget child;
    final src = widget.src;
    final currentWidth = max(_kImageBlockComponentMinWidth, imageWidth - moveDistanceX);
    final currentHeight = _computedHeight != null
        ? max(_kImageBlockComponentMinHeight, _computedHeight! - moveDistanceY)
        : imageHeight != null
            ? max(_kImageBlockComponentMinHeight, imageHeight! - moveDistanceY)
            : null;

    if (isURL(src)) {
      _cacheImage = FlowyNetworkImage(
        url: widget.src,
        width: currentWidth,
        height: currentHeight,
        fit: currentHeight != null ? BoxFit.fill : BoxFit.contain,
        userProfilePB: _userProfilePB,
        onImageLoaded: (isImageInCache) {
          if (isImageInCache) {
            widget.onStateChange?.call(ResizableImageState.loaded);
          }
        },
        progressIndicatorBuilder: (context, _, progress) {
          if (progress.totalSize != null) {
            if (progress.progress == 1) {
              widget.onStateChange?.call(ResizableImageState.loaded);
            } else {
              widget.onStateChange?.call(ResizableImageState.loading);
            }
          }

          return _buildLoading(context);
        },
        errorWidgetBuilder: (_, __, error) {
          widget.onStateChange?.call(ResizableImageState.failed);
          return _ImageLoadFailedWidget(
            width: imageWidth,
            error: error,
            onRetry: () {
              setState(() {
                final retryCounter = FlowyNetworkRetryCounter();
                retryCounter.clear(tag: src, url: src);
              });
            },
          );
        },
      );

      child = _cacheImage!;
    } else {
      // load local file
      final currentWidth = max(_kImageBlockComponentMinWidth, imageWidth - moveDistanceX);
      final currentHeight = _computedHeight != null
          ? max(_kImageBlockComponentMinHeight, _computedHeight! - moveDistanceY)
          : imageHeight != null
              ? max(_kImageBlockComponentMinHeight, imageHeight! - moveDistanceY)
              : null;
      _cacheImage ??= Image.file(
        File(src),
        width: currentWidth,
        height: currentHeight,
        fit: currentHeight != null ? BoxFit.fill : BoxFit.contain,
      );
      child = _cacheImage!;
    }

    return Stack(
      children: [
        child,
        if (widget.editable) ...[
          // Left edge - horizontal resize
          _buildEdgeGesture(
            context,
            isHorizontal: true,
            isLeft: true,
            top: 0,
            left: 0,
            bottom: 0,
            width: 16,
            onUpdateX: (distance) =>
                setState(() => moveDistanceX = distance),
          ),
          // Right edge - horizontal resize
          _buildEdgeGesture(
            context,
            isHorizontal: true,
            isLeft: false,
            top: 0,
            right: 0,
            bottom: 0,
            width: 16,
            onUpdateX: (distance) =>
                setState(() => moveDistanceX = -distance),
          ),
          // Top edge - vertical resize
          _buildEdgeGesture(
            context,
            isHorizontal: false,
            isLeft: true,
            top: 0,
            left: 0,
            right: 0,
            height: 16,
            onUpdateY: (distance) =>
                setState(() => moveDistanceY = distance),
          ),
          // Bottom edge - vertical resize
          _buildEdgeGesture(
            context,
            isHorizontal: false,
            isLeft: true,
            bottom: 0,
            left: 0,
            right: 0,
            height: 16,
            onUpdateY: (distance) =>
                setState(() => moveDistanceY = -distance),
          ),
          // Top-left corner
          _buildCornerGesture(
            context,
            isTop: true,
            isLeft: true,
            top: 0,
            left: 0,
            onUpdateX: (distance) =>
                setState(() => moveDistanceX = distance),
            onUpdateY: (distance) =>
                setState(() => moveDistanceY = distance),
          ),
          // Top-right corner
          _buildCornerGesture(
            context,
            isTop: true,
            isLeft: false,
            top: 0,
            right: 0,
            onUpdateX: (distance) =>
                setState(() => moveDistanceX = -distance),
            onUpdateY: (distance) =>
                setState(() => moveDistanceY = distance),
          ),
          // Bottom-left corner
          _buildCornerGesture(
            context,
            isTop: false,
            isLeft: true,
            bottom: 0,
            left: 0,
            onUpdateX: (distance) =>
                setState(() => moveDistanceX = distance),
            onUpdateY: (distance) =>
                setState(() => moveDistanceY = -distance),
          ),
          // Bottom-right corner
          _buildCornerGesture(
            context,
            isTop: false,
            isLeft: false,
            bottom: 0,
            right: 0,
            onUpdateX: (distance) =>
                setState(() => moveDistanceX = -distance),
            onUpdateY: (distance) =>
                setState(() => moveDistanceY = -distance),
          ),
        ],
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.fromSize(
            size: const Size(18, 18),
            child: const CircularProgressIndicator(),
          ),
          SizedBox.fromSize(size: const Size(10, 10)),
          Text(AppFlowyEditorL10n.current.loading),
        ],
      ),
    );
  }

  Widget _buildEdgeGesture(
    BuildContext context, {
    required bool isHorizontal,
    required bool isLeft,
    double? top,
    double? left,
    double? right,
    double? bottom,
    double? width,
    double? height,
    void Function(double distance)? onUpdateX,
    void Function(double distance)? onUpdateY,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: isHorizontal
            ? <Type, GestureRecognizerFactory>{
                _ImmediateHorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<_ImmediateHorizontalDragGestureRecognizer>(
                  () => _ImmediateHorizontalDragGestureRecognizer(),
                  (_ImmediateHorizontalDragGestureRecognizer instance) {
                    instance.onStart = (details) {
                      initialOffsetX = details.globalPosition.dx;
                    };
                    instance.onUpdate = (details) {
                      if (onUpdateX != null) {
                        double offset = details.globalPosition.dx - initialOffsetX;
                        if (widget.alignment == Alignment.center) {
                          offset *= 2.0;
                        }
                        onUpdateX(offset);
                      }
                    };
                    instance.onEnd = (_) {
                      final newWidth = max(
                          _kImageBlockComponentMinWidth,
                          imageWidth - moveDistanceX);
                      imageWidth = newWidth;
                      initialOffsetX = 0;
                      moveDistanceX = 0;
                      widget.onResize(imageWidth, _computedHeight ?? imageHeight);
                    };
                  },
                ),
              }
            : <Type, GestureRecognizerFactory>{
                _ImmediateVerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<_ImmediateVerticalDragGestureRecognizer>(
                  () => _ImmediateVerticalDragGestureRecognizer(),
                  (_ImmediateVerticalDragGestureRecognizer instance) {
                    instance.onStart = (details) {
                      initialOffsetY = details.globalPosition.dy;
                    };
                    instance.onUpdate = (details) {
                      if (onUpdateY != null) {
                        final offset = details.globalPosition.dy - initialOffsetY;
                        onUpdateY(offset);
                      }
                    };
                    instance.onEnd = (_) {
                      final currentHeight = _computedHeight ?? imageHeight;
                      if (currentHeight != null) {
                        final newHeight = max(
                            _kImageBlockComponentMinHeight,
                            currentHeight - moveDistanceY);
                        if (_computedHeight != null) {
                          _computedHeight = newHeight;
                        } else {
                          imageHeight = newHeight;
                        }
                      }
                      initialOffsetY = 0;
                      moveDistanceY = 0;
                      widget.onResize(imageWidth, _computedHeight ?? imageHeight);
                    };
                  },
                ),
              },
        child: MouseRegion(
          cursor: isHorizontal
              ? SystemMouseCursors.resizeLeftRight
              : SystemMouseCursors.resizeUpDown,
          child: onFocus
              ? Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: isHorizontal ? 8 : null,
                    height: !isHorizontal ? 8 : null,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(4.0),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: isHorizontal ? 2 : 24,
                        height: isHorizontal ? 24 : 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  void _commitCornerResize() {
    final newWidth = max(
        _kImageBlockComponentMinWidth,
        imageWidth - moveDistanceX);
    imageWidth = newWidth;

    final currentHeight = _computedHeight ?? imageHeight;
    if (currentHeight != null) {
      final newHeight = max(
          _kImageBlockComponentMinHeight,
          currentHeight - moveDistanceY);
      if (_computedHeight != null) {
        _computedHeight = newHeight;
      } else {
        imageHeight = newHeight;
      }
    }

    initialOffsetX = 0;
    initialOffsetY = 0;
    moveDistanceX = 0;
    moveDistanceY = 0;
    widget.onResize(imageWidth, _computedHeight ?? imageHeight);
  }

  Widget _buildCornerGesture(
    BuildContext context, {
    required bool isTop,
    required bool isLeft,
    double? top,
    double? left,
    double? right,
    double? bottom,
    void Function(double distance)? onUpdateX,
    void Function(double distance)? onUpdateY,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: 20,
      height: 20,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _ImmediatePanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_ImmediatePanGestureRecognizer>(
            () => _ImmediatePanGestureRecognizer(),
            (_ImmediatePanGestureRecognizer instance) {
              instance.onStart = (_) {
                _cornerAccumulatedX = 0;
                _cornerAccumulatedY = 0;
              };
              instance.onUpdate = (details) {
                _cornerAccumulatedX += details.delta.dx;
                _cornerAccumulatedY += details.delta.dy;
                double finalOffsetX = _cornerAccumulatedX;
                if (widget.alignment == Alignment.center) {
                  finalOffsetX *= 2.0;
                }
                if (onUpdateX != null) {
                  onUpdateX(finalOffsetX);
                }
                if (onUpdateY != null) {
                  onUpdateY(_cornerAccumulatedY);
                }
              };
              instance.onEnd = (_) => _commitCornerResize();
            },
          ),
        },
        child: MouseRegion(
          cursor: _getCornerCursor(isTop, isLeft),
          child: onFocus
              ? Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(2.0),
                      ),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  MouseCursor _getCornerCursor(bool isTop, bool isLeft) {
    if (isTop && isLeft) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    } else if (isTop && !isLeft) {
      return SystemMouseCursors.resizeUpRightDownLeft;
    } else if (!isTop && isLeft) {
      return SystemMouseCursors.resizeUpRightDownLeft;
    } else {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }
  }
}

class _ImageLoadFailedWidget extends StatelessWidget {
  const _ImageLoadFailedWidget({
    required this.width,
    required this.error,
    required this.onRetry,
  });

  final double width;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = _getErrorMessage();
    return Container(
      height: 160,
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4.0)),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FlowySvg(
            FlowySvgs.broken_image_xl,
            size: Size.square(36),
          ),
          FlowyText(
            AppFlowyEditorL10n.current.imageLoadFailed,
            fontSize: 14,
          ),
          const VSpace(4),
          if (error != null)
            FlowyText(
              error,
              textAlign: TextAlign.center,
              color: Theme.of(context).hintColor.withValues(alpha: 0.6),
              fontSize: 10,
              maxLines: 2,
            ),
          const VSpace(12),
          Listener(
            onPointerDown: (event) {
              onRetry();
            },
            child: OutlinedRoundedButton(
              text: LocaleKeys.chat_retry.tr(),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  String? _getErrorMessage() {
    if (error is HttpExceptionWithStatus) {
      return 'Error ${(error as HttpExceptionWithStatus).statusCode}';
    }

    return null;
  }
}
