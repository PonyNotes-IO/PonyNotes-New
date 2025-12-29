import 'package:flutter/material.dart';

/// ✅ 颜色选择器对话框（全彩调色盘）
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    this.colorHistory = const [],
  });

  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final List<Color> colorHistory; // ✅ 颜色历史记录

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();

  /// ✅ 显示颜色选择器对话框
  static Future<Color?> show(
    BuildContext context, {
    required Color initialColor,
    List<Color> colorHistory = const [],
  }) async {
    Color? selectedColor;
    await showDialog(
      context: context,
      builder: (context) => ColorPickerDialog(
        initialColor: initialColor,
        colorHistory: colorHistory,
        onColorChanged: (color) {
          selectedColor = color;
        },
      ),
    );
    return selectedColor;
  }
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _currentColor;
  late HSVColor _hsvColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _hsvColor = HSVColor.fromColor(_currentColor);
  }

  void _updateColor(Color color) {
    setState(() {
      _currentColor = color;
      _hsvColor = HSVColor.fromColor(color);
    });
    widget.onColorChanged(color);
  }

  void _updateHSV(HSVColor hsvColor) {
    setState(() {
      _hsvColor = hsvColor;
      _currentColor = hsvColor.toColor();
    });
    widget.onColorChanged(_currentColor);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('颜色选择器'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ 颜色预览
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: _currentColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  '#${_currentColor.value.toRadixString(16).toUpperCase().substring(2).padLeft(6, '0')}',
                  style: TextStyle(
                    color: _currentColor.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ✅ 色相条（先选择色相）
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '色相 (拖动选择颜色)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                _HueSlider(
                  hue: _hsvColor.hue,
                  onChanged: (hue) {
                    _updateHSV(_hsvColor.withHue(hue));
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ✅ 全彩调色盘（饱和度/明度面板）
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '饱和度和明度 (点击调整深浅)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                _ColorPalette(
                  hsvColor: _hsvColor,
                  onColorChanged: _updateHSV,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ✅ 颜色历史记录
            if (widget.colorHistory.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '最近使用',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.colorHistory.map((color) {
                  return GestureDetector(
                    onTap: () => _updateColor(color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            widget.onColorChanged(_currentColor);
            Navigator.of(context).pop(_currentColor);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// ✅ 全彩调色盘（饱和度/明度面板）
class _ColorPalette extends StatefulWidget {
  const _ColorPalette({
    required this.hsvColor,
    required this.onColorChanged,
  });

  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onColorChanged;

  @override
  State<_ColorPalette> createState() => _ColorPaletteState();
}

class _ColorPaletteState extends State<_ColorPalette> {
  void _handleGesture(Offset localPosition, Size size) {
    final saturation = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final value = 1.0 - (localPosition.dy / size.height).clamp(0.0, 1.0);
    
    widget.onColorChanged(
      widget.hsvColor.withSaturation(saturation).withValue(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanDown: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            _handleGesture(details.localPosition, box.size);
          },
          onPanUpdate: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            _handleGesture(details.localPosition, box.size);
          },
          child: Container(
            width: 300,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                painter: _ColorPalettePainter(
                  hue: widget.hsvColor.hue,
                  saturation: widget.hsvColor.saturation,
                  value: widget.hsvColor.value,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ✅ 调色盘画笔
class _ColorPalettePainter extends CustomPainter {
  _ColorPalettePainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制饱和度/明度渐变
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    // 基础色（当前色相的纯色）
    final baseColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    
    // 水平渐变：白色到基础色（饱和度）
    final saturationGradient = LinearGradient(
      colors: [Colors.white, baseColor],
    );
    canvas.drawRect(rect, Paint()..shader = saturationGradient.createShader(rect));
    
    // 垂直渐变：透明到黑色（明度）
    final valueGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    );
    canvas.drawRect(rect, Paint()..shader = valueGradient.createShader(rect));
    
    // 绘制当前选中位置的指示器
    final indicatorX = saturation * size.width;
    final indicatorY = (1.0 - value) * size.height;
    
    // 外圈（白色）
    canvas.drawCircle(
      Offset(indicatorX, indicatorY),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    
    // 内圈（黑色）
    canvas.drawCircle(
      Offset(indicatorX, indicatorY),
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ColorPalettePainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value;
  }
}

/// ✅ 色相滑块
class _HueSlider extends StatefulWidget {
  const _HueSlider({
    required this.hue,
    required this.onChanged,
  });

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  State<_HueSlider> createState() => _HueSliderState();
}

class _HueSliderState extends State<_HueSlider> {
  final GlobalKey _sliderKey = GlobalKey();

  void _handleGesture(Offset localPosition) {
    final RenderBox? box = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final hue = (localPosition.dx / box.size.width * 360).clamp(0.0, 360.0);
      widget.onChanged(hue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 40,
      child: GestureDetector(
        onPanDown: (details) => _handleGesture(details.localPosition),
        onPanUpdate: (details) => _handleGesture(details.localPosition),
        onTapDown: (details) => _handleGesture(details.localPosition),
        child: Container(
          key: _sliderKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              painter: _HueSliderPainter(hue: widget.hue),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ 色相滑块画笔
class _HueSliderPainter extends CustomPainter {
  _HueSliderPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    // 绘制色相渐变
    final gradient = LinearGradient(
      colors: [
        const HSVColor.fromAHSV(1.0, 0, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 60, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 120, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 180, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 240, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 300, 1.0, 1.0).toColor(),
        const HSVColor.fromAHSV(1.0, 360, 1.0, 1.0).toColor(),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    
    // 绘制当前位置指示器
    final indicatorX = (hue / 360) * size.width;
    
    // 白色竖线
    canvas.drawLine(
      Offset(indicatorX, 0),
      Offset(indicatorX, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    
    // 黑色竖线（内部）
    canvas.drawLine(
      Offset(indicatorX, 0),
      Offset(indicatorX, size.height),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_HueSliderPainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}
