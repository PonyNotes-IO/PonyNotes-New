import 'package:flutter/material.dart';

/// ✅ 颜色选择器对话框
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
  bool _isRgbMode = false; // false = HSV模式, true = RGB模式

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('颜色选择器'),
      content: SizedBox(
        width: 400,
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
                  '#${_currentColor.value.toRadixString(16).toUpperCase().padLeft(8, '0')}',
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
            const SizedBox(height: 16),
            // ✅ 模式切换（HSV/RGB）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => _isRgbMode = false),
                  style: TextButton.styleFrom(
                    backgroundColor: !_isRgbMode
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('HSV'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _isRgbMode = true),
                  style: TextButton.styleFrom(
                    backgroundColor: _isRgbMode
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('RGB'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ✅ HSV模式选择器
            if (!_isRgbMode) _buildHsvPicker(),
            // ✅ RGB模式选择器
            if (_isRgbMode) _buildRgbPicker(),
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

  /// ✅ 构建HSV模式选择器
  Widget _buildHsvPicker() {
    return Column(
      children: [
        // 色相（H）滑块
        Row(
          children: [
            const SizedBox(width: 60, child: Text('色相 (H)')),
            Expanded(
              child: Slider(
                value: _hsvColor.hue,
                min: 0,
                max: 360,
                divisions: 360,
                label: _hsvColor.hue.toStringAsFixed(0),
                onChanged: (value) {
                  _updateColor(
                    HSVColor.fromAHSV(
                      _hsvColor.alpha,
                      value,
                      _hsvColor.saturation,
                      _hsvColor.value,
                    ).toColor(),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(_hsvColor.hue.toStringAsFixed(0)),
            ),
          ],
        ),
        // 饱和度（S）滑块
        Row(
          children: [
            const SizedBox(width: 60, child: Text('饱和度 (S)')),
            Expanded(
              child: Slider(
                value: _hsvColor.saturation,
                min: 0,
                max: 1,
                divisions: 100,
                label: (_hsvColor.saturation * 100).toStringAsFixed(0),
                onChanged: (value) {
                  _updateColor(
                    HSVColor.fromAHSV(
                      _hsvColor.alpha,
                      _hsvColor.hue,
                      value,
                      _hsvColor.value,
                    ).toColor(),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text('${(_hsvColor.saturation * 100).toStringAsFixed(0)}%'),
            ),
          ],
        ),
        // 明度（V）滑块
        Row(
          children: [
            const SizedBox(width: 60, child: Text('明度 (V)')),
            Expanded(
              child: Slider(
                value: _hsvColor.value,
                min: 0,
                max: 1,
                divisions: 100,
                label: (_hsvColor.value * 100).toStringAsFixed(0),
                onChanged: (value) {
                  _updateColor(
                    HSVColor.fromAHSV(
                      _hsvColor.alpha,
                      _hsvColor.hue,
                      _hsvColor.saturation,
                      value,
                    ).toColor(),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text('${(_hsvColor.value * 100).toStringAsFixed(0)}%'),
            ),
          ],
        ),
      ],
    );
  }

  /// ✅ 构建RGB模式选择器
  Widget _buildRgbPicker() {
    return Column(
      children: [
        // 红色（R）滑块
        Row(
          children: [
            const SizedBox(width: 60, child: Text('红色 (R)')),
            Expanded(
              child: Slider(
                value: _currentColor.red.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: _currentColor.red.toString(),
                onChanged: (value) {
                  _updateColor(
                    Color.fromARGB(
                      _currentColor.alpha,
                      value.toInt(),
                      _currentColor.green,
                      _currentColor.blue,
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(_currentColor.red.toString()),
            ),
          ],
        ),
        // 绿色（G）滑块
        Row(
          children: [
            const SizedBox(width: 60, child: Text('绿色 (G)')),
            Expanded(
              child: Slider(
                value: _currentColor.green.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: _currentColor.green.toString(),
                onChanged: (value) {
                  _updateColor(
                    Color.fromARGB(
                      _currentColor.alpha,
                      _currentColor.red,
                      value.toInt(),
                      _currentColor.blue,
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(_currentColor.green.toString()),
            ),
          ],
        ),
        // 蓝色（B）滑块
        Row(
          children: [
            const SizedBox(width: 60, child: Text('蓝色 (B)')),
            Expanded(
              child: Slider(
                value: _currentColor.blue.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: _currentColor.blue.toString(),
                onChanged: (value) {
                  _updateColor(
                    Color.fromARGB(
                      _currentColor.alpha,
                      _currentColor.red,
                      _currentColor.green,
                      value.toInt(),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(_currentColor.blue.toString()),
            ),
          ],
        ),
      ],
    );
  }
}

