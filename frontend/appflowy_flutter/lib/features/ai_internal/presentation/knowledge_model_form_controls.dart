import 'package:appflowy/features/ai_internal/presentation/knowledge_model_widgets.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Groups digits in threes, matching the model settings design.
String modelThousands(Object? value) {
  final digits = '${value ?? ''}'.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Reads a grouped number back; commas are display-only.
int? modelNumber(String? text) =>
    int.tryParse((text ?? '').replaceAll(',', '').trim());

class ModelThousandsFormatter extends TextInputFormatter {
  const ModelThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    final formatted = modelThousands(digits);
    final caret =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final typed = newValue.text
        .substring(0, caret)
        .replaceAll(RegExp('[^0-9]'), '')
        .length;
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < typed) {
      if (formatted[offset] != ',') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class ModelSelect extends StatefulWidget {
  const ModelSelect({
    super.key,
    required this.entries,
    required this.value,
    required this.onChanged,
    this.selectedChild,
    this.hint,
  });

  final List<DropdownMenuEntry<String>> entries;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final Widget? selectedChild;
  final String? hint;

  @override
  State<ModelSelect> createState() => _ModelSelectState();
}

class _ModelSelectState extends State<ModelSelect> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final value = widget.value;
    final onChanged = widget.onChanged;
    final selectedChild = widget.selectedChild;
    final hint = widget.hint;
    final theme = AppFlowyTheme.of(context);
    final foreground = theme.textColorScheme.primary;
    final selected = entries.where((entry) => entry.value == value).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        return MenuAnchor(
          childFocusNode: _focus,
          crossAxisUnconstrained: false,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            alignment: AlignmentDirectional.bottomStart,
            minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
            maximumSize:
                WidgetStatePropertyAll(Size(constraints.maxWidth, 360)),
            backgroundColor:
                WidgetStatePropertyAll(theme.backgroundColorScheme.primary),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shadowColor:
                WidgetStatePropertyAll(Colors.black.withValues(alpha: .12)),
            elevation: const WidgetStatePropertyAll(2),
            side: WidgetStatePropertyAll(
              BorderSide(color: foreground.withValues(alpha: .055)),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
          ),
          menuChildren: [
            for (final entry in entries)
              MenuItemButton(
                key: ValueKey('model-option-${entry.value}'),
                onPressed: onChanged == null || !entry.enabled
                    ? null
                    : () => onChanged(entry.value),
                style: MenuItemButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                  backgroundColor: value == entry.value
                      ? foreground.withValues(alpha: .035)
                      : Colors.transparent,
                  foregroundColor: foreground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ).copyWith(
                  overlayColor: WidgetStatePropertyAll(
                    foreground.withValues(alpha: .02),
                  ),
                ),
                child: Row(
                  children: [
                    if (entry.leadingIcon != null) ...[
                      entry.leadingIcon!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: entry.labelWidget ??
                          Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                    if (value == entry.value) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.check, size: 16, color: modelAccent),
                    ],
                  ],
                ),
              ),
          ],
          builder: (context, controller, child) => Semantics(
            expanded: controller.isOpen,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    controller.close,
              },
              child: OutlinedButton(
                focusNode: _focus,
                onPressed: onChanged == null
                    ? null
                    : () {
                        _focus.requestFocus();
                        controller.isOpen
                            ? controller.close()
                            : controller.open();
                      },
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(double.infinity, 36),
                  tapTargetSize: MediaQuery.sizeOf(context).width >= 480
                      ? MaterialTapTargetSize.shrinkWrap
                      : MaterialTapTargetSize.padded,
                  side: BorderSide(
                    color: controller.isOpen
                        ? foreground.withValues(alpha: .45)
                        : modelFieldBorder(context),
                    width: controller.isOpen ? 1 : modelFieldBorderWidth(context),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: selectedChild ??
                          Text(
                            selected?.label ?? hint ?? '请选择',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      controller.isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: foreground.withValues(alpha: .45),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ModelSliderControl extends StatelessWidget {
  const ModelSliderControl({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.hint,
    this.id,
    this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String hint;
  final String? id;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            decoration: modelSurface(context, radius: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      valueLabel,
                      key: id == null ? null : ValueKey('$id-value'),
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12, color: modelAccent),
                    ),
                  ],
                ),
                SizedBox(
                  height: 26,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: modelAccent,
                      inactiveTrackColor: AppFlowyTheme.of(context)
                          .textColorScheme
                          .primary
                          .withValues(alpha: .07),
                      thumbColor: modelAccent,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      key: id == null ? null : ValueKey('$id-slider'),
                      min: min,
                      max: max,
                      divisions: divisions,
                      value: value.clamp(min, max),
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: AppFlowyTheme.of(context).textColorScheme.secondary,
            ),
          ),
        ],
      );
}

class ModelTokenControl extends StatelessWidget {
  const ModelTokenControl({
    super.key,
    required this.label,
    required this.controller,
    required this.validator,
    required this.id,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final String id;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            decoration: modelSurface(context, radius: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: 78 * MediaQuery.textScalerOf(context).scale(1),
                      child: TextFormField(
                        key: ValueKey('$id-value'),
                        controller: controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        inputFormatters: const [ModelThousandsFormatter()],
                        style:
                            const TextStyle(fontSize: 12, color: modelAccent),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          suffixText: ' tokens',
                          suffixStyle: TextStyle(fontSize: 9),
                        ),
                        validator: validator,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 26,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: modelAccent,
                        inactiveTrackColor: AppFlowyTheme.of(context)
                            .textColorScheme
                            .primary
                            .withValues(alpha: .07),
                        thumbColor: modelAccent,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        key: ValueKey('$id-slider'),
                        min: 1,
                        max: 2000000,
                        value: (modelNumber(value.text) ?? 1)
                            .clamp(1, 2000000)
                            .toDouble(),
                        onChanged: (value) =>
                            controller.text = modelThousands(value.round()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: AppFlowyTheme.of(context).textColorScheme.secondary,
            ),
          ),
        ],
      );
}
