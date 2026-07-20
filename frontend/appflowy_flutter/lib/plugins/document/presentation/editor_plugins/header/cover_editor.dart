import 'dart:ui';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

const String kLocalImagesKey = 'local_images';

/// 文档封面的内置可选背景图。
///
/// 【封面图替换 2026-07-20】原为 AppFlowy 自带的 m_cover_image_1~6，
/// 现整体替换为小马笔记的 9 张自有封面图（3165x600，与封面横幅比例一致）。
///
/// 顺带修复一处既有缺陷：原代码引用的扩展名为 `.jpg`，而资源目录中实际文件
/// 一直是 `.png`，路径对不上导致内置封面图始终加载失败。
List<String> get builtInAssetImages => [
      'assets/images/built_in_cover_images/appflowy-cover-01-aurora-glass.png',
      'assets/images/built_in_cover_images/appflowy-cover-02-paper-collage.png',
      'assets/images/built_in_cover_images/appflowy-cover-03-ink-mountains.png',
      'assets/images/built_in_cover_images/appflowy-cover-04-retro-geometry.png',
      'assets/images/built_in_cover_images/appflowy-cover-05-botanical-miniature.png',
      'assets/images/built_in_cover_images/appflowy-cover-06-textile-waves.png',
      'assets/images/built_in_cover_images/appflowy-cover-07-mineral-terrazzo.png',
      'assets/images/built_in_cover_images/appflowy-cover-08-celestial-blueprint.png',
      'assets/images/built_in_cover_images/appflowy-cover-09-clay-relief.png',
    ];

class ColorOption {
  const ColorOption({
    required this.colorHex,
    required this.name,
  });

  final String colorHex;
  final String name;
}

class CoverColorPicker extends StatefulWidget {
  const CoverColorPicker({
    super.key,
    this.selectedBackgroundColorHex,
    required this.pickerBackgroundColor,
    required this.backgroundColorOptions,
    required this.pickerItemHoverColor,
    required this.onSubmittedBackgroundColorHex,
  });

  final String? selectedBackgroundColorHex;
  final Color pickerBackgroundColor;
  final List<ColorOption> backgroundColorOptions;
  final Color pickerItemHoverColor;
  final void Function(String color) onSubmittedBackgroundColorHex;

  @override
  State<CoverColorPicker> createState() => _CoverColorPickerState();
}

class _CoverColorPickerState extends State<CoverColorPicker> {
  final scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      alignment: Alignment.center,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          },
          platform: TargetPlatform.windows,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _buildColorItems(
            widget.backgroundColorOptions,
            widget.selectedBackgroundColorHex,
          ),
        ),
      ),
    );
  }

  Widget _buildColorItems(List<ColorOption> options, String? selectedColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: options
          .map(
            (e) => ColorItem(
              option: e,
              isChecked: e.colorHex == selectedColor,
              hoverColor: widget.pickerItemHoverColor,
              onTap: widget.onSubmittedBackgroundColorHex,
            ),
          )
          .toList(),
    );
  }
}

@visibleForTesting
class ColorItem extends StatelessWidget {
  const ColorItem({
    super.key,
    required this.option,
    required this.isChecked,
    required this.hoverColor,
    required this.onTap,
  });

  final ColorOption option;
  final bool isChecked;
  final Color hoverColor;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10.0),
      child: InkWell(
        customBorder: const CircleBorder(),
        hoverColor: hoverColor,
        onTap: () => onTap(option.colorHex),
        child: SizedBox.square(
          dimension: 25,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: option.colorHex.tryToColor(),
              shape: BoxShape.circle,
            ),
            child: isChecked
                ? SizedBox.square(
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).cardColor,
                          width: 3.0,
                        ),
                        color: option.colorHex.tryToColor(),
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
